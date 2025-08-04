// FILE: services/users/internal/seeder/seeder.go

package seeder

import (
	"context"
	"log"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

// SeedDatabase initializes the users database if needed
// Users service typically doesn't need pre-seeded data as users register themselves
func SeedDatabase(db interface{}) {
	// Handle both database interfaces
	var collection *mongo.Collection

	switch v := db.(type) {
	case *mongo.Database:
		collection = v.Collection("users")
	default:
		// For database.Database interface, we don't need to seed anything
		// Users are created through the API when they register
		log.Println("Users service: No seeding required - users register via API")
		return
	}

	// Check if any users exist
	count, err := collection.CountDocuments(context.Background(), bson.M{})
	if err != nil {
		log.Printf("WARN: Failed to count documents in users collection: %v", err)
		return
	}

	if count > 0 {
		log.Printf("Users collection already has %d documents. Skipping seed.", count)
		return
	}

	// Create indexes for performance
	err = createIndexes(collection)
	if err != nil {
		log.Printf("WARN: Failed to create indexes: %v", err)
	}

	log.Println("Users service initialized successfully")
}

// createIndexes creates necessary indexes for the users collection
func createIndexes(collection *mongo.Collection) error {
	ctx := context.Background()

	// Create unique index on auth0_id
	indexModel := mongo.IndexModel{
		Keys: bson.D{
			{Key: "auth0_id", Value: 1},
		},
		Options: options.Index().SetUnique(true),
	}

	_, err := collection.Indexes().CreateOne(ctx, indexModel)
	if err != nil {
		return err
	}

	log.Println("Created unique index on auth0_id field")
	return nil
}
