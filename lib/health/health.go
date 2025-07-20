// FILE: lib/health/health.go
// This package provides a comprehensive health check handler for all services.

package health

import (
	"context"
	"fmt"
	"net"
	"net/http"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/readpref"
)

// HealthStatus represents the overall health of the service
type HealthStatus struct {
	Status      string                 `json:"status"`      // "healthy" or "unhealthy"
	Service     string                 `json:"service"`     // Service name
	Version     string                 `json:"version"`     // Service version
	Timestamp   time.Time              `json:"timestamp"`   // Current time
	Uptime      string                 `json:"uptime"`      // How long service has been running
	Checks      map[string]CheckResult `json:"checks"`      // Individual health checks
	Environment string                 `json:"environment"` // dev/staging/production
}

// CheckResult represents the result of an individual health check
type CheckResult struct {
	Status    string        `json:"status"`            // "healthy" or "unhealthy"
	Message   string        `json:"message,omitempty"` // Optional details
	Duration  time.Duration `json:"duration"`          // How long check took
	Timestamp time.Time     `json:"timestamp"`         // When check was performed
	Details   interface{}   `json:"details,omitempty"` // Additional context
}

// DependencyConfig holds configuration for a service dependency
type DependencyConfig struct {
	Name         string            `json:"name"`
	URL          string            `json:"url"`
	Timeout      time.Duration     `json:"timeout"`
	Critical     bool              `json:"critical"`   // Whether this dependency is critical for service operation
	CheckType    string            `json:"check_type"` // "http", "grpc", "tcp"
	Headers      map[string]string `json:"headers,omitempty"`
	ExpectedCode int               `json:"expected_code,omitempty"`
}

// CircuitBreakerConfig holds circuit breaker configuration
type CircuitBreakerConfig struct {
	FailureThreshold int           `json:"failure_threshold"` // Number of failures before opening circuit
	RecoveryTimeout  time.Duration `json:"recovery_timeout"`  // Time to wait before trying again
	SuccessThreshold int           `json:"success_threshold"` // Number of successes needed to close circuit
	Enabled          bool          `json:"enabled"`
}

// CircuitBreaker implements a basic circuit breaker pattern
type CircuitBreaker struct {
	config          CircuitBreakerConfig
	state           string // "closed", "open", "half-open"
	failureCount    int
	successCount    int
	lastFailureTime time.Time
	mutex           sync.RWMutex
}

// HealthChecker provides methods for health checking
type HealthChecker struct {
	serviceName     string
	version         string
	environment     string
	startTime       time.Time
	mongoClient     *mongo.Client
	dbName          string
	dependencies    map[string]*DependencyConfig
	circuitBreakers map[string]*CircuitBreaker
	defaultTimeout  time.Duration
	mutex           sync.RWMutex
}

// NewHealthChecker creates a new health checker instance
func NewHealthChecker(serviceName, version, environment string) *HealthChecker {
	return &HealthChecker{
		serviceName:     serviceName,
		version:         version,
		environment:     environment,
		startTime:       time.Now(),
		dependencies:    make(map[string]*DependencyConfig),
		circuitBreakers: make(map[string]*CircuitBreaker),
		defaultTimeout:  10 * time.Second,
	}
}

// NewCircuitBreaker creates a new circuit breaker with default configuration
func NewCircuitBreaker() *CircuitBreaker {
	return &CircuitBreaker{
		config: CircuitBreakerConfig{
			FailureThreshold: 5,
			RecoveryTimeout:  30 * time.Second,
			SuccessThreshold: 2,
			Enabled:          true,
		},
		state: "closed",
	}
}

// CanExecute checks if the circuit breaker allows execution
func (cb *CircuitBreaker) CanExecute() bool {
	cb.mutex.RLock()
	defer cb.mutex.RUnlock()

	if !cb.config.Enabled {
		return true
	}

	switch cb.state {
	case "closed":
		return true
	case "open":
		return time.Since(cb.lastFailureTime) >= cb.config.RecoveryTimeout
	case "half-open":
		return true
	default:
		return false
	}
}

// RecordSuccess records a successful operation
func (cb *CircuitBreaker) RecordSuccess() {
	cb.mutex.Lock()
	defer cb.mutex.Unlock()

	if !cb.config.Enabled {
		return
	}

	cb.failureCount = 0
	if cb.state == "half-open" {
		cb.successCount++
		if cb.successCount >= cb.config.SuccessThreshold {
			cb.state = "closed"
			cb.successCount = 0
		}
	}
}

// RecordFailure records a failed operation
func (cb *CircuitBreaker) RecordFailure() {
	cb.mutex.Lock()
	defer cb.mutex.Unlock()

	if !cb.config.Enabled {
		return
	}

	cb.failureCount++
	cb.lastFailureTime = time.Now()

	if cb.failureCount >= cb.config.FailureThreshold {
		cb.state = "open"
		cb.successCount = 0
	} else if cb.state == "half-open" {
		cb.state = "open"
		cb.successCount = 0
	}
}

