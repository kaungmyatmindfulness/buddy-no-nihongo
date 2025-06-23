// FILE: services/content/internal/models/content.go

package models

import "go.mongodb.org/mongo-driver/bson/primitive"

// Vocabulary represents a single vocabulary item from the seed file.
type Vocabulary struct {
	ID        primitive.ObjectID `json:"_id,omitempty" bson:"_id,omitempty"`
	Kana      string             `json:"kana" bson:"kana"`
	Kanji     *string            `json:"kanji" bson:"kanji"`
	Furigana  *string            `json:"furigana" bson:"furigana"`
	Romaji    string             `json:"romaji" bson:"romaji"`
	English   string             `json:"english" bson:"english"`
	Burmese   string             `json:"burmese" bson:"burmese"`
	Lesson    string             `json:"lesson" bson:"lesson"`
	Type      string             `json:"type" bson:"type"`
	WordClass string             `json:"word-class" bson:"word-class"`
}
