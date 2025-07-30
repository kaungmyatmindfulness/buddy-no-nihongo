package database

import (
	"log"
	"wise-owl/lib/config"
)

// DatabaseConfig holds database-specific configuration
type DatabaseConfig struct {
	Type DatabaseType
	URI  string
}

// LoadDatabaseConfig loads database configuration from the main config
func LoadDatabaseConfig(cfg *config.Config) *DatabaseConfig {
	dbType := DatabaseType(cfg.DB_TYPE)

	// Validate database type
	switch dbType {
	case MongoDB, DocumentDB:
		// Valid types
	default:
		log.Printf("Warning: Unknown database type '%s', defaulting to mongodb", cfg.DB_TYPE)
		dbType = MongoDB
	}

	return &DatabaseConfig{
		Type: dbType,
		URI:  cfg.MONGODB_URI,
	}
}

// CreateDatabase creates a database instance based on configuration
func CreateDatabase(cfg *config.Config) (DatabaseInterface, error) {
	dbConfig := LoadDatabaseConfig(cfg)

	log.Printf("Initializing database connection - Type: %s", dbConfig.Type)

	return NewDatabase(dbConfig.Type, dbConfig.URI)
}