// SetMongoClient sets the MongoDB client for database health checks
func (hc *HealthChecker) SetMongoClient(client *mongo.Client, dbName string) {
	hc.mutex.Lock()
	defer hc.mutex.Unlock()
	hc.mongoClient = client
	hc.dbName = dbName
}

// AddDependency adds a service dependency to check with default configuration
func (hc *HealthChecker) AddDependency(serviceName, url string) {
	hc.AddDependencyWithConfig(serviceName, &DependencyConfig{
		Name:         serviceName,
		URL:          url,
		Timeout:      5 * time.Second,
		Critical:     true,
		CheckType:    "http",
		ExpectedCode: http.StatusOK,
	})
}

// AddDependencyWithConfig adds a service dependency with custom configuration
func (hc *HealthChecker) AddDependencyWithConfig(serviceName string, config *DependencyConfig) {
	hc.mutex.Lock()
	defer hc.mutex.Unlock()
	hc.dependencies[serviceName] = config

	// Initialize circuit breaker for this dependency
	if hc.circuitBreakers[serviceName] == nil {
		hc.circuitBreakers[serviceName] = NewCircuitBreaker()
	}
}

// SetCircuitBreakerConfig updates circuit breaker configuration for a dependency
func (hc *HealthChecker) SetCircuitBreakerConfig(serviceName string, config CircuitBreakerConfig) {
	hc.mutex.Lock()
	defer hc.mutex.Unlock()

	if cb := hc.circuitBreakers[serviceName]; cb != nil {
		cb.config = config
	}
}

// CreateHandler returns a Gin handler for the health check endpoint
func (hc *HealthChecker) CreateHandler() gin.HandlerFunc {
	return func(c *gin.Context) {
		ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
		defer cancel()

		health := hc.performHealthCheck(ctx)

		// Return appropriate HTTP status based on health
		if health.Status == "healthy" {
			c.JSON(http.StatusOK, health)
		} else {
			c.JSON(http.StatusServiceUnavailable, health)
		}
	}
}

// CreateReadinessHandler returns a Gin handler for the readiness check endpoint
func (hc *HealthChecker) CreateReadinessHandler() gin.HandlerFunc {
	return func(c *gin.Context) {
		ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
		defer cancel()

		checks := make(map[string]CheckResult)
		overallHealthy := true

		// Only check critical dependencies for readiness
		if hc.mongoClient != nil {
			mongoResult := hc.checkMongoDB(ctx)
			checks["mongodb"] = mongoResult
			if mongoResult.Status != "healthy" {
				overallHealthy = false
			}
		}

		status := "ready"
		if !overallHealthy {
			status = "not_ready"
		}

		result := map[string]interface{}{
			"status":    status,
			"service":   hc.serviceName,
			"timestamp": time.Now(),
			"checks":    checks,
		}

		if overallHealthy {
			c.JSON(http.StatusOK, result)
		} else {
			c.JSON(http.StatusServiceUnavailable, result)
		}
	}
}

// CreateLivenessHandler returns a Gin handler for the liveness check endpoint
func (hc *HealthChecker) CreateLivenessHandler() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Liveness is just checking if the service is alive
		// This should be very lightweight
		c.JSON(http.StatusOK, map[string]interface{}{
			"status":    "alive",
			"service":   hc.serviceName,
			"timestamp": time.Now(),
			"uptime":    time.Since(hc.startTime).String(),
		})
	}
}

// performHealthCheck executes all health checks
func (hc *HealthChecker) performHealthCheck(ctx context.Context) HealthStatus {
	checks := make(map[string]CheckResult)
	overallHealthy := true

	// Check MongoDB if configured
	if hc.mongoClient != nil {
		mongoResult := hc.checkMongoDB(ctx)
		checks["mongodb"] = mongoResult
		if mongoResult.Status != "healthy" {
			overallHealthy = false
		}
	}

	// Check service dependencies
	hc.mutex.RLock()
	deps := make(map[string]*DependencyConfig)
	for k, v := range hc.dependencies {
		deps[k] = v
	}
	hc.mutex.RUnlock()

	for serviceName, config := range deps {
		depResult := hc.checkDependencyWithConfig(ctx, serviceName, config)
		checks[serviceName] = depResult
		if depResult.Status != "healthy" && config.Critical {
			overallHealthy = false
		}
	}

	status := "healthy"
	if !overallHealthy {
		status = "unhealthy"
	}

	return HealthStatus{
		Status:      status,
		Service:     hc.serviceName,
		Version:     hc.version,
		Timestamp:   time.Now(),
		Uptime:      time.Since(hc.startTime).String(),
		Checks:      checks,
		Environment: hc.environment,
	}
}

