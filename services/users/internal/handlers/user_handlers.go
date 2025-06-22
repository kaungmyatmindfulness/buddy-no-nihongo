// FILE: services/users/internal/handlers/user_handlers.go
// This package contains the business logic for all user-related API endpoints.

package handlers

import (
	"net/http"
	"time"

	"wise-owl/services/users/internal/models"

	"github.com/gin-gonic/gin"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
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
		ID:       primitive.NewObjectID(),
		Auth0ID:  auth0ID.(string),
		Username: req.Username,
		Email:    req.Email,
		NotificationPrefs: models.NotificationPreferences{
			Enabled: false, // Notifications are off by default
		},
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
		Username          *string                         `json:"username"`
		NotificationPrefs *models.NotificationPreferences `json:"notification_preferences"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid_request", "message": err.Error()})
		return
	}

	updates := bson.M{}
	if req.Username != nil {
		updates["username"] = *req.Username
	}
	if req.NotificationPrefs != nil {
		updates["notification_prefs"] = *req.NotificationPrefs
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

	// TODO: In a real system, you would publish a 'UserDeleted' event here
	// so other services (like the Quiz Service) can clean up related data.

	c.Status(http.StatusNoContent)
}
