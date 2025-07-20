// FILE: lib/health/simple.go
// Simplified health check system - replaces the complex health.go

package health

import (
	"context"
	"net/http"
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

// HealthResponse represents a simple health check response
type HealthResponse struct {
	Status    string    `json:"status"`
	Service   string    `json:"service"`
	Timestamp time.Time `json:"timestamp"`
	Uptime    string    `json:"uptime"`
	Database  string    `json:"database,omitempty"`
}

// NewSimpleHealthChecker creates a basic health checker
func NewSimpleHealthChecker(serviceName string) *SimpleHealthChecker {
	return &SimpleHealthChecker{
		serviceName: serviceName,
		startTime:   time.Now(),
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
