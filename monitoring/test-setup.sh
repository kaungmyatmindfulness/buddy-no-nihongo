#!/bin/bash
# Wise Owl Monitoring Test Script

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "🧪 Testing Wise Owl Monitoring Setup"
echo "===================================="

# Test 1: Check if monitoring scripts are executable
echo -n "Testing script permissions... "
if [ -x "monitoring/scripts/monitor-stack.sh" ] && [ -x "monitoring/scripts/system-monitor.sh" ]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    echo "Run: chmod +x monitoring/scripts/*.sh"
fi

# Test 2: Check if Docker is running
echo -n "Testing Docker availability... "
if docker info >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    echo "Docker is not running or not accessible"
    exit 1
fi

# Test 3: Check if monitoring configuration exists
echo -n "Testing monitoring configuration... "
if [ -f "monitoring/prometheus/config/prometheus.yml" ] && [ -f "docker-compose.monitoring.yml" ]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    echo "Monitoring configuration files missing"
fi

# Test 4: Check network creation
echo -n "Testing network creation... "
if docker network create wo-monitoring-test >/dev/null 2>&1; then
    docker network rm wo-monitoring-test >/dev/null 2>&1
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}⚠${NC} (network might already exist)"
fi

# Test 5: Test system monitoring script
echo -n "Testing system monitoring script... "
if ./monitoring/scripts/system-monitor.sh help >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
fi

# Test 6: Test main wise-owl monitoring commands
echo -n "Testing wise-owl monitoring commands... "
if ./wise-owl monitor help >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
fi

echo ""
echo "🚀 Quick Start Test:"
echo "Run './wise-owl monitor start' to test the full stack"
echo ""
echo "📊 After starting, access:"
echo "- Grafana: http://localhost:3000"
echo "- Prometheus: http://localhost:9090"
echo "- System Monitor: ./wise-owl monitor system"
