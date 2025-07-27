#!/bin/bash
# Development Environment Test Script

set -e

# Load common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utils/common.sh"

# Test configuration
SERVICES=(
    "Users:8081:/health"
    "Content:8082:/health"
    "Quiz:8083:/health"
)
GATEWAY_URL="http://localhost:8080/health-check"

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
