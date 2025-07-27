#!/bin/bash
# filepath: /opt/deploy-wise-owl.sh
# Wise Owl Deployment Script for Prepared Raspberry Pi
# Run this after setup-raspberry-pi-generic.sh
# Includes Japanese Vocabulary Learning Platform Microservices

set -e

# Configuration
WISE_OWL_REPO="git@github.com:kaungmyatmindfulness/wise-owl-nihongo-golang.git"
INSTALL_DIR="/opt/wise-owl"
DEPLOY_USER="${DEPLOY_USER:-deploy}"
BRANCH="${BRANCH:-master}"
GO_VERSION="1.21.5"

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
| |     / (_)_______      / __ \_      _/ /
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
# PHASE 1: Repository Setup
# ========================================
print_info "Phase 1: Repository Setup"

print_step "Creating Wise Owl directories..."
sudo mkdir -p $INSTALL_DIR/{backups,logs,data}
sudo chown -R $DEPLOY_USER:$DEPLOY_USER $INSTALL_DIR

print_step "Cloning Wise Owl repository..."
if [ ! -d "$INSTALL_DIR/.git" ]; then
  $RUN_AS git clone -b $BRANCH $WISE_OWL_REPO $INSTALL_DIR
else
  print_info "Repository exists, pulling latest changes..."
  cd $INSTALL_DIR
  $RUN_AS git fetch origin
  $RUN_AS git checkout $BRANCH
  $RUN_AS git pull origin $BRANCH
fi

cd $INSTALL_DIR

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
    
    # Create proto generation script
    cat > $INSTALL_DIR/generate-protos.sh << 'EOF'
#!/bin/bash
set -e

# Find all proto files
proto_files=$(find . -name "*.proto" -type f)

if [ -z "$proto_files" ]; then
  echo "No proto files found"
  exit 0
fi

echo "Found proto files:"
echo "$proto_files"

# Install protoc and Go plugins
apk add --no-cache protobuf-dev
go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest

export PATH=$PATH:$(go env GOPATH)/bin

# Generate for each proto file
for proto_file in $proto_files; do
  echo "Generating for: $proto_file"
  
  # Determine output directory based on proto file location
  proto_dir=$(dirname "$proto_file")
  
  # Generate Go files
  protoc \
    --proto_path=. \
    --go_out=. \
    --go_opt=paths=source_relative \
    --go-grpc_out=. \
    --go-grpc_opt=paths=source_relative \
    "$proto_file"
done

echo "Proto generation completed"
EOF
    
    chmod +x $INSTALL_DIR/generate-protos.sh
    
    # Run proto generation in Docker
    $RUN_AS docker run --rm \
      -v "$INSTALL_DIR:/workspace" \
      -w /workspace \
      -u "$(id -u):$(id -g)" \
      -e GOCACHE=/tmp/.gocache \
      -e GOMODCACHE=/tmp/.gomodcache \
      golang:${GO_VERSION}-alpine \
      ./generate-protos.sh
    
    # Clean up
    rm -f $INSTALL_DIR/generate-protos.sh
    
    print_info "Proto files generated successfully"
  else
    print_warning "No proto files or Makefile proto target found, skipping proto generation"
  fi
fi

# ========================================
# PHASE 3: Environment Configuration
# ========================================
print_info "Phase 3: Environment Configuration"

print_step "Creating production environment file..."
if [ ! -f "$INSTALL_DIR/.env.docker" ]; then
  cat > $INSTALL_DIR/.env.docker << EOF
# Wise Owl Production Configuration
# Generated on: $(date)
# Service: Japanese Vocabulary Learning Platform

# MongoDB Configuration (for mongodb service initialization)
MONGO_INITDB_ROOT_USERNAME=wiseowl_admin
MONGO_INITDB_ROOT_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)

# MongoDB Connection (for application services)
MONGO_USERNAME=\${MONGO_INITDB_ROOT_USERNAME}
MONGO_PASSWORD=\${MONGO_INITDB_ROOT_PASSWORD}
MONGO_HOST=mongodb
MONGO_PORT=27017

# JWT Configuration for authentication
JWT_SECRET=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)

# Service Configuration
SERVICE_ENV=production
LOG_LEVEL=info

# Auth0 Configuration (optional - leave empty if not using)
AUTH0_DOMAIN=
AUTH0_AUDIENCE=

# CORS Configuration
CORS_ALLOWED_ORIGINS=https://wise-owl.yourdomain.com

# Database Names (set per service in docker-compose.yml)
# users-service uses: DB_NAME=users_db
# content-service uses: DB_NAME=content_db  
# quiz-service uses: DB_NAME=quiz_db

# Service Ports (internal container ports)
USERS_HTTP_PORT=8080
USERS_GRPC_PORT=50051
CONTENT_HTTP_PORT=8080
CONTENT_GRPC_PORT=50052
QUIZ_HTTP_PORT=8080
QUIZ_GRPC_PORT=50053

# API Gateway (nginx external port)
NGINX_PORT=8080
EOF
  
  chmod 600 $INSTALL_DIR/.env.docker
  sudo chown $DEPLOY_USER:$DEPLOY_USER $INSTALL_DIR/.env.docker
  
  print_warning "Environment file created at $INSTALL_DIR/.env.docker"
  print_warning "Please update AUTH0 and domain settings if needed"
fi

# ========================================
# PHASE 4: Production Configuration
# ========================================
print_info "Phase 4: Production Configuration"

