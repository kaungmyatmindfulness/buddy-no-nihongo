#!/bin/bash
# Production Deployment Dry Run Test
# This script simulates the production deployment flow to identify potential issues

set -e

# Load common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utils/common.sh"

show_banner "Production Deployment Dry Run"

# Configuration
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SETUP_SCRIPT="$SCRIPT_DIR/setup-raspberry-pi-generic.sh"
DEPLOY_SCRIPT="$SCRIPT_DIR/deploy-wise-owl.sh"
TEST_INSTALL_DIR="/tmp/wise-owl-test"

print_info "Testing production deployment flow in dry-run mode..."
echo ""

issues_found=0

# ========================================
# Phase 1: Pre-deployment Setup Simulation
# ========================================
print_step "Phase 1: Pre-deployment Setup Simulation"

# Test if we can create install directory structure
print_info "Testing directory creation..."
if mkdir -p "$TEST_INSTALL_DIR"/{backups,logs,data} 2>/dev/null; then
    print_success "✅ Can create deployment directories"
    rm -rf "$TEST_INSTALL_DIR"
else
    print_error "❌ Cannot create deployment directories"
    ((issues_found++))
fi

# Test Git repository URL accessibility (without cloning)
print_info "Testing repository accessibility..."
repo_url=$(grep "WISE_OWL_REPO=" "$DEPLOY_SCRIPT" | head -1 | cut -d'"' -f2)

# Check if SSH key is configured for GitHub
if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
    print_success "✅ SSH key configured for GitHub access"
elif ssh -T git@github.com 2>&1 | grep -q "Permission denied"; then
    print_warning "⚠️  SSH key not configured - deployment will require HTTPS or SSH setup"
else
    print_info "ℹ️  SSH connection test inconclusive (normal if not on target server)"
fi

# ========================================
# Phase 2: Docker Environment Test
# ========================================
print_step "Phase 2: Docker Environment Test"

if command -v docker >/dev/null 2>&1; then
    print_success "✅ Docker is available"
    
    # Test Docker Compose
    if docker compose version >/dev/null 2>&1; then
        compose_version=$(docker compose version --short)
        print_success "✅ Docker Compose v2 available: $compose_version"
        
        # Check if supports watch mode (for development)
        if echo "$compose_version" | grep -E '^2\.(2[2-9]|[3-9][0-9])' >/dev/null; then
            print_success "✅ Docker Compose supports watch mode"
        else
            print_warning "⚠️  Docker Compose version may not support watch mode"
        fi
    else
        print_warning "⚠️  Docker Compose v2 not available"
    fi
    
    # Test basic Docker functionality
    if docker info >/dev/null 2>&1; then
        print_success "✅ Docker daemon is running"
    else
        print_error "❌ Docker daemon is not running"
        ((issues_found++))
    fi
    
    # Test image pulling capability
    print_info "Testing Docker image access..."
    if docker pull hello-world >/dev/null 2>&1; then
        print_success "✅ Can pull Docker images"
        docker rmi hello-world >/dev/null 2>&1
    else
        print_warning "⚠️  Cannot pull Docker images (may need registry access)"
    fi
else
    print_error "❌ Docker not available"
    ((issues_found++))
fi

# ========================================
# Phase 3: Build Environment Test
# ========================================
print_step "Phase 3: Build Environment Test"

# Test if we can build the services
print_info "Testing Docker build capability..."

# Create a temporary minimal Dockerfile to test build
temp_dockerfile=$(mktemp)
cat > "$temp_dockerfile" << 'EOF'
FROM golang:1.21-alpine
WORKDIR /app
COPY go.work .
RUN echo "Build test successful"
EOF

if docker build -f "$temp_dockerfile" -t wise-owl-build-test "$PROJECT_ROOT" >/dev/null 2>&1; then
    print_success "✅ Docker build environment working"
    docker rmi wise-owl-build-test >/dev/null 2>&1
else
    print_warning "⚠️  Docker build test failed - may need dependencies"
fi

rm -f "$temp_dockerfile"

# Test protobuf generation capability
print_info "Testing protobuf generation..."
if command -v protoc >/dev/null 2>&1; then
    print_success "✅ protoc available locally"
elif docker run --rm golang:1.21-alpine sh -c "apk add --no-cache protobuf-dev && protoc --version" >/dev/null 2>&1; then
    print_success "✅ protoc available via Docker"
else
    print_warning "⚠️  protoc generation may fail - will use Docker fallback"
fi

# ========================================
# Phase 4: Network and Port Availability
# ========================================
print_step "Phase 4: Network and Port Availability Test"

# Check required ports
required_ports=(8080 8081 8082 8083 27017 9090 3000)
for port in "${required_ports[@]}"; do
    if lsof -i ":$port" >/dev/null 2>&1; then
        print_warning "⚠️  Port $port is in use"
    else
        print_success "✅ Port $port is available"
    fi
done

# Test Docker network creation
print_info "Testing Docker network capability..."
test_network="wise-owl-test-$$"
if docker network create "$test_network" >/dev/null 2>&1; then
    print_success "✅ Can create Docker networks"
    docker network rm "$test_network" >/dev/null 2>&1
else
    print_error "❌ Cannot create Docker networks"
    ((issues_found++))
fi

# ========================================
# Phase 5: Environment Configuration Test
# ========================================
print_step "Phase 5: Environment Configuration Test"

