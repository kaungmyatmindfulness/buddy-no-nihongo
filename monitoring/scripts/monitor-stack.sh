#!/bin/bash
# Wise Owl Monitoring Stack Management Script

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Check if we're in the right directory
check_project_root() {
    if [ ! -f "$PROJECT_ROOT/docker-compose.dev.yml" ]; then
        print_error "Please run this script from the Wise Owl project root directory"
        exit 1
    fi
}

# Start monitoring stack
start_monitoring() {
    print_info "Starting Wise Owl monitoring stack..."
    
    print_step "Creating monitoring network..."
    docker network create wo-monitoring 2>/dev/null || true
    
    print_step "Starting monitoring services..."
    cd "$PROJECT_ROOT"
    docker compose -f docker-compose.monitoring.yml up -d
    
    print_step "Waiting for services to be ready..."
    sleep 30
    
    print_step "Verifying service health..."
    check_monitoring_health
    
    print_info "✅ Monitoring stack started successfully!"
    show_access_urls
}

# Stop monitoring stack
stop_monitoring() {
    print_info "Stopping Wise Owl monitoring stack..."
    
    cd "$PROJECT_ROOT"
    docker compose -f docker-compose.monitoring.yml down
    
    print_info "✅ Monitoring stack stopped"
}

# Restart monitoring stack
restart_monitoring() {
    print_info "Restarting Wise Owl monitoring stack..."
    stop_monitoring
    sleep 5
    start_monitoring
}

# Check monitoring service health
check_monitoring_health() {
    local services=("prometheus:9090" "grafana:3000" "alertmanager:9093")
    local all_healthy=true
    
    for service in "${services[@]}"; do
        local name="${service%%:*}"
        local port="${service##*:}"
        
        if curl -s "http://localhost:$port" > /dev/null 2>&1; then
            echo -e "$name: ${GREEN}Healthy${NC}"
        else
            echo -e "$name: ${RED}Unhealthy${NC}"
            all_healthy=false
        fi
    done
    
    if [ "$all_healthy" = true ]; then
        print_info "All monitoring services are healthy"
    else
        print_warning "Some monitoring services are not responding"
    fi
}

# Show monitoring access URLs
show_access_urls() {
    local host_ip=$(hostname -I | awk '{print $1}')
    
    echo ""
    print_info "📊 Monitoring Dashboard Access:"
    echo "   Grafana:      http://${host_ip}:3000 (admin/admin)"
    echo "   Prometheus:   http://${host_ip}:9090"
    echo "   Alertmanager: http://${host_ip}:9093"
    echo "   Jaeger:       http://${host_ip}:16686"
    echo ""
    print_info "🔧 System Tools:"
    echo "   System Monitor: ./monitoring/scripts/system-monitor.sh"
    echo "   Docker Logs:    docker logs wo-<service-name>"
    echo "   Shell Access:   docker exec -it wo-system-tools bash"
    echo ""
}

# View logs for monitoring services
view_logs() {
    local service=${1:-all}
    
    case $service in
        "prometheus")
            docker logs -f wo-prometheus
            ;;
        "grafana")
            docker logs -f wo-grafana
            ;;
        "alertmanager")
            docker logs -f wo-alertmanager
            ;;
        "loki")
            docker logs -f wo-loki
            ;;
        "promtail")
            docker logs -f wo-promtail
            ;;
        "all")
            docker compose -f "$PROJECT_ROOT/docker-compose.monitoring.yml" logs -f
            ;;
        *)
            print_error "Unknown service: $service"
            echo "Available services: prometheus, grafana, alertmanager, loki, promtail, all"
            exit 1
            ;;
    esac
}

# Show monitoring status
show_status() {
    print_info "=== Wise Owl Monitoring Status ==="
    
    cd "$PROJECT_ROOT"
    docker compose -f docker-compose.monitoring.yml ps
    
    echo ""
    check_monitoring_health
    
    echo ""
    print_info "Resource usage:"
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" \
        $(docker ps --filter "name=wo-" --format "{{.Names}}")
}

# Update monitoring stack
update_monitoring() {
    print_info "Updating Wise Owl monitoring stack..."
    
    cd "$PROJECT_ROOT"
    
    print_step "Pulling latest images..."
    docker compose -f docker-compose.monitoring.yml pull
    
    print_step "Recreating services..."
    docker compose -f docker-compose.monitoring.yml up -d --force-recreate
    
    print_info "✅ Monitoring stack updated successfully!"
}

# Configure monitoring for development
setup_dev_monitoring() {
    print_info "Setting up monitoring for development environment..."
    
    print_step "Starting main application stack..."
    cd "$PROJECT_ROOT"
    docker compose -f docker-compose.dev.yml up -d
    
    print_step "Starting monitoring stack..."
    start_monitoring
    
    print_info "✅ Development monitoring setup complete!"
}

# Configure monitoring for production
setup_prod_monitoring() {
    print_info "Setting up monitoring for production environment..."
    
    print_step "Starting main application stack..."
    cd "$PROJECT_ROOT"
    docker compose up -d
    
    print_step "Starting monitoring stack..."
    start_monitoring
    
    print_info "✅ Production monitoring setup complete!"
}

# Backup monitoring data
backup_monitoring() {
    local backup_dir="/opt/backups/monitoring"
    local timestamp=$(date +%Y%m%d-%H%M%S)
    
    print_info "Creating monitoring backup..."
    
    mkdir -p "$backup_dir"
    
    print_step "Backing up Prometheus data..."
    docker run --rm \
        -v wo-monitoring_prometheus_data:/source \
        -v "$backup_dir":/backup \
        alpine tar czf "/backup/prometheus-$timestamp.tar.gz" -C /source .
    
    print_step "Backing up Grafana data..."
    docker run --rm \
        -v wo-monitoring_grafana_data:/source \
        -v "$backup_dir":/backup \
        alpine tar czf "/backup/grafana-$timestamp.tar.gz" -C /source .
    
    print_info "✅ Monitoring backup completed: $backup_dir"
}

# Show help
show_help() {
    echo "Wise Owl Monitoring Management Script"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  start              - Start monitoring stack"
    echo "  stop               - Stop monitoring stack"
    echo "  restart            - Restart monitoring stack"
    echo "  status             - Show monitoring status"
    echo "  health             - Check service health"
    echo "  logs [service]     - View logs (service: prometheus, grafana, alertmanager, loki, promtail, all)"
    echo "  update             - Update monitoring stack"
    echo "  urls               - Show access URLs"
    echo "  setup-dev          - Setup monitoring for development"
    echo "  setup-prod         - Setup monitoring for production"
    echo "  backup             - Backup monitoring data"
    echo "  help               - Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 start           - Start all monitoring services"
    echo "  $0 logs grafana    - View Grafana logs"
    echo "  $0 status          - Show current status"
}

# Main execution
main() {
    check_project_root
    
    case "${1:-help}" in
        "start")
            start_monitoring
            ;;
        "stop")
            stop_monitoring
            ;;
        "restart")
            restart_monitoring
            ;;
        "status")
            show_status
            ;;
        "health")
            check_monitoring_health
            ;;
        "logs")
            view_logs "$2"
            ;;
        "update")
            update_monitoring
            ;;
        "urls")
            show_access_urls
            ;;
        "setup-dev")
            setup_dev_monitoring
            ;;
        "setup-prod")
            setup_prod_monitoring
            ;;
        "backup")
            backup_monitoring
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            print_error "Unknown command: $1"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
