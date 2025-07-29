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
	// 1. Load Configuration
	cfg, err := config.LoadConfig()
	if err != nil {
		log.Fatalf("FATAL: could not load config: %v", err)
	}

	dbName := cfg.DB_NAME
	if dbName == "" {
		dbName = "quiz_db"
	}
	log.Printf("Configuration loaded. Using database: %s (Type: %s)", dbName, cfg.DB_TYPE)

	// 2. Connect to Database
	db := database.CreateDatabaseSingleton(cfg)
	mongoClient := db.GetClient().(*mongo.Client)
	mongoDatabase := mongoClient.Database(dbName)
	log.Println("Database connection established.")

	// 3. Initialize simple health checker
	healthChecker := health.NewSimpleHealthChecker("Quiz Service")
	healthChecker.SetMongoClient(mongoClient, dbName)

	// 4. gRPC Client Setup for Content Service
	contentServiceURL := "content-service:50052"
	conn, err := grpc.Dial(contentServiceURL, grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		log.Fatalf("Did not connect to content-service: %v", err)
	}
	defer conn.Close()
	contentClient := pb_content.NewContentServiceClient(conn)
	log.Printf("Successfully connected to content-service gRPC at %s", contentServiceURL)

	// 5. Initialize HTTP Router and Handler
	router := gin.Default()

	authMiddleware := auth.EnsureValidToken(cfg.Auth0Domain, cfg.Auth0Audience)

	// Type assert dbHandle to *mongo.Database for quiz handler
	var quizHandler *handlers.QuizHandler
	quizHandler = handlers.NewQuizHandler(mongoDatabase, contentClient)

	// 6. Define API Routes
	// Simple health endpoints
	router.GET("/health", healthChecker.Handler())
	router.HEAD("/health", healthChecker.Handler())
	router.GET("/health/ready", healthChecker.ReadyHandler())
	router.HEAD("/health/ready", healthChecker.ReadyHandler())

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

	// 7. Start HTTP Server with Graceful Shutdown
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
