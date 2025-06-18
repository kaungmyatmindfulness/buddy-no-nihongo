package config

import (
	"github.com/spf13/viper"
)

// Config struct holds all configuration for the application.
// The `mapstructure` tag is used by Viper to map env vars to struct fields.
type Config struct {
	ServerPort    string `mapstructure:"SERVER_PORT"`
	DBHost        string `mapstructure:"DB_HOST"`
	DBPort        string `mapstructure:"DB_PORT"`
	DBUser        string `mapstructure:"DB_USER"`
	DBPassword    string `mapstructure:"DB_PASSWORD"`
	DBName        string `mapstructure:"DB_NAME"`
	SrsServiceUrl string `mapstructure:"SRS_SERVICE_URL"` // Example for service-to-service
}

// LoadConfig reads configuration from environment variables.
func LoadConfig() (config Config, err error) {
	// Tell viper to look for environment variables
	viper.AutomaticEnv()

	// You can optionally set a prefix to avoid collisions
	// viper.SetEnvPrefix("BNN") // e.g. BNN_SERVER_PORT

	// Bind environment variables to the struct fields
	// This is often redundant with AutomaticEnv if your names match, but can be explicit.
	viper.BindEnv("SERVER_PORT")
	viper.BindEnv("DB_HOST")
	viper.BindEnv("DB_PORT")
	viper.BindEnv("DB_USER")
	viper.BindEnv("DB_PASSWORD")
	viper.BindEnv("DB_NAME")
	viper.BindEnv("SRS_SERVICE_URL")

	// Set default values for keys
	viper.SetDefault("SERVER_PORT", "8080")

	// Unmarshal the configuration into the Config struct
	err = viper.Unmarshal(&config)
	return
}
