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
	// 1. Load Configuration (supports both local and AWS environments)
	cfg, err := config.LoadConfig()
	if err != nil {
		log.Fatalf("FATAL: could not load config: %v", err)
	}

	dbName := cfg.DB_NAME
	if dbName == "" {
		dbName = "content_db"
	}
	log.Printf("Configuration loaded. Using database: %s (Type: %s)", dbName, cfg.DB_TYPE)

	// 2. Connect to Database (supports MongoDB and DocumentDB)
	db := database.CreateDatabaseSingleton(cfg)
	mongoClient := db.GetClient().(*mongo.Client)
	mongoDatabase := mongoClient.Database(dbName)
	log.Println("Database connection established.")

	// 3. Seed data
	seeder.SeedData(dbName, mongoClient)

	// 4. Initialize health checker (choose based on environment)
	var healthChecker interface {
		RegisterRoutes(*gin.Engine)
		Handler() gin.HandlerFunc
		ReadyHandler() gin.HandlerFunc
	}

	// Use AWS health checker if running in AWS environment
	if config.IsAWSEnvironment() {
		log.Println("AWS environment detected, using enhanced health checks")
		awsHealthChecker := health.NewAWSHealthChecker("Content Service", mongoDatabase)
		healthChecker = awsHealthChecker
	} else {
		log.Println("Local environment detected, using simple health checks")
		simpleHealthChecker := health.NewSimpleHealthChecker("Content Service")
		simpleHealthChecker.SetMongoClient(mongoClient, dbName)
		healthChecker = simpleHealthChecker
	}

	// 5. Start gRPC Server (for internal communication)
	grpcPort := cfg.GRPCPort
	if grpcPort == "" {
		grpcPort = "50052" // Default for content service
	}

	go func() {
		lis, err := net.Listen("tcp", ":"+grpcPort)
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

	// Initialize content handler
	var contentHandler *handlers.ContentHandler
	contentHandler = handlers.NewContentHandler(mongoDatabase)

	// 7. Register health check routes
	healthChecker.RegisterRoutes(router)

	// 8. Define API Routes
	apiV1 := router.Group("/api/v1")
	{
		lessonRoutes := apiV1.Group("/lessons")
		{
			lessonRoutes.GET("", contentHandler.GetLessons)
			lessonRoutes.GET("/:lessonId", contentHandler.GetLessonContent)
		}
	}

	// 9. Graceful Shutdown Logic
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
