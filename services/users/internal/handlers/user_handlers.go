// FILE: services/users/internal/handlers/user_handlers.go
// This package contains the business logic for all user-related API endpoints.

package handlers

import (
	"net/http"
	"strconv"
	"time"

	"wise-owl/services/users/internal/models"

	"github.com/gin-gonic/gin"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

// UserHandler holds dependencies, such as the database collection handle.
type UserHandler struct {
	collection *mongo.Collection
}

// NewUserHandler creates a new handler with its dependencies.
func NewUserHandler(collection *mongo.Collection) *UserHandler {
	return &UserHandler{collection: collection}
}

// OnboardUser creates a user profile after initial Auth0 sign-up.
func (h *UserHandler) OnboardUser(c *gin.Context) {
	auth0ID, _ := c.Get("userID")

	var req struct {
		Username string `json:"username" binding:"required"`
		Email    string `json:"email" binding:"required,email"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": err.Error()})
		return
	}

	// Check if user already exists
	count, err := h.collection.CountDocuments(c, bson.M{"auth0_id": auth0ID.(string)})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "database_error"})
		return
	}
	if count > 0 {
		c.JSON(http.StatusConflict, gin.H{"error": "user_exists", "message": "User profile already exists."})
		return
	}

	newUser := models.User{
		ID:        primitive.NewObjectID(),
		Auth0ID:   auth0ID.(string),
		Username:  req.Username,
		Email:     req.Email,
		Level:     "N5",
		Progress:  models.UserProgress{XP: 0, CompletedChapters: []int{}},
		CreatedAt: time.Now().UTC(),
		UpdatedAt: time.Now().UTC(),
	}

	_, err = h.collection.InsertOne(c, newUser)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "create_failed"})
		return
	}

	c.JSON(http.StatusCreated, newUser)
}

// GetUserProfile fetches the profile of the currently authenticated user.
func (h *UserHandler) GetUserProfile(c *gin.Context) {
	auth0ID, _ := c.Get("userID")

	var user models.User
	err := h.collection.FindOne(c, bson.M{"auth0_id": auth0ID.(string)}).Decode(&user)
	if err != nil {
		if err == mongo.ErrNoDocuments {
			c.JSON(http.StatusNotFound, gin.H{"error": "not_found", "message": "User profile not found."})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "database_error"})
		return
	}

	c.JSON(http.StatusOK, user)
}

// UpdateUserProfile allows a user to update their own profile information.
func (h *UserHandler) UpdateUserProfile(c *gin.Context) {
	auth0ID, _ := c.Get("userID")

	var req struct {
		Username *string `json:"username"` // Use pointers to detect if a field was provided
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": err.Error()})
		return
	}

	updates := bson.M{}
	if req.Username != nil {
		updates["username"] = *req.Username
	}

	if len(updates) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "no_updates_provided"})
		return
	}

	updates["updated_at"] = time.Now().UTC()
	filter := bson.M{"auth0_id": auth0ID.(string)}
	updateDoc := bson.M{"$set": updates}

	result, err := h.collection.UpdateOne(c, filter, updateDoc)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "update_failed"})
		return
	}
	if result.MatchedCount == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "not_found"})
		return
	}

	c.Status(http.StatusNoContent)
}

// DeleteUserAccount handles the deletion of a user's account.
func (h *UserHandler) DeleteUserAccount(c *gin.Context) {
	auth0ID, _ := c.Get("userID")

	filter := bson.M{"auth0_id": auth0ID.(string)}
	result, err := h.collection.DeleteOne(c, filter)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "delete_failed"})
		return
	}
	if result.DeletedCount == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "not_found"})
		return
	}

	// TODO: You would also need to trigger cleanup in other services,
	//       e.g., by publishing a 'UserDeleted' event.

	c.Status(http.StatusNoContent)
}

// GetUserDashboard retrieves aggregate stats for the user's dashboard.
func (h *UserHandler) GetUserDashboard(c *gin.Context) {
	// For now, we return mock data. In a real app, this would involve
	// more complex aggregation queries or calls to other services.
	dashboardData := gin.H{
		"xp":            1500,
		"level":         "N5",
		"review_streak": 5,
		"words_learned": 120,
	}
	c.JSON(http.StatusOK, dashboardData)
}

// GetChapterProgress retrieves the user's completion status for all chapters.
func (h *UserHandler) GetChapterProgress(c *gin.Context) {
	auth0ID, _ := c.Get("userID")

	var user models.User
	// We only need the 'progress' field, so we use projection to be efficient.
	opts := options.FindOne().SetProjection(bson.M{"progress": 1})
	err := h.collection.FindOne(c, bson.M{"auth0_id": auth0ID.(string)}, opts).Decode(&user)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "not_found"})
		return
	}

	// This is a simplified response. A real app might join this with a list of all chapters.
	c.JSON(http.StatusOK, user.Progress)
}

// CompleteChapter marks a chapter as complete for a user.
func (h *UserHandler) CompleteChapter(c *gin.Context) {
	auth0ID, _ := c.Get("userID")
	chapterIDStr := c.Param("chapterId")
	chapterID, err := strconv.Atoi(chapterIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_chapter_id"})
		return
	}

	filter := bson.M{"auth0_id": auth0ID.(string)}
	// Use $addToSet to ensure the chapter is only added if it doesn't already exist.
	update := bson.M{
		"$addToSet": bson.M{"progress.completed_chapters": chapterID},
		"$set":      bson.M{"updated_at": time.Now().UTC()},
	}

	result, err := h.collection.UpdateOne(c, filter, update)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "update_failed"})
		return
	}
	if result.MatchedCount == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "not_found"})
		return
	}

	// TODO: Here you would publish an event or make a gRPC call to the SRS service
	//       to inform it to seed the vocabulary for this chapter for this user.

	c.Status(http.StatusNoContent)
}
