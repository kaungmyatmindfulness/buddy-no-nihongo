package config

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"runtime"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/secretsmanager"
	"github.com/aws/aws-sdk-go-v2/service/ssm"
)

// Config holds the essential configuration for all services
// Maintains backward compatibility while adding new AWS-specific fields
type Config struct {
	ServerPort    string
	GRPCPort      string
	LogLevel      string
	MONGODB_URI   string
	DB_NAME       string
	DB_TYPE       string
	Auth0Domain   string
	Auth0Audience string
	JWT_SECRET    string
	Environment   string // Added for AWS environment detection
}

// AppConfig provides a more structured configuration approach for AWS deployments
type AppConfig struct {
	Port        string
	GRPCPort    string
	LogLevel    string
	Environment string
	Database    DatabaseConfig
	JWT         JWTConfig
	Auth0       Auth0Config
}

type DatabaseConfig struct {
	URI  string
	Name string
	Type string
}

type JWTConfig struct {
	Secret string
}

type Auth0Config struct {
	Domain   string
	Audience string
}

// AWSConfigLoader handles loading configuration from AWS services
type AWSConfigLoader struct {
	secretsClient *secretsmanager.Client
	ssmClient     *ssm.Client
}

// NewAWSConfigLoader creates a new AWS config loader
func NewAWSConfigLoader() (*AWSConfigLoader, error) {
	cfg, err := config.LoadDefaultConfig(context.TODO())
	if err != nil {
		return nil, fmt.Errorf("unable to load AWS config: %v", err)
	}

	return &AWSConfigLoader{
		secretsClient: secretsmanager.NewFromConfig(cfg),
		ssmClient:     ssm.NewFromConfig(cfg),
	}, nil
}

// LoadSecrets retrieves secrets from AWS Secrets Manager
func (a *AWSConfigLoader) LoadSecrets(secretName string) (map[string]string, error) {
	result, err := a.secretsClient.GetSecretValue(context.TODO(), &secretsmanager.GetSecretValueInput{
		SecretId: aws.String(secretName),
	})
	if err != nil {
		return nil, fmt.Errorf("failed to retrieve secret %s: %v", secretName, err)
	}

	var secrets map[string]string
	if err := json.Unmarshal([]byte(*result.SecretString), &secrets); err != nil {
		return nil, fmt.Errorf("failed to parse secret JSON: %v", err)
	}

	return secrets, nil
}

// LoadParameter retrieves a parameter from AWS Systems Manager Parameter Store
func (a *AWSConfigLoader) LoadParameter(paramName string) (string, error) {
	result, err := a.ssmClient.GetParameter(context.TODO(), &ssm.GetParameterInput{
		Name: aws.String(paramName),
	})
	if err != nil {
		return "", fmt.Errorf("failed to retrieve parameter %s: %v", paramName, err)
	}

	return *result.Parameter.Value, nil
}

// isRunningInAWS checks if the application is running in AWS environment
func isRunningInAWS() bool {
	// Check for AWS execution environment variables
	if os.Getenv("AWS_EXECUTION_ENV") != "" {
		return true
	}
	if os.Getenv("AWS_LAMBDA_FUNCTION_NAME") != "" {
		return true
	}
	if os.Getenv("ECS_CONTAINER_METADATA_URI") != "" {
		return true
	}
	if os.Getenv("ECS_CONTAINER_METADATA_URI_V4") != "" {
		return true
	}
	return false
}

