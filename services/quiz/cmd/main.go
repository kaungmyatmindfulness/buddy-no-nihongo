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
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

func main() {
	cfg, err := config.LoadConfig()
	if err != nil {
		log.Fatalf("FATAL: could not load config: %v", err)
	}

	dbName := cfg.DB_NAME
	if dbName == "" {
		dbName = "quiz_db"
	}
	log.Printf("Configuration loaded. Using database: %s", dbName)

	dbConn := database.Connect(cfg.MONGODB_URI)
	dbHandle := dbConn.Client.Database(dbName)
	log.Println("Database connection established.")

	// Initialize Health Checker with enhanced configuration
	healthConfig := health.LoadHealthConfigFromEnv()
	healthChecker := health.NewHealthChecker("Quiz Service", "1.0.0", "development")
	healthChecker.SetMongoClient(dbConn.Client, dbName)
	healthConfig.ApplyToHealthChecker(healthChecker)

	// --- gRPC Client Setup for Content Service ---
	// Address is "service-name:port" from docker-compose
	contentServiceURL := "content-service:50052"
	conn, err := grpc.Dial(contentServiceURL, grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		log.Fatalf("Did not connect to content-service: %v", err)
	}
	defer conn.Close()
	contentClient := pb_content.NewContentServiceClient(conn)
	log.Printf("Successfully connected to content-service gRPC at %s", contentServiceURL)

	// Setup common dependencies and add custom ones
	health.SetupCommonDependencies(healthChecker, "Quiz Service", healthConfig)

	// Add additional custom dependencies if needed
	// For example, add gRPC health check (when available)
	// healthChecker.AddDependencyWithConfig("content-service-grpc", &health.DependencyConfig{
	//     Name: "content-service-grpc",
	//     URL: "content-service:50052",
	//     Timeout: 5*time.Second,
	//     Critical: true,
	//     CheckType: "tcp",
	// })

	router := gin.Default()

	// Use custom logging middleware to reduce health check noise
	router.Use(health.LoggingMiddleware())

	authMiddleware := auth.EnsureValidToken(cfg.Auth0Domain, cfg.Auth0Audience)
	quizHandler := handlers.NewQuizHandler(dbHandle, contentClient)

	// Enhanced health check endpoints (support both GET and HEAD for Docker health checks)
	router.GET("/health", healthChecker.CreateEnhancedHandler())
	router.HEAD("/health", healthChecker.CreateEnhancedHandler())
	router.GET("/health/ready", healthChecker.CreateDetailedReadinessHandler())
	router.HEAD("/health/ready", healthChecker.CreateDetailedReadinessHandler())
	router.GET("/health/live", healthChecker.CreateLivenessHandler())
	router.HEAD("/health/live", healthChecker.CreateLivenessHandler())
	router.GET("/health/metrics", healthChecker.CreateMetricsHandler())
	router.HEAD("/health/metrics", healthChecker.CreateMetricsHandler())

	// Legacy health endpoint for backward compatibility
	router.GET("/health-legacy", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok", "service": "Quiz Service"})
	})

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

	srv := &http.Server{Addr: ":" + cfg.ServerPort, Handler: router}
	go func() {
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
