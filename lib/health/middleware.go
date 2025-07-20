// FILE: lib/health/middleware.go
// This file provides middleware and utilities for health check observability

package health

import (
	"context"
	"log"
	"time"

	"github.com/gin-gonic/gin"
)

// HealthMetrics holds metrics about health checks
type HealthMetrics struct {
	TotalChecks       int64                  `json:"total_checks"`
	FailedChecks      int64                  `json:"failed_checks"`
	LastCheck         time.Time              `json:"last_check"`
	AverageCheckTime  time.Duration          `json:"average_check_time"`
	DependencyMetrics map[string]*DepMetrics `json:"dependency_metrics"`
}

// DepMetrics holds metrics for individual dependencies
type DepMetrics struct {
	TotalChecks      int64         `json:"total_checks"`
	SuccessfulChecks int64         `json:"successful_checks"`
	FailedChecks     int64         `json:"failed_checks"`
	LastSuccess      time.Time     `json:"last_success"`
	LastFailure      time.Time     `json:"last_failure"`
	AverageLatency   time.Duration `json:"average_latency"`
	CircuitState     string        `json:"circuit_state"`
}

// HealthChecker metrics methods
func (hc *HealthChecker) GetMetrics() HealthMetrics {
	hc.mutex.RLock()
	defer hc.mutex.RUnlock()

	metrics := HealthMetrics{
		DependencyMetrics: make(map[string]*DepMetrics),
	}

	for name, cb := range hc.circuitBreakers {
		if cb != nil {
			depMetrics := &DepMetrics{
				CircuitState: cb.state,
			}
			metrics.DependencyMetrics[name] = depMetrics
		}
	}

	return metrics
}

// LoggingMiddleware provides logging for health check requests
func LoggingMiddleware() gin.HandlerFunc {
	return gin.LoggerWithFormatter(func(param gin.LogFormatterParams) string {
		// Custom log format for health checks - suppress health check logs
		if param.Path == "/health" || param.Path == "/health/ready" || param.Path == "/health/live" {
			return ""
		}
		// Return default format for non-health endpoints
		return param.TimeStamp.Format("2006/01/02 - 15:04:05") + " | " +
			param.StatusCodeColor() + string(rune(param.StatusCode)) + param.ResetColor() + " | " +
			param.Latency.String() + " | " +
			param.ClientIP + " | " +
			param.Method + " | " +
			param.Path + "\n"
	})
}

// HealthCheckLogger logs health check results
func (hc *HealthChecker) logHealthStatus(status HealthStatus) {
	if status.Status != "healthy" {
		log.Printf("HEALTH CHECK FAILED: %s - %s", status.Service, status.Status)
		for checkName, result := range status.Checks {
			if result.Status != "healthy" {
				log.Printf("  - %s: %s (took %v)", checkName, result.Message, result.Duration)
			}
		}
	} else {
		log.Printf("Health check passed for %s (uptime: %s)", status.Service, status.Uptime)
	}
}

// Enhanced handler that includes logging
func (hc *HealthChecker) CreateEnhancedHandler() gin.HandlerFunc {
	return func(c *gin.Context) {
		ctx, cancel := context.WithTimeout(c.Request.Context(), hc.defaultTimeout)
		defer cancel()

		health := hc.performHealthCheck(ctx)

		// Log health status
		hc.logHealthStatus(health)

		// Return appropriate HTTP status based on health
		if health.Status == "healthy" {
			c.JSON(200, health)
		} else {
			c.JSON(503, health)
		}
	}
}

// MetricsHandler provides a separate endpoint for health metrics
func (hc *HealthChecker) CreateMetricsHandler() gin.HandlerFunc {
	return func(c *gin.Context) {
		metrics := hc.GetMetrics()
		c.JSON(200, metrics)
	}
}

// DetailedReadinessHandler provides more detailed readiness information
func (hc *HealthChecker) CreateDetailedReadinessHandler() gin.HandlerFunc {
	return func(c *gin.Context) {
		ctx, cancel := context.WithTimeout(c.Request.Context(), hc.defaultTimeout)
		defer cancel()

		checks := make(map[string]CheckResult)
		criticalHealthy := true
		totalHealthy := true

		// Only check critical dependencies for readiness
		hc.mutex.RLock()
		deps := make(map[string]*DependencyConfig)
		for k, v := range hc.dependencies {
			deps[k] = v
		}
		hc.mutex.RUnlock()

		// Check MongoDB first (always critical)
		if hc.mongoClient != nil {
			mongoResult := hc.checkMongoDB(ctx)
			checks["mongodb"] = mongoResult
			if mongoResult.Status != "healthy" {
				criticalHealthy = false
				totalHealthy = false
			}
		}

		// Check dependencies
		for serviceName, config := range deps {
			depResult := hc.checkDependencyWithConfig(ctx, serviceName, config)
			checks[serviceName] = depResult

			if depResult.Status != "healthy" {
				totalHealthy = false
				if config.Critical {
					criticalHealthy = false
				}
			}
		}

		// Determine readiness level
		readinessLevel := "fully_ready"
		if !totalHealthy && criticalHealthy {
			readinessLevel = "partially_ready"
		} else if !criticalHealthy {
			readinessLevel = "not_ready"
		}

		result := map[string]interface{}{
			"status":           readinessLevel,
			"service":          hc.serviceName,
			"timestamp":        time.Now(),
			"critical_healthy": criticalHealthy,
			"total_healthy":    totalHealthy,
			"checks":           checks,
		}

		statusCode := 200
		if readinessLevel == "not_ready" {
			statusCode = 503
		} else if readinessLevel == "partially_ready" {
			statusCode = 202 // Accepted but not fully ready
		}

		c.JSON(statusCode, result)
	}
}
