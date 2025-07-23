#!/bin/bash
# Wise Owl Production Monitoring Script
# Continuous health monitoring with alerts and failure tracking

set -e

# Configuration
CHECK_INTERVAL=30  # seconds between health checks
ALERT_THRESHOLD=3  # consecutive failures before alert
LOG_FILE="logs/monitor.log"

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Service configuration (using arrays instead of associative arrays for compatibility)
SERVICES=("nginx:80" "users-service:8081" "content-service:8082" "quiz-service:8083")

# Failure tracking files (using temp files instead of associative arrays)
TEMP_DIR="/tmp/wise-owl-monitor"
mkdir -p "$TEMP_DIR"

# Initialize failure counters
init_counters() {
    for service_info in "${SERVICES[@]}"; do
        IFS=':' read -r service port <<< "$service_info"
        echo "0" > "$TEMP_DIR/${service}_failures"
        echo "unknown" > "$TEMP_DIR/${service}_status"
    done
}

# Get failure count for service
get_failures() {
    local service=$1
    cat "$TEMP_DIR/${service}_failures" 2>/dev/null || echo "0"
}

# Set failure count for service
set_failures() {
    local service=$1
    local count=$2
    echo "$count" > "$TEMP_DIR/${service}_failures"
}

# Get status for service
get_status() {
    local service=$1
    cat "$TEMP_DIR/${service}_status" 2>/dev/null || echo "unknown"
}

# Set status for service
set_status() {
    local service=$1
    local status=$2
    echo "$status" > "$TEMP_DIR/${service}_status"
}

# Print functions
print_status() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

print_alert() {
    echo -e "${RED}[ALERT]$(date '+%Y-%m-%d %H:%M:%S') $1${NC}"
}

print_info() {
    echo -e "${GREEN}[INFO]$(date '+%Y-%m-%d %H:%M:%S') $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]$(date '+%Y-%m-%d %H:%M:%S') $1${NC}"
}

# Setup logging
setup_logging() {
    mkdir -p logs
    if [ ! -f "$LOG_FILE" ]; then
        touch "$LOG_FILE"
    fi
}

