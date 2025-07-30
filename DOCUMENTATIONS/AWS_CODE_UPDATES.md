# AWS-Optimized Code Updates for Manual Deployment

This document contains the code changes needed to optimize your Wise Owl microservices for manual AWS deployment.

## 1. Enhanced AWS Configuration (lib/config/aws.go)

```go
package config

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/secretsmanager"
	"github.com/aws/aws-sdk-go-v2/service/ssm"
)

type AWSConfigLoader struct {
	secretsClient *secretsmanager.Client
	ssmClient     *ssm.Client
}

func NewAWSConfigLoader() (*AWSConfigLoader, error) {
	cfg, err := config.LoadDefaultConfig(context.TODO())
	if err != nil {
		return nil, fmt.Errorf("unable to load AWS config: %v", err)
	}

	return &AWSConfigLoader{
		secretsClient: secretsmanager.NewFromConfig(cfg),
		ssmClient:     ssm.NewFromConfig(cfg),
	}, nil
}

func (a *AWSConfigLoader) LoadSecrets(secretName string) (map[string]string, error) {
	result, err := a.secretsClient.GetSecretValue(context.TODO(), &secretsmanager.GetSecretValueInput{
		SecretId: aws.String(secretName),
	})
	if err != nil {
		return nil, fmt.Errorf("failed to retrieve secret %s: %v", secretName, err)
	}

	var secrets map[string]string
	if err := json.Unmarshal([]byte(*result.SecretString), &secrets); err != nil {
		return nil, fmt.Errorf("failed to parse secret JSON: %v", err)
	}

	return secrets, nil
}

// Enhanced LoadConfig function for AWS deployment
func LoadConfigAWS() (*AppConfig, error) {
	cfg := &AppConfig{
		Port:     getEnvWithDefault("PORT", "8080"),
		GRPCPort: getEnvWithDefault("GRPC_PORT", "50051"),
		LogLevel: getEnvWithDefault("LOG_LEVEL", "info"),
	}

	// Load from AWS if running in AWS environment
	if getEnvWithDefault("AWS_EXECUTION_ENV", "") != "" {
		awsLoader, err := NewAWSConfigLoader()
		if err != nil {
			log.Printf("Failed to initialize AWS config loader: %v", err)
			return LoadConfig() // Fallback to local config
		}

		// Load secrets
		secrets, err := awsLoader.LoadSecrets("wise-owl/production")
		if err != nil {
			log.Printf("Failed to load AWS secrets: %v", err)
		} else {
			cfg.Database.URI = secrets["MONGODB_URI"]
			cfg.JWT.Secret = secrets["JWT_SECRET"]
			cfg.Auth0.Domain = secrets["AUTH0_DOMAIN"]
			cfg.Auth0.Audience = secrets["AUTH0_AUDIENCE"]
		}
	}

	// Fallback to environment variables
	if cfg.Database.URI == "" {
		cfg.Database.URI = getEnvWithDefault("MONGODB_URI", "mongodb://localhost:27017")
	}
	if cfg.Database.Type == "" {
		cfg.Database.Type = getEnvWithDefault("DB_TYPE", "mongodb")
	}

	return cfg, nil
}

func getEnvWithDefault(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}
```

## 2. DocumentDB Connection Support (lib/database/documentdb.go)

```go
package database

import (
	"context"
	"crypto/tls"
	"fmt"
	"net"

	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
	"go.mongodb.org/mongo-driver/mongo/readpref"
)

func CreateDocumentDBConnection(uri string) (*mongo.Client, error) {
	// DocumentDB requires TLS
	tlsConfig := &tls.Config{
		InsecureSkipVerify: false,
	}

	// Custom dialer for DocumentDB
	dialer := &net.Dialer{}

	clientOptions := options.Client().
		ApplyURI(uri).
		SetTLSConfig(tlsConfig).
		SetDialer(dialer).
		SetReplicaSet("rs0").
		SetReadPreference(readpref.SecondaryPreferred())

	client, err := mongo.Connect(context.TODO(), clientOptions)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to DocumentDB: %v", err)
	}

	// Test the connection
	err = client.Ping(context.TODO(), nil)
	if err != nil {
		return nil, fmt.Errorf("failed to ping DocumentDB: %v", err)
	}

	return client, nil
}
```

