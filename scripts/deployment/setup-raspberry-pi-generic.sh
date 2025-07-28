#!/bin/bash
# filepath: /opt/vps-setup.sh
# VPS Setup Script for API and Frontend Hosting with Docker
# Includes Prometheus + Grafana monitoring stack

set -e

# Configuration
CURRENT_USER="$(logname 2>/dev/null || echo $SUDO_USER)"  # Get the original user if running with sudo
PROMETHEUS_VERSION="v2.45.0"
GRAFANA_VERSION="10.0.0"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Print functions
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

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    print_error "This script must be run as root"
    exit 1
fi

# ASCII Art
echo -e "${BLUE}"
cat << "EOF"
__     ______  ____   ____       _               
\ \   / /  _ \/ ___| / ___|  ___| |_ _   _ _ __  
 \ \ / /| |_) \___ \ \___ \ / _ \ __| | | | '_ \ 
  \ V / |  __/ ___) | ___) |  __/ |_| |_| | |_) |
   \_/  |_|   |____/ |____/ \___|\__|\__,_| .__/ 
                                           |_|    
EOF
echo -e "${NC}"

# ========================================
# PHASE 1: System Updates
# ========================================
print_info "Phase 1: System Updates"

print_step "Updating package lists..."
apt update

print_step "Upgrading system packages..."
apt upgrade -y

print_step "Installing essential packages..."
apt install -y \
    curl \
    wget \
    vim \
    git \
    ufw \
    fail2ban \
    ca-certificates \
    gnupg \
    lsb-release \
    software-properties-common \
    apt-transport-https \
    jq \
    logrotate

# ========================================
# PHASE 2: User Setup
# ========================================
print_info "Phase 2: User Setup"

print_info "Using current user: $CURRENT_USER"

print_step "SSH key setup..."
print_info "To set up SSH key authentication for user '$CURRENT_USER':"
print_info "1. mkdir -p /home/$CURRENT_USER/.ssh"
print_info "2. Add your SSH public key to /home/$CURRENT_USER/.ssh/authorized_keys"
print_info "3. chmod 600 /home/$CURRENT_USER/.ssh/authorized_keys"
print_info "4. chown $CURRENT_USER:$CURRENT_USER /home/$CURRENT_USER/.ssh/authorized_keys"
print_info "5. Disable password authentication in /etc/ssh/sshd_config"

# ========================================
# PHASE 3: Security Hardening
# ========================================
print_info "Phase 3: Security Hardening"

print_step "Configuring firewall..."
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 80/tcp comment "HTTP"
ufw allow 443/tcp comment "HTTPS"
ufw allow 9090/tcp comment "Prometheus"
ufw allow 3000/tcp comment "Grafana"
ufw --force enable

print_step "Configuring fail2ban..."
cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local

# Add HTTP flood protection
cat > /etc/fail2ban/jail.d/http-flood.conf << EOF
[http-flood]
enabled = true
filter = http-flood
logpath = /var/log/nginx/access.log
         /opt/traefik/logs/access.log
maxretry = 100
findtime = 60
bantime = 600
action = iptables-multiport[name=http-flood, port="http,https"]
EOF

# Create HTTP flood filter
cat > /etc/fail2ban/filter.d/http-flood.conf << EOF
[Definition]
failregex = ^<HOST> -.*"(GET|POST|HEAD).*HTTP.*"
ignoreregex =
EOF

systemctl enable fail2ban
systemctl restart fail2ban

# ========================================
# PHASE 4: Docker Installation
# ========================================
print_info "Phase 4: Docker Installation"

if ! command -v docker &> /dev/null; then
    print_step "Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
    
    print_info "Docker installed successfully"
else
    print_info "Docker already installed: $(docker --version)"
fi

# Check for Docker Compose
print_step "Checking Docker Compose..."
if docker compose version &> /dev/null; then
    print_info "Docker Compose v2 installed: $(docker compose version)"
else
    print_warning "Docker Compose v2 not found, installing plugin..."
    
    # Install Docker Compose plugin
    DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
    mkdir -p $DOCKER_CONFIG/cli-plugins
    curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$(uname -m) -o $DOCKER_CONFIG/cli-plugins/docker-compose
    chmod +x $DOCKER_CONFIG/cli-plugins/docker-compose
    
    # Verify installation
    if docker compose version &> /dev/null; then
        print_info "Docker Compose installed successfully"
    else
        print_error "Failed to install Docker Compose"
        exit 1
    fi
fi

print_step "Configuring Docker daemon..."
cat > /etc/docker/daemon.json << EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "metrics-addr": "0.0.0.0:9323",
  "experimental": true
}
EOF

