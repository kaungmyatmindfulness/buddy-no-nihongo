#!/bin/bash
# Wise Owl System Monitoring Script
# This script provides system monitoring functionality using Docker containers

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

# Check if system-tools container is running
check_system_tools() {
    if ! docker ps | grep -q wo-system-tools; then
        print_warning "System tools container not running. Starting it..."
        docker run -d --name wo-system-tools \
            --network host \
            --pid host \
            --privileged \
            -v /:/host:ro \
            -v /var/run/docker.sock:/var/run/docker.sock:ro \
            nicolaka/netshoot:latest sleep infinity
    fi
}

# System information
system_info() {
    print_info "=== Wise Owl System Information ==="
    echo "Hostname: $(hostname)"
    echo "Uptime: $(uptime -p)"
    echo "Kernel: $(uname -r)"
    echo "Architecture: $(uname -m)"
    echo ""
}

# CPU and Memory information
cpu_memory_info() {
    print_info "=== CPU and Memory ==="
    
    # CPU usage
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
    echo "CPU Usage: ${cpu_usage}%"
    
    # Load average
    echo "Load Average: $(uptime | awk -F'load average:' '{print $2}')"
    
    # Memory usage
    free -h | awk 'NR==2{printf "Memory: %s/%s (%.2f%%)\n", $3,$2,$3*100/$2 }'
    
    echo ""
}

# Disk usage information
disk_info() {
    print_info "=== Disk Usage ==="
    df -h | grep -E '^/dev/' | awk '{print $1 " - Used: " $3 "/" $2 " (" $5 ")"}'
    echo ""
}

# Network information using system-tools container
network_info() {
    print_info "=== Network Information ==="
    check_system_tools
    
    echo "Active connections: $(docker exec wo-system-tools netstat -an 2>/dev/null | grep ESTABLISHED | wc -l || echo 'N/A')"
    echo "Listening ports: $(docker exec wo-system-tools netstat -tuln 2>/dev/null | grep LISTEN | wc -l || echo 'N/A')"
    
    print_step "Network interfaces:"
    docker exec wo-system-tools ip addr show 2>/dev/null | grep -E '^[0-9]+:' | awk '{print $2}' | sed 's/:$//' || echo "N/A"
    echo ""
}

# Docker container status
container_status() {
    print_info "=== Docker Containers ==="
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | head -20
    echo ""
    
    print_step "Container resource usage:"
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" | head -10
    echo ""
}

# Service health checks
service_health() {
    print_info "=== Wise Owl Service Health ==="
    
    services=("wo-nginx" "wo-users-service" "wo-content-service" "wo-quiz-service" "wo-mongodb")
    monitoring_services=("wo-prometheus" "wo-grafana" "wo-node-exporter" "wo-cadvisor")
    
    print_step "Core services:"
    for service in "${services[@]}"; do
        if docker ps | grep -q $service; then
            echo -e "$service: ${GREEN}Running${NC}"
        else
            echo -e "$service: ${RED}Not Running${NC}"
        fi
    done
    
    echo ""
    print_step "Monitoring services:"
    for service in "${monitoring_services[@]}"; do
        if docker ps | grep -q $service; then
            echo -e "$service: ${GREEN}Running${NC}"
        else
            echo -e "$service: ${YELLOW}Not Running${NC}"
        fi
    done
    echo ""
}

# Monitoring endpoints
monitoring_endpoints() {
    print_info "=== Monitoring Endpoints ==="
    
    # Check Prometheus
    if curl -s http://localhost:9090/-/healthy > /dev/null 2>&1; then
        echo -e "Prometheus: ${GREEN}Healthy${NC} - http://localhost:9090"
        targets=$(curl -s http://localhost:9090/api/v1/targets 2>/dev/null | jq '.data.activeTargets | length' 2>/dev/null || echo "N/A")
        echo "  Active targets: $targets"
    else
        echo -e "Prometheus: ${RED}Unreachable${NC}"
    fi
    
    # Check Grafana
    if curl -s http://localhost:3000/api/health > /dev/null 2>&1; then
        echo -e "Grafana: ${GREEN}Healthy${NC} - http://localhost:3000"
    else
        echo -e "Grafana: ${RED}Unreachable${NC}"
    fi
    
    # Check Alertmanager
    if curl -s http://localhost:9093/-/healthy > /dev/null 2>&1; then
        echo -e "Alertmanager: ${GREEN}Healthy${NC} - http://localhost:9093"
    else
        echo -e "Alertmanager: ${YELLOW}Not Running${NC}"
    fi
    
    echo ""
}

# Log analysis using system-tools
log_analysis() {
    print_info "=== Recent Log Analysis ==="
    check_system_tools
    
    print_step "Recent errors in system logs:"
    docker exec wo-system-tools tail -n 20 /host/var/log/syslog 2>/dev/null | grep -i error | tail -5 || echo "No recent errors found"
    
    echo ""
    print_step "Recent Docker events:"
    docker events --since="10m" --until="now" | tail -5 || echo "No recent events"
    echo ""
}

# Process information
process_info() {
    print_info "=== Top Processes ==="
    
    print_step "Top CPU processes:"
    ps aux --sort=-%cpu | head -6 | awk 'NR>1 {printf "%-15s %5s%% %s\n", $11, $3, $2}'
    
    echo ""
    print_step "Top Memory processes:"
    ps aux --sort=-%mem | head -6 | awk 'NR>1 {printf "%-15s %5s%% %s\n", $11, $4, $2}'
    echo ""
}

# Quick troubleshooting tools
troubleshoot() {
    print_info "=== Quick Troubleshoot Tools ==="
    check_system_tools
    
    echo "Available troubleshooting commands:"
    echo "1. Network diagnosis: docker exec wo-system-tools nslookup <domain>"
    echo "2. Port scanning: docker exec wo-system-tools nmap -p <port> <host>"
    echo "3. HTTP testing: docker exec wo-system-tools curl -I <url>"
    echo "4. DNS lookup: docker exec wo-system-tools dig <domain>"
    echo "5. Trace route: docker exec wo-system-tools traceroute <host>"
    echo "6. TCP dump: docker exec wo-system-tools tcpdump -i any -n host <host>"
    echo ""
}

# Main function
main() {
    case "${1:-all}" in
        "system")
            system_info
            cpu_memory_info
            disk_info
            ;;
        "network")
            network_info
            ;;
        "containers")
            container_status
            ;;
        "health")
            service_health
            monitoring_endpoints
            ;;
        "logs")
            log_analysis
            ;;
        "processes")
            process_info
            ;;
        "troubleshoot")
            troubleshoot
            ;;
        "all"|*)
            system_info
            cpu_memory_info
            disk_info
            network_info
            container_status
            service_health
            monitoring_endpoints
            process_info
            ;;
    esac
}

# Help function
show_help() {
    echo "Wise Owl System Monitor"
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  system       - Show system information"
    echo "  network      - Show network information"
    echo "  containers   - Show Docker container status"
    echo "  health       - Show service health status"
    echo "  logs         - Show recent log analysis"
    echo "  processes    - Show top processes"
    echo "  troubleshoot - Show troubleshooting tools"
    echo "  all          - Show all information (default)"
    echo "  help         - Show this help message"
    echo ""
}

# Script entry point
if [ "$1" = "help" ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

main "$@"
