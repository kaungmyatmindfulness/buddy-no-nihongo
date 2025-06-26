// FILE: services/quiz/internal/handlers/quiz_handlers.go

package handlers

import (
	"context"
	"log"
	"net/http"
	"time"

	pb_content "wise-owl/gen/proto/content/v1"
	"wise-owl/services/quiz/internal/models"

	"github.com/gin-gonic/gin"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

// QuizHandler holds dependencies for the quiz service handlers.
type QuizHandler struct {
	collection    *mongo.Collection
	contentClient pb_content.ContentServiceClient // gRPC client for the content service
}

// NewQuizHandler creates a new handler with its dependencies.
func NewQuizHandler(db *mongo.Database, contentClient pb_content.ContentServiceClient) *QuizHandler {
	return &QuizHandler{
		collection:    db.Collection("incorrect_words"),
		contentClient: contentClient,
	}
}

// RecordIncorrectWord saves a record that a user answered a word incorrectly.
func (h *QuizHandler) RecordIncorrectWord(c *gin.Context) {
	userID, _ := c.Get("userID")

	var req struct {
		VocabularyID string `json:"vocabulary_id" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request"})
		return
	}

	// Use an "upsert" operation to avoid creating duplicate entries.
	// If a document with this user_id and vocabulary_id already exists, it does nothing.
	// If it doesn't exist, it inserts a new one.
	filter := bson.M{"user_id": userID, "vocabulary_id": req.VocabularyID}
	update := bson.M{
		"$setOnInsert": bson.M{
			"_id":        primitive.NewObjectID(),
			"created_at": time.Now().UTC(),
		},
	}
	opts := options.Update().SetUpsert(true)

	_, err := h.collection.UpdateOne(c, filter, update, opts)
	if err != nil {
		log.Printf("Error recording incorrect word: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "database_error"})
		return
	}

	c.Status(http.StatusCreated)
}

// GetIncorrectWords retrieves the full details of all words the user has marked incorrect.
func (h *QuizHandler) GetIncorrectWords(c *gin.Context) {
	userID, _ := c.Get("userID")

	// 1. Find all incorrect word records for the user in our own database.
	cursor, err := h.collection.Find(c, bson.M{"user_id": userID})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "database_error"})
		return
	}

	var incorrectWordRecords []models.IncorrectWord
	if err = cursor.All(c, &incorrectWordRecords); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "deserialization_error"})
		return
	}

	if len(incorrectWordRecords) == 0 {
		c.JSON(http.StatusOK, []interface{}{})
		return
	}

	// 2. Extract just the vocabulary IDs to send to the content service.
	var vocabIDs []string
	for _, record := range incorrectWordRecords {
		vocabIDs = append(vocabIDs, record.VocabularyID)
	}

	// 3. Make a single batch gRPC call to the content service.
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	grpcRes, err := h.contentClient.GetVocabularyBatch(ctx, &pb_content.GetVocabularyBatchRequest{VocabularyIds: vocabIDs})
	if err != nil {
		log.Printf("gRPC call to content service failed: %v", err)
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "content_service_unavailable"})
		return
	}

	c.JSON(http.StatusOK, grpcRes.Items)
}

// DeleteIncorrectWords performs a batch deletion of words from a user's incorrect list.
func (h *QuizHandler) DeleteIncorrectWords(c *gin.Context) {
	userID, _ := c.Get("userID")

	var req struct {
		VocabularyIDs []string `json:"vocabulary_ids" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request"})
		return
	}

	if len(req.VocabularyIDs) == 0 {
		c.Status(http.StatusNoContent)
		return
	}

	// The filter will match documents for the current user WHERE the vocabulary_id
	// is in the list provided in the request body.
	filter := bson.M{
		"user_id":       userID,
		"vocabulary_id": bson.M{"$in": req.VocabularyIDs},
	}

	_, err := h.collection.DeleteMany(c, filter)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "delete_failed"})
		return
	}

	c.Status(http.StatusNoContent)
}
