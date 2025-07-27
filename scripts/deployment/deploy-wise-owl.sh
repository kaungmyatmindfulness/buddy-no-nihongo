#!/bin/bash
# filepath: /opt/deploy-wise-owl.sh
# Wise Owl Deployment Script for Prepared Raspberry Pi
# Run this after setup-raspberry-pi-generic.sh
# Assumes the repository is already cloned

set -e

# Configuration
INSTALL_DIR="$(pwd)"  # Use current directory as install directory
DEPLOY_USER="${DEPLOY_USER:-deploy}"
BRANCH="${BRANCH:-master}"
GO_VERSION="1.24.5"

# Detect platform
if [[ "$OSTYPE" == "darwin"* ]]; then
  IS_MAC=true
  PLATFORM="darwin/arm64"
  echo "Detected: macOS (Apple Silicon)"
else
  IS_MAC=false
  PLATFORM="linux/arm64"
  echo "Detected: Linux (Raspberry Pi/ARM64)"
fi

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Print functions
print_info() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
  echo -e "${BLUE}[STEP]${NC} $1"
}

# Check if running as the deploy user or root
if [ "$EUID" -eq 0 ]; then 
  print_warning "Running as root, will use sudo -u $DEPLOY_USER for operations"
  RUN_AS="sudo -u $DEPLOY_USER"
else
  RUN_AS=""
fi

# ASCII Art
echo -e "${GREEN}"
cat << "EOF"
 _       _____              ____          __
| |     / (_)_______      / __  \_      _/ /
| | /| / / / ___/ _ \    / / / / | /| / / / 
| |/ |/ / (__  )  __/   / /_/ /| |/ |/ / /  
|__/|__/_/____/\___/    \____/ |__/|__/_/   
                                             
    Japanese Vocabulary Learning Platform
         Microservices Deployment
EOF
echo -e "${NC}"

# ========================================
# Pre-flight Checks
# ========================================
print_info "Running pre-flight checks..."

# Check Docker
if ! command -v docker &> /dev/null; then
  print_error "Docker not found! Run setup-raspberry-pi-generic.sh first"
  exit 1
fi

# Check if protoc is available (for proto generation)
if ! command -v protoc &> /dev/null; then
  print_warning "protoc not found. Proto generation will be done in Docker container..."
fi

# ========================================
# PHASE 1: Directory Setup
# ========================================
print_info "Phase 1: Directory Setup"

print_step "Creating Wise Owl directories..."
if [ "$IS_MAC" = true ]; then
  # On Mac, use mkdir without sudo and ensure current user owns directories
  mkdir -p $INSTALL_DIR/{backups,logs,data}
  chown -R $DEPLOY_USER $INSTALL_DIR 2>/dev/null || true
else
  # On Linux (Pi), use sudo for directory creation
  sudo mkdir -p $INSTALL_DIR/{backups,logs,data}
  sudo chown -R $DEPLOY_USER:$DEPLOY_USER $INSTALL_DIR
fi

# Verify repository
if [ ! -f "go.work" ]; then
  print_error "This doesn't appear to be a Wise Owl repository (no go.work file found)"
  print_error "Please run this script from the root of the cloned repository"
  exit 1
fi

print_info "Using existing repository in $INSTALL_DIR"

# ========================================
# PHASE 2: Proto Generation
# ========================================
print_info "Phase 2: Protocol Buffer Generation"

print_step "Generating proto files using Docker..."
if [ -f "Makefile" ] && grep -q "proto:" "Makefile"; then
  # Use Docker to run proto generation in a controlled environment
  print_step "Running proto generation in Docker container..."
  
  # Create a temporary docker-compose for proto generation
  cat > $INSTALL_DIR/docker-compose.proto.yml << EOF
version: '3.8'
services:
  proto-gen:
    image: golang:${GO_VERSION}-alpine
    working_dir: /workspace
    volumes:
      - .:/workspace
    command: sh -c "
      apk add --no-cache protobuf-dev make &&
      go install google.golang.org/protobuf/cmd/protoc-gen-go@latest &&
      go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest &&
      export PATH=\$PATH:\$(go env GOPATH)/bin &&
      make proto
    "
    user: "$(id -u):$(id -g)"
    environment:
      - GOCACHE=/tmp/.gocache
      - GOMODCACHE=/tmp/.gomodcache
EOF

  # Run proto generation
  $RUN_AS docker compose -f docker-compose.proto.yml run --rm proto-gen
  
  # Clean up temporary compose file
  rm -f $INSTALL_DIR/docker-compose.proto.yml
  
  print_info "Proto files generated successfully"
else
  # Alternative: check for proto files and generate manually if needed
  if [ -d "proto" ] || find . -name "*.proto" -type f | head -1 | grep -q .; then
    print_step "Found proto files, generating with Docker..."
    
    # Run proto generation directly in Docker without separate script
    if $RUN_AS docker run --rm \
      -v "$INSTALL_DIR:/workspace" \
      -w /workspace \
      -u "$(id -u):$(id -g)" \
      -e GOCACHE=/tmp/.gocache \
      -e GOMODCACHE=/tmp/.gomodcache \
      golang:${GO_VERSION}-alpine \
      sh -c "
        set -e
        
        # Find all proto files
        proto_files=\$(find . -name '*.proto' -type f)
        
        if [ -z \"\$proto_files\" ]; then
          echo 'No proto files found'
          exit 0
        fi
        
        echo 'Found proto files:'
        echo \"\$proto_files\"
        
        # Install protoc and Go plugins
        echo 'Installing protoc and dependencies...'
        apk add --no-cache protobuf-dev >/dev/null 2>&1
        
        echo 'Installing Go protobuf plugins...'
        go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
        go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest
        
        export PATH=\$PATH:\$(go env GOPATH)/bin
        
        # Generate for each proto file
        echo 'Generating Go code from proto files...'
        for proto_file in \$proto_files; do
          echo \"Processing: \$proto_file\"
          
          # Generate Go files
          protoc \
            --proto_path=. \
            --go_out=. \
            --go_opt=paths=source_relative \
            --go-grpc_out=. \
            --go-grpc_opt=paths=source_relative \
            \"\$proto_file\"
        done
        
        echo 'Proto generation completed successfully'
        
        # List generated files
        generated_files=\$(find . -name '*.pb.go' -type f)
        if [ -n \"\$generated_files\" ]; then
          echo 'Generated files:'
          echo \"\$generated_files\"
        fi
      "; then
      print_info "Proto files generated successfully"
    else
      print_error "Proto generation failed! Please check the logs above."
      print_error "This might be due to Go version compatibility or network issues."
      exit 1
    fi
  else
    print_warning "No proto files or Makefile proto target found, skipping proto generation"
  fi
fi

# ========================================
# PHASE 3: Prepare Dependencies and Build Services
# ========================================
print_info "Phase 3: Preparing Dependencies and Building Services"

print_step "Ensuring vendor directory exists..."
if [ ! -d "$INSTALL_DIR/vendor" ] || [ ! -f "$INSTALL_DIR/vendor/modules.txt" ]; then
  print_step "Creating vendor directory..."
  $RUN_AS docker run --rm \
    -v "$INSTALL_DIR:/workspace" \
    -w /workspace \
    -u "$(id -u):$(id -g)" \
    -e GOCACHE=/tmp/.gocache \
    -e GOMODCACHE=/tmp/.gomodcache \
    golang:${GO_VERSION}-alpine \
    sh -c "
      set -e
      echo 'Downloading Go dependencies...'
      go mod download
      echo 'Creating vendor directory...'
      go work vendor
      echo 'Vendor directory created successfully'
    "
  print_info "Vendor directory created successfully"
else
  print_info "Vendor directory already exists"
fi

print_step "Building services for ARM64..."
services=("users" "content" "quiz")

for service in "${services[@]}"; do
  print_step "Building $service service..."
  
  # Build with context from root directory and service-specific Dockerfile
  # Use appropriate platform based on detected OS
  if [ "$IS_MAC" = true ]; then
    # On Mac, build for both local testing and ARM64 deployment
    $RUN_AS docker build \
      --platform linux/arm64 \
      -t wo-$service-service:latest \
      -f ./services/$service/Dockerfile \
      .
  else
    # On Pi, build for local ARM64
    $RUN_AS docker build \
      --platform linux/arm64 \
      -t wo-$service-service:latest \
      -f ./services/$service/Dockerfile \
      .
  fi
done

# Note: nginx uses the standard nginx:stable-alpine image with custom config volume

# ========================================
# PHASE 4: Production Scripts
# ========================================
print_info "Phase 4: Setting up production scripts"

# Ensure scripts are executable
chmod +x $INSTALL_DIR/*.sh 2>/dev/null || true

# Create systemd service for Wise Owl
print_step "Creating systemd service..."
if [ "$IS_MAC" = true ]; then
  print_warning "Skipping systemd service creation on macOS"
  print_info "On macOS, use: docker compose -f docker-compose.prod.yml up -d"
else
  sudo tee /etc/systemd/system/wise-owl.service > /dev/null << EOF
[Unit]
Description=Wise Owl Japanese Vocabulary Learning Platform
Documentation=https://github.com/yourusername/wise-owl-golang
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=true
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/docker compose -f docker-compose.prod.yml up -d
ExecStop=/usr/bin/docker compose -f docker-compose.prod.yml down
Restart=on-failure
User=$DEPLOY_USER
Group=docker
Environment="PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin"

# Service dependencies
Environment="SERVICE_ENV=production"

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable wise-owl.service
fi

# ========================================
# PHASE 5: Cron Jobs for Wise Owl
# ========================================
print_info "Phase 5: Setting up automated tasks"

if [ "$IS_MAC" = true ]; then
  print_warning "Skipping cron job setup on macOS"
  print_info "Consider setting up automated tasks manually using launchd or cron"
else
  sudo tee /etc/cron.d/wise-owl > /dev/null << EOF
# Wise Owl Automated Tasks
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# Daily backup at 2 AM (includes all MongoDB databases)
0 2 * * * $DEPLOY_USER cd $INSTALL_DIR && ./backup-prod.sh create >> $INSTALL_DIR/logs/backup.log 2>&1

# Weekly cleanup on Sunday at 3 AM
0 3 * * 0 root docker system prune -af >> $INSTALL_DIR/logs/cleanup.log 2>&1

# Monitor vocabulary seeding completion (runs every 5 minutes for first day)
*/5 * * * * $DEPLOY_USER cd $INSTALL_DIR && docker compose -f docker-compose.prod.yml logs wo-content-service | grep -q "Seeding completed successfully" && touch $INSTALL_DIR/.seeding-complete 2>&1
EOF
fi

# ========================================
# PHASE 6: Initial Data Preparation
# ========================================
print_info "Phase 6: Data Seeding Preparation"

print_step "Checking for vocabulary seed data..."
if [ -f "services/content/seed/wise-owl-vocabulary.json" ]; then
  vocab_count=$(jq '. | length' services/content/seed/wise-owl-vocabulary.json 2>/dev/null || echo "unknown")
  print_info "Found vocabulary data with $vocab_count entries"
  print_info "Content service will automatically seed on first startup"
else
  print_warning "Vocabulary seed data not found"
  print_warning "Ensure services/content/seed/wise-owl-vocabulary.json exists"
fi

# ========================================
# PHASE 7: Health Check Script
# ========================================
print_info "Phase 7: Creating health check script"

cat > $INSTALL_DIR/check-wise-owl.sh << 'EOF'
#!/bin/bash
# Wise Owl Health Check Script

echo "🦉 Wise Owl Health Status"
echo "========================"
echo ""

# Check services
services=("wo-nginx:8080:/health" "wo-users-service:internal" "wo-content-service:internal" "wo-quiz-service:internal")

for service_info in "${services[@]}"; do
  IFS=':' read -r container port endpoint <<< "$service_info"
  
  echo -n "Checking $container... "
  
  if docker ps --format "{{.Names}}" | grep -q "^$container$"; then
    if [ "$port" = "internal" ]; then
      # For internal services, just check if container is running and healthy
      if docker inspect "$container" --format='{{.State.Status}}' | grep -q "running"; then
        echo "✅ Running"
      else
        echo "❌ Not running properly"
      fi
    else
      # For nginx, check HTTP endpoint
      if curl -s "http://localhost:$port$endpoint" > /dev/null 2>&1; then
        echo "✅ Running and responding"
      else
        echo "⚠️  Running but not responding on $port$endpoint"
      fi
    fi
  else
    echo "❌ Not running"
  fi
done

echo ""
echo "MongoDB Status:"
if docker ps --format "{{.Names}}" | grep -q "^wo-mongodb$"; then
  if docker exec wo-mongodb mongosh --quiet --eval "db.adminCommand('ping')" &>/dev/null; then
    echo "✅ MongoDB responsive"
  else
    echo "⚠️  MongoDB running but not responding"
  fi
else
  echo "❌ MongoDB not running"
fi

echo ""
echo "Vocabulary Data Status:"
if [ -f "$INSTALL_DIR/.seeding-complete" ]; then
  echo "✅ Vocabulary seeding completed"
else
  echo "⏳ Vocabulary seeding in progress or pending"
fi

echo ""
echo "Container Status Summary:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" --filter "name=wo-"
EOF

chmod +x $INSTALL_DIR/check-wise-owl.sh

# ========================================
# COMPLETION
# ========================================
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
print_info "Wise Owl Deployment Complete!"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${GREEN}=== Summary ===${NC}"
echo "✅ Using existing repository in $INSTALL_DIR"
echo "✅ Protocol buffers generated using Docker"
if [ "$IS_MAC" = true ]; then
  echo "✅ Environment ready for macOS development/testing"
else
  echo "✅ Production environment configured"  
fi
echo "✅ Docker services built for ARM64"
if [ "$IS_MAC" = true ]; then
  echo "⚠️  Systemd service skipped (macOS)"
  echo "⚠️  Automated tasks skipped (macOS)"
else
  echo "✅ Systemd service configured"
  echo "✅ Automated tasks scheduled"
fi
echo "✅ Health monitoring configured"
echo ""

echo -e "${YELLOW}=== Deployment Summary ===${NC}"
echo "Install Dir: $INSTALL_DIR"
echo "Service User: $DEPLOY_USER"
echo ""

echo -e "${BLUE}=== Architecture ===${NC}"
echo "- API Gateway (Nginx) → Port 8080 (wo-nginx)"
echo "- Users Service → Internal (wo-users-service)"
echo "- Content Service → Internal (wo-content-service)"
echo "- Quiz Service → Internal (wo-quiz-service)"
echo "- MongoDB → Port 27017 (wo-mongodb)"
echo ""

echo -e "${GREEN}=== Start Commands ===${NC}"
if [ "$IS_MAC" = true ]; then
  echo "macOS: cd $INSTALL_DIR && docker compose -f docker-compose.prod.yml up -d"
else
  echo "Option 1: sudo systemctl start wise-owl"
  echo "Option 2: cd $INSTALL_DIR && docker compose -f docker-compose.prod.yml up -d"
fi
echo ""

echo -e "${BLUE}=== Monitoring ===${NC}"
echo "- Check status: docker compose -f docker-compose.prod.yml ps"
echo "- View logs: docker compose -f docker-compose.prod.yml logs [service-name]"
echo "- Health check: ./check-wise-owl.sh"
echo ""

echo -e "${YELLOW}=== Access Points ===${NC}"
if [ "$IS_MAC" = true ]; then
  echo "- API Gateway: http://localhost:8080"
else
  echo "- API Gateway: http://$(hostname -I | awk '{print $1}'):8080"
fi
echo "- All API endpoints are routed through nginx"
if [ "$IS_MAC" = false ]; then
  echo "- MongoDB: $(hostname -I | awk '{print $1}'):27017 (if external access needed)"
else
  echo "- MongoDB: localhost:27017 (if external access needed)"
fi
echo ""

echo -e "${GREEN}=== Important Notes ===${NC}"
echo "1. Content service will seed vocabulary entries on first start"
echo "2. Initial seeding may take 5-10 minutes"
echo "3. Check seeding progress: docker compose -f docker-compose.prod.yml logs wo-content-service"
echo "4. Update .env.docker with your Auth0 credentials if using authentication"
echo "5. Nginx config should be placed in ./nginx/ directory"
echo ""

echo -e "${BLUE}=== Next Steps ===${NC}"
if [ "$IS_MAC" = true ]; then
  echo "1. Ensure .env.docker file exists with proper configuration"
  echo "2. Ensure nginx configuration exists in ./nginx/ directory"
  echo "3. Start the services: docker compose -f docker-compose.prod.yml up -d"
  echo "4. Monitor initial vocabulary seeding"
  echo "5. Set up automated tasks manually if needed"
else
  echo "1. Review and update $INSTALL_DIR/.env.docker"
  echo "2. Ensure nginx configuration exists in ./nginx/ directory"
  echo "3. Start the services: sudo systemctl start wise-owl"
  echo "4. Monitor initial vocabulary seeding"
  echo "5. Set up CI/CD with GitHub Actions"
fi
echo ""

print_info "Ready for production deployment with Japanese vocabulary learning! 🚀"