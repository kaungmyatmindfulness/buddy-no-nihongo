// FILE: lib/health/config.go
// This file provides configuration helpers for health checks

package health

import (
	"log"
	"os"
	"strconv"
	"time"
)

// HealthConfig provides configuration for health checks
type HealthConfig struct {
	DefaultTimeout       time.Duration
	CircuitBreakerConfig CircuitBreakerConfig
	MongoTimeout         time.Duration
	HTTPTimeout          time.Duration
	TCPTimeout           time.Duration
}

// DefaultHealthConfig returns a default health configuration
func DefaultHealthConfig() *HealthConfig {
	return &HealthConfig{
		DefaultTimeout: 10 * time.Second,
		CircuitBreakerConfig: CircuitBreakerConfig{
			FailureThreshold: 5,
			RecoveryTimeout:  30 * time.Second,
			SuccessThreshold: 2,
			Enabled:          true,
		},
		MongoTimeout: 5 * time.Second,
		HTTPTimeout:  5 * time.Second,
		TCPTimeout:   3 * time.Second,
	}
}

// LoadHealthConfigFromEnv loads health configuration from environment variables
func LoadHealthConfigFromEnv() *HealthConfig {
	config := DefaultHealthConfig()

	// Load default timeout
	if timeoutStr := os.Getenv("HEALTH_DEFAULT_TIMEOUT"); timeoutStr != "" {
		if timeout, err := time.ParseDuration(timeoutStr); err == nil {
			config.DefaultTimeout = timeout
		}
	}

	// Load circuit breaker config
	if thresholdStr := os.Getenv("HEALTH_CB_FAILURE_THRESHOLD"); thresholdStr != "" {
		if threshold, err := strconv.Atoi(thresholdStr); err == nil {
			config.CircuitBreakerConfig.FailureThreshold = threshold
		}
	}

	if recoveryStr := os.Getenv("HEALTH_CB_RECOVERY_TIMEOUT"); recoveryStr != "" {
		if recovery, err := time.ParseDuration(recoveryStr); err == nil {
			config.CircuitBreakerConfig.RecoveryTimeout = recovery
		}
	}

	if successStr := os.Getenv("HEALTH_CB_SUCCESS_THRESHOLD"); successStr != "" {
		if success, err := strconv.Atoi(successStr); err == nil {
			config.CircuitBreakerConfig.SuccessThreshold = success
		}
	}

	if enabledStr := os.Getenv("HEALTH_CB_ENABLED"); enabledStr != "" {
		if enabled, err := strconv.ParseBool(enabledStr); err == nil {
			config.CircuitBreakerConfig.Enabled = enabled
		}
	}

	// Load specific timeouts
	if mongoTimeoutStr := os.Getenv("HEALTH_MONGO_TIMEOUT"); mongoTimeoutStr != "" {
		if timeout, err := time.ParseDuration(mongoTimeoutStr); err == nil {
			config.MongoTimeout = timeout
		}
	}

	if httpTimeoutStr := os.Getenv("HEALTH_HTTP_TIMEOUT"); httpTimeoutStr != "" {
		if timeout, err := time.ParseDuration(httpTimeoutStr); err == nil {
			config.HTTPTimeout = timeout
		}
	}

	if tcpTimeoutStr := os.Getenv("HEALTH_TCP_TIMEOUT"); tcpTimeoutStr != "" {
		if timeout, err := time.ParseDuration(tcpTimeoutStr); err == nil {
			config.TCPTimeout = timeout
		}
	}

	return config
}

// ApplyToHealthChecker applies configuration to a health checker
func (config *HealthConfig) ApplyToHealthChecker(hc *HealthChecker) {
	hc.defaultTimeout = config.DefaultTimeout

	// Apply circuit breaker config to all existing dependencies
	hc.mutex.Lock()
	defer hc.mutex.Unlock()

	for serviceName := range hc.dependencies {
		if cb := hc.circuitBreakers[serviceName]; cb != nil {
			cb.config = config.CircuitBreakerConfig
		}
	}
}

// ServiceDependencies holds common service dependencies for Wise Owl services
type ServiceDependencies struct {
	ContentService string
	UsersService   string
	QuizService    string
	MongoDB        string
}

// GetServiceDependencies returns service dependencies based on environment
func GetServiceDependencies() ServiceDependencies {
	// Default Docker Compose service names
	deps := ServiceDependencies{
		ContentService: "http://content-service:8080",
		UsersService:   "http://users-service:8080",
		QuizService:    "http://quiz-service:8080",
		MongoDB:        "mongodb://mongodb:27017",
	}

	// Override with environment variables if provided
	if contentURL := os.Getenv("CONTENT_SERVICE_URL"); contentURL != "" {
		deps.ContentService = contentURL
	}
	if usersURL := os.Getenv("USERS_SERVICE_URL"); usersURL != "" {
		deps.UsersService = usersURL
	}
	if quizURL := os.Getenv("QUIZ_SERVICE_URL"); quizURL != "" {
		deps.QuizService = quizURL
	}
	if mongoURL := os.Getenv("MONGODB_URL"); mongoURL != "" {
		deps.MongoDB = mongoURL
	}

	return deps
}

// SetupCommonDependencies sets up common dependencies for a service
func SetupCommonDependencies(hc *HealthChecker, serviceName string, config *HealthConfig) {
	deps := GetServiceDependencies()

	switch serviceName {
	case "Content Service":
		// Content service doesn't depend on other services directly
		log.Println("Content Service: No inter-service dependencies configured")

	case "Users Service":
		// Users service doesn't depend on other services directly
		log.Println("Users Service: No inter-service dependencies configured")

	case "Quiz Service":
		// Quiz service depends on Content service via gRPC
		hc.AddDependencyWithConfig("content-service", &DependencyConfig{
			Name:         "content-service",
			URL:          deps.ContentService,
			Timeout:      config.HTTPTimeout,
			Critical:     true,
			CheckType:    "http",
			ExpectedCode: 200,
		})
		log.Println("Quiz Service: Added Content Service dependency")

	default:
		log.Printf("Unknown service name: %s, no common dependencies configured", serviceName)
	}
}