systemctl restart docker

print_step "Adding user to docker group..."
# Add current user to docker group (will take effect after next login)
if id "$CURRENT_USER" &>/dev/null; then
  usermod -aG docker "$CURRENT_USER"
  print_info "User '$CURRENT_USER' added to docker group"
  print_warning "Please log out and log back in for docker group changes to take effect"
else
  print_warning "Could not find user '$CURRENT_USER'. Make sure to add your user to docker group manually."
fi

# ========================================
# PHASE 5: Docker Networks
# ========================================
print_info "Phase 5: Docker Networks"

print_step "Creating Docker networks..."
docker network create web 2>/dev/null || true
docker network create internal 2>/dev/null || true
docker network create monitoring 2>/dev/null || true

# ========================================
# PHASE 6: Traefik Reverse Proxy
# ========================================
print_info "Phase 6: Traefik Reverse Proxy Setup"

print_step "Setting up Traefik..."
mkdir -p /opt/traefik/{config,data,logs}
chown -R $CURRENT_USER:$CURRENT_USER /opt/traefik

# Get email for Let's Encrypt
read -p "Enter email for Let's Encrypt SSL certificates: " le_email
le_email=${le_email:-admin@example.com}

# Create Traefik docker-compose
cat > /opt/traefik/docker-compose.yml << EOF
version: '3.8'

services:
  traefik:
    image: traefik:v3.0
    container_name: traefik
    restart: always
    ports:
      - "80:80"
      - "443:443"
      - "9080:8080"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik.yml:/traefik.yml:ro
      - ./config/dynamic.yml:/etc/traefik/dynamic.yml:ro
      - ./data:/data
      - ./logs:/logs
    networks:
      - web
      - monitoring
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.api.entrypoints=websecure"
      - "traefik.http.routers.api.tls=true"
      - "traefik.http.routers.api.service=api@internal"
      - "traefik.http.services.api.loadbalancer.server.port=8080"
      # Prometheus metrics
      - "prometheus.io/scrape=true"
      - "prometheus.io/port=8080"
      - "prometheus.io/path=/metrics"
    environment:
      - CF_API_EMAIL=\${CF_API_EMAIL}
      - CF_API_KEY=\${CF_API_KEY}

networks:
  web:
    external: true
  monitoring:
    external: true
EOF

# Create Traefik static configuration
cat > /opt/traefik/traefik.yml << EOF
global:
  checkNewVersion: true
  sendAnonymousUsage: false

api:
  dashboard: true
  debug: false

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entrypoint:
          to: websecure
          scheme: https
  websecure:
    address: ":443"
    
providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
    network: web
  file:
    filename: /etc/traefik/dynamic.yml
    watch: true

certificatesResolvers:
  letsencrypt:
    acme:
      email: ${le_email}
      storage: /data/letsencrypt/acme.json
      httpChallenge:
        entryPoint: web
      # caServer: https://acme-staging-v02.api.letsencrypt.org/directory

log:
  level: INFO
  filePath: /logs/traefik.log
  format: json

accessLog:
  filePath: /logs/access.log
  format: json
  bufferingSize: 100

metrics:
  prometheus:
    buckets:
      - 0.1
      - 0.3
      - 1.2
      - 5.0
    addEntryPointsLabels: true
    addServicesLabels: true
EOF

# Create dynamic configuration
cat > /opt/traefik/config/dynamic.yml << EOF
http:
  middlewares:
    security-headers:
      headers:
        frameDeny: true
        browserXssFilter: true
        contentTypeNosniff: true
        forceSTSHeader: true
        stsIncludeSubdomains: true
        stsPreload: true
        stsSeconds: 31536000
        customFrameOptionsValue: "SAMEORIGIN"
        referrerPolicy: "strict-origin-when-cross-origin"
        contentSecurityPolicy: "default-src 'self'"
    
    rate-limit:
      rateLimit:
        average: 100
        period: 1m
        burst: 50
    
    compress:
      compress:
        excludedContentTypes:
          - text/event-stream
    
    cors:
      headers:
        accessControlAllowMethods:
          - GET
          - OPTIONS
          - PUT
          - POST
          - DELETE
        accessControlAllowHeaders:
          - Origin
          - Content-Type
          - Accept
          - Authorization
        accessControlAllowOriginList:
          - "*"
        accessControlMaxAge: 100
        addVaryHeader: true

tls:
  options:
    default:
      minVersion: VersionTLS12
      cipherSuites:
        - TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256
        - TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
        - TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305
        - TLS_AES_128_GCM_SHA256
        - TLS_AES_256_GCM_SHA384
        - TLS_CHACHA20_POLY1305_SHA256