## 3. Enhanced Health Checks (lib/health/aws.go)

```go
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

type AWSHealthChecker struct {
	*SimpleHealthChecker
	db *mongo.Database
}

func NewAWSHealthChecker(serviceName string, db *mongo.Database) *AWSHealthChecker {
	return &AWSHealthChecker{
		SimpleHealthChecker: NewSimpleHealthChecker(serviceName),
		db:                  db,
	}
}

func (h *AWSHealthChecker) RegisterAWSRoutes(router *gin.Engine) {
	health := router.Group("/health")
	{
		health.GET("/", h.Health)
		health.GET("/ready", h.ReadinessCheck)
		health.GET("/live", h.LivenessCheck)
		health.GET("/deep", h.DeepHealthCheck)
	}
}

func (h *AWSHealthChecker) ReadinessCheck(c *gin.Context) {
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

func (h *AWSHealthChecker) LivenessCheck(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"status":    "alive",
		"service":   h.serviceName,
		"timestamp": time.Now().UTC(),
	})
}

func (h *AWSHealthChecker) DeepHealthCheck(c *gin.Context) {
	var m runtime.MemStats
	runtime.ReadMemStats(&m)

	checks := map[string]interface{}{
		"database": h.getDatabaseStatus(),
		"memory": map[string]interface{}{
			"alloc_mb":      m.Alloc / 1024 / 1024,
			"total_alloc_mb": m.TotalAlloc / 1024 / 1024,
			"sys_mb":        m.Sys / 1024 / 1024,
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

func (h *AWSHealthChecker) checkDatabase() bool {
	if h.db == nil {
		return false
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	return h.db.Client().Ping(ctx, nil) == nil
}

func (h *AWSHealthChecker) getDatabaseStatus() map[string]interface{} {
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
```

## 4. Update main.go for AWS (example for users service)

```go
package main

import (
	"context"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"
	"google.golang.org/grpc"

	"your-module/lib/auth"
	"your-module/lib/config"
	"your-module/lib/database"
	"your-module/lib/health"
	"your-module/services/users/internal/handlers"
	"your-module/services/users/internal/seeder"
)

func main() {
	// Load configuration (AWS-aware)
	var cfg *config.AppConfig
	var err error

	if os.Getenv("AWS_EXECUTION_ENV") != "" {
		cfg, err = config.LoadConfigAWS()
	} else {
		cfg, err = config.LoadConfig()
	}

	if err != nil {
		log.Fatalf("Failed to load configuration: %v", err)
	}

	// Set Gin mode
	if cfg.Environment == "production" {
		gin.SetMode(gin.ReleaseMode)
	}

	// Connect to database (supports both MongoDB and DocumentDB)
	var db *mongo.Database
	if cfg.Database.Type == "documentdb" {
		client, err := database.CreateDocumentDBConnection(cfg.Database.URI)
		if err != nil {
			log.Fatalf("Failed to connect to DocumentDB: %v", err)
		}
		db = client.Database("users_db")
	} else {
		db = database.CreateDatabaseSingleton(cfg)
	}

	// Run seeder
	seeder.SeedDatabase(db)

	// Initialize health checker
	healthChecker := health.NewAWSHealthChecker("users-service", db)

	// Setup HTTP router
	router := gin.Default()

	// Add health check routes
	healthChecker.RegisterAWSRoutes(router)

	// Add auth middleware
	authMiddleware := auth.EnsureValidToken(cfg.JWT.Secret)

	// Setup API routes
	api := router.Group("/api/v1/users")
	{
		api.GET("/health", healthChecker.Health)

		// Protected routes
		protected := api.Group("/")
		protected.Use(authMiddleware)
		{
			protected.GET("/profile", handlers.GetProfile)
			// Add other routes...
		}
	}

	// Setup gRPC server (if needed)
	grpcServer := grpc.NewServer()
	// Register gRPC services here

	// Start servers
	httpServer := &http.Server{
		Addr:    fmt.Sprintf(":%s", cfg.Port),
		Handler: router,
	}

	// Start HTTP server
	go func() {
		log.Printf("Starting HTTP server on port %s", cfg.Port)
		if err := httpServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("HTTP server failed to start: %v", err)
		}
	}()

	// Start gRPC server
	go func() {
		lis, err := net.Listen("tcp", fmt.Sprintf(":%s", cfg.GRPCPort))
		if err != nil {
			log.Fatalf("Failed to listen on gRPC port %s: %v", cfg.GRPCPort, err)
		}
		log.Printf("Starting gRPC server on port %s", cfg.GRPCPort)
		if err := grpcServer.Serve(lis); err != nil {
			log.Fatalf("gRPC server failed to start: %v", err)
		}
	}()

	// Wait for interrupt signal to gracefully shutdown
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Println("Shutting down servers...")

	// Graceful shutdown
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if err := httpServer.Shutdown(ctx); err != nil {
		log.Printf("HTTP server forced to shutdown: %v", err)
	}

	grpcServer.GracefulStop()
	log.Println("Servers exited")
}
```

