#!/bin/bash
# Wise Owl Development with Hot Reload
# This script starts all services with Docker Compose watch mode for automatic reloading

set -e

# Load common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utils/common.sh"

# Project configuration
PROJECT_ROOT=$(get_project_root)
COMPOSE_FILE="$PROJECT_ROOT/docker-compose.dev.yml"

show_banner "Development with Hot Reload"

print_info "Starting Wise Owl Development Environment with Hot Reload..."

# Check prerequisites
check_docker || exit 1

# Check if Docker Compose supports watch (requires Docker Compose 2.22+)
if ! supports_watch; then
    print_warning "Docker Compose watch requires version 2.22 or higher"
    print_info "Falling back to regular development mode..."
    
    cd "$PROJECT_ROOT"
    docker-compose -f "$COMPOSE_FILE" up --build
    exit 0
fi

# Create necessary directories
cd "$PROJECT_ROOT"
mkdir -p tmp

# Start services with watch mode for automatic rebuilds on file changes
print_info "Starting services with file watching enabled..."
print_info "File change behaviors:"
echo "   - Changes to service code will trigger automatic rebuilds"
echo "   - Changes to shared lib/ or gen/ will sync automatically"
echo "   - Changes to go.work will trigger full rebuilds"
echo ""

# Use Docker Compose watch mode
compose_cmd=$(get_docker_compose_cmd)
$compose_cmd -f "$COMPOSE_FILE" watch

print_success "Wise Owl Development Environment stopped."
