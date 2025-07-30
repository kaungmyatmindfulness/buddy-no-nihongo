// FILE: lib/health/simple.go
// Simplified health check system with AWS enhancements

package health

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"runtime"
	"time"

	"github.com/gin-gonic/gin"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/readpref"
)

// SimpleHealthChecker provides basic health checking
type SimpleHealthChecker struct {
	serviceName string
	startTime   time.Time
	mongoClient *mongo.Client
	dbName      string
}

// AWSHealthChecker extends SimpleHealthChecker with AWS-specific features
type AWSHealthChecker struct {
	*SimpleHealthChecker
	db         *mongo.Database
	grpcServer interface{}
}

// HealthResponse represents a simple health check response
type HealthResponse struct {
	Status    string    `json:"status"`
	Service   string    `json:"service"`
	Timestamp time.Time `json:"timestamp"`
	Uptime    string    `json:"uptime"`
	Database  string    `json:"database,omitempty"`
}

// DetailedHealthResponse represents a comprehensive health check response
type DetailedHealthResponse struct {
	Status    string                 `json:"status"`
	Service   string                 `json:"service"`
	Timestamp time.Time              `json:"timestamp"`
	Uptime    float64                `json:"uptime"`
	Checks    map[string]interface{} `json:"checks"`
	Memory    map[string]interface{} `json:"memory,omitempty"`
}

// NewSimpleHealthChecker creates a basic health checker
func NewSimpleHealthChecker(serviceName string) *SimpleHealthChecker {
	return &SimpleHealthChecker{
		serviceName: serviceName,
		startTime:   time.Now(),
	}
}

// NewAWSHealthChecker creates an AWS-enhanced health checker
func NewAWSHealthChecker(serviceName string, db *mongo.Database) *AWSHealthChecker {
	return &AWSHealthChecker{
		SimpleHealthChecker: NewSimpleHealthChecker(serviceName),
		db:                  db,
	}
}

// SetMongoClient configures MongoDB health checking
func (hc *SimpleHealthChecker) SetMongoClient(client *mongo.Client, dbName string) {
	hc.mongoClient = client
	hc.dbName = dbName
}

// Handler returns a simple health check handler
func (hc *SimpleHealthChecker) Handler() gin.HandlerFunc {
	return func(c *gin.Context) {
		response := HealthResponse{
			Service:   hc.serviceName,
			Timestamp: time.Now(),
			Uptime:    time.Since(hc.startTime).String(),
		}

		// Check MongoDB if configured
		if hc.mongoClient != nil {
			ctx, cancel := context.WithTimeout(c.Request.Context(), 3*time.Second)
			defer cancel()

			if err := hc.mongoClient.Ping(ctx, readpref.Primary()); err != nil {
				response.Status = "unhealthy"
				response.Database = "disconnected"
				c.JSON(http.StatusServiceUnavailable, response)
				return
			}
			response.Database = "connected"
		}

		response.Status = "healthy"
		c.JSON(http.StatusOK, response)
	}
}

// ReadyHandler returns a readiness probe handler
func (hc *SimpleHealthChecker) ReadyHandler() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Simple readiness check - just verify MongoDB if present
		if hc.mongoClient != nil {
			ctx, cancel := context.WithTimeout(c.Request.Context(), 2*time.Second)
			defer cancel()

			if err := hc.mongoClient.Ping(ctx, readpref.Primary()); err != nil {
				c.JSON(http.StatusServiceUnavailable, gin.H{"ready": false})
				return
			}
		}
		c.JSON(http.StatusOK, gin.H{"ready": true})
	}
}

// LiveHandler returns a liveness probe handler
func (hc *SimpleHealthChecker) LiveHandler() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"status":    "alive",
			"service":   hc.serviceName,
			"timestamp": time.Now().UTC(),
		})
	}
}

// RegisterRoutes registers health check routes based on environment
func (hc *SimpleHealthChecker) RegisterRoutes(router *gin.Engine) {
	health := router.Group("/health")
	{
		health.GET("/", hc.Handler())
		health.HEAD("/", hc.Handler())
		health.GET("/ready", hc.ReadyHandler())
		health.HEAD("/ready", hc.ReadyHandler())
		health.GET("/live", hc.LiveHandler())
		health.HEAD("/live", hc.LiveHandler())
	}
}

