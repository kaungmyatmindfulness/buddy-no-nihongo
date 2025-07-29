#!/bin/bash
# Wise Owl Development Script - Main Entry Point
# This script provides easy access to development and monitoring scripts

set -e

# Load common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/scripts/utils/common.sh"

print_usage() {
    show_banner
    
    echo "Development and monitoring scripts for Wise Owl"
    echo ""
    echo "Usage: $0 <category> <command> [args...]"
    echo ""
    echo "Categories:"
    echo "  dev, development   - Development environment management"
    echo "  monitor, monitoring - Monitoring stack management"
    echo ""
    echo "Development Commands:"
    echo "  ./wise-owl dev setup     - Initial development setup"
    echo "  ./wise-owl dev start     - Start all services"
    echo "  ./wise-owl dev watch     - Start with hot reload"
    echo "  ./wise-owl dev stop      - Stop all services"
    echo "  ./wise-owl dev test      - Test service health"
    echo "  ./wise-owl dev logs      - Show service logs"
    echo "  ./wise-owl dev status    - Show service status"
    echo "  ./wise-owl dev clean     - Clean up containers and volumes"
    echo ""
    echo "Monitoring Commands:"
    echo "  ./wise-owl monitor start    - Start monitoring stack"
    echo "  ./wise-owl monitor stop     - Stop monitoring stack"
    echo "  ./wise-owl monitor status   - Show monitoring status"
    echo "  ./wise-owl monitor logs     - View monitoring logs"
    echo "  ./wise-owl monitor health   - Check service health"
    echo "  ./wise-owl monitor urls     - Show dashboard URLs"
    echo "  ./wise-owl monitor system   - System monitoring info"
    echo ""
    echo "Direct script access:"
    echo "  scripts/development/dev.sh         - Development management"
    echo "  scripts/development/dev-watch.sh   - Hot reload development"
    echo "  scripts/development/test-dev.sh    - Health check tests"
    echo "  monitoring/scripts/monitor-stack.sh - Monitoring management"
    echo "  monitoring/scripts/system-monitor.sh - System monitoring"
    echo ""
    echo "Note: Deployment scripts have been removed and will be added later."
}

# Main script routing
case "$1" in
    "dev"|"development")
        case "$2" in
            "watch")
                exec "$SCRIPT_DIR/scripts/development/dev-watch.sh" "${@:3}"
                ;;
            "test")
                exec "$SCRIPT_DIR/scripts/development/test-dev.sh" "${@:3}"
                ;;
            *)
                exec "$SCRIPT_DIR/scripts/development/dev.sh" "${@:2}"
                ;;
        esac
        ;;
    
    "monitor"|"monitoring")
        case "$2" in
            "system")
                exec "$SCRIPT_DIR/monitoring/scripts/system-monitor.sh" "${@:3}"
                ;;
            *)
                exec "$SCRIPT_DIR/monitoring/scripts/monitor-stack.sh" "${@:2}"
                ;;
        esac
        ;;
    
    "help"|"-h"|"--help"|"")
        print_usage
        ;;
    
    *)
        print_error "Unknown category: $1"
        print_info "Available categories: dev (development), monitor (monitoring)"
        print_usage
        exit 1
        ;;
esac