// LoadConfig loads configuration from environment variables with sensible defaults
// Maintains backward compatibility for local development
func LoadConfig() (*Config, error) {
	config := &Config{
		ServerPort:  getEnv("SERVER_PORT", "8080"),
		GRPCPort:    getEnv("GRPC_PORT", "50051"),
		LogLevel:    getEnv("LOG_LEVEL", "info"),
		MONGODB_URI: getEnv("MONGODB_URI", "mongodb://localhost:27017"),
		DB_NAME:     getEnv("DB_NAME", ""),
		DB_TYPE:     getEnv("DB_TYPE", "mongodb"),
		JWT_SECRET:  getEnv("JWT_SECRET", ""),
	}

	// Auth0 config (optional, only for services that need it)
	config.Auth0Domain = os.Getenv("AUTH0_DOMAIN")
	config.Auth0Audience = os.Getenv("AUTH0_AUDIENCE")

	// Try to load from AWS if running in AWS environment
	if isRunningInAWS() {
		log.Println("AWS environment detected, attempting to load configuration from AWS services...")
		if err := loadAWSConfig(config); err != nil {
			log.Printf("Warning: Failed to load AWS config, falling back to environment variables: %v", err)
		}
	} else {
		log.Println("Local environment detected, using environment variables and defaults")
	}

	log.Printf("Configuration loaded - Server Port: %s, GRPC Port: %s, DB Type: %s, DB: %s",
		config.ServerPort, config.GRPCPort, config.DB_TYPE, config.DB_NAME)

	return config, nil
}

// loadAWSConfig attempts to load configuration from AWS services
func loadAWSConfig(cfg *Config) error {
	awsLoader, err := NewAWSConfigLoader()
	if err != nil {
		return fmt.Errorf("failed to initialize AWS config loader: %v", err)
	}

	// Get environment-specific secret name
	secretName := GetSecretName()
	paramPrefix := GetParameterPrefix()

	// Load secrets from AWS Secrets Manager
	secrets, err := awsLoader.LoadSecrets(secretName)
	if err != nil {
		log.Printf("Failed to load AWS secrets from %s: %v", secretName, err)
	} else {
		// Only override if the secret value exists and is not already set from environment
		if mongoURI, ok := secrets["MONGODB_URI"]; ok && mongoURI != "" {
			if cfg.MONGODB_URI == "mongodb://localhost:27017" || cfg.MONGODB_URI == "" {
				cfg.MONGODB_URI = mongoURI
				log.Println("Loaded MONGODB_URI from AWS Secrets Manager")
			}
		}
		if jwtSecret, ok := secrets["JWT_SECRET"]; ok && jwtSecret != "" {
			if cfg.JWT_SECRET == "" {
				cfg.JWT_SECRET = jwtSecret
				log.Println("Loaded JWT_SECRET from AWS Secrets Manager")
			}
		}
		if auth0Domain, ok := secrets["AUTH0_DOMAIN"]; ok && auth0Domain != "" {
			if cfg.Auth0Domain == "" {
				cfg.Auth0Domain = auth0Domain
				log.Println("Loaded AUTH0_DOMAIN from AWS Secrets Manager")
			}
		}
		if auth0Audience, ok := secrets["AUTH0_AUDIENCE"]; ok && auth0Audience != "" {
			if cfg.Auth0Audience == "" {
				cfg.Auth0Audience = auth0Audience
				log.Println("Loaded AUTH0_AUDIENCE from AWS Secrets Manager")
			}
		}
	}

	// Load parameters from AWS Systems Manager Parameter Store
	if dbType, err := awsLoader.LoadParameter(paramPrefix + "/DB_TYPE"); err == nil && dbType != "" {
		if cfg.DB_TYPE == "mongodb" { // Only override default
			cfg.DB_TYPE = dbType
			log.Printf("Loaded DB_TYPE from AWS Parameter Store: %s", dbType)
		}
	}

	// Load log level parameter
	if logLevel, err := awsLoader.LoadParameter(paramPrefix + "/LOG_LEVEL"); err == nil && logLevel != "" {
		if cfg.LogLevel == "info" { // Only override default
			cfg.LogLevel = logLevel
			log.Printf("Loaded LOG_LEVEL from AWS Parameter Store: %s", logLevel)
		}
	}

	return nil
}

