# Health Checks and Dependencies

This document describes the enhanced health check system implemented for the Wise Owl services.

## Overview

The health check system provides comprehensive monitoring capabilities with:

- **Circuit breaker pattern** to prevent cascading failures
- **Detailed dependency tracking** with configurable timeouts
- **Multiple health endpoints** for different use cases
- **Metrics collection** for observability
- **Enhanced logging** with reduced noise

## Health Endpoints

### Primary Endpoints

| Endpoint          | Purpose                        | Response Codes                                      |
| ----------------- | ------------------------------ | --------------------------------------------------- |
| `/health`         | Overall service health         | 200 (healthy), 503 (unhealthy)                      |
| `/health/ready`   | Kubernetes readiness probe     | 200 (ready), 202 (partially ready), 503 (not ready) |
| `/health/live`    | Kubernetes liveness probe      | 200 (always, unless service is completely down)     |
| `/health/metrics` | Health check metrics and stats | 200                                                 |

### Legacy Endpoint

- `/health-legacy` - Simple health check for backward compatibility

## Service Dependencies

### Content Service

- **Dependencies**: None (base service)
- **Health Checks**: MongoDB connection only

### Users Service

- **Dependencies**: None (independent service)
- **Health Checks**: MongoDB connection only

### Quiz Service

- **Dependencies**: Content Service (via HTTP and gRPC)
- **Health Checks**: MongoDB + Content Service availability

## Circuit Breaker Pattern

Each service dependency is protected by a circuit breaker that:

- **Closed State**: Normal operation, requests pass through
- **Open State**: Service is failing, requests are rejected immediately
- **Half-Open State**: Testing if service has recovered

### Configuration

```env
HEALTH_CB_ENABLED=true
HEALTH_CB_FAILURE_THRESHOLD=5      # Failures before opening circuit
HEALTH_CB_RECOVERY_TIMEOUT=30s     # Time before trying again
HEALTH_CB_SUCCESS_THRESHOLD=2      # Successes needed to close circuit
```

## Health Check Configuration

### Timeouts

```env
HEALTH_DEFAULT_TIMEOUT=10s    # Overall health check timeout
HEALTH_MONGO_TIMEOUT=5s       # MongoDB ping timeout
HEALTH_HTTP_TIMEOUT=5s        # HTTP dependency check timeout
HEALTH_TCP_TIMEOUT=3s         # TCP connection timeout
```

### Service URLs (optional overrides)

```env
CONTENT_SERVICE_URL=http://content-service:8080
USERS_SERVICE_URL=http://users-service:8080
QUIZ_SERVICE_URL=http://quiz-service:8080
```

## Response Examples

### Healthy Service

```json
{
	"status": "healthy",
	"service": "Content Service",
	"version": "1.0.0",
	"timestamp": "2024-01-15T10:30:00Z",
	"uptime": "2h45m30s",
	"environment": "development",
	"checks": {
		"mongodb": {
			"status": "healthy",
			"message": "MongoDB connection successful",
			"duration": "2ms",
			"timestamp": "2024-01-15T10:30:00Z",
			"details": {
				"database": "content_db"
			}
		}
	}
}
```

### Unhealthy Service with Dependencies

```json
{
	"status": "unhealthy",
	"service": "Quiz Service",
	"version": "1.0.0",
	"timestamp": "2024-01-15T10:30:00Z",
	"uptime": "1h15m22s",
	"environment": "development",
	"checks": {
		"mongodb": {
			"status": "healthy",
			"message": "MongoDB connection successful",
			"duration": "3ms",
			"timestamp": "2024-01-15T10:30:00Z",
			"details": {
				"database": "quiz_db"
			}
		},
		"content-service": {
			"status": "unhealthy",
			"message": "Failed to connect to content-service: connection refused",
			"duration": "5s",
			"timestamp": "2024-01-15T10:30:00Z",
			"details": {
				"url": "http://content-service:8080/health"
			}
		}
	}
}
```

### Readiness Check - Partially Ready

```json
{
	"status": "partially_ready",
	"service": "Quiz Service",
	"timestamp": "2024-01-15T10:30:00Z",
	"critical_healthy": true,
	"total_healthy": false,
	"checks": {
		"mongodb": {
			"status": "healthy",
			"message": "MongoDB connection successful",
			"duration": "2ms",
			"timestamp": "2024-01-15T10:30:00Z"
		},
		"content-service": {
			"status": "unhealthy",
			"message": "Service returned status 503",
			"duration": "100ms",
			"timestamp": "2024-01-15T10:30:00Z"
		}
	}
}
```

## Docker Compose Integration

The health checks are integrated with Docker Compose health checks:

```yaml
healthcheck:
  test:
    [
      "CMD",
      "wget",
      "--no-verbose",
      "--tries=1",
      "--spider",
      "http://localhost:8080/health/ready",
    ]
  interval: 15s
  timeout: 10s
  retries: 3
  start_period: 45s
```

## Kubernetes Integration

For Kubernetes deployments:

```yaml
livenessProbe:
  httpGet:
    path: /health/live
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10

readinessProbe:
  httpGet:
    path: /health/ready
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5
```

## Monitoring and Alerting

### Key Metrics to Monitor

- Health check response times
- Circuit breaker state changes
- Dependency availability percentages
- Error rates and patterns

### Alerting Recommendations

- Alert on service unhealthy for > 2 minutes
- Alert on circuit breaker open state
- Alert on MongoDB connection failures
- Monitor dependency cascade failures

## Troubleshooting

### Common Issues

1. **Circuit Breaker Stuck Open**

   - Check if dependent service is actually healthy
   - Verify network connectivity
   - Review failure threshold configuration

2. **MongoDB Health Check Failures**

   - Verify MongoDB connection string
   - Check MongoDB server status
   - Review timeout configurations

3. **False Positive Health Failures**
   - Adjust timeout values for slow networks
   - Review circuit breaker thresholds
   - Check for resource constraints

### Debugging Commands

```bash
# Check service health
curl http://localhost:8080/health

# Check readiness status
curl http://localhost:8080/health/ready

# View health metrics
curl http://localhost:8080/health/metrics

# Test with verbose output
curl -v http://localhost:8080/health
```