# Log to file
log_event() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Check service health
check_service() {
    local service=$1
    local port=$2
    
    # Try health endpoint first, fall back to basic connectivity
    if curl -s -f --max-time 5 "http://localhost:$port/health/ready" > /dev/null 2>&1; then
        return 0
    elif curl -s -f --max-time 5 "http://localhost:$port/health" > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Send alert (can be extended for email, Slack, etc.)
send_alert() {
    local service=$1
    local failure_count=$2
    
    local alert_msg="🚨 ALERT: $service has failed $failure_count consecutive health checks!"
    
    print_alert "$alert_msg"
    log_event "ALERT: $alert_msg"
    
    # Here you can add integrations for:
    # - Email notifications
    # - Slack webhooks
    # - PagerDuty alerts
    # - Discord notifications
    
    # Example: Send to webhook (uncomment and configure)
    # curl -X POST "$WEBHOOK_URL" \
    #   -H 'Content-Type: application/json' \
    #   -d "{\"text\":\"$alert_msg\"}" 2>/dev/null || true
}

# Recovery notification
send_recovery() {
    local service=$1
    
    local recovery_msg="✅ RECOVERY: $service is now healthy after being down"
    
    print_info "$recovery_msg"
    log_event "RECOVERY: $recovery_msg"
}

# Monitor single service
monitor_service() {
    local service=$1
    local port=$2
    local current_status
    local current_failures
    local last_status_val
    
    current_failures=$(get_failures "$service")
    last_status_val=$(get_status "$service")
    
    if check_service "$service" "$port"; then
        current_status="healthy"
        
        # Check if this is a recovery
        if [ "$last_status_val" = "failed" ] && [ "$current_failures" -ge $ALERT_THRESHOLD ]; then
            send_recovery "$service"
        fi
        
        set_failures "$service" "0"
        set_status "$service" "healthy"
        
        return 0
    else
        current_status="failed"
        current_failures=$((current_failures + 1))
        set_failures "$service" "$current_failures"
        set_status "$service" "failed"
        
        # Send alert if threshold reached
        if [ "$current_failures" -eq $ALERT_THRESHOLD ]; then
            send_alert "$service" "$current_failures"
        fi
        
        return 1
    fi
}

# Display dashboard
display_dashboard() {
    # Clear screen for dashboard view
    clear
    
    echo "🦉 Wise Owl Production Monitoring Dashboard"
    echo "================================================"
    echo "Last updated: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Check interval: ${CHECK_INTERVAL}s | Alert threshold: ${ALERT_THRESHOLD} failures"
    echo ""
    
    # Service status table
    printf "%-20s %-10s %-15s %-10s\n" "SERVICE" "STATUS" "FAILURES" "LAST_CHECK"
    echo "------------------------------------------------------------"
    
    local all_healthy=true
    
    for service_info in "${SERVICES[@]}"; do
        IFS=':' read -r service port <<< "$service_info"
        
        local status_icon
        local status_color
        local current_status
        local current_failures
        
        current_status=$(get_status "$service")
        current_failures=$(get_failures "$service")
        
        if [ "$current_status" = "healthy" ]; then
            status_icon="✅"
            status_color="$GREEN"
        else
            status_icon="❌"
            status_color="$RED"
            all_healthy=false
        fi
        
        printf "${status_color}%-20s %-10s %-15s %-10s${NC}\n" \
            "$service" \
            "${status_icon} ${current_status}" \
            "${current_failures}" \
            "$(date '+%H:%M:%S')"
    done
    
    echo ""
    
    # Overall system status
    if [ "$all_healthy" = true ]; then
        echo -e "${GREEN}🟢 System Status: ALL SERVICES HEALTHY${NC}"
    else
        echo -e "${RED}🔴 System Status: SOME SERVICES DOWN${NC}"
    fi
    
    echo ""
    echo "📊 Quick Stats:"
    echo "  - Total checks: $(grep -c "health check" "$LOG_FILE" 2>/dev/null || echo "0")"
    echo "  - Recent alerts: $(grep -c "ALERT" "$LOG_FILE" 2>/dev/null | tail -100 || echo "0")"
    echo "  - Log file: $LOG_FILE"
    echo ""
    echo "Press Ctrl+C to stop monitoring"
    echo "================================================"
}

# Main monitoring loop
monitor() {
    setup_logging
    init_counters
    
    print_info "Starting Wise Owl production monitoring..."
    print_info "Monitoring ${#SERVICES[@]} services every ${CHECK_INTERVAL}s"
    log_event "Monitoring started with ${#SERVICES[@]} services"
    
    # Initial status display
    echo ""
    
    while true; do
        # Monitor all services
        for service_info in "${SERVICES[@]}"; do
            IFS=':' read -r service port <<< "$service_info"
            monitor_service "$service" "$port"
        done
        
        # Update dashboard
        display_dashboard
        
        # Log periodic status
        local healthy_count=0
        for service_info in "${SERVICES[@]}"; do
            IFS=':' read -r service port <<< "$service_info"
            if [ "$(get_status "$service")" = "healthy" ]; then
                healthy_count=$((healthy_count + 1))
            fi
        done
        
        log_event "Health check completed: $healthy_count/${#SERVICES[@]} services healthy"
        
        # Wait for next check
        sleep $CHECK_INTERVAL
    done
}

# Show help
show_help() {
    echo "🦉 Wise Owl Production Monitoring"
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  monitor  - Start continuous monitoring (default)"
    echo "  check    - Single health check of all services"
    echo "  logs     - Show monitoring logs"
    echo "  status   - Show current service status"
    echo "  reset    - Reset failure counters"
    echo ""
    echo "Configuration:"
    echo "  CHECK_INTERVAL=$CHECK_INTERVAL seconds"
    echo "  ALERT_THRESHOLD=$ALERT_THRESHOLD failures"
    echo "  LOG_FILE=$LOG_FILE"
    echo ""
}

# Single health check
single_check() {
    setup_logging
    init_counters
    
    print_info "Performing single health check..."
    
    local all_healthy=true
    
    for service_info in "${SERVICES[@]}"; do
        IFS=':' read -r service port <<< "$service_info"
        
        echo -n "  Checking $service (port $port)... "
        
        if check_service "$service" "$port"; then
            echo -e "${GREEN}✅ healthy${NC}"
        else
            echo -e "${RED}❌ failed${NC}"
            all_healthy=false
        fi
    done
    
    echo ""
    
    if [ "$all_healthy" = true ]; then
        print_info "All services are healthy! 🎉"
        exit 0
    else
        print_warning "Some services are not responding"
        exit 1
    fi
}

# Show logs
show_logs() {
    if [ -f "$LOG_FILE" ]; then
        echo "📊 Recent monitoring events:"
        echo "=========================="
        tail -50 "$LOG_FILE"
    else
        echo "No log file found at $LOG_FILE"
    fi
}

# Reset counters
reset_counters() {
    for service_info in "${SERVICES[@]}"; do
        IFS=':' read -r service port <<< "$service_info"
        set_failures "$service" "0"
        set_status "$service" "unknown"
    done
    
    print_info "Reset failure counters for all services"
    log_event "Failure counters reset manually"
}

# Cleanup temp files on exit
cleanup() {
    rm -rf "$TEMP_DIR"
}

# Handle graceful shutdown
trap 'echo ""; print_info "Monitoring stopped by user"; log_event "Monitoring stopped"; cleanup; exit 0' INT TERM

# Main command dispatcher
case "${1:-monitor}" in
    "monitor")
        monitor
        ;;
    
    "check")
        single_check
        ;;
    
    "logs")
        show_logs
        ;;
    
    "status")
        single_check
        ;;
    
    "reset")
        reset_counters
        ;;
    
    "help"|"-h"|"--help")
        show_help
        ;;
    
    *)
        echo "Unknown command: $1"
        show_help
        exit 1
        ;;
esac