EOF

# Set permissions for acme.json
mkdir -p /opt/traefik/data/letsencrypt
touch /opt/traefik/data/letsencrypt/acme.json
chmod 600 /opt/traefik/data/letsencrypt/acme.json
chown $CURRENT_USER:$CURRENT_USER /opt/traefik/data/letsencrypt/acme.json

# ========================================
# PHASE 7: Prometheus Monitoring
# ========================================
print_info "Phase 7: Prometheus Setup"

print_step "Setting up Prometheus..."
mkdir -p /opt/prometheus/{config,data}
chown -R $CURRENT_USER:$CURRENT_USER /opt/prometheus

# Create Prometheus configuration
cat > /opt/prometheus/config/prometheus.yml << EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    monitor: 'vps-monitor'

alerting:
  alertmanagers:
    - static_configs:
        - targets: []

rule_files:
  - "alerts.yml"

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']

  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']

  - job_name: 'traefik'
    static_configs:
      - targets: ['traefik:8080']

  - job_name: 'docker'
    static_configs:
      - targets: ['172.17.0.1:9323']

  - job_name: 'docker-containers'
    docker_sd_configs:
      - host: unix:///var/run/docker.sock
    relabel_configs:
      - source_labels: [__meta_docker_container_name]
        regex: '/(.*)'
        target_label: container_name
      - source_labels: [__meta_docker_container_label_prometheus_io_scrape]
        regex: true
        action: keep
      - source_labels: [__meta_docker_container_label_prometheus_io_path]
        regex: (.+)
        target_label: __metrics_path__
      - source_labels: [__address__, __meta_docker_container_label_prometheus_io_port]
        regex: ([^:]+):(\d+);(\d+)
        replacement: \${1}:\${3}
        target_label: __address__
EOF

