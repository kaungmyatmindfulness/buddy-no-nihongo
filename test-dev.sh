#!/bin/bash
# Test script to verify the development environment is working

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[TEST]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Test if services are running
test_service() {
    local service_name=$1
    local port=$2
    local endpoint=${3:-"/health"}
    
    print_status "Testing $service_name on port $port..."
    
    if curl -s -f "http://localhost:$port$endpoint" > /dev/null 2>&1; then
        print_status "✅ $service_name is responding"
        return 0
    else
        print_error "❌ $service_name is not responding on port $port"
        return 1
    fi
}

# Test MongoDB
test_mongodb() {
    print_status "Testing MongoDB connection..."
    
    if docker exec wo-mongodb-dev mongosh --eval "db.adminCommand('ping')" > /dev/null 2>&1; then
        print_status "✅ MongoDB is responding"
        return 0
    else
        print_error "❌ MongoDB is not responding"
        return 1
    fi
}

# Main test flow
main() {
    print_status "Starting development environment health check..."
    
    # Check if containers are running
    if ! docker-compose -f docker-compose.dev.yml ps | grep -q "Up"; then
        print_error "Development environment is not running. Start it with: ./dev.sh start"
        exit 1
    fi
    
    # Test MongoDB
    if ! test_mongodb; then
        print_warning "MongoDB test failed"
    fi
    
    # Test services (adjust endpoints based on your actual health check endpoints)
    failed_tests=0
    
    # Test if services are accessible (they might not have health endpoints yet)
    for service in "Users:8081" "Content:8082" "Quiz:8083"; do
        name=$(echo $service | cut -d: -f1)
        port=$(echo $service | cut -d: -f2)
        
        if curl -s "http://localhost:$port" > /dev/null 2>&1; then
            print_status "✅ $name service is responding on port $port"
        else
            print_warning "⚠️  $name service may not be ready yet on port $port"
        fi
    done
    
    # Test nginx gateway
    if curl -s "http://localhost" > /dev/null 2>&1; then
        print_status "✅ Nginx gateway is responding"
    else
        print_warning "⚠️  Nginx gateway may not be ready yet"
    fi
    
    print_status "Health check complete!"
    print_status "View logs with: ./dev.sh logs"
    print_status "Stop services with: ./dev.sh stop"
}

main "$@"
