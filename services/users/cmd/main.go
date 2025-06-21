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

	cfg, err := config.LoadConfig()

	if err != nil {
		log.Fatalf("FATAL: could not load config: %v", err)
	}
	if cfg.Auth0Domain == "" || cfg.Auth0Audience == "" {
		log.Fatal("FATAL: AUTH0_DOMAIN and AUTH0_AUDIENCE must be set")
	}
	log.Println("Configuration loaded.")

	dbConn := database.Connect(cfg.MONGODB_URI)
	userCollection := dbConn.GetCollection(cfg.DB_NAME, "users")
	log.Println("Database connection established.")

	router := gin.Default()
	authMiddleware := auth.EnsureValidToken(cfg.Auth0Domain, cfg.Auth0Audience)

	userHandler := handlers.NewUserHandler(userCollection)

	router.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok", "service": "Users Service"})
	})

	apiV1 := router.Group("/api/v1")
	{
		userRoutes := apiV1.Group("/users")

		userRoutes.Use(authMiddleware)
		{
			userRoutes.POST("/onboarding", userHandler.OnboardUser)
			userRoutes.GET("/me/profile", userHandler.GetUserProfile)
			userRoutes.PATCH("/me/profile", userHandler.UpdateUserProfile)
			userRoutes.DELETE("/me", userHandler.DeleteUserAccount)
			userRoutes.GET("/me/dashboard", userHandler.GetUserDashboard)
			userRoutes.GET("/me/progress/chapters", userHandler.GetChapterProgress)
			userRoutes.POST("/me/progress/chapters/:chapterId/complete", userHandler.CompleteChapter)
		}
	}

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
