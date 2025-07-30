// FILE: services/users/cmd/main.go
// This is the entry point for the Wise Owl Users Service. It wires everything together.
// Hot reload test comment - if you see this rebuild, hot reload is working!

package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"wise-owl/lib/auth"
	"wise-owl/lib/config"
	"wise-owl/lib/database"
	"wise-owl/lib/health"
	"wise-owl/services/users/internal/handlers"

	"github.com/gin-gonic/gin"
	"go.mongodb.org/mongo-driver/mongo"
)

func main() {
	// 1. Load Configuration (supports both local and AWS environments)
	cfg, err := config.LoadConfig()
	if err != nil {
		log.Fatalf("FATAL: could not load config: %v", err)
	}

	// 2. Validate Auth0 configuration (optional for development)
	if cfg.Auth0Domain == "" || cfg.Auth0Audience == "" {
		log.Println("WARNING: AUTH0_DOMAIN and AUTH0_AUDIENCE not set. Authentication will be skipped in development.")
	}

	dbName := cfg.DB_NAME
	if dbName == "" {
		dbName = "users_db"
	}
	log.Printf("Configuration loaded. Using database: %s (Type: %s)", dbName, cfg.DB_TYPE)

	// 3. Connect to Database (supports MongoDB and DocumentDB)
	db := database.CreateDatabaseSingleton(cfg)
	userCollection := db.GetCollection(dbName, "users")
	log.Println("Database connection established.")

	// 4. Initialize health checker (choose based on environment)
	var healthChecker interface {
		RegisterRoutes(*gin.Engine)
		Handler() gin.HandlerFunc
		ReadyHandler() gin.HandlerFunc
	}

	// Use AWS health checker if running in AWS environment
	if config.IsAWSEnvironment() {
		log.Println("AWS environment detected, using enhanced health checks")
		if mongoClient, ok := db.GetClient().(*mongo.Client); ok {
			mongoDatabase := mongoClient.Database(dbName)
			awsHealthChecker := health.NewAWSHealthChecker("Users Service", mongoDatabase)
			healthChecker = awsHealthChecker
		} else {
			log.Println("WARNING: Could not get mongo client for AWS health checker, falling back to simple health checker")
			simpleHealthChecker := health.NewSimpleHealthChecker("Users Service")
			if mongoClient, ok := db.GetClient().(*mongo.Client); ok {
				simpleHealthChecker.SetMongoClient(mongoClient, dbName)
			}
			healthChecker = simpleHealthChecker
		}
	} else {
		log.Println("Local environment detected, using simple health checks")
		simpleHealthChecker := health.NewSimpleHealthChecker("Users Service")
		if mongoClient, ok := db.GetClient().(*mongo.Client); ok {
			simpleHealthChecker.SetMongoClient(mongoClient, dbName)
		}
		healthChecker = simpleHealthChecker
	}

	// 5. Initialize HTTP Router and Middleware
	router := gin.Default()

	// Initialize auth middleware (skip if Auth0 not configured)
	var authMiddleware gin.HandlerFunc
	if cfg.Auth0Domain != "" && cfg.Auth0Audience != "" {
		authMiddleware = auth.EnsureValidToken(cfg.Auth0Domain, cfg.Auth0Audience)
		log.Println("Auth0 authentication enabled")
	} else {
		// No-op middleware for development
		authMiddleware = func(c *gin.Context) {
			c.Next()
		}
		log.Println("Authentication disabled for development")
	}

	// 6. Initialize user handler
	var userHandler *handlers.UserHandler
	if mongoCol, ok := userCollection.(*database.MongoCollection); ok {
		userHandler = handlers.NewUserHandler(mongoCol.Collection)
	} else {
		log.Fatal("FATAL: Failed to get mongo collection from database interface")
	}

	// 7. Register health check routes
	healthChecker.RegisterRoutes(router)

	// 8. Define API Routes
	apiV1 := router.Group("/api/v1")
	{
		userRoutes := apiV1.Group("/users")
		// Apply auth middleware to all user routes
		userRoutes.Use(authMiddleware)
		{
			userRoutes.POST("/onboarding", userHandler.OnboardUser)
			userRoutes.GET("/me/profile", userHandler.GetUserProfile)
			userRoutes.PATCH("/me/profile", userHandler.UpdateUserProfile)
			userRoutes.DELETE("/me", userHandler.DeleteUserAccount)
		}
	}

	// 9. Start HTTP Server with Graceful Shutdown
	srv := &http.Server{
		Addr:    ":" + cfg.ServerPort,
		Handler: router,
	}

	go func() {
		log.Printf("HTTP server listening on port %s", cfg.ServerPort)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("FATAL: listen: %s\n", err)
		}
	}()

	// Wait for interrupt signal for a graceful shutdown.
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Println("Shutting down server...")

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		log.Fatal("Server forced to shutdown:", err)
	}

	log.Println("Server exiting.")
}