# Create alert rules
cat > /opt/prometheus/config/alerts.yml << EOF
groups:
  - name: system
    rules:
      - alert: HighCPUUsage
        expr: 100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage detected"
          description: "CPU usage is above 80% (current value: {{ \$value }}%)"

      - alert: HighMemoryUsage
        expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage detected"
          description: "Memory usage is above 85% (current value: {{ \$value }}%)"

      - alert: HighDiskUsage
        expr: (1 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"})) * 100 > 90
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "High disk usage detected"
          description: "Disk usage is above 90% (current value: {{ \$value }}%)"

      - alert: ContainerDown
        expr: up{job="docker-containers"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Container is down"
          description: "Container {{ \$labels.container_name }} is down"

      - alert: HighHTTPErrorRate
        expr: rate(traefik_service_requests_total{code=~"5.."}[5m]) > 0.05
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High HTTP error rate"
          description: "HTTP 5xx error rate is above 5% for {{ \$labels.service }}"
EOF

# Create Prometheus docker-compose
cat > /opt/prometheus/docker-compose.yml << EOF
version: '3.8'

services:
  prometheus:
    image: prom/prometheus:${PROMETHEUS_VERSION}
    container_name: prometheus
    restart: always
    volumes:
      - ./config:/etc/prometheus
      - ./data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/usr/share/prometheus/console_libraries'
      - '--web.console.templates=/usr/share/prometheus/consoles'
      - '--web.enable-lifecycle'
      - '--storage.tsdb.retention.time=30d'
    ports:
      - "9090:9090"
    networks:
      - monitoring
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.prometheus.rule=Host(\`prometheus.\${DOMAIN}\`)"
      - "traefik.http.routers.prometheus.entrypoints=websecure"
      - "traefik.http.routers.prometheus.tls.certresolver=letsencrypt"
      - "traefik.http.services.prometheus.loadbalancer.server.port=9090"

  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    restart: always
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--path.rootfs=/rootfs'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
    networks:
      - monitoring
    expose:
      - 9100

  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest
    container_name: cadvisor
    restart: always
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker:/var/lib/docker:ro
      - /dev/disk/:/dev/disk:ro
    privileged: true
    devices:
      - /dev/kmsg
    networks:
      - monitoring
    expose:
      - 8080

  # System monitoring tools container
  monitoring-tools:
    image: nicolaka/netshoot:latest
    container_name: monitoring-tools
    restart: unless-stopped
    network_mode: host
    pid: host
    privileged: true
    volumes:
      - /:/host:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
    command: sleep infinity
    labels:
      - "traefik.enable=false"
    expose:
      - 8080

networks:
  monitoring:
    external: true
EOF

chown -R $CURRENT_USER:$CURRENT_USER /opt/prometheus

# ========================================
# PHASE 8: Grafana Dashboard
# ========================================
print_info "Phase 8: Grafana Setup"

print_step "Setting up Grafana..."
mkdir -p /opt/grafana/{data,provisioning/{dashboards,datasources}}
chown -R 472:472 /opt/grafana

# Create Grafana datasource
cat > /opt/grafana/provisioning/datasources/prometheus.yml << EOF
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: true
EOF

# Create Grafana dashboard provisioning
cat > /opt/grafana/provisioning/dashboards/dashboard.yml << EOF
apiVersion: 1

providers:
  - name: 'default'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    options:
      path: /etc/grafana/provisioning/dashboards
EOF

# Create a basic system dashboard
cat > /opt/grafana/provisioning/dashboards/system-overview.json << 'EOF'
{
  "dashboard": {
    "id": null,
    "uid": "system-overview",
    "title": "System Overview",
    "tags": ["system"],
    "timezone": "browser",
    "panels": [
      {
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
        "id": 1,
        "title": "CPU Usage",
        "type": "graph",
        "targets": [
          {
            "expr": "100 - (avg by (instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)",
            "legendFormat": "CPU Usage %"
          }
        ]
      },
      {
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0},
        "id": 2,
        "title": "Memory Usage",
        "type": "graph",
        "targets": [
          {
            "expr": "(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100",
            "legendFormat": "Memory Usage %"
          }
        ]
      },
      {
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8},
        "id": 3,
        "title": "Disk Usage",
        "type": "graph",
        "targets": [
          {
            "expr": "(1 - (node_filesystem_avail_bytes{mountpoint=\"/\"} / node_filesystem_size_bytes{mountpoint=\"/\"})) * 100",
            "legendFormat": "Disk Usage %"
          }
        ]
      },
      {
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8},
        "id": 4,
        "title": "Network Traffic",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(node_network_receive_bytes_total[5m])",
            "legendFormat": "RX {{device}}"
          },
          {
            "expr": "rate(node_network_transmit_bytes_total[5m])",
            "legendFormat": "TX {{device}}"
          }
        ]
      }
    ],
    "schemaVersion": 27,
    "version": 1
  }
}
EOF

# Create Grafana docker-compose
cat > /opt/grafana/docker-compose.yml << EOF
version: '3.8'

services:
  grafana:
    image: grafana/grafana:${GRAFANA_VERSION}
    container_name: grafana
    restart: always
    volumes:
      - ./data:/var/lib/grafana
      - ./provisioning:/etc/grafana/provisioning
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
      - GF_USERS_ALLOW_SIGN_UP=false
      - GF_INSTALL_PLUGINS=grafana-piechart-panel,grafana-worldmap-panel
      - GF_SERVER_ROOT_URL=https://grafana.\${DOMAIN}
      - GF_SMTP_ENABLED=false
    ports:
      - "3000:3000"
    networks:
      - monitoring
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.grafana.rule=Host(\`grafana.\${DOMAIN}\`)"
      - "traefik.http.routers.grafana.entrypoints=websecure"
      - "traefik.http.routers.grafana.tls.certresolver=letsencrypt"
      - "traefik.http.services.grafana.loadbalancer.server.port=3000"

networks:
  monitoring:
    external: true
EOF

chown -R 472:472 /opt/grafana

# ========================================
# PHASE 9: Resource Monitoring Script
# ========================================
print_info "Phase 9: Resource Monitoring Tools"

print_step "Creating resource monitoring script..."
cat > /usr/local/bin/vps-monitor << 'EOF'
#!/bin/bash

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== VPS Resource Monitor ===${NC}"
echo ""

# System Info
echo -e "${GREEN}System Information:${NC}"
echo "Hostname: $(hostname)"
echo "Uptime: $(uptime -p)"
echo "Kernel: $(uname -r)"
echo ""

# CPU Usage
echo -e "${GREEN}CPU Usage:${NC}"
cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
echo "CPU Usage: ${cpu_usage}%"
echo "Load Average: $(uptime | awk -F'load average:' '{print $2}')"
echo ""

# Memory Usage
echo -e "${GREEN}Memory Usage:${NC}"
free -h | awk 'NR==2{printf "Used: %s/%s (%.2f%%)\n", $3,$2,$3*100/$2 }'
echo ""

# Disk Usage
echo -e "${GREEN}Disk Usage:${NC}"
df -h | grep -E '^/dev/' | awk '{print $1 " - Used: " $3 "/" $2 " (" $5 ")"}'
echo ""

# Docker Containers
echo -e "${GREEN}Docker Containers:${NC}"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | head -10
echo ""

# Network Statistics (using monitoring-tools container)
echo -e "${GREEN}Network Statistics:${NC}"
if docker ps | grep -q monitoring-tools; then
    active_conn=$(docker exec monitoring-tools netstat -an 2>/dev/null | grep ESTABLISHED | wc -l || echo "N/A")
    listen_ports=$(docker exec monitoring-tools netstat -tuln 2>/dev/null | grep LISTEN | wc -l || echo "N/A")
    echo "Active connections: $active_conn"
    echo "Listening ports: $listen_ports"
else
    echo "Network monitoring unavailable (monitoring-tools container not running)"
fi
echo ""

# Top Processes (simplified)
echo -e "${GREEN}Top CPU Processes:${NC}"
ps aux --sort=-%cpu | head -6 | awk 'NR>1 {printf "%-15s %5s%% %s\n", $11, $3, $2}'
echo ""

echo -e "${GREEN}Top Memory Processes:${NC}"
ps aux --sort=-%mem | head -6 | awk 'NR>1 {printf "%-15s %5s%% %s\n", $11, $4, $2}'
echo ""
# Service Health
echo -e "${GREEN}Service Health:${NC}"
services=("traefik" "prometheus" "grafana" "node-exporter" "cadvisor" "monitoring-tools")
for service in "${services[@]}"; do
    if docker ps | grep -q $service; then
        echo -e "$service: ${GREEN}Running${NC}"
    else
        echo -e "$service: ${RED}Not Running${NC}"
    fi
done
echo ""

# Prometheus Metrics
if curl -s http://localhost:9090/-/healthy > /dev/null 2>&1; then
    echo -e "${GREEN}Prometheus Status:${NC} Healthy"
    targets=$(curl -s http://localhost:9090/api/v1/targets 2>/dev/null | jq '.data.activeTargets | length' 2>/dev/null || echo "N/A")
    echo "Targets: $targets active"
else
    echo -e "${RED}Prometheus Status:${NC} Unreachable"
fi
echo ""

# Quick Links
echo -e "${BLUE}Access URLs:${NC}"
echo "Grafana: http://$(hostname -I | awk '{print $1}'):3000"
echo "Prometheus: http://$(hostname -I | awk '{print $1}'):9090"
echo "Traefik: http://$(hostname -I | awk '{print $1}'):9080"
EOF

chmod +x /usr/local/bin/vps-monitor

# Create detailed monitoring script
cat > /usr/local/bin/vps-health << 'EOF'
#!/bin/bash

# Generate health report
REPORT_FILE="/tmp/vps-health-$(date +%Y%m%d-%H%M%S).json"

# Collect metrics
cat > $REPORT_FILE << EOJSON
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "hostname": "$(hostname)",
  "uptime_seconds": $(awk '{print $1}' /proc/uptime),
  "load_average": {
    "1m": $(uptime | awk -F'load average:' '{print $2}' | awk -F', ' '{print $1}'),
    "5m": $(uptime | awk -F'load average:' '{print $2}' | awk -F', ' '{print $2}'),
    "15m": $(uptime | awk -F'load average:' '{print $2}' | awk -F', ' '{print $3}')
  },
  "cpu": {
    "usage_percent": $(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}'),
    "cores": $(nproc)
  },
  "memory": {
    "total_mb": $(free -m | awk 'NR==2{print $2}'),
    "used_mb": $(free -m | awk 'NR==2{print $3}'),
    "free_mb": $(free -m | awk 'NR==2{print $4}'),
    "usage_percent": $(free | awk 'NR==2{printf "%.2f", $3*100/$2}')
  },
  "disk": {
    "total_gb": $(df -BG / | awk 'NR==2{print $2}' | sed 's/G//'),
    "used_gb": $(df -BG / | awk 'NR==2{print $3}' | sed 's/G//'),
    "free_gb": $(df -BG / | awk 'NR==2{print $4}' | sed 's/G//'),
    "usage_percent": $(df / | awk 'NR==2{print $5}' | sed 's/%//')
  },
  "docker": {
    "containers_running": $(docker ps -q | wc -l),
    "containers_total": $(docker ps -aq | wc -l),
    "images": $(docker images -q | wc -l)
  }
}
EOJSON

echo "Health report generated: $REPORT_FILE"
cat $REPORT_FILE | jq .
EOF

chmod +x /usr/local/bin/vps-health

# ========================================
# PHASE 10: Cloudflare Tunnel Setup
# ========================================
print_info "Phase 10: Cloudflare Tunnel Setup"

print_step "Setting up Cloudflare Tunnel (Docker-based)..."

# Create config directory
mkdir -p /opt/cloudflared
chown $CURRENT_USER:$CURRENT_USER /opt/cloudflared

# Create Cloudflare Tunnel docker-compose
cat > /opt/cloudflared/docker-compose.yml << EOF
services:
  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: cloudflared
    restart: unless-stopped
    command: tunnel --config /etc/cloudflared/config.yml run
    volumes:
      - ./config.yml:/etc/cloudflared/config.yml:ro
      - ./credentials.json:/etc/cloudflared/credentials.json:ro
    networks:
      - web
    labels:
      - "prometheus.io/scrape=true"
      - "prometheus.io/port=2000"
      - "prometheus.io/path=/metrics"

networks:
  web:
    external: true
EOF

# Create sample config
cat > /opt/cloudflared/config.yml << EOF
# Cloudflare Tunnel Configuration
# Replace with your tunnel credentials and UUID

tunnel: YOUR_TUNNEL_UUID
credentials-file: /etc/cloudflared/credentials.json

# Metrics for monitoring
metrics: 0.0.0.0:2000

ingress:
  # Grafana
  - hostname: grafana.yourdomain.com
    service: http://traefik:3000
  
  # Prometheus
  - hostname: prometheus.yourdomain.com
    service: http://traefik:9090
  
  # Your API
  - hostname: api.yourdomain.com
    service: http://traefik:8000
  
  # Your Frontend
  - hostname: app.yourdomain.com
    service: http://traefik:3001
  
  # Catch-all
  - service: http_status:404
EOF

# Create placeholder credentials file
cat > /opt/cloudflared/credentials.json << EOF
{
  "AccountTag": "your-account-tag",
  "TunnelSecret": "your-tunnel-secret",
  "TunnelID": "your-tunnel-id"
}
EOF

chmod 600 /opt/cloudflared/credentials.json
chown -R $CURRENT_USER:$CURRENT_USER /opt/cloudflared

print_warning "To set up Cloudflare Tunnel:"
print_warning "1. Run: docker run --rm -v /opt/cloudflared:/etc/cloudflared cloudflare/cloudflared:latest tunnel login"
print_warning "2. Create tunnel: docker run --rm -v /opt/cloudflared:/etc/cloudflared cloudflare/cloudflared:latest tunnel create wise-owl"
print_warning "3. Replace the config.yml and credentials.json with your actual tunnel details"
print_warning "4. Start with: cd /opt/cloudflared && docker compose up -d"

# ========================================
# PHASE 11: Uptime Kuma with Monitoring Integration
# ========================================
print_info "Phase 11: Uptime Kuma Setup"

print_step "Setting up Uptime Kuma..."
mkdir -p /opt/uptime-kuma
chown -R $CURRENT_USER:$CURRENT_USER /opt/uptime-kuma

cat > /opt/uptime-kuma/docker-compose.yml << EOF
version: '3.8'

services:
  uptime-kuma:
    image: louislam/uptime-kuma:1
    container_name: uptime-kuma
    restart: always
    volumes:
      - ./data:/app/data
    ports:
      - "3001:3001"
    networks:
      - monitoring
      - web
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.uptime.rule=Host(\`uptime.\${DOMAIN}\`)"
      - "traefik.http.routers.uptime.entrypoints=websecure"
      - "traefik.http.routers.uptime.tls.certresolver=letsencrypt"
      - "traefik.http.services.uptime.loadbalancer.server.port=3001"
      # Prometheus metrics
      - "prometheus.io/scrape=true"
      - "prometheus.io/port=3001"
      - "prometheus.io/path=/metrics"

volumes:
  data:

networks:
  monitoring:
    external: true
  web:
    external: true
EOF

# ========================================
# PHASE 12: Logging & Backups
# ========================================
print_info "Phase 12: Logging & Backup Infrastructure"

print_step "Creating logging directories..."
mkdir -p /var/log/api-logs/{access,error,audit}
mkdir -p /opt/logging/scripts
chown -R $CURRENT_USER:$CURRENT_USER /var/log/api-logs

# Create log rotation config
cat > /etc/logrotate.d/api-logs << EOF
/var/log/api-logs/*/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 0644 $CURRENT_USER $CURRENT_USER
    sharedscripts
    postrotate
        docker kill -s USR1 \$(docker ps -q) 2>/dev/null || true
    endscript
}
EOF

# Enhanced backup script with monitoring data
cat > /opt/backup.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/opt/backups"
DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_NAME="vps-backup-$DATE"

mkdir -p $BACKUP_DIR

echo "🔄 Starting VPS backup..."

# Backup configurations
tar -czf $BACKUP_DIR/$BACKUP_NAME-configs.tar.gz \
    /opt/traefik \
    /opt/prometheus/config \
    /opt/grafana/provisioning \
    /opt/cloudflared \
    2>/dev/null

# Backup Docker volumes
docker run --rm \
    -v /var/lib/docker/volumes:/volumes \
    -v $BACKUP_DIR:/backup \
    alpine tar -czf /backup/$BACKUP_NAME-volumes.tar.gz /volumes

# Backup Prometheus data (last 24h)
docker exec prometheus promtool tsdb snapshot /prometheus
docker cp prometheus:/prometheus/snapshots $BACKUP_DIR/$BACKUP_NAME-prometheus
docker exec prometheus rm -rf /prometheus/snapshots

# Export Grafana dashboards
mkdir -p $BACKUP_DIR/$BACKUP_NAME-grafana-dashboards
curl -s -u admin:admin http://localhost:3000/api/search | jq -r '.[] | .uid' | while read uid; do
    curl -s -u admin:admin http://localhost:3000/api/dashboards/uid/$uid \
        > $BACKUP_DIR/$BACKUP_NAME-grafana-dashboards/$uid.json
done

# Remove old backups (keep last 7 days)
find $BACKUP_DIR -name "vps-backup-*" -mtime +7 -delete

echo "✅ Backup completed: $BACKUP_DIR/$BACKUP_NAME-*"

# Send metrics to Prometheus
cat << METRICS | curl -X POST http://localhost:9091/metrics/job/backup --data-binary @-
# TYPE backup_last_run_timestamp gauge
backup_last_run_timestamp $(date +%s)
# TYPE backup_size_bytes gauge
backup_size_bytes $(du -sb $BACKUP_DIR/$BACKUP_NAME-* | awk '{sum+=$1} END {print sum}')
# TYPE backup_duration_seconds gauge
backup_duration_seconds $SECONDS
METRICS
EOF

chmod +x /opt/backup.sh

# Schedule daily backups
echo "0 3 * * * root /opt/backup.sh >> /var/log/backup.log 2>&1" > /etc/cron.d/vps-backup

# ========================================
# PHASE 13: Monitoring Dashboard Setup
# ========================================
print_info "Phase 13: Additional Monitoring Dashboards"

# Create Docker monitoring dashboard
cat > /opt/grafana/provisioning/dashboards/docker-monitoring.json << 'EOF'
{
  "dashboard": {
    "id": null,
    "uid": "docker-monitoring",
    "title": "Docker Container Monitoring",
    "tags": ["docker"],
    "timezone": "browser",
    "panels": [
      {
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
        "id": 1,
        "title": "Container CPU Usage",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(container_cpu_usage_seconds_total{name=~\".+\"}[5m]) * 100",
            "legendFormat": "{{name}}"
          }
        ]
      },
      {
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0},
        "id": 2,
        "title": "Container Memory Usage",
        "type": "graph",
        "targets": [
          {
            "expr": "container_memory_usage_bytes{name=~\".+\"} / 1024 / 1024",
            "legendFormat": "{{name}}"
          }
        ]
      }
    ],
    "schemaVersion": 27,
    "version": 1
  }
}
EOF

# ========================================
# PHASE 14: Example Service with Monitoring
# ========================================
print_info "Phase 14: Example Service Configuration"

mkdir -p /opt/example-service
cat > /opt/example-service/docker-compose.yml << 'EOF'
version: '3.8'

services:
  api:
    image: your-api:latest
    container_name: api
    restart: always
    environment:
      - NODE_ENV=production
      - PORT=8000
      - PROMETHEUS_PORT=9100
    volumes:
      - /var/log/api-logs/access:/app/logs
    networks:
      - web
      - internal
      - monitoring
    labels:
      # Traefik configuration
      - "traefik.enable=true"
      - "traefik.http.routers.api.rule=Host(`api.${DOMAIN}`)"
      - "traefik.http.routers.api.entrypoints=websecure"
      - "traefik.http.routers.api.tls.certresolver=letsencrypt"
      - "traefik.http.routers.api.middlewares=rate-limit@file,security-headers@file,compress@file"
      - "traefik.http.services.api.loadbalancer.server.port=8000"
      # Prometheus monitoring
      - "prometheus.io/scrape=true"
      - "prometheus.io/port=9100"
      - "prometheus.io/path=/metrics"
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:8000/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  frontend:
    image: your-frontend:latest
    container_name: frontend
    restart: always
    environment:
      - NODE_ENV=production
      - API_URL=https://api.${DOMAIN}
    networks:
      - web
      - monitoring
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.frontend.rule=Host(`app.${DOMAIN}`)"
      - "traefik.http.routers.frontend.entrypoints=websecure"
      - "traefik.http.routers.frontend.tls.certresolver=letsencrypt"
      - "traefik.http.routers.frontend.middlewares=security-headers@file,compress@file"
      - "traefik.http.services.frontend.loadbalancer.server.port=3000"
      # Prometheus monitoring
      - "prometheus.io/scrape=true"
      - "prometheus.io/port=3000"
      - "prometheus.io/path=/metrics"

networks:
  web:
    external: true
  internal:
    external: true
  monitoring:
    external: true
EOF

# ========================================
# PHASE 15: Startup Scripts
# ========================================
print_info "Phase 15: Creating Startup Scripts"

# Create master startup script
cat > /usr/local/bin/vps-start << 'EOF'
#!/bin/bash

echo "🚀 Starting VPS services..."

# Start monitoring stack
echo "Starting Prometheus..."
cd /opt/prometheus && docker compose up -d

echo "Starting Grafana..."
cd /opt/grafana && docker compose up -d

echo "Starting Traefik..."
cd /opt/traefik && docker compose up -d

echo "Starting Uptime Kuma..."
cd /opt/uptime-kuma && docker compose up -d

echo "Starting Cloudflare Tunnel (if configured)..."
if [ -f /opt/cloudflared/credentials.json ] && [ -s /opt/cloudflared/credentials.json ]; then
    cd /opt/cloudflared && docker compose up -d
else
    echo "⚠️  Cloudflare Tunnel not configured yet"
fi

# Wait for services to be ready
sleep 10

# Check services
/usr/local/bin/vps-monitor

echo "✅ All services started!"
echo ""
echo "📊 Access your monitoring dashboards:"
echo "   Grafana: http://$(hostname -I | awk '{print $1}'):3000 (admin/admin)"
echo "   Prometheus: http://$(hostname -I | awk '{print $1}'):9090"
echo "   Uptime Kuma: http://$(hostname -I | awk '{print $1}'):3001"
echo "   Traefik: http://$(hostname -I | awk '{print $1}'):9080"
EOF

chmod +x /usr/local/bin/vps-start

# Create systemd service for auto-start
cat > /etc/systemd/system/vps-services.service << EOF
[Unit]
Description=VPS Docker Services
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/vps-start
ExecStop=/usr/bin/docker stop \$(docker ps -q)
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable vps-services

# ========================================
# COMPLETION
# ========================================
print_info "🎉 VPS Setup Complete!"

echo ""
echo -e "${GREEN}=== Summary ===${NC}"
echo "✅ System updated and secured"
echo "✅ Docker installed with optimized config"
echo "✅ Traefik reverse proxy configured"
echo "✅ Prometheus monitoring stack deployed"
echo "✅ Grafana dashboards configured"
echo "✅ Resource monitoring tools installed (Docker-based)"
echo "✅ Uptime Kuma monitoring ready"
echo "✅ Cloudflare Tunnel configured (Docker-based)"
echo "✅ Backup system configured"
echo ""
 
echo -e "${YELLOW}=== Monitoring Access ===${NC}"
echo "Grafana: http://$(hostname -I | awk '{print $1}'):3000"
echo "  Username: admin"
echo "  Password: admin (change on first login)"
echo ""
echo "Prometheus: http://$(hostname -I | awk '{print $1}'):9090"
echo "Uptime Kuma: http://$(hostname -I | awk '{print $1}'):3001"
echo "Traefik Dashboard: http://$(hostname -I | awk '{print $1}'):9080"
echo ""

echo -e "${BLUE}=== Quick Commands ===${NC}"
echo "Monitor resources: vps-monitor"
echo "Health check: vps-health"
echo "Start all services: vps-start"
echo "View logs: docker logs <container-name>"
echo "Backup now: /opt/backup.sh"
echo "System tools: docker exec -it monitoring-tools <command>"
echo ""

echo -e "${YELLOW}=== Next Steps ===${NC}"
echo "1. Add SSH key: echo 'your-key' >> /home/$CURRENT_USER/.ssh/authorized_keys"
echo "2. Configure Grafana alerts and notification channels"
echo "3. Set up Cloudflare Tunnel: cd /opt/cloudflared && docker compose run --rm cloudflared tunnel login"
echo "4. Deploy your applications using the example in /opt/example-service"
echo "5. Configure Uptime Kuma monitors for your services"
echo "6. Review Prometheus alerts in /opt/prometheus/config/alerts.yml"
echo ""

echo -e "${GREEN}Ready for production deployment with full monitoring! 🚀${NC}"