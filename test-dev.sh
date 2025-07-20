#!/bin/bash
# Simple Development Test Script

set -e

print_status() {
    echo "✅ $1"
}

print_warning() {
    echo "⚠️  $1"
}

main() {
    echo "🔍 Testing development services..."
    
    # Test all services
    for service in "Users:8081" "Content:8082" "Quiz:8083"; do
        name=$(echo $service | cut -d: -f1)
        port=$(echo $service | cut -d: -f2)
        
        if curl -s "http://localhost:$port/health" > /dev/null 2>&1; then
            print_status "$name service is healthy on port $port"
        else
            print_warning "$name service may not be ready yet on port $port"
        fi
    done
    
    # Test nginx gateway
    if curl -s "http://localhost" > /dev/null 2>&1; then
        print_status "Nginx gateway is responding"
    else
        print_warning "Nginx gateway may not be ready yet"
    fi
    
    echo "✅ Health check complete!"
    echo "📋 Commands:"
    echo "  ./dev.sh logs     - View logs"
    echo "  ./dev.sh stop     - Stop services"
}

main "$@"
