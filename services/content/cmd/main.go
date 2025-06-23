// FILE: services/content/cmd/main.go
// Entry point for the Wise Owl Content Service.
// API endpoints are now updated to use '/lessons' for consistency.

package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"wise-owl/lib/config"
	"wise-owl/lib/database"
	"wise-owl/services/content/internal/handlers"
	"wise-owl/services/content/internal/seeder"

	"github.com/gin-gonic/gin"
)

func main() {
	cfg, err := config.LoadConfig()
	if err != nil {
		log.Fatalf("FATAL: could not load config: %v", err)
	}

	dbName := cfg.DB_NAME
	if dbName == "" {
		dbName = "content_db"
	}
	log.Printf("Configuration loaded. Using database: %s", dbName)

	dbConn := database.Connect(cfg.MONGODB_URI)
	dbHandle := dbConn.Client.Database(dbName)
	log.Println("Database connection established.")

	seeder.SeedData(dbName, dbConn.Client)

	router := gin.Default()

	contentHandler := handlers.NewContentHandler(dbHandle)

	router.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok", "service": "Content Service"})
	})

	apiV1 := router.Group("/api/v1")
	{
		// Renamed the route group from /chapters to /lessons
		lessonRoutes := apiV1.Group("/lessons")
		{
			// GET /api/v1/lessons
			lessonRoutes.GET("", contentHandler.GetLessons)
			// GET /api/v1/lessons/lesson-1
			lessonRoutes.GET("/:lessonId", contentHandler.GetLessonContent)
		}
	}

	srv := &http.Server{Addr: ":" + cfg.ServerPort, Handler: router}
	go func() {
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
