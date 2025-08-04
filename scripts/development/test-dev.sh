#!/bin/bash
# Development Environment Test Script

set -e

# Load common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utils/common.sh"

# Test configuration
SERVICES=(
    "Users:8081:/health/"
    "Content:8082:/health/"
    "Quiz:8083:/health/"
)
GATEWAY_URL="http://localhost:8080/health-check"
GATEWAY_HEALTH_ROUTES=(
    "users:http://localhost:8080/api/v1/users/health"
    "content:http://localhost:8080/api/v1/content/health"
    "quiz:http://localhost:8080/api/v1/quiz/health"
)

test_service() {
    local name=$1
    local port=$2
    local endpoint=$3
    local url="http://localhost:${port}${endpoint}"
    
    if curl -s "$url" > /dev/null 2>&1; then
        print_success "$name service is healthy on port $port"
        return 0
    else
        print_warning "$name service may not be ready yet on port $port"
        return 1
    fi
}

test_gateway() {
    if curl -s "$GATEWAY_URL" > /dev/null 2>&1; then
        print_success "Nginx gateway is responding"
        return 0
    else
        print_warning "Nginx gateway may not be ready yet"
        return 1
    fi
}

test_gateway_routing() {
    local failed_routes=0
    print_info "Testing gateway routing..."
    
    for route in "${GATEWAY_HEALTH_ROUTES[@]}"; do
        IFS=':' read -r service_name url <<< "$route"
        
        if curl -s "$url" > /dev/null 2>&1; then
            print_success "Gateway routing to $service_name service working"
        else
            print_warning "Gateway routing to $service_name service may have issues"
            ((failed_routes++))
        fi
    done
    
    return $failed_routes
}

main() {
    show_banner "Development Environment Health Check"
    
    print_info "Testing development services..."
    
    local failed_services=0
    
    # Test all microservices
    for service in "${SERVICES[@]}"; do
        IFS=':' read -r name port endpoint <<< "$service"
        
        if ! test_service "$name" "$port" "$endpoint"; then
            ((failed_services++))
        fi
    done
    
    # Test nginx gateway
    if ! test_gateway; then
        ((failed_services++))
    fi
    
    # Test gateway routing to services
    if ! test_gateway_routing; then
        print_warning "Some gateway routing may have issues"
    fi
    
    echo ""
    if [ $failed_services -eq 0 ]; then
        print_success "All services are healthy! ✨"
    else
        print_warning "$failed_services service(s) may have issues"
    fi
    
    echo ""
    print_info "Development commands:"
    echo "  ./scripts/development/dev.sh logs     - View logs"
    echo "  ./scripts/development/dev.sh stop     - Stop services"
    echo "  ./scripts/development/dev.sh status   - Show service status"
    
    return $failed_services
}

main "$@"
