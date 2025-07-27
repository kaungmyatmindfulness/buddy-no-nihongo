#!/bin/bash
# Production Flow Verification Script
# This script checks the complete production deployment flow for issues

set -e

# Load common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utils/common.sh"

show_banner "Production Flow Verification"

# Configuration
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SETUP_SCRIPT="$SCRIPT_DIR/setup-raspberry-pi-generic.sh"
DEPLOY_SCRIPT="$SCRIPT_DIR/deploy-wise-owl.sh"

print_info "Checking production deployment flow for Wise Owl..."
echo ""

# ========================================
# Phase 1: Script Validation
# ========================================
print_step "Phase 1: Script Validation"

issues_found=0

# Check if scripts exist and are executable
scripts_to_check=(
    "$SETUP_SCRIPT"
    "$DEPLOY_SCRIPT" 
    "$PROJECT_ROOT/wise-owl"
    "$SCRIPT_DIR/../utils/common.sh"
    "$SCRIPT_DIR/../development/dev.sh"
)

for script in "${scripts_to_check[@]}"; do
    if [ -f "$script" ]; then
        if [ -x "$script" ]; then
            print_success "✅ $script exists and is executable"
        else
            print_warning "⚠️  $script exists but is not executable"
            ((issues_found++))
        fi
    else
        print_error "❌ $script not found"
        ((issues_found++))
    fi
done

# ========================================
# Phase 2: Repository Configuration
# ========================================
print_step "Phase 2: Repository Configuration Validation"

# Check repository URL in deploy script
repo_url=$(grep "WISE_OWL_REPO=" "$DEPLOY_SCRIPT" | head -1 | cut -d'"' -f2)
print_info "Repository URL: $repo_url"

# Validate Git URL format
if [[ "$repo_url" =~ ^git@github.com:.+/.+\.git$ ]]; then
    print_success "✅ Repository URL format is valid (SSH)"
