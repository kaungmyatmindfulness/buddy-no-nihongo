# Production Deployment Guide

This guide covers production deployment and management for the Wise Owl Golang microservices platform.

## Quick Start

### 1. Initial Setup

```bash
# Create production environment file
cp .env.docker.example .env.docker
# Edit .env.docker with your production values

# Start production services
./prod.sh start
```

### 2. Verify Deployment

```bash
# Check service status and health
./prod.sh status

# Monitor services in real-time
./monitor-prod.sh
```

### 3. Create Backup

```bash
# Create initial backup
./backup-prod.sh create
```

## Production Scripts Overview

### `prod.sh` - Main Production Management

**Key Features:**

- Uses `docker-compose.yml` (production configuration)
- Comprehensive health checks with 30-second timeout
- Service scaling capabilities
- Rolling deployment support
- Integrated backup commands

**Commands:**

```bash
./prod.sh start          # Start all services
./prod.sh stop           # Stop all services
./prod.sh restart        # Restart all services
./prod.sh status         # Show service status and health
./prod.sh logs [service] # View logs
./prod.sh deploy         # Deploy updates
./prod.sh deploy --pull  # Deploy with registry pull
./prod.sh backup         # Create database backup
./prod.sh scale users-service 3  # Scale service to 3 instances
```

### `monitor-prod.sh` - Continuous Health Monitoring

**Key Features:**

- Real-time dashboard with service status
- Configurable failure thresholds (default: 3 consecutive failures)
- Alert system (ready for webhook integration)
- Persistent logging to `logs/monitor.log`
- Automatic recovery detection

**Commands:**

```bash
./monitor-prod.sh         # Start monitoring dashboard
./monitor-prod.sh check   # Single health check
./monitor-prod.sh logs    # Show monitoring logs
./monitor-prod.sh reset   # Reset failure counters
```

**Configuration:**

- `CHECK_INTERVAL=30` - Seconds between checks
- `ALERT_THRESHOLD=3` - Failures before alert

### `backup-prod.sh` - Backup Management

**Key Features:**

- Automated compression with gzip + tar
- 7-day retention policy with automatic rotation
- Backup verification functionality
- Interactive restore with safety prompts
- Comprehensive manifest files

**Commands:**

```bash
./backup-prod.sh create           # Create new backup
./backup-prod.sh list             # List available backups
./backup-prod.sh restore <file>   # Restore from backup
./backup-prod.sh verify <file>    # Verify backup integrity
./backup-prod.sh rotate           # Manually rotate old backups
./backup-prod.sh clean            # Interactive cleanup
```

## Production Architecture

### Service Configuration

- **Nginx Gateway**: Port 80 (public access)
- **Users Service**: Port 8081 (internal health checks)
- **Content Service**: Port 8082 (internal health checks)
- **Quiz Service**: Port 8083 (internal health checks)
- **MongoDB**: Port 27017 (internal only)

### Health Check Strategy

1. **Initial Health Checks**: 30-second timeout with 2-second intervals
2. **Continuous Monitoring**: 30-second intervals with failure tracking
3. **Alert Thresholds**: 3 consecutive failures trigger alerts
4. **Recovery Detection**: Automatic notification when services recover

### Backup Strategy

1. **Database Coverage**: All service databases (users_db, content_db, quiz_db)
2. **Compression**: gzip + tar for optimal storage
3. **Retention**: 7-day automatic rotation
4. **Verification**: Built-in integrity checking
5. **Restore Safety**: Confirmation prompts and database replacement warnings

## Daily Operations

### Service Management

```bash
# Check overall system health
./prod.sh status

# View logs for troubleshooting
./prod.sh logs content

# Scale services under load
./prod.sh scale content-service 2
```

### Monitoring

```bash
# Start continuous monitoring (run in separate terminal)
./monitor-prod.sh

# Check recent monitoring events
./monitor-prod.sh logs
```

### Backup Operations

```bash
# Daily backup (can be automated via cron)
./backup-prod.sh create

# List available backups
./backup-prod.sh list

# Emergency restore
./backup-prod.sh restore backups/wise-owl-backup-20240124_120000.tar.gz
```

## Deployment Workflow

### Standard Deployment

```bash
# Deploy new version
./prod.sh deploy

# Monitor deployment
./monitor-prod.sh check

# Create post-deployment backup
./backup-prod.sh create
```

### Registry-Based Deployment

```bash
# Pull latest images and deploy
./prod.sh deploy --pull

# Verify all services are healthy
./prod.sh status
```

## Automation Setup

### Automated Backups (Crontab)

```bash
# Edit crontab
crontab -e

# Add daily backup at 2 AM
0 2 * * * /path/to/wise-owl-golang/backup-prod.sh create

# Add weekly cleanup at 3 AM Sunday
0 3 * * 0 /path/to/wise-owl-golang/backup-prod.sh rotate
```

### Health Monitoring Service

```bash
# Create systemd service for monitoring
sudo tee /etc/systemd/system/wise-owl-monitor.service << EOF
[Unit]
Description=Wise Owl Production Monitor
After=docker.service

[Service]
Type=simple
User=your-user
WorkingDirectory=/path/to/wise-owl-golang
ExecStart=/path/to/wise-owl-golang/monitor-prod.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Enable and start
sudo systemctl enable wise-owl-monitor
sudo systemctl start wise-owl-monitor
```

## Alert Integration

The monitoring script supports webhook integration for alerts. To enable:

1. **Edit `monitor-prod.sh`**:

   ```bash
   # Uncomment and configure webhook in send_alert() function
   WEBHOOK_URL="https://hooks.slack.com/services/your/webhook/url"
   ```

2. **Common Integration Examples**:
   - **Slack**: Use incoming webhooks
   - **Discord**: Use webhook URLs
   - **Email**: Add mail command integration
   - **PagerDuty**: Use Events API

## Troubleshooting

### Service Not Starting

```bash
# Check service logs
./prod.sh logs [service-name]

# Verify environment configuration
cat .env.docker

# Check Docker resources
docker system df
```

### Health Check Failures

```bash
# Manual health check
curl http://localhost/health-check

# Check individual service health
curl http://localhost:8081/health/ready  # users
curl http://localhost:8082/health/ready  # content
curl http://localhost:8083/health/ready  # quiz
```

### Backup Issues

```bash
# Verify MongoDB container
docker ps | grep mongodb

# Check backup permissions
ls -la backups/

# Test backup integrity
./backup-prod.sh verify backups/wise-owl-backup-latest.tar.gz
```

## Security Considerations

1. **Environment Variables**: Never commit `.env.docker` with real credentials
2. **Backup Security**: Store backups in secure, encrypted storage
3. **Network Security**: Use proper firewall rules for production
4. **Container Security**: Regularly update base images
5. **Access Control**: Limit SSH access to production servers

## Performance Monitoring

### Resource Usage

```bash
# Container resource usage
docker stats

# Service-specific stats
docker stats wo-users-service wo-content-service wo-quiz-service
```

### Database Performance

```bash
# MongoDB stats
docker exec wo-mongodb mongosh --eval "db.stats()"

# Check database sizes
docker exec wo-mongodb mongosh --eval "
  ['users_db', 'content_db', 'quiz_db'].forEach(db => {
    print(db + ': ' + (db.stats().dataSize / 1024 / 1024).toFixed(2) + ' MB')
  })
"
```

This production setup provides enterprise-grade reliability while maintaining the simplicity of your development workflow.
