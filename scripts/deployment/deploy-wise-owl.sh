#!/bin/bash
# filepath: /opt/deploy-wise-owl.sh
# Wise Owl Deployment Script for Prepared Raspberry Pi
# Run this after setup-raspberry-pi-generic.sh
# Assumes the repository is already cloned

set -e

# Configuration
INSTALL_DIR="$(pwd)"  # Use current directory as install directory
CURRENT_USER="$(whoami)"
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

# Check if running as root
if [ "$EUID" -eq 0 ]; then 
  print_warning "Running as root, operations will run as root user"
  RUN_AS=""
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
  chown -R $CURRENT_USER $INSTALL_DIR 2>/dev/null || true
else
  # On Linux (Pi), create directories and set ownership to current user
  mkdir -p $INSTALL_DIR/{backups,logs,data}
  if [ "$EUID" -eq 0 ]; then
    chown -R $CURRENT_USER:$CURRENT_USER $INSTALL_DIR
  fi
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
User=$CURRENT_USER
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
else
  echo "✅ Systemd service configured"
fi
echo ""

echo -e "${YELLOW}=== Deployment Summary ===${NC}"
echo "Install Dir: $INSTALL_DIR"
echo "Current User: $CURRENT_USER"
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
echo "1. Update .env.docker with your Auth0 credentials if using authentication"
echo "2. Nginx config should be placed in ./nginx/ directory"
echo ""

echo -e "${BLUE}=== Next Steps ===${NC}"
if [ "$IS_MAC" = true ]; then
  echo "1. Ensure .env.docker file exists with proper configuration"
  echo "2. Ensure nginx configuration exists in ./nginx/ directory"
  echo "3. Start the services: docker compose -f docker-compose.prod.yml up -d"
else
  echo "1. Review and update $INSTALL_DIR/.env.docker"
  echo "2. Ensure nginx configuration exists in ./nginx/ directory"
  echo "3. Start the services: sudo systemctl start wise-owl"
  echo "4. Set up CI/CD with GitHub Actions"
fi
echo ""

print_info "Ready for production deployment with Japanese vocabulary learning! 🚀"