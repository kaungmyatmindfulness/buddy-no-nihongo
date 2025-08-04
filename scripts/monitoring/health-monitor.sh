#!/bin/bash
# Comprehensive Health Monitoring Script for Wise Owl Microservices
# This script provides detailed health monitoring for both development and production environments

set -e

# Load common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utils/common.sh"

# Configuration
ENVIRONMENT="${1:-local}"
INTERVAL="${2:-30}"
LOG_FILE="/tmp/wise-owl-health-monitor.log"

# Service endpoints based on environment
if [ "$ENVIRONMENT" = "aws" ] || [ "$ENVIRONMENT" = "production" ]; then
    # AWS/Production endpoints (ALB DNS name)
    ALB_DNS="${ALB_DNS:-your-alb-dns-name.elb.amazonaws.com}"
    BASE_URL="http://$ALB_DNS"
    SERVICES=(
        "users:$BASE_URL/api/v1/users/health/ready"
        "content:$BASE_URL/api/v1/content/health/ready"
        "quiz:$BASE_URL/api/v1/quiz/health/ready"
    )
    GATEWAY_URL="$BASE_URL/health-check"
else
    # Local development endpoints
    BASE_URL="http://localhost:8080"
    SERVICES=(
        "users:$BASE_URL/api/v1/users/health"
        "content:$BASE_URL/api/v1/content/health"
        "quiz:$BASE_URL/api/v1/quiz/health"
        "users-direct:http://localhost:8081/health/"
        "content-direct:http://localhost:8082/health/"
        "quiz-direct:http://localhost:8083/health/"
    )
    GATEWAY_URL="$BASE_URL/health-check"
fi

# Monitoring functions
check_service_health() {
    local service_name=$1
    local url=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    if response=$(curl -s -w "%{http_code}" "$url" 2>/dev/null); then
        http_code="${response: -3}"
        response_body="${response%???}"
        
        if [ "$http_code" = "200" ]; then
            echo "[$timestamp] ✅ $service_name - HEALTHY ($http_code)" | tee -a "$LOG_FILE"
            return 0
        else
            echo "[$timestamp] ❌ $service_name - UNHEALTHY ($http_code)" | tee -a "$LOG_FILE"
            return 1
        fi
    else
        echo "[$timestamp] ❌ $service_name - CONNECTION FAILED" | tee -a "$LOG_FILE"
        return 1
    fi
}

get_detailed_health() {
    local service_name=$1
    local url=$2
    
    # Try to get detailed health information
    local health_url="${url%/ready}"
    if [ "$health_url" = "$url" ]; then
        health_url="$url"
    fi
    
    if response=$(curl -s "$health_url" 2>/dev/null); then
        echo "  Details: $response"
    fi
}

monitor_once() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local failed_services=0
    
    show_banner "Health Monitor - $ENVIRONMENT Environment"
    echo "[$timestamp] Starting health check cycle..."
    
    # Check gateway
    if check_service_health "nginx-gateway" "$GATEWAY_URL"; then
        true
    else
        ((failed_services++))
    fi
    
    # Check all services
    for service in "${SERVICES[@]}"; do
        IFS=':' read -r name url <<< "$service"
        
        if check_service_health "$name" "$url"; then
            if [ "$ENVIRONMENT" = "local" ]; then
                get_detailed_health "$name" "$url"
            fi
        else
            ((failed_services++))
            if [ "$ENVIRONMENT" = "local" ]; then
                get_detailed_health "$name" "$url"
            fi
        fi
        echo ""
    done
    
    # Summary
    local total_services=$((${#SERVICES[@]} + 1)) # +1 for gateway
    local healthy_services=$((total_services - failed_services))
    
    echo "[$timestamp] Summary: $healthy_services/$total_services services healthy"
    
    if [ $failed_services -eq 0 ]; then
        print_success "All services are healthy! ✨"
    else
        print_warning "$failed_services service(s) have issues"
    fi
    
    return $failed_services
}

monitor_continuous() {
    echo "Starting continuous monitoring (interval: ${INTERVAL}s)"
    echo "Log file: $LOG_FILE"
    echo "Press Ctrl+C to stop"
    echo ""
    
    while true; do
        monitor_once
        echo ""
        echo "Waiting ${INTERVAL}s for next check..."
        sleep "$INTERVAL"
        echo ""
    done
}

generate_status_report() {
    local report_file="/tmp/wise-owl-status-report.json"
    local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    
    echo "Generating status report..."
    
    cat > "$report_file" << EOF
{
  "timestamp": "$timestamp",
  "environment": "$ENVIRONMENT",
  "services": [
EOF
    
    local first=true
    for service in "${SERVICES[@]}"; do
        IFS=':' read -r name url <<< "$service"
        
        if [ "$first" = true ]; then
            first=false
        else
            echo "," >> "$report_file"
        fi
        
        if response=$(curl -s "$url" 2>/dev/null); then
            local status="healthy"
            local response_json=$(echo "$response" | jq -c . 2>/dev/null || echo "\"$response\"")
        else
            local status="unhealthy"
            local response_json="\"Connection failed\""
        fi
        
        cat >> "$report_file" << EOF
    {
      "name": "$name",
      "status": "$status",
      "url": "$url",
      "response": $response_json
    }
EOF
    done
    
    cat >> "$report_file" << EOF
  ]
}
EOF
    
    echo "Status report generated: $report_file"
    cat "$report_file"
}

show_usage() {
    echo "Usage: $0 [ENVIRONMENT] [INTERVAL]"
    echo ""
    echo "ENVIRONMENT:"
    echo "  local      - Monitor local development services (default)"
    echo "  aws        - Monitor AWS production services"
    echo "  production - Monitor production services"
    echo ""
    echo "INTERVAL: Seconds between checks for continuous monitoring (default: 30)"
    echo ""
    echo "Commands:"
    echo "  $0 local once          - Single health check (local)"
    echo "  $0 aws continuous      - Continuous monitoring (AWS)"
    echo "  $0 local report        - Generate JSON status report"
    echo ""
}

# Main execution
case "${2:-once}" in
    "once")
        monitor_once
        ;;
    "continuous")
        monitor_continuous
        ;;
    "report")
        generate_status_report
        ;;
    *)
        if [[ "$2" =~ ^[0-9]+$ ]]; then
            INTERVAL=$2
            monitor_continuous
        else
            show_usage
            exit 1
        fi
        ;;
esac
