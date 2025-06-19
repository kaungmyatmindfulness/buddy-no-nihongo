package config

import (
	"github.com/spf13/viper"
)

type Config struct {
	ServerPort string `mapstructure:"SERVER_PORT"`

	MONGODB_URI string `mapstructure:"MONGODB_URI"`

	USERS_SERVICE_URL string `mapstructure:"USERS_SERVICE_URL"`

	DB_NAME string `mapstructure:"DB_NAME"`
}

func LoadConfig() (config Config, err error) {

	viper.AutomaticEnv()

	viper.SetDefault("SERVER_PORT", "8080")

	err = viper.Unmarshal(&config)
	return
}
