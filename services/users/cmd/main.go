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
	"wise-owl/services/users/internal/handlers"

	"github.com/gin-gonic/gin"
)

func main() {
	// 1. Load Configuration
	cfg, err := config.LoadConfig()
	if err != nil {
		log.Fatalf("FATAL: could not load config: %v", err)
	}
	if cfg.Auth0Domain == "" || cfg.Auth0Audience == "" {
		log.Fatal("FATAL: AUTH0_DOMAIN and AUTH0_AUDIENCE must be set")
	}

	dbName := cfg.DB_NAME
	if dbName == "" {
		dbName = "users_db"
	}
	log.Printf("Configuration loaded. Using database: %s", dbName)

	// 2. Connect to Database
	dbConn := database.Connect(cfg.MONGODB_URI)
	userCollection := dbConn.GetCollection(dbName, "users")
	log.Println("Database connection established.")

	// 3. Initialize HTTP Router and Shared Middleware
	router := gin.Default()
	authMiddleware := auth.EnsureValidToken(cfg.Auth0Domain, cfg.Auth0Audience)

	// Dependency Injection: Pass the collection handle to the handlers.
	userHandler := handlers.NewUserHandler(userCollection)

	// 4. Define API Routes
	router.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok", "service": "Users Service"})
	})

	apiV1 := router.Group("/api/v1")
	{
		userRoutes := apiV1.Group("/users")
		// All routes in this group will be protected by the shared auth middleware.
		userRoutes.Use(authMiddleware)
		{
			userRoutes.POST("/onboarding", userHandler.OnboardUser)
			userRoutes.GET("/me/profile", userHandler.GetUserProfile)
			userRoutes.PATCH("/me/profile", userHandler.UpdateUserProfile)
			userRoutes.DELETE("/me", userHandler.DeleteUserAccount)
		}
	}

	// 5. Start HTTP Server with Graceful Shutdown
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