elif [[ "$repo_url" =~ ^https://github.com/.+/.+ ]]; then
    print_success "✅ Repository URL format is valid (HTTPS)"
else
    print_error "❌ Invalid repository URL format"
    ((issues_found++))
fi

# Check branch configuration
branch=$(grep "BRANCH=" "$DEPLOY_SCRIPT" | head -1 | cut -d'"' -f2 | sed 's/\${BRANCH:-//' | sed 's/}//')
print_info "Target branch: ${branch:-master}"

# ========================================
# Phase 3: Docker Configuration Files
# ========================================
print_step "Phase 3: Docker Configuration Validation"

# Check docker-compose files
compose_files=(
    "$PROJECT_ROOT/docker-compose.yml"
    "$PROJECT_ROOT/docker-compose.dev.yml"
    "$PROJECT_ROOT/docker-compose.monitoring.yml"
)

for compose_file in "${compose_files[@]}"; do
    if [ -f "$compose_file" ]; then
        print_success "✅ $(basename "$compose_file") exists"
        
        # Validate YAML syntax (skip monitoring as it depends on main services)
        if command -v docker >/dev/null 2>&1 && [[ "$(basename "$compose_file")" != "docker-compose.monitoring.yml" ]]; then
            # Create temporary env files if needed for validation
            temp_env_files=()
            if [[ "$(basename "$compose_file")" == "docker-compose.yml" ]] && [ ! -f ".env.docker" ]; then
                cp .env.example .env.docker
                temp_env_files+=(".env.docker")
            elif [[ "$(basename "$compose_file")" == "docker-compose.dev.yml" ]] && [ ! -f ".env.local" ]; then
                cp .env.example .env.local
                temp_env_files+=(".env.local")
            fi
            
            if docker compose -f "$compose_file" config >/dev/null 2>&1; then
                print_success "✅ $(basename "$compose_file") has valid syntax"
            else
                print_error "❌ $(basename "$compose_file") has invalid YAML syntax"
                ((issues_found++))
            fi
            
            # Clean up temporary files
            for temp_file in "${temp_env_files[@]}"; do
                rm -f "$temp_file"
            done
        else
            print_success "✅ $(basename "$compose_file") syntax check skipped (monitoring or no docker)"
        fi
    else
        print_error "❌ $(basename "$compose_file") not found"
        ((issues_found++))
    fi
done

# ========================================
# Phase 4: Service Dockerfiles
# ========================================
print_step "Phase 4: Service Dockerfiles Validation"

services=("users" "content" "quiz")
for service in "${services[@]}"; do
    dockerfile="$PROJECT_ROOT/services/$service/Dockerfile"
    dockerfile_dev="$PROJECT_ROOT/services/$service/Dockerfile.dev"
    
    if [ -f "$dockerfile" ]; then
        print_success "✅ $service/Dockerfile exists"
    else
        print_error "❌ $service/Dockerfile not found"
        ((issues_found++))
    fi
    
    if [ -f "$dockerfile_dev" ]; then
        print_success "✅ $service/Dockerfile.dev exists"
    else
        print_warning "⚠️  $service/Dockerfile.dev not found (optional for production)"
    fi
done

# ========================================
# Phase 5: Environment Configuration
# ========================================
print_step "Phase 5: Environment Configuration Validation"

# Check environment templates
env_files=(
    "$PROJECT_ROOT/.env.example"
    "$PROJECT_ROOT/.env.monitoring.example"
)

for env_file in "${env_files[@]}"; do
    if [ -f "$env_file" ]; then
        print_success "✅ $(basename "$env_file") exists"
        
        # Check for required variables
        required_vars=("MONGO_INITDB_ROOT_USERNAME" "MONGO_INITDB_ROOT_PASSWORD")
        for var in "${required_vars[@]}"; do
            if grep -q "^${var}=" "$env_file"; then
                print_success "✅ $var found in $(basename "$env_file")"
            else
                print_warning "⚠️  $var not found in $(basename "$env_file")"
            fi
        done
    else
        print_error "❌ $(basename "$env_file") not found"
        ((issues_found++))
    fi
done

# ========================================
# Phase 6: Nginx Configuration
# ========================================
print_step "Phase 6: Nginx Configuration Validation"

nginx_config="$PROJECT_ROOT/nginx/default.conf"
if [ -f "$nginx_config" ]; then
    print_success "✅ Nginx configuration exists"
    
    # Check for service upstreams
    services_to_check=("users_service" "content_service" "quiz_service")
    for service in "${services_to_check[@]}"; do
        if grep -q "upstream $service" "$nginx_config"; then
            print_success "✅ $service upstream configured"
        else
            print_error "❌ $service upstream not found in nginx config"
            ((issues_found++))
        fi
    done
    
    # Check for API routes
    api_routes=("/api/v1/users/" "/api/v1/content/" "/api/v1/quiz/")
    for route in "${api_routes[@]}"; do
        if grep -q "location $route" "$nginx_config"; then
            print_success "✅ $route configured"
        else
            print_error "❌ $route not found in nginx config"
            ((issues_found++))
        fi
    done
else
    print_error "❌ Nginx configuration not found"
    ((issues_found++))
fi

# ========================================
# Phase 7: Proto/gRPC Configuration
# ========================================
print_step "Phase 7: Protocol Buffers Validation"

proto_dir="$PROJECT_ROOT/proto"
gen_dir="$PROJECT_ROOT/gen"

if [ -d "$proto_dir" ]; then
    print_success "✅ Proto directory exists"
    
    # Check for proto files
    proto_files=$(find "$proto_dir" -name "*.proto" 2>/dev/null | wc -l)
    if [ "$proto_files" -gt 0 ]; then
        print_success "✅ Found $proto_files proto file(s)"
    else
        print_warning "⚠️  No proto files found"
    fi
else
    print_warning "⚠️  Proto directory not found"
fi

if [ -d "$gen_dir" ]; then
    print_success "✅ Generated code directory exists"
else
    print_warning "⚠️  Generated code directory not found (will be created during deployment)"
fi

# ========================================
# Phase 8: Go Workspace Configuration
# ========================================
print_step "Phase 8: Go Workspace Validation"

go_work="$PROJECT_ROOT/go.work"
if [ -f "$go_work" ]; then
    print_success "✅ go.work file exists"
    
    # Check workspace modules
    expected_modules=("./lib" "./gen" "./services/users" "./services/content" "./services/quiz")
    for module in "${expected_modules[@]}"; do
        if grep -q "$module" "$go_work"; then
            print_success "✅ $module included in workspace"
        else
            print_warning "⚠️  $module not found in workspace"
        fi
    done
else
    print_error "❌ go.work file not found"
    ((issues_found++))
fi

# Check individual service go.mod files
for service in "${services[@]}"; do
    go_mod="$PROJECT_ROOT/services/$service/go.mod"
    if [ -f "$go_mod" ]; then
        print_success "✅ $service/go.mod exists"
    else
        print_error "❌ $service/go.mod not found"
        ((issues_found++))
    fi
done

# ========================================
# Phase 9: Deployment Script Analysis
# ========================================
print_step "Phase 9: Deployment Script Logic Validation"

# Check for critical deployment phases in deploy script
deployment_phases=(
    "Pre-flight Checks"
    "Repository Setup"
    "Proto Generation"
    "Environment Configuration"
    "Production Configuration"
    "Building Wise Owl Services"
    "Production Scripts"
    "Cron Jobs"
    "Health Check Script"
)

for phase in "${deployment_phases[@]}"; do
    if grep -q "$phase" "$DEPLOY_SCRIPT"; then
        print_success "✅ $phase found in deployment script"
    else
        print_warning "⚠️  $phase not found in deployment script"
    fi
done

# Check for systemd service creation
if grep -q "systemd service" "$DEPLOY_SCRIPT"; then
    print_success "✅ Systemd service configuration found"
else
    print_warning "⚠️  Systemd service configuration not found"
fi

# ========================================
# Phase 10: Security Configuration
# ========================================
print_step "Phase 10: Security Configuration Validation"

# Check setup script for security measures
security_features=(
    "ufw"
    "fail2ban" 
    "SSH key authentication"
    "user creation"
    "firewall"
)

for feature in "${security_features[@]}"; do
    if grep -qi "$feature" "$SETUP_SCRIPT"; then
        print_success "✅ $feature configuration found"
    else
        print_warning "⚠️  $feature configuration not found"
    fi
done

# ========================================
# Summary and Recommendations
# ========================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ $issues_found -eq 0 ]; then
    print_success "✅ Production Flow Validation PASSED"
    print_info "All critical components are in place for production deployment"
else
    print_warning "⚠️  Production Flow Validation completed with $issues_found issue(s)"
    print_info "Some issues were found that should be addressed before production deployment"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
print_info "Production Deployment Process:"
echo "1. 🔧 Server Setup: sudo $SETUP_SCRIPT"
echo "2. 🚀 Application Deployment: $DEPLOY_SCRIPT"
echo "3. 🔍 Health Check: ./check-wise-owl.sh"
echo "4. 📊 Monitoring: ./wise-owl monitor start"

echo ""
print_info "Quick Start Commands:"
echo "# Development:"
echo "./wise-owl dev start"
echo ""
echo "# Production Setup:"
echo "sudo ./scripts/deployment/setup-raspberry-pi-generic.sh"
echo "./scripts/deployment/deploy-wise-owl.sh"
echo ""
echo "# Check Status:"
echo "./scripts/deployment/check-production-flow.sh"

exit $issues_found