// RegisterRoutes for AWSHealthChecker - interface compatibility
func (h *AWSHealthChecker) RegisterRoutes(router *gin.Engine) {
	h.RegisterAWSRoutes(router)
}

// AWS-specific methods for AWSHealthChecker

// RegisterAWSRoutes registers AWS-enhanced health check routes
func (h *AWSHealthChecker) RegisterAWSRoutes(router *gin.Engine) {
	health := router.Group("/health")
	{
		health.GET("/", h.Handler())
		health.HEAD("/", h.Handler())
		health.GET("/ready", h.ReadinessCheck)
		health.HEAD("/ready", h.ReadinessCheck)
		health.GET("/live", h.LivenessCheck)
		health.HEAD("/live", h.LivenessCheck)
		health.GET("/deep", h.DeepHealthCheck) // For ALB health checks
	}
}

// ReadinessCheck provides AWS ALB-compatible readiness checking
func (h *AWSHealthChecker) ReadinessCheck(c *gin.Context) {
	// Check if service is ready to receive traffic
	checks := map[string]bool{
		"database": h.checkDatabase(),
		"grpc":     h.checkGRPC(),
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

// LivenessCheck provides AWS ALB-compatible liveness checking
func (h *AWSHealthChecker) LivenessCheck(c *gin.Context) {
	// Simple check if service is alive
	c.JSON(http.StatusOK, gin.H{
		"status":    "alive",
		"service":   h.serviceName,
		"timestamp": time.Now().UTC(),
	})
}

// DeepHealthCheck provides comprehensive health check for monitoring
func (h *AWSHealthChecker) DeepHealthCheck(c *gin.Context) {
	// Comprehensive health check for monitoring
	checks := map[string]interface{}{
		"database":    h.getDatabaseStatus(),
		"memory":      h.getMemoryUsage(),
		"uptime":      time.Since(h.startTime).Seconds(),
		"environment": h.getEnvironmentInfo(),
	}

	c.JSON(http.StatusOK, gin.H{
		"service":   h.serviceName,
		"status":    "healthy",
		"checks":    checks,
		"timestamp": time.Now().UTC(),
	})
}

// checkDatabase verifies database connectivity
func (h *AWSHealthChecker) checkDatabase() bool {
	if h.db == nil {
		return false
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	return h.db.Client().Ping(ctx, nil) == nil
}

// checkGRPC verifies gRPC server status (placeholder for future implementation)
func (h *AWSHealthChecker) checkGRPC() bool {
	// TODO: Implement gRPC health check when gRPC servers are added
	return true
}

// getDatabaseStatus returns detailed database status
func (h *AWSHealthChecker) getDatabaseStatus() map[string]interface{} {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	status := map[string]interface{}{
		"connected": false,
		"latency":   0,
	}

	if h.db != nil {
		start := time.Now()
		if err := h.db.Client().Ping(ctx, nil); err == nil {
			status["connected"] = true
			status["latency"] = time.Since(start).Milliseconds()
		}
	}

	return status
}

// getMemoryUsage returns current memory usage statistics
func (h *AWSHealthChecker) getMemoryUsage() map[string]interface{} {
	var m runtime.MemStats
	runtime.ReadMemStats(&m)

	return map[string]interface{}{
		"alloc":      m.Alloc,
		"totalAlloc": m.TotalAlloc,
		"sys":        m.Sys,
		"numGC":      m.NumGC,
	}
}

// getEnvironmentInfo returns environment information
func (h *AWSHealthChecker) getEnvironmentInfo() map[string]interface{} {
	return map[string]interface{}{
		"aws_execution_env": os.Getenv("AWS_EXECUTION_ENV"),
		"ecs_container":     os.Getenv("ECS_CONTAINER_METADATA_URI") != "",
		"go_version":        runtime.Version(),
		"arch":              runtime.GOARCH,
		"os":                runtime.GOOS,
	}
}
