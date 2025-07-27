#!/bin/bash
# Development Helper Script for Wise Owl Golang Microservices

set -e

# Load common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utils/common.sh"

# Project configuration
PROJECT_ROOT=$(get_project_root)
COMPOSE_FILE="$PROJECT_ROOT/docker-compose.dev.yml"
ENV_FILE="$PROJECT_ROOT/.env.local"
ENV_EXAMPLE="$PROJECT_ROOT/.env.example"

# Functions
print_usage() {
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  setup     - Initial setup (create .env.local from example)"
    echo "  start     - Start all services in development mode"
    echo "  stop      - Stop all services"
    echo "  restart   - Restart all services"
    echo "  logs      - Show logs for all services"
    echo "  logs [service] - Show logs for specific service"
    echo "  build     - Rebuild all development containers"
    echo "  clean     - Stop and remove all containers and volumes"
    echo "  status    - Show status of all services"
    echo ""
    echo "Available services: nginx, users-service, content-service, quiz-service, mongodb"
}

check_prerequisites() {
    check_docker || exit 1
    
    if [ ! -f "$ENV_FILE" ] && [ "$1" != "setup" ]; then
        print_warning ".env.local not found. Run: $0 setup"
        exit 1
    fi
}

setup_environment() {
    print_info "Setting up development environment..."
    
    if [ ! -f "$ENV_FILE" ]; then
        if [ ! -f "$ENV_EXAMPLE" ]; then
            print_error "Environment example file not found: $ENV_EXAMPLE"
            exit 1
        fi
        
        cp "$ENV_EXAMPLE" "$ENV_FILE"
        print_success "Created .env.local from example"
        print_info "Please edit $ENV_FILE with your actual values"
    else
        print_warning ".env.local already exists. Not overwriting."
    fi
}

start_services() {
    print_info "Starting all services in development mode..."
    
    cd "$PROJECT_ROOT"
    local compose_cmd=$(get_docker_compose_cmd)
    
    $compose_cmd -f "$COMPOSE_FILE" up -d
    
    print_success "Services started! Access points:"
    echo "  - Nginx Gateway: http://localhost:8080"
    echo "  - Users Service: http://localhost:8081"
    echo "  - Content Service: http://localhost:8082"
    echo "  - Quiz Service: http://localhost:8083"
    echo "  - MongoDB: mongodb://localhost:27017"
}

stop_services() {
    print_info "Stopping all services..."
    
    cd "$PROJECT_ROOT"
    local compose_cmd=$(get_docker_compose_cmd)
    
    $compose_cmd -f "$COMPOSE_FILE" down
    print_success "Services stopped"
}

restart_services() {
    print_info "Restarting all services..."
    stop_services
    start_services
}

show_logs() {
    cd "$PROJECT_ROOT"
    local compose_cmd=$(get_docker_compose_cmd)
    
    if [ -n "$1" ]; then
        print_info "Showing logs for $1..."
        $compose_cmd -f "$COMPOSE_FILE" logs -f "$1"
    else
        print_info "Showing logs for all services..."
        $compose_cmd -f "$COMPOSE_FILE" logs -f
    fi
}

build_services() {
    print_info "Rebuilding all development containers..."
    
    cd "$PROJECT_ROOT"
    local compose_cmd=$(get_docker_compose_cmd)
    
    $compose_cmd -f "$COMPOSE_FILE" build --no-cache
    print_success "Build complete"
}

clean_services() {
    print_warning "This will stop and remove all containers and volumes!"
    read -p "Are you sure? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_info "Cleaning up..."
        
        cd "$PROJECT_ROOT"
        local compose_cmd=$(get_docker_compose_cmd)
        
        $compose_cmd -f "$COMPOSE_FILE" down -v --remove-orphans
        docker system prune -f
        
        print_success "Cleanup complete!"
    else
        print_info "Cancelled."
    fi
}

show_status() {
    print_info "Service status:"
    
    cd "$PROJECT_ROOT"
    local compose_cmd=$(get_docker_compose_cmd)
    
    $compose_cmd -f "$COMPOSE_FILE" ps
}

# Main script logic
main() {
    local command=$1
    shift || true
    
    case "$command" in
        "setup")
            setup_environment
            ;;
        "start")
            check_prerequisites "$command"
            start_services
            ;;
        "stop")
            check_prerequisites "$command"
            stop_services
            ;;
        "restart")
            check_prerequisites "$command"
            restart_services
            ;;
        "logs")
            check_prerequisites "$command"
            show_logs "$1"
            ;;
        "build")
            check_prerequisites "$command"
            build_services
            ;;
        "clean")
            check_prerequisites "$command"
            clean_services
            ;;
        "status")
            check_prerequisites "$command"
            show_status
            ;;
        *)
            print_usage
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"
