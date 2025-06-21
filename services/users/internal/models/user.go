package models

import (
	"time"

	"go.mongodb.org/mongo-driver/bson/primitive"
)

// User represents a user document in the database.
type User struct {
	ID        primitive.ObjectID `bson:"_id,omitempty"`
	Auth0ID   string             `bson:"auth0_id"` // The 'sub' claim from the Auth0 JWT. Must be unique.
	Username  string             `bson:"username"`
	Email     string             `bson:"email"`
	Level     string             `bson:"level"`
	Progress  UserProgress       `bson:"progress"`
	CreatedAt time.Time          `bson:"created_at"`
	UpdatedAt time.Time          `bson:"updated_at"`
}

// UserProgress is an embedded document for tracking user progress.
type UserProgress struct {
	XP                int   `bson:"xp"`
	CompletedChapters []int `bson:"completed_chapters"`
}