## 5. Production Dockerfiles

### services/users/Dockerfile.aws

```dockerfile
FROM golang:1.21-alpine AS builder

WORKDIR /app

# Copy go mod files
COPY go.work go.work.sum ./
COPY lib/go.mod lib/go.sum lib/
COPY gen/go.mod gen/go.sum gen/
COPY services/users/go.mod services/users/go.sum services/users/

# Download dependencies
RUN go mod download

# Copy source code
COPY . .

# Build the application
RUN cd services/users && CGO_ENABLED=0 GOOS=linux go build -o main cmd/main.go

# Production stage
FROM alpine:latest

RUN apk --no-cache add ca-certificates curl
WORKDIR /root/

# Copy the binary
COPY --from=builder /app/services/users/main .

# Copy seed data
COPY --from=builder /app/services/users/seed ./seed

EXPOSE 8081 50051

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8081/health/ready || exit 1

CMD ["./main"]
```

## 6. Simple Deployment Script

```bash
#!/bin/bash

set -e

echo "🚀 Deploying Wise Owl to AWS (Manual Setup)"

# Configuration
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
ECR_REGISTRY="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

# Services to deploy
SERVICES=("users" "content" "quiz")

echo "📦 Building and pushing Docker images..."

# Login to ECR
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $ECR_REGISTRY

# Build and push each service
for service in "${SERVICES[@]}"; do
    echo "Building $service service..."

    docker build -t wise-owl-$service:latest \
      -f services/$service/Dockerfile.aws .

    docker tag wise-owl-$service:latest \
      $ECR_REGISTRY/wise-owl-$service:latest

    docker push $ECR_REGISTRY/wise-owl-$service:latest

    echo "✅ $service pushed successfully"
done

echo "🔄 Updating ECS services..."

# Update ECS services (assumes they're already created)
for service in "${SERVICES[@]}"; do
    echo "Updating $service service..."

    aws ecs update-service \
        --cluster wise-owl-cluster \
        --service wise-owl-$service \
        --force-new-deployment \
        --region $AWS_REGION
done

echo "⏳ Waiting for deployments to complete..."

# Wait for services to stabilize
for service in "${SERVICES[@]}"; do
    echo "Waiting for $service to stabilize..."

    aws ecs wait services-stable \
        --cluster wise-owl-cluster \
        --services wise-owl-$service \
        --region $AWS_REGION
done

echo "✅ Deployment completed successfully!"
echo "🌐 Check your ALB DNS name for the application URL"
```

## 7. Environment Variables for ECS

When creating your ECS task definitions, use these environment variables:

```bash
# Common for all services
PORT=808X  # 8081 for users, 8082 for content, 8083 for quiz
GRPC_PORT=5005X  # 50051 for users, 50052 for content, 50053 for quiz
AWS_EXECUTION_ENV=AWS_ECS_FARGATE
DB_TYPE=documentdb
LOG_LEVEL=info
ENVIRONMENT=production

# Secrets (from AWS Secrets Manager)
MONGODB_URI=wise-owl/production:MONGODB_URI::
JWT_SECRET=wise-owl/production:JWT_SECRET::
AUTH0_DOMAIN=wise-owl/production:AUTH0_DOMAIN::
AUTH0_AUDIENCE=wise-owl/production:AUTH0_AUDIENCE::
```

This setup is much more beginner-friendly and allows you to manually configure each AWS service while learning how they work together!
