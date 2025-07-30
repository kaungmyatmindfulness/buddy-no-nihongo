// FILE: lib/config/aws.go
// AWS environment detection and utilities

package config

import (
	"os"
)

// IsAWSEnvironment checks if the application is running in AWS environment
// This function is exported for use by services
func IsAWSEnvironment() bool {
	return isRunningInAWS()
}

// GetAWSRegion returns the AWS region from environment variables
func GetAWSRegion() string {
	// Check various AWS region environment variables
	if region := os.Getenv("AWS_REGION"); region != "" {
		return region
	}
	if region := os.Getenv("AWS_DEFAULT_REGION"); region != "" {
		return region
	}
	return "us-east-1" // Default fallback
}

// GetSecretName returns the secret name for the current environment
func GetSecretName() string {
	env := os.Getenv("ENVIRONMENT")
	switch env {
	case "production":
		return "wise-owl/production"
	case "staging":
		return "wise-owl/staging"
	default:
		return "wise-owl/production" // Default to production
	}
}

// GetParameterPrefix returns the parameter prefix for the current environment
func GetParameterPrefix() string {
	env := os.Getenv("ENVIRONMENT")
	switch env {
	case "production":
		return "/wise-owl"
	case "staging":
		return "/wise-owl-staging"
	default:
		return "/wise-owl" // Default to production
	}
}

// IsLocalDevelopment checks if running in local development mode
func IsLocalDevelopment() bool {
	// Check for local development indicators
	if os.Getenv("ENVIRONMENT") == "development" {
		return true
	}
	if os.Getenv("ENVIRONMENT") == "local" {
		return true
	}
	// If no AWS environment variables are set, assume local
	return !isRunningInAWS()
}
