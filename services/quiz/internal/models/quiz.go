// FILE: services/quiz/internal/models/quiz.go

package models

import (
	"time"

	"go.mongodb.org/mongo-driver/bson/primitive"
)

// IncorrectWord represents the relationship between a user and a vocabulary item
// they have answered incorrectly.
type IncorrectWord struct {
	ID           primitive.ObjectID `bson:"_id,omitempty"`
	UserID       string             `bson:"user_id"`       // The Auth0 ID of the user
	VocabularyID string             `bson:"vocabulary_id"` // The ObjectID (as a string) of the vocab item
	CreatedAt    time.Time          `bson:"created_at"`
}
