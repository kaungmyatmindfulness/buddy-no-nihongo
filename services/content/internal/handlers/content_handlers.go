// FILE: services/content/internal/handlers/content_handlers.go

package handlers

import (
	"net/http"
	"sort"

	"wise-owl/services/content/internal/models"

	"github.com/gin-gonic/gin"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

// ContentHandler holds the database collection handle.
type ContentHandler struct {
	vocabulary *mongo.Collection
}

// NewContentHandler creates a new handler with its dependencies.
func NewContentHandler(db *mongo.Database) *ContentHandler {
	return &ContentHandler{
		vocabulary: db.Collection("vocabulary"),
	}
}

// GetLessons retrieves a sorted list of all unique lesson identifiers.
func (h *ContentHandler) GetLessons(c *gin.Context) {
	// Use the Distinct function to get all unique lesson strings (e.g., "lesson-1", "lesson-2").
	results, err := h.vocabulary.Distinct(c, "lesson", bson.M{})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "database_error"})
		return
	}

	// Convert the []interface{} from MongoDB to a []string for sorting.
	var lessonStrings []string
	for _, res := range results {
		if lessonStr, ok := res.(string); ok {
			lessonStrings = append(lessonStrings, lessonStr)
		}
	}

	sort.Strings(lessonStrings) // Sort the lesson strings alphabetically.

	c.JSON(http.StatusOK, gin.H{"lessons": lessonStrings})
}

// GetLessonContent retrieves all vocabulary for a specific lesson identifier.
func (h *ContentHandler) GetLessonContent(c *gin.Context) {
	// Get the lesson identifier directly from the URL parameter (e.g., "lesson-1").
	lessonID := c.Param("lessonId")

	opts := options.Find().SetSort(bson.D{{Key: "kana", Value: 1}}) // Sort alphabetically by kana
	cursor, err := h.vocabulary.Find(c, bson.M{"lesson": lessonID}, opts)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "database_error"})
		return
	}

	var vocabList []models.Vocabulary
	if err = cursor.All(c, &vocabList); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "deserialization_error"})
		return
	}

	if len(vocabList) == 0 {
		// This could mean the lesson identifier is invalid, or the lesson has no vocab.
		// Returning an empty list is a safe and predictable response for the client.
		c.JSON(http.StatusOK, []models.Vocabulary{})
		return
	}

	c.JSON(http.StatusOK, vocabList)
}
