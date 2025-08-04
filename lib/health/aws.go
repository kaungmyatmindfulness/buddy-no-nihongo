// FILE: lib/health/aws.go
// Enhanced health checks for AWS deployment

package health

import (
	"context"
	"fmt"
	"net/http"
	"runtime"
	"time"

	"github.com/gin-gonic/gin"
	"go.mongodb.org/mongo-driver/mongo"
)

// AWSEnhancedHealthChecker extends SimpleHealthChecker with AWS-specific features
type AWSEnhancedHealthChecker struct {
	*SimpleHealthChecker
	db *mongo.Database
}

// NewAWSEnhancedHealthChecker creates a new AWS-optimized health checker
func NewAWSEnhancedHealthChecker(serviceName string, db *mongo.Database) *AWSEnhancedHealthChecker {
	return &AWSEnhancedHealthChecker{
		SimpleHealthChecker: NewSimpleHealthChecker(serviceName),
		db:                  db,
	}
}

// RegisterRoutes registers health check routes for interface compatibility
func (h *AWSEnhancedHealthChecker) RegisterRoutes(router *gin.Engine) {
	h.RegisterAWSRoutes(router)
}

// RegisterAWSRoutes registers AWS-specific health check routes
func (h *AWSEnhancedHealthChecker) RegisterAWSRoutes(router *gin.Engine) {
	health := router.Group("/health")
	{
		health.GET("/", h.BasicHealth)
		health.GET("/ready", h.ReadinessCheck)
		health.GET("/live", h.LivenessCheck)
		health.GET("/deep", h.DeepHealthCheck)
	}
}

// BasicHealth provides a simple health status
func (h *AWSEnhancedHealthChecker) BasicHealth(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"status":    "healthy",
		"service":   h.serviceName,
		"timestamp": time.Now().UTC(),
	})
}

// ReadinessCheck performs comprehensive readiness checks for AWS ALB
func (h *AWSEnhancedHealthChecker) ReadinessCheck(c *gin.Context) {
	checks := map[string]bool{
		"database": h.checkDatabase(),
	}

	allReady := true
	for _, ready := range checks {
		if !ready {
			allReady = false
			break
		}
	}

	status := http.StatusOK
	if !allReady {
		status = http.StatusServiceUnavailable
	}

	c.JSON(status, gin.H{
		"status": map[string]string{
			"ready": fmt.Sprintf("%t", allReady),
		},
		"checks":    checks,
		"timestamp": time.Now().UTC(),
	})
}

// LivenessCheck performs basic liveness check for AWS ECS
func (h *AWSEnhancedHealthChecker) LivenessCheck(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"status":    "alive",
		"service":   h.serviceName,
		"timestamp": time.Now().UTC(),
	})
}

// DeepHealthCheck provides comprehensive health information for monitoring
func (h *AWSEnhancedHealthChecker) DeepHealthCheck(c *gin.Context) {
	var m runtime.MemStats
	runtime.ReadMemStats(&m)

	checks := map[string]interface{}{
		"database": h.getDatabaseStatus(),
		"memory": map[string]interface{}{
			"alloc_mb":       m.Alloc / 1024 / 1024,
			"total_alloc_mb": m.TotalAlloc / 1024 / 1024,
			"sys_mb":         m.Sys / 1024 / 1024,
		},
		"uptime": time.Since(h.startTime).Seconds(),
	}

	c.JSON(http.StatusOK, gin.H{
		"service":   h.serviceName,
		"status":    "healthy",
		"checks":    checks,
		"timestamp": time.Now().UTC(),
	})
}

// checkDatabase verifies database connectivity
func (h *AWSEnhancedHealthChecker) checkDatabase() bool {
	if h.db == nil {
		return false
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	return h.db.Client().Ping(ctx, nil) == nil
}

// getDatabaseStatus returns detailed database status information
func (h *AWSEnhancedHealthChecker) getDatabaseStatus() map[string]interface{} {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	status := map[string]interface{}{
		"connected": false,
		"latency":   0,
	}

	start := time.Now()
	if err := h.db.Client().Ping(ctx, nil); err == nil {
		status["connected"] = true
		status["latency"] = time.Since(start).Milliseconds()
	}

	return status
}

// Handler returns the basic health handler for interface compatibility
func (h *AWSEnhancedHealthChecker) Handler() gin.HandlerFunc {
	return h.BasicHealth
}

// ReadyHandler returns the readiness handler for interface compatibility
func (h *AWSEnhancedHealthChecker) ReadyHandler() gin.HandlerFunc {
	return h.ReadinessCheck
}