# Test environment file creation
temp_env=$(mktemp)
cat > "$temp_env" << 'EOF'
MONGO_INITDB_ROOT_USERNAME=test_user
MONGO_INITDB_ROOT_PASSWORD=test_password
MONGODB_URI=mongodb://test_user:test_password@mongodb:27017/?authSource=admin
JWT_SECRET=test_secret
EOF

if [ -f "$temp_env" ] && grep -q "MONGO_INITDB_ROOT_USERNAME" "$temp_env"; then
    print_success "✅ Environment file creation works"
else
    print_error "❌ Environment file creation failed"
    ((issues_found++))
fi

rm -f "$temp_env"

# ========================================
# Phase 6: Service Configuration Test
# ========================================
print_step "Phase 6: Service Configuration Test"

# Test MongoDB initialization
print_info "Testing MongoDB container startup..."
mongo_test_container="mongo-test-$$"
if docker run --name "$mongo_test_container" -d \
    -e MONGO_INITDB_ROOT_USERNAME=test \
    -e MONGO_INITDB_ROOT_PASSWORD=test \
    mongo:latest >/dev/null 2>&1; then
    
    # Wait for startup
    sleep 5
    
    if docker exec "$mongo_test_container" mongosh --quiet --eval "db.adminCommand('ping')" >/dev/null 2>&1; then
        print_success "✅ MongoDB container startup and connection works"
    else
        print_warning "⚠️  MongoDB container started but connection test failed"
    fi
    
    docker stop "$mongo_test_container" >/dev/null 2>&1
    docker rm "$mongo_test_container" >/dev/null 2>&1
else
    print_error "❌ MongoDB container test failed"
    ((issues_found++))
fi

# ========================================
# Phase 7: Monitoring Stack Test
# ========================================
print_step "Phase 7: Monitoring Stack Test"

# Test if monitoring images are accessible
monitoring_images=("prom/prometheus:v2.45.0" "grafana/grafana:10.0.0" "nginx:stable-alpine")
for image in "${monitoring_images[@]}"; do
    if docker inspect "$image" >/dev/null 2>&1 || docker pull "$image" >/dev/null 2>&1; then
        print_success "✅ $image is accessible"
    else
        print_warning "⚠️  $image may not be accessible"
    fi
done

# ========================================
# Phase 8: Deployment Script Validation
# ========================================
print_step "Phase 8: Deployment Script Validation"

# Check if scripts have correct permissions
if [ -x "$SETUP_SCRIPT" ] && [ -x "$DEPLOY_SCRIPT" ]; then
    print_success "✅ Deployment scripts are executable"
else
    print_error "❌ Deployment scripts are not executable"
    ((issues_found++))
fi

# Check for required system tools in deployment scripts
required_tools=("git" "docker" "systemctl" "openssl" "jq")
for tool in "${required_tools[@]}"; do
    if command -v "$tool" >/dev/null 2>&1; then
        print_success "✅ $tool is available"
    else
        print_warning "⚠️  $tool not found - may be installed during server setup"
    fi
done

# ========================================
# Phase 9: Security Configuration Test
# ========================================
print_step "Phase 9: Security Configuration Test"

# Check if we can generate secure passwords/secrets
if openssl rand -base64 32 >/dev/null 2>&1; then
    print_success "✅ Can generate secure passwords"
else
    print_error "❌ Cannot generate secure passwords"
    ((issues_found++))
fi

# Test firewall rule creation (if available)
if command -v ufw >/dev/null 2>&1; then
    print_success "✅ UFW firewall is available"
elif command -v iptables >/dev/null 2>&1; then
    print_success "✅ iptables is available"
else
    print_warning "⚠️  No firewall tools detected"
fi

# ========================================
# Summary and Recommendations
# ========================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ $issues_found -eq 0 ]; then
    print_success "✅ Production Deployment Dry Run PASSED"
    print_info "The environment is ready for production deployment"
else
    print_warning "⚠️  Production Deployment Dry Run completed with $issues_found critical issue(s)"
    print_info "These issues should be resolved before attempting production deployment"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
print_info "🎯 Production Deployment Readiness:"
echo ""

if [ $issues_found -eq 0 ]; then
    echo "🟢 Ready for production deployment"
    echo ""
    print_info "Next steps:"
    echo "1. 🔧 Run server setup: sudo $SETUP_SCRIPT"
    echo "2. 🚀 Deploy application: $DEPLOY_SCRIPT"  
    echo "3. 🔍 Verify deployment: ./check-wise-owl.sh"
    echo "4. 📊 Start monitoring: ./wise-owl monitor start"
else
    echo "🟡 Needs attention before production deployment"
    echo ""
    print_info "Recommendations:"
    echo "• Review and resolve the critical issues found above"
    echo "• Ensure Docker and Docker Compose are properly installed"
    echo "• Verify network connectivity and port availability"
    echo "• Check system requirements and dependencies"
fi

echo ""
print_info "📋 Deployment Checklist:"
echo "☐ Server meets minimum requirements (2GB RAM, 20GB disk)"
echo "☐ Docker and Docker Compose installed"
echo "☐ SSH key configured for GitHub access"
echo "☐ Required ports available (8080, 27017, 9090, 3000)"
echo "☐ Firewall and security tools available"
echo "☐ SSL certificates configured (for production domain)"
echo "☐ Backup strategy planned"
echo "☐ Monitoring and alerting configured"

exit $issues_found