print_step "Creating docker-compose.prod.yml..."
if [ ! -f "docker-compose.prod.yml" ] && [ -f "docker-compose.yml" ]; then
  cp docker-compose.yml docker-compose.prod.yml
  
  # Update for production (replace build contexts with pre-built images)
  # Update users-service
  sed -i '/users-service:/,/depends_on:/s/build:/# build:/' docker-compose.prod.yml
  sed -i '/users-service:/,/depends_on:/s/context: \./# context: \./' docker-compose.prod.yml
  sed -i '/users-service:/,/depends_on:/s/dockerfile: \.\/services\/users\/Dockerfile/# dockerfile: \.\/services\/users\/Dockerfile/' docker-compose.prod.yml
  sed -i '/users-service:/,/depends_on:/s/# build:/image: wo-users-service:latest/' docker-compose.prod.yml
  
  # Update content-service
  sed -i '/content-service:/,/depends_on:/s/build:/# build:/' docker-compose.prod.yml
  sed -i '/content-service:/,/depends_on:/s/context: \./# context: \./' docker-compose.prod.yml
  sed -i '/content-service:/,/depends_on:/s/dockerfile: \.\/services\/content\/Dockerfile/# dockerfile: \.\/services\/content\/Dockerfile/' docker-compose.prod.yml
  sed -i '/content-service:/,/depends_on:/s/# build:/image: wo-content-service:latest/' docker-compose.prod.yml
  
  # Update quiz-service
  sed -i '/quiz-service:/,/depends_on:/s/build:/# build:/' docker-compose.prod.yml
  sed -i '/quiz-service:/,/depends_on:/s/context: \./# context: \./' docker-compose.prod.yml
  sed -i '/quiz-service:/,/depends_on:/s/dockerfile: \.\/services\/quiz\/Dockerfile/# dockerfile: \.\/services\/quiz\/Dockerfile/' docker-compose.prod.yml
  sed -i '/quiz-service:/,/depends_on:/s/# build:/image: wo-quiz-service:latest/' docker-compose.prod.yml
  
  print_info "Created docker-compose.prod.yml with image references"
fi

# ========================================
# PHASE 5: Build Services
# ========================================
print_info "Phase 5: Building Wise Owl Services"

print_step "Building services for ARM64..."
services=("users" "content" "quiz")

for service in "${services[@]}"; do
  print_step "Building $service service..."
  
  # Build with context from root directory and service-specific Dockerfile
  $RUN_AS docker build \
    --platform linux/arm64 \
    -t wo-$service-service:latest \
    -f ./services/$service/Dockerfile \
    .
done

# Note: nginx uses the standard nginx:stable-alpine image with custom config volume

# ========================================
# PHASE 6: Production Scripts
# ========================================
print_info "Phase 6: Setting up production scripts"

# Ensure scripts are executable
chmod +x $INSTALL_DIR/*.sh 2>/dev/null || true

# Create systemd service for Wise Owl
print_step "Creating systemd service..."
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

# ========================================
# PHASE 7: Cron Jobs for Wise Owl
# ========================================
print_info "Phase 7: Setting up automated tasks"

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

# ========================================
# PHASE 8: Initial Data Preparation
# ========================================
print_info "Phase 8: Data Seeding Preparation"

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
# PHASE 9: Health Check Script
# ========================================
print_info "Phase 9: Creating health check script"

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
echo "✅ Repository cloned and configured"
echo "✅ Protocol buffers generated using Docker"
echo "✅ Production environment configured"  
echo "✅ Docker services built for ARM64"
echo "✅ Systemd service configured"
echo "✅ Automated tasks scheduled"
echo "✅ Health monitoring configured"
echo ""

echo -e "${YELLOW}=== Deployment Summary ===${NC}"
echo "Repository: $WISE_OWL_REPO"
echo "Branch: $BRANCH"
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
echo "Option 1: sudo systemctl start wise-owl"
echo "Option 2: cd $INSTALL_DIR && docker compose -f docker-compose.prod.yml up -d"
echo ""

echo -e "${BLUE}=== Monitoring ===${NC}"
echo "- Check status: docker compose -f docker-compose.prod.yml ps"
echo "- View logs: docker compose -f docker-compose.prod.yml logs [service-name]"
echo "- Health check: ./check-wise-owl.sh"
echo ""

echo -e "${YELLOW}=== Access Points ===${NC}"
echo "- API Gateway: http://$(hostname -I | awk '{print $1}'):8080"
echo "- All API endpoints are routed through nginx"
echo "- MongoDB: $(hostname -I | awk '{print $1}'):27017 (if external access needed)"
echo ""

echo -e "${GREEN}=== Important Notes ===${NC}"
echo "1. Content service will seed vocabulary entries on first start"
echo "2. Initial seeding may take 5-10 minutes"
echo "3. Check seeding progress: docker compose -f docker-compose.prod.yml logs wo-content-service"
echo "4. Update .env.docker with your Auth0 credentials if using authentication"
echo "5. Nginx config should be placed in ./nginx/ directory"
echo ""

echo -e "${BLUE}=== Next Steps ===${NC}"
echo "1. Review and update $INSTALL_DIR/.env.docker"
echo "2. Ensure nginx configuration exists in ./nginx/ directory"
echo "3. Start the services: sudo systemctl start wise-owl"
echo "4. Monitor initial vocabulary seeding"
echo "5. Set up CI/CD with GitHub Actions"
echo ""

print_info "Ready for production deployment with Japanese vocabulary learning! 🚀"