// checkMongoDB performs a health check on MongoDB connection
func (hc *HealthChecker) checkMongoDB(ctx context.Context) CheckResult {
	start := time.Now()

	// Create a context with timeout for the MongoDB ping
	pingCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()

	err := hc.mongoClient.Ping(pingCtx, readpref.Primary())
	duration := time.Since(start)

	if err != nil {
		return CheckResult{
			Status:    "unhealthy",
			Message:   "Failed to ping MongoDB: " + err.Error(),
			Duration:  duration,
			Timestamp: time.Now(),
			Details:   map[string]interface{}{"database": hc.dbName},
		}
	}

	return CheckResult{
		Status:    "healthy",
		Message:   "MongoDB connection successful",
		Duration:  duration,
		Timestamp: time.Now(),
		Details:   map[string]interface{}{"database": hc.dbName},
	}
}

// checkDependencyWithConfig performs a health check on a service dependency with configuration
func (hc *HealthChecker) checkDependencyWithConfig(ctx context.Context, serviceName string, config *DependencyConfig) CheckResult {
	start := time.Now()

	// Get circuit breaker for this dependency
	cb := hc.circuitBreakers[serviceName]
	if cb != nil && !cb.CanExecute() {
		return CheckResult{
			Status:    "unhealthy",
			Message:   fmt.Sprintf("Circuit breaker is open for %s", serviceName),
			Duration:  time.Since(start),
			Timestamp: time.Now(),
			Details: map[string]interface{}{
				"circuit_breaker_state": cb.state,
				"failure_count":         cb.failureCount,
			},
		}
	}

	// Perform the actual health check
	var result CheckResult
	switch config.CheckType {
	case "http":
		result = hc.checkHTTPDependency(ctx, config)
	case "tcp":
		result = hc.checkTCPDependency(ctx, config)
	default:
		result = hc.checkHTTPDependency(ctx, config) // Default to HTTP
	}

	// Update circuit breaker based on result
	if cb != nil {
		if result.Status == "healthy" {
			cb.RecordSuccess()
		} else {
			cb.RecordFailure()
		}
	}

	return result
}

// checkHTTPDependency performs HTTP health check
func (hc *HealthChecker) checkHTTPDependency(ctx context.Context, config *DependencyConfig) CheckResult {
	start := time.Now()

	client := &http.Client{Timeout: config.Timeout}

	// Create health check URL
	healthURL := config.URL + "/health"
	req, err := http.NewRequestWithContext(ctx, "GET", healthURL, nil)
	if err != nil {
		return CheckResult{
			Status:    "unhealthy",
			Message:   "Failed to create request: " + err.Error(),
			Duration:  time.Since(start),
			Timestamp: time.Now(),
			Details:   map[string]interface{}{"url": healthURL},
		}
	}

	// Add custom headers
	for key, value := range config.Headers {
		req.Header.Set(key, value)
	}

	resp, err := client.Do(req)
	duration := time.Since(start)

	if err != nil {
		return CheckResult{
			Status:    "unhealthy",
			Message:   fmt.Sprintf("Failed to connect to %s: %s", config.Name, err.Error()),
			Duration:  duration,
			Timestamp: time.Now(),
			Details:   map[string]interface{}{"url": healthURL},
		}
	}
	defer resp.Body.Close()

	expectedCode := config.ExpectedCode
	if expectedCode == 0 {
		expectedCode = http.StatusOK
	}

	if resp.StatusCode != expectedCode {
		return CheckResult{
			Status:    "unhealthy",
			Message:   fmt.Sprintf("Service returned status %d (expected %d)", resp.StatusCode, expectedCode),
			Duration:  duration,
			Timestamp: time.Now(),
			Details: map[string]interface{}{
				"url":           healthURL,
				"status_code":   resp.StatusCode,
				"expected_code": expectedCode,
			},
		}
	}

	return CheckResult{
		Status:    "healthy",
		Message:   "Service responding normally",
		Duration:  duration,
		Timestamp: time.Now(),
		Details: map[string]interface{}{
			"url":         healthURL,
			"status_code": resp.StatusCode,
		},
	}
}

// checkTCPDependency performs TCP connectivity check
func (hc *HealthChecker) checkTCPDependency(ctx context.Context, config *DependencyConfig) CheckResult {
	start := time.Now()

	// Parse the URL to get host and port
	// For simplicity, assuming format "host:port" in URL
	conn, err := (&net.Dialer{Timeout: config.Timeout}).DialContext(ctx, "tcp", config.URL)
	duration := time.Since(start)

	if err != nil {
		return CheckResult{
			Status:    "unhealthy",
			Message:   fmt.Sprintf("Failed to connect to %s: %s", config.Name, err.Error()),
			Duration:  duration,
			Timestamp: time.Now(),
			Details:   map[string]interface{}{"address": config.URL},
		}
	}

	if conn != nil {
		conn.Close()
	}

	return CheckResult{
		Status:    "healthy",
		Message:   "TCP connection successful",
		Duration:  duration,
		Timestamp: time.Now(),
		Details:   map[string]interface{}{"address": config.URL},
	}
}
