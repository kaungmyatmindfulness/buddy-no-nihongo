# Wise Owl Monitoring Stack

This directory contains the complete monitoring setup for the Wise Owl Japanese vocabulary learning platform, featuring Docker-based tools that were moved from host installations for better isolation and management.

## 🎯 Overview

The monitoring stack provides comprehensive observability for the Wise Owl microservices architecture with:

- **Metrics Collection**: Prometheus with custom scraping for Wise Owl services
- **Visualization**: Grafana with pre-configured dashboards
- **Log Aggregation**: Loki and Promtail for centralized logging
- **Alerting**: Alertmanager with Slack/Discord integration
- **Distributed Tracing**: Jaeger for request tracing
- **System Monitoring**: Containerized system tools (htop, iotop, netstat, etc.)

## 🛠️ Tools Moved to Docker

Previously installed on host, now containerized:

| Tool                       | Container         | Purpose                 |
| -------------------------- | ----------------- | ----------------------- |
| `htop`, `iotop`, `sysstat` | `wo-system-tools` | System monitoring       |
| `net-tools`, `dnsutils`    | `wo-system-tools` | Network diagnostics     |
| `cloudflared`              | `wo-cloudflared`  | Tunnel management       |
| Prometheus                 | `wo-prometheus`   | Metrics collection      |
| Grafana                    | `wo-grafana`      | Dashboard visualization |

## 🚀 Quick Start

### 1. Start Monitoring Stack

```bash
# Start monitoring services
./wise-owl monitor start

# Or use the direct script
./monitoring/scripts/monitor-stack.sh start
```

### 2. Access Dashboards

- **Grafana**: http://localhost:3000 (admin/admin)
- **Prometheus**: http://localhost:9090
- **Alertmanager**: http://localhost:9093
- **Jaeger**: http://localhost:16686

### 3. System Monitoring

```bash
# Complete system overview
./wise-owl monitor system

# Specific monitoring areas
./monitoring/scripts/system-monitor.sh network
./monitoring/scripts/system-monitor.sh containers
./monitoring/scripts/system-monitor.sh health
```

## 📊 Available Commands

### Main Monitoring Commands

```bash
./wise-owl monitor start      # Start monitoring stack
./wise-owl monitor stop       # Stop monitoring stack
./wise-owl monitor status     # Show current status
./wise-owl monitor health     # Check service health
./wise-owl monitor logs       # View monitoring logs
./wise-owl monitor urls       # Show dashboard URLs
```

### System Monitoring Commands

```bash
./wise-owl monitor system              # Full system overview
./wise-owl monitor system network      # Network information
./wise-owl monitor system containers   # Container status
./wise-owl monitor system processes    # Process information
./wise-owl monitor system troubleshoot # Troubleshooting tools
```

### Advanced Management

```bash
# Setup for different environments
./monitoring/scripts/monitor-stack.sh setup-dev    # Development
./monitoring/scripts/monitor-stack.sh setup-prod   # Production

# Maintenance operations
./monitoring/scripts/monitor-stack.sh update       # Update images
./monitoring/scripts/monitor-stack.sh backup       # Backup data
./monitoring/scripts/monitor-stack.sh restart      # Restart services
```

## 🔧 System Tools Access

Access the containerized system tools:

```bash
# Interactive shell with all tools
docker exec -it wo-system-tools bash

# Direct command execution
docker exec wo-system-tools htop
docker exec wo-system-tools iotop
docker exec wo-system-tools netstat -tuln
docker exec wo-system-tools nslookup google.com
docker exec wo-system-tools tcpdump -i any
```

## 📈 Pre-configured Dashboards

### 1. System Overview Dashboard

- CPU, Memory, Disk usage
- Network traffic
- Container status
- Load averages

### 2. Services Dashboard

- Service response times
- Request rates and error rates
- Container resource usage
- MongoDB metrics
- Quiz service specific metrics

### 3. Logs Dashboard

- Centralized log viewing
- Log filtering and searching
- Error rate tracking

## 🚨 Alerting

### Alert Types

