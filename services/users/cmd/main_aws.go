//go:build aws
// +build aws

// FILE: services/users/cmd/main_aws.go
// AWS-optimized version of main.go with enhanced configuration and health checks

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
	"go.mongodb.org/mongo-driver/mongo"
	"google.golang.org/grpc"

	"wise-owl/lib/auth"
	"wise-owl/lib/config"
	"wise-owl/lib/database"
	"wise-owl/lib/health"
	"wise-owl/services/users/internal/handlers"
	"wise-owl/services/users/internal/seeder"
)

func main() {
	// Load configuration (AWS-aware)
	var cfg *config.AppConfig
	var err error

	if os.Getenv("AWS_EXECUTION_ENV") != "" {
		cfg, err = config.LoadConfigAWS()
	} else {
		// Convert legacy config to new format for backward compatibility
		legacyCfg, legacyErr := config.LoadConfig()
		if legacyErr != nil {
			log.Fatalf("Failed to load configuration: %v", legacyErr)
		}
		cfg = &config.AppConfig{
			Port:        legacyCfg.ServerPort,
			GRPCPort:    legacyCfg.GRPCPort,
			LogLevel:    legacyCfg.LogLevel,
			Environment: os.Getenv("ENVIRONMENT"),
			Database: config.DatabaseConfig{
				URI:  legacyCfg.MONGODB_URI,
				Name: legacyCfg.DB_NAME,
				Type: legacyCfg.DB_TYPE,
			},
			JWT: config.JWTConfig{
				Secret: legacyCfg.JWT_SECRET,
			},
			Auth0: config.Auth0Config{
				Domain:   legacyCfg.Auth0Domain,
				Audience: legacyCfg.Auth0Audience,
			},
		}
	}

	if err != nil {
		log.Fatalf("Failed to load configuration: %v", err)
	}

	// Set Gin mode based on environment
	if cfg.Environment == "production" {
		gin.SetMode(gin.ReleaseMode)
	}

	// Connect to database (supports both MongoDB and DocumentDB)
	var db *mongo.Database
	dbName := cfg.Database.Name
	if dbName == "" {
		dbName = "users_db"
	}

	if cfg.Database.Type == "documentdb" {
		client, err := database.CreateDocumentDBConnection(cfg.Database.URI)
		if err != nil {
			log.Fatalf("Failed to connect to DocumentDB: %v", err)
		}
		db = client.Database(dbName)
		log.Printf("Connected to DocumentDB: %s", dbName)
	} else {
		// Use existing database singleton for backward compatibility
		legacyCfg := &config.Config{
			ServerPort:    cfg.Port,
			GRPCPort:      cfg.GRPCPort,
			LogLevel:      cfg.LogLevel,
			MONGODB_URI:   cfg.Database.URI,
			DB_NAME:       cfg.Database.Name,
			DB_TYPE:       cfg.Database.Type,
			Auth0Domain:   cfg.Auth0.Domain,
			Auth0Audience: cfg.Auth0.Audience,
			JWT_SECRET:    cfg.JWT.Secret,
		}
		dbInterface := database.CreateDatabaseSingleton(legacyCfg)
		// For MongoDB, extract the underlying client and get the database
		if mongoCol, ok := dbInterface.GetCollection(dbName, "temp").(*database.MongoCollection); ok {
			db = mongoCol.Collection.Database()
		} else {
			log.Fatal("FATAL: Failed to get mongo database from database interface")
		}
		log.Printf("Connected to MongoDB: %s", dbName)
	}

	// Run seeder
	seeder.SeedDatabase(db)

	// Initialize health checker (choose based on environment)
	var healthChecker interface {
		RegisterRoutes(*gin.Engine)
	}

	if os.Getenv("AWS_EXECUTION_ENV") != "" {
		healthChecker = health.NewAWSEnhancedHealthChecker("users-service", db)
	} else {
		healthChecker = health.NewSimpleHealthChecker("users-service")
	}

	// Setup HTTP router
	router := gin.Default()

	// Register health check routes
	healthChecker.RegisterRoutes(router)

	// Add auth middleware
	var authMiddleware gin.HandlerFunc
	if cfg.Auth0.Domain != "" && cfg.Auth0.Audience != "" {
		authMiddleware = auth.EnsureValidToken(cfg.Auth0.Domain, cfg.Auth0.Audience)
		log.Println("Auth0 authentication enabled")
	} else {
		// Skip auth in development if no Auth0 is configured
		authMiddleware = func(c *gin.Context) { c.Next() }
		log.Println("WARNING: Auth0 not configured, skipping authentication")
	}

	// Initialize user handler
	userCollection := db.Collection("users")
	userHandler := handlers.NewUserHandler(userCollection)

	// Setup API routes
	api := router.Group("/api/v1/users")
	{
		api.GET("/health", func(c *gin.Context) {
			c.JSON(http.StatusOK, gin.H{
				"status":    "healthy",
				"service":   "users-service",
				"timestamp": time.Now().UTC(),
			})
		})

		// Protected routes
		protected := api.Group("/")
		protected.Use(authMiddleware)
		{
			protected.GET("/profile", userHandler.GetUserProfile)
			// Add other routes as needed
		}
	}

	// Setup gRPC server (if needed)
	grpcServer := grpc.NewServer()
	// Register gRPC services here if you have them

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
