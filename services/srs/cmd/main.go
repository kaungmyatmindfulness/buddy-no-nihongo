package main

import (
	"log"
	"net/http"

	"buddy-no-nihongo/lib/config" // Uses the shared config library

	"github.com/gin-gonic/gin"
)

func main() {
	// Step 1: Load configuration from environment variables
	cfg, err := config.LoadConfig()
	if err != nil {
		log.Fatalf("FATAL: could not load config: %v", err)
	}

	// Step 2: Initialize the Gin router
	router := gin.Default()

	// Step 3: Define a simple health check route
	router.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"status":  "ok",
			"service": "SRS Service",
			"port":    cfg.ServerPort,
		})
	})

	// TODO: Add other SRS-specific routes here later...

	// Step 4: Start the HTTP server
	log.Printf("Starting SRS Service on port %s", cfg.ServerPort)
	if err := router.Run(":" + cfg.ServerPort); err != nil {
		log.Fatalf("FATAL: could not start SRS Service: %v", err)
	}
}
