package main

import (
	"log"
	"net/http"

	"wise-owl/lib/config" // Uses the shared config library

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
	// This proves the server is up and responding to requests.
	router.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"status":  "ok",
			"service": "Users Service",
			"port":    cfg.ServerPort,
		})
	})

	// TODO: Add other user-specific routes here later...

	// Step 4: Start the HTTP server
	// This is a blocking call, so it will keep the container running.
	log.Printf("Starting Users Service on port %s", cfg.ServerPort)
	if err := router.Run(":" + cfg.ServerPort); err != nil {
		log.Fatalf("FATAL: could not start Users Service: %v", err)
	}
}
