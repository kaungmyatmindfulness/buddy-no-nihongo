package config

import (
	"fmt"
	"strings"

	"github.com/spf13/viper"
)

type Config struct {
	ServerPort    string `mapstructure:"SERVER_PORT"`
	MONGODB_URI   string `mapstructure:"MONGODB_URI"`
	DB_NAME       string `mapstructure:"DB_NAME"`
	Auth0Domain   string `mapstructure:"AUTH0_DOMAIN"`
	Auth0Audience string `mapstructure:"AUTH0_AUDIENCE"`
}

func LoadConfig() (config Config, err error) {
	viper.SetEnvPrefix("")
	viper.AutomaticEnv()

	viper.SetEnvKeyReplacer(strings.NewReplacer(".", "_"))

	envVars := []string{
		"SERVER_PORT",
		"MONGODB_URI",
		"DB_NAME",
		"AUTH0_DOMAIN",
		"AUTH0_AUDIENCE",
	}

	for _, key := range envVars {
		if err := viper.BindEnv(key); err != nil {
			return config, fmt.Errorf("error binding env var %s: %w", key, err)
		}
	}

	if err := viper.Unmarshal(&config); err != nil {
		return config, fmt.Errorf("unable to decode into config struct: %w", err)
	}

	return
}
