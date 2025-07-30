// FILE: services/quiz/cmd/main.go
// Entry point for the Wise Owl Quiz Service.

package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	pb_content "wise-owl/gen/proto/content"
	"wise-owl/lib/auth"
	"wise-owl/lib/config"
	"wise-owl/lib/database"
	"wise-owl/lib/health"
	"wise-owl/services/quiz/internal/handlers"

	"github.com/gin-gonic/gin"
	"go.mongodb.org/mongo-driver/mongo"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

func main() {
	// 1. Load Configuration (supports both local and AWS environments)
	cfg, err := config.LoadConfig()
	if err != nil {
		log.Fatalf("FATAL: could not load config: %v", err)
	}

	dbName := cfg.DB_NAME
	if dbName == "" {
		dbName = "quiz_db"
	}
	log.Printf("Configuration loaded. Using database: %s (Type: %s)", dbName, cfg.DB_TYPE)

	// 2. Connect to Database (supports MongoDB and DocumentDB)
	db := database.CreateDatabaseSingleton(cfg)
	mongoClient := db.GetClient().(*mongo.Client)
	mongoDatabase := mongoClient.Database(dbName)
	log.Println("Database connection established.")

	// 3. Initialize health checker (choose based on environment)
	var healthChecker interface {
		RegisterRoutes(*gin.Engine)
		Handler() gin.HandlerFunc
		ReadyHandler() gin.HandlerFunc
	}

	// Use AWS health checker if running in AWS environment
	if config.IsAWSEnvironment() {
		log.Println("AWS environment detected, using enhanced health checks")
		awsHealthChecker := health.NewAWSHealthChecker("Quiz Service", mongoDatabase)
		healthChecker = awsHealthChecker
	} else {
		log.Println("Local environment detected, using simple health checks")
		simpleHealthChecker := health.NewSimpleHealthChecker("Quiz Service")
		simpleHealthChecker.SetMongoClient(mongoClient, dbName)
		healthChecker = simpleHealthChecker
	}

	// 4. gRPC Client Setup for Content Service
	contentServiceURL := getContentServiceURL()
	conn, err := grpc.Dial(contentServiceURL, grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		log.Fatalf("Did not connect to content-service: %v", err)
	}
	defer conn.Close()
	contentClient := pb_content.NewContentServiceClient(conn)
	log.Printf("Successfully connected to content-service gRPC at %s", contentServiceURL)

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

	// Initialize quiz handler
	var quizHandler *handlers.QuizHandler
	quizHandler = handlers.NewQuizHandler(mongoDatabase, contentClient)

	// 6. Register health check routes
	healthChecker.RegisterRoutes(router)

	// 7. Define API Routes
	apiV1 := router.Group("/api/v1")
	{
		quizRoutes := apiV1.Group("/quiz")
		quizRoutes.Use(authMiddleware)
		{
			quizRoutes.POST("/incorrect-words", quizHandler.RecordIncorrectWord)
			quizRoutes.GET("/incorrect-words", quizHandler.GetIncorrectWords)
			quizRoutes.DELETE("/incorrect-words", quizHandler.DeleteIncorrectWords)
		}
	}

	// 8. Start HTTP Server with Graceful Shutdown
	srv := &http.Server{Addr: ":" + cfg.ServerPort, Handler: router}
	go func() {
		log.Printf("Quiz HTTP server listening on port %s", cfg.ServerPort)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("FATAL: listen: %s\n", err)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Println("Shutting down Quiz Service...")
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	srv.Shutdown(ctx)
}

// getContentServiceURL returns the appropriate content service URL based on environment
func getContentServiceURL() string {
	// In AWS/ECS, services communicate via service discovery or load balancer
	if config.IsAWSEnvironment() {
		// In AWS ECS, use service discovery DNS or ALB internal endpoint
		if url := os.Getenv("CONTENT_SERVICE_URL"); url != "" {
			return url
		}
		// Default for ECS service discovery
		return "content-service.wise-owl-cluster.local:50052"
	}

	// Local development - use docker-compose service name or localhost
	if url := os.Getenv("CONTENT_SERVICE_URL"); url != "" {
		return url
	}
	return "content-service:50052"
}
