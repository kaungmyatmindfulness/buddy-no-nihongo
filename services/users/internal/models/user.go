// FILE: services/users/internal/models/user.go

package models

import (
	"time"

	"go.mongodb.org/mongo-driver/bson/primitive"
)

// User represents a user document in the database.
type User struct {
	ID                primitive.ObjectID      `bson:"_id,omitempty"`
	Auth0ID           string                  `bson:"auth0_id"` // The 'sub' claim from the Auth0 JWT. Must be unique.
	Username          string                  `bson:"username"`
	Email             string                  `bson:"email"`
	NotificationPrefs NotificationPreferences `bson:"notification_prefs,omitempty"`
	CreatedAt         time.Time               `bson:"created_at"`
	UpdatedAt         time.Time               `bson:"updated_at"`
}

// NotificationPreferences defines the structure for user notification settings.
type NotificationPreferences struct {
	Enabled bool   `bson:"enabled"`
	TimeUTC string `bson:"time_utc"` // Stored as "HH:MM" in UTC
}
