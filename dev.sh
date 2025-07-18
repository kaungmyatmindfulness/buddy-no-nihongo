#!/bin/bash
# Development Helper Script for Wise Owl Golang Microservices

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
print_usage() {
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  start     - Start all services in development mode"
    echo "  stop      - Stop all services"
    echo "  restart   - Restart all services"
    echo "  logs      - Show logs for all services"
    echo "  logs [service] - Show logs for specific service (nginx, users-service, content-service, quiz-service, mongodb)"
    echo "  build     - Rebuild all development containers"
    echo "  clean     - Stop and remove all containers and volumes"
    echo "  setup     - Initial setup (create .env.local from example)"
    echo ""
}

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_env() {
    if [ ! -f .env.local ]; then
        print_warning ".env.local not found. Please run: $0 setup"
        exit 1
    fi
}

case "$1" in
    "setup")
        print_info "Setting up development environment..."
        if [ ! -f .env.local ]; then
            cp .env.local.example .env.local
            print_info "Created .env.local from example. Please edit it with your actual values."
        else
            print_warning ".env.local already exists. Not overwriting."
        fi
        ;;
    
    "start")
        check_env
        print_info "Starting all services in development mode..."
        docker-compose -f docker-compose.dev.yml up -d
        print_info "Services started! Access points:"
        echo "  - Nginx Gateway: http://localhost"
        echo "  - Users Service: http://localhost:8081"
        echo "  - Content Service: http://localhost:8082"
        echo "  - Quiz Service: http://localhost:8083"
        echo "  - MongoDB: mongodb://localhost:27017"
        ;;
    
    "stop")
        print_info "Stopping all services..."
        docker-compose -f docker-compose.dev.yml down
        ;;
    
    "restart")
        check_env
        print_info "Restarting all services..."
        docker-compose -f docker-compose.dev.yml down
        docker-compose -f docker-compose.dev.yml up -d
        ;;
    
    "logs")
        if [ -n "$2" ]; then
            print_info "Showing logs for $2..."
            docker-compose -f docker-compose.dev.yml logs -f "$2"
        else
            print_info "Showing logs for all services..."
            docker-compose -f docker-compose.dev.yml logs -f
        fi
        ;;
    
    "build")
        check_env
        print_info "Rebuilding all development containers..."
        docker-compose -f docker-compose.dev.yml build --no-cache
        ;;
    
    "clean")
        print_warning "This will stop and remove all containers and volumes!"
        read -p "Are you sure? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_info "Cleaning up..."
            docker-compose -f docker-compose.dev.yml down -v --remove-orphans
            docker system prune -f
            print_info "Cleanup complete!"
        else
            print_info "Cancelled."
        fi
        ;;
    
    *)
        print_usage
        exit 1
        ;;
esac
