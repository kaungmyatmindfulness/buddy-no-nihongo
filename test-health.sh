#!/bin/bash

# Health Check Testing Script
# This script demonstrates the enhanced health check features

set -e

echo "🏥 Enhanced Health Check Testing Script"
echo "========================================"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Function to test health endpoint
test_health_endpoint() {
    local service_name="$1"
    local port="$2"
    local endpoint="$3"
    
    echo ""
    print_info "Testing $service_name $endpoint endpoint on port $port"
    
    if curl -s -f "http://localhost:$port$endpoint" > /dev/null 2>&1; then
        print_status "$service_name $endpoint endpoint is healthy"
        
        # Show response with pretty formatting
        echo "Response:"
        curl -s "http://localhost:$port$endpoint" | jq '.' 2>/dev/null || curl -s "http://localhost:$port$endpoint"
    else
        print_warning "$service_name $endpoint endpoint may not be ready yet"
        
        # Show response even if it's an error for debugging
        echo "Response:"
        curl -s "http://localhost:$port$endpoint" 2>/dev/null || echo "No response received"
    fi
}

# Function to test all health endpoints for a service
test_all_endpoints() {
    local service_name="$1"
    local port="$2"
    
    echo ""
    echo "=================================================="
    print_info "Testing $service_name (port $port)"
    echo "=================================================="
    
    test_health_endpoint "$service_name" "$port" "/health"
    test_health_endpoint "$service_name" "$port" "/health/ready"
    test_health_endpoint "$service_name" "$port" "/health/live"
    test_health_endpoint "$service_name" "$port" "/health/metrics"
    test_health_endpoint "$service_name" "$port" "/health-legacy"
}

main() {
    echo ""
    print_info "Starting enhanced health check tests..."
    print_info "Make sure services are running with: ./dev.sh up"
    echo ""
    
    # Wait a moment for services to be ready
    sleep 2
    
    # Test all services
    test_all_endpoints "Users Service" "8081"
    test_all_endpoints "Content Service" "8082" 
    test_all_endpoints "Quiz Service" "8083"
    
    echo ""
    echo "=================================================="
    print_info "Testing Nginx Gateway Health Check"
    echo "=================================================="
    
    if curl -s "http://localhost/health-check" > /dev/null 2>&1; then
        print_status "Nginx gateway is responding"
    else
        print_warning "Nginx gateway may not be ready yet"
    fi
    
    echo ""
    echo "=================================================="
    print_info "Enhanced Health Check Features Demo"
    echo "=================================================="
    
    print_info "Circuit Breaker Testing:"
    echo "- Stop a service to see circuit breaker in action"
    echo "- Watch /health/metrics for circuit breaker state changes"
    echo ""
    
    print_info "Dependency Monitoring:"
    echo "- Quiz Service monitors Content Service dependency"
    echo "- Check /health/ready for detailed dependency status"
    echo ""
    
    print_info "Configuration Options:"
    echo "- Set HEALTH_CB_FAILURE_THRESHOLD to adjust circuit breaker sensitivity"
    echo "- Set HEALTH_DEFAULT_TIMEOUT to adjust health check timeouts"
    echo "- See .env.health.example for all configuration options"
    echo ""
    
    print_status "Enhanced health check testing complete!"
    print_info "Monitor logs with: ./dev.sh logs"
    print_info "Stop services with: ./dev.sh stop"
}

# Check if required tools are available
command -v curl >/dev/null 2>&1 || { print_error "curl is required but not installed. Aborting."; exit 1; }
command -v jq >/dev/null 2>&1 || print_warning "jq not found. JSON responses will not be formatted."

main "$@"