| Alert             | Severity | Threshold     | Action                 |
| ----------------- | -------- | ------------- | ---------------------- |
| High CPU Usage    | Warning  | >80% for 5min | Slack notification     |
| High Memory Usage | Warning  | >85% for 5min | Slack notification     |
| High Disk Usage   | Critical | >90% for 5min | Immediate notification |
| Container Down    | Critical | >1min down    | Immediate notification |
| High Error Rate   | Critical | >5% errors    | Immediate notification |

### Configuration

1. Copy environment template:

   ```bash
   cp .env.monitoring.example .env.monitoring
   ```

2. Configure Slack webhook in `.env.monitoring`:

   ```bash
   SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK
   ```

3. Update Alertmanager config in `monitoring/alertmanager/config.yml`

## 🏗️ Architecture Integration

### Network Configuration

```yaml
networks:
  wise-owl-network: # Main application network
  wo-monitoring: # Monitoring network
```

### Service Discovery

Prometheus automatically discovers Wise Owl services using Docker labels:

```yaml
labels:
  - "prometheus.io/scrape=true"
  - "prometheus.io/port=8080"
  - "prometheus.io/path=/health/metrics"
```

### Log Collection

Promtail collects logs from:

- All Wise Owl containers (`wo-*`)
- System logs (`/var/log/syslog`)
- Nginx access/error logs
- Application-specific logs

## 📁 Directory Structure

```
monitoring/
├── prometheus/
│   └── config/
│       ├── prometheus.yml           # Main Prometheus config
│       └── rules/
│           └── wise-owl-alerts.yml  # Alert rules
├── grafana/
│   ├── provisioning/
│   │   ├── datasources/             # Data source configs
│   │   └── dashboards/              # Dashboard provisioning
│   └── dashboards/                  # Dashboard JSON files
├── alertmanager/
│   └── config.yml                   # Alertmanager config
├── loki/
│   └── local-config.yaml           # Loki configuration
├── promtail/
│   └── config.yml                   # Log collection config
└── scripts/
    ├── monitor-stack.sh             # Main management script
    └── system-monitor.sh            # System monitoring script
```

## 🔍 Troubleshooting

### Common Issues

1. **Services not discovered by Prometheus**

   ```bash
   # Check service labels
   docker inspect wo-users-service | grep prometheus.io

   # Verify network connectivity
   docker exec wo-prometheus wget -qO- http://wo-users-service:8080/health/metrics
   ```

2. **High resource usage**

   ```bash
   # Check container resources
   ./wise-owl monitor system containers

   # Adjust resource limits in docker-compose.monitoring.yml
   ```

3. **Missing system tools**

   ```bash
   # Restart system tools container
   docker restart wo-system-tools

   # Or recreate with latest image
   docker compose -f docker-compose.monitoring.yml up -d --force-recreate wo-system-tools
   ```

### Log Analysis

```bash
# View specific service logs
./wise-owl monitor logs prometheus
./wise-owl monitor logs grafana

# Search logs in Grafana
# Use Loki data source with queries like:
# {container="wo-users-service"} |= "error"
# {job="system-logs"} |~ "failed|error"
```

## 🚀 Production Deployment

### Server Setup

```bash
# Setup production server with monitoring
./wise-owl deploy setup

# Deploy application with monitoring
./wise-owl monitor setup-prod
```

### Backup Strategy

```bash
# Automated backup (can be scheduled)
./monitoring/scripts/monitor-stack.sh backup

# Manual backup of specific data
docker run --rm \
  -v wo-monitoring_prometheus_data:/source \
  -v /opt/backups:/backup \
  alpine tar czf /backup/prometheus-$(date +%Y%m%d).tar.gz -C /source .
```

## 🔐 Security Considerations

1. **Change default passwords** in `.env.monitoring`
2. **Configure firewall** to restrict monitoring ports
3. **Use HTTPS** in production (configure in Traefik/Nginx)
4. **Regular updates** of monitoring images
5. **Secure alerting channels** (encrypted webhooks)

## 📚 Further Reading

- [Prometheus Configuration](https://prometheus.io/docs/prometheus/latest/configuration/configuration/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Loki Documentation](https://grafana.com/docs/loki/)
- [Alertmanager Configuration](https://prometheus.io/docs/alerting/latest/alertmanager/)
- [Wise Owl Architecture](../README.md)
