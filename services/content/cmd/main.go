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
	"wise-owl/lib/health"
	content_grpc "wise-owl/services/content/internal/grpc"
	"wise-owl/services/content/internal/handlers"
	"wise-owl/services/content/internal/seeder"

	pb "wise-owl/gen/proto/content"

	"github.com/gin-gonic/gin"
	"go.mongodb.org/mongo-driver/mongo"
	"google.golang.org/grpc"
)

func main() {
	// 1. Load Configuration
	cfg, err := config.LoadConfig()
	if err != nil {
		log.Fatalf("FATAL: could not load config: %v", err)
	}

	dbName := cfg.DB_NAME
	if dbName == "" {
		dbName = "content_db"
	}
	log.Printf("Configuration loaded. Using database: %s (Type: %s)", dbName, cfg.DB_TYPE)

	// 2. Connect to Database
	db := database.CreateDatabaseSingleton(cfg)
	mongoClient := db.GetClient().(*mongo.Client)
	mongoDatabase := mongoClient.Database(dbName)
	log.Println("Database connection established.")

	// 3. Seed data
	seeder.SeedData(dbName, mongoClient)

	// 4. Initialize simple health checker
	healthChecker := health.NewSimpleHealthChecker("Content Service")
	healthChecker.SetMongoClient(mongoClient, dbName)

	// 5. Start gRPC Server (for internal communication)
	go func() {
		lis, err := net.Listen("tcp", ":50052") // Use a unique internal port
		if err != nil {
			log.Fatalf("FATAL: Failed to listen for gRPC: %v", err)
		}
		s := grpc.NewServer()

		// Register content service with mongo database
		pb.RegisterContentServiceServer(s, content_grpc.NewServer(mongoDatabase))

		log.Printf("Content gRPC server listening at %v", lis.Addr())
		if err := s.Serve(lis); err != nil {
			log.Fatalf("FATAL: Failed to serve gRPC: %v", err)
		}
	}()

	// 6. Initialize and Start Gin HTTP Server
	router := gin.Default()

	// Type assert dbHandle to *mongo.Database for content handler
	var contentHandler *handlers.ContentHandler
	contentHandler = handlers.NewContentHandler(mongoDatabase)

	// 7. Define API Routes
	// Simple health endpoints
	router.GET("/health", healthChecker.Handler())
	router.HEAD("/health", healthChecker.Handler())
	router.GET("/health/ready", healthChecker.ReadyHandler())
	router.HEAD("/health/ready", healthChecker.ReadyHandler())

	apiV1 := router.Group("/api/v1")
	{
		lessonRoutes := apiV1.Group("/lessons")
		{
			lessonRoutes.GET("", contentHandler.GetLessons)
			lessonRoutes.GET("/:lessonId", contentHandler.GetLessonContent)
		}
	}

	// 8. Graceful Shutdown Logic
	srv := &http.Server{Addr: ":" + cfg.ServerPort, Handler: router}
	go func() {
		log.Printf("Content HTTP server listening on port %s", cfg.ServerPort)
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
