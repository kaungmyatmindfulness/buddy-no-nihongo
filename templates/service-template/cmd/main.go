// FILE: templates/service-template/cmd/main.go
// Template for creating new services in the Wise Owl system

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

	"github.com/gin-gonic/gin"
)

func main() {
	// 1. Load Configuration
	cfg, err := config.LoadConfig()
	if err != nil {
		log.Fatalf("Could not load config: %v", err)
	}

	// 2. Set database name (change this for each service)
	dbName := cfg.DB_NAME
	if dbName == "" {
		dbName = "SERVICE_NAME_db" // Replace SERVICE_NAME with actual service name
	}

	// 3. Connect to Database
	dbConn := database.Connect(cfg.MONGODB_URI)
	dbHandle := dbConn.Client.Database(dbName)
	log.Printf("Connected to database: %s", dbName)

	// 4. Initialize Health Checker
	healthChecker := health.NewSimpleHealthChecker("SERVICE_NAME Service") // Replace SERVICE_NAME
	healthChecker.SetMongoClient(dbConn.Client, dbName)

	// 5. Initialize HTTP Router
	router := gin.Default()

	// 6. Add Health Endpoints (same for all services)
	router.GET("/health", healthChecker.Handler())
	router.HEAD("/health", healthChecker.Handler())
	router.GET("/health/ready", healthChecker.ReadyHandler())
	router.HEAD("/health/ready", healthChecker.ReadyHandler())

	// 7. Add Authentication Middleware (if needed)
	authMiddleware := auth.EnsureValidToken(cfg.Auth0Domain, cfg.Auth0Audience)

	// 8. Add API Routes
	apiV1 := router.Group("/api/v1")
	{
		// Example protected routes
		protectedRoutes := apiV1.Group("/example")
		protectedRoutes.Use(authMiddleware)
		{
			// Add your routes here
			// protectedRoutes.GET("/items", handler.GetItems)
			// protectedRoutes.POST("/items", handler.CreateItem)
		}

		// Example public routes
		// apiV1.GET("/public", handler.GetPublicData)
	}

	// 9. Start Server with Graceful Shutdown
	srv := &http.Server{Addr: ":" + cfg.ServerPort, Handler: router}

	go func() {
		log.Printf("Service listening on port %s", cfg.ServerPort)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Server error: %v", err)
		}
	}()

	// Wait for interrupt signal
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Println("Shutting down service...")

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		log.Printf("Server shutdown error: %v", err)
	}
	log.Println("Service stopped")
}
