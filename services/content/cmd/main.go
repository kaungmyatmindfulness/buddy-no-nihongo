// FILE: services/content/cmd/main.go

package main

import (
	"context"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"wise-owl/lib/config"
	"wise-owl/lib/database"
	content_grpc "wise-owl/services/content/internal/grpc"
	"wise-owl/services/content/internal/handlers"
	"wise-owl/services/content/internal/seeder"

	pb "wise-owl/gen/proto/content"

	"github.com/gin-gonic/gin"
	"google.golang.org/grpc"
)

func main() {
	// ... (config loading, db connection, and seeder logic is unchanged) ...
	cfg, err := config.LoadConfig()
	if err != nil {
		log.Fatalf("FATAL: could not load config: %v", err)
	}
	dbName := cfg.DB_NAME
	if dbName == "" {
		dbName = "content_db"
	}
	dbConn := database.Connect(cfg.MONGODB_URI)
	dbHandle := dbConn.Client.Database(dbName)
	seeder.SeedData(dbName, dbConn.Client)

	// --- Start gRPC Server (for internal communication) ---
	go func() {
		lis, err := net.Listen("tcp", ":50052") // Use a unique internal port
		if err != nil {
			log.Fatalf("FATAL: Failed to listen for gRPC: %v", err)
		}
		s := grpc.NewServer()
		pb.RegisterContentServiceServer(s, content_grpc.NewServer(dbHandle))
		log.Printf("Content gRPC server listening at %v", lis.Addr())
		if err := s.Serve(lis); err != nil {
			log.Fatalf("FATAL: Failed to serve gRPC: %v", err)
		}
	}()

	// --- Initialize and Start Gin HTTP Server ---
	router := gin.Default()
	contentHandler := handlers.NewContentHandler(dbHandle)
	router.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok", "service": "Content Service"})
	})
	apiV1 := router.Group("/api/v1")
	{
		lessonRoutes := apiV1.Group("/lessons")
		{
			lessonRoutes.GET("", contentHandler.GetLessons)
			lessonRoutes.GET("/:lessonId", contentHandler.GetLessonContent)
		}
	}

	// --- Graceful Shutdown Logic ---
	srv := &http.Server{Addr: ":" + cfg.ServerPort, Handler: router}
	go func() {
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("FATAL: listen: %s\n", err)
		}
	}()
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Println("Shutting down Content Service...")
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	srv.Shutdown(ctx)
}
