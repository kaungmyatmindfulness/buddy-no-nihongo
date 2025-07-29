package config

import (
	"log"
	"os"
)

// Config holds the essential configuration for all services
type Config struct {
	ServerPort    string
	MONGODB_URI   string
	DB_NAME       string
	DB_TYPE       string
	Auth0Domain   string
	Auth0Audience string
}

// LoadConfig loads configuration from environment variables with sensible defaults
func LoadConfig() (*Config, error) {
	config := &Config{
		ServerPort:  getEnv("SERVER_PORT", "8080"),
		MONGODB_URI: getEnv("MONGODB_URI", "mongodb://localhost:27017"),
		DB_NAME:     getEnv("DB_NAME", ""),
		DB_TYPE:     getEnv("DB_TYPE", "mongodb"),
	}

	// Auth0 config (optional, only for services that need it)
	config.Auth0Domain = os.Getenv("AUTH0_DOMAIN")
	config.Auth0Audience = os.Getenv("AUTH0_AUDIENCE")

	log.Printf("Configuration loaded - Server Port: %s, DB Type: %s, DB: %s",
		config.ServerPort, config.DB_TYPE, config.DB_NAME)

	return config, nil
}

// getEnv gets environment variable with fallback
func getEnv(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}