// LoadConfigAWS provides enhanced AWS-aware configuration loading
func LoadConfigAWS() (*AppConfig, error) {
	cfg := &AppConfig{
		Port:        getEnv("PORT", "8080"),
		GRPCPort:    getEnv("GRPC_PORT", "50051"),
		LogLevel:    getEnv("LOG_LEVEL", "info"),
		Environment: getEnv("ENVIRONMENT", "production"),
	}

	// Initialize database config with defaults
	cfg.Database.URI = getEnv("MONGODB_URI", "mongodb://localhost:27017")
	cfg.Database.Type = getEnv("DB_TYPE", "mongodb")
	cfg.Database.Name = getEnv("DB_NAME", "")

	// Initialize JWT config
	cfg.JWT.Secret = getEnv("JWT_SECRET", "")

	// Initialize Auth0 config
	cfg.Auth0.Domain = getEnv("AUTH0_DOMAIN", "")
	cfg.Auth0.Audience = getEnv("AUTH0_AUDIENCE", "")

	// Load from AWS if running in AWS environment
	if getEnv("AWS_EXECUTION_ENV", "") != "" {
		log.Println("AWS execution environment detected, loading configuration from AWS services...")
		awsLoader, err := NewAWSConfigLoader()
		if err != nil {
			log.Printf("Failed to initialize AWS config loader: %v", err)
			return convertToAppConfig(LoadConfig()) // Fallback to existing config
		}

		// Load secrets
		secrets, err := awsLoader.LoadSecrets("wise-owl/production")
		if err != nil {
			log.Printf("Failed to load AWS secrets: %v", err)
		} else {
			if mongoURI, ok := secrets["MONGODB_URI"]; ok && mongoURI != "" {
				cfg.Database.URI = mongoURI
				log.Println("Loaded MONGODB_URI from AWS Secrets Manager")
			}
			if jwtSecret, ok := secrets["JWT_SECRET"]; ok && jwtSecret != "" {
				cfg.JWT.Secret = jwtSecret
				log.Println("Loaded JWT_SECRET from AWS Secrets Manager")
			}
			if auth0Domain, ok := secrets["AUTH0_DOMAIN"]; ok && auth0Domain != "" {
				cfg.Auth0.Domain = auth0Domain
				log.Println("Loaded AUTH0_DOMAIN from AWS Secrets Manager")
			}
			if auth0Audience, ok := secrets["AUTH0_AUDIENCE"]; ok && auth0Audience != "" {
				cfg.Auth0.Audience = auth0Audience
				log.Println("Loaded AUTH0_AUDIENCE from AWS Secrets Manager")
			}
		}

		// Load parameters from Systems Manager
		paramPrefix := GetParameterPrefix()
		if dbType, err := awsLoader.LoadParameter(paramPrefix + "/DB_TYPE"); err == nil && dbType != "" {
			cfg.Database.Type = dbType
			log.Printf("Loaded DB_TYPE from AWS Parameter Store: %s", dbType)
		}
	}

	log.Printf("AWS Configuration loaded - Port: %s, GRPC Port: %s, DB Type: %s, Environment: %s",
		cfg.Port, cfg.GRPCPort, cfg.Database.Type, cfg.Environment)

	return cfg, nil
}

// convertToAppConfig converts legacy Config to new AppConfig structure
func convertToAppConfig(oldCfg *Config, err error) (*AppConfig, error) {
	if err != nil {
		return nil, err
	}

	return &AppConfig{
		Port:        oldCfg.ServerPort,
		GRPCPort:    oldCfg.GRPCPort,
		LogLevel:    oldCfg.LogLevel,
		Environment: getEnv("ENVIRONMENT", "development"),
		Database: DatabaseConfig{
			URI:  oldCfg.MONGODB_URI,
			Name: oldCfg.DB_NAME,
			Type: oldCfg.DB_TYPE,
		},
		JWT: JWTConfig{
			Secret: oldCfg.JWT_SECRET,
		},
		Auth0: Auth0Config{
			Domain:   oldCfg.Auth0Domain,
			Audience: oldCfg.Auth0Audience,
		},
	}, nil
}

// getEnvWithDefault gets environment variable with fallback (exported version)
func getEnvWithDefault(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

// getEnv gets environment variable with fallback
func getEnv(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

// GetMemoryUsage returns current memory usage statistics
func GetMemoryUsage() map[string]interface{} {
	var m runtime.MemStats
	runtime.ReadMemStats(&m)

	return map[string]interface{}{
		"alloc":      m.Alloc,
		"totalAlloc": m.TotalAlloc,
		"sys":        m.Sys,
		"numGC":      m.NumGC,
	}
}
