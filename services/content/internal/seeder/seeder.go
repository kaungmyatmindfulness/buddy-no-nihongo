// FILE: services/content/internal/seeder/seeder.go

package seeder

import (
	"context"
	"encoding/json"
	"log"
	"os"

	"wise-owl/services/content/internal/models"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
)

const seedFilePathInContainer = "/app/seed/vocabulary.json"
const seedFilePathForLocal = "services/content/seed/vocabulary.json"

// SeedData checks if the vocabulary collection is empty and populates it from the JSON file.
func SeedData(dbName string, client *mongo.Client) {
	collection := client.Database(dbName).Collection("vocabulary")

	count, err := collection.CountDocuments(context.Background(), bson.M{})
	if err != nil {
		log.Fatalf("FATAL: Failed to count documents in vocabulary collection: %v", err)
	}

	if count > 0 {
		log.Println("Vocabulary data already exists. Skipping seed.")
		return
	}

	log.Println("No vocabulary data found. Seeding database from vocabulary.json...")

	jsonFile, err := os.ReadFile(seedFilePathInContainer)
	if err != nil {
		jsonFile, err = os.ReadFile(seedFilePathForLocal)
		if err != nil {
			log.Printf("WARN: Could not read seed file. Skipping seed. Error: %v", err)
			return
		}
	}

	var vocabList []models.Vocabulary
	if err := json.Unmarshal(jsonFile, &vocabList); err != nil {
		log.Fatalf("FATAL: Failed to unmarshal seed JSON: %v", err)
	}

	if len(vocabList) > 0 {
		documents := make([]interface{}, len(vocabList))
		for i, vocab := range vocabList {
			documents[i] = vocab
		}

		_, err = collection.InsertMany(context.Background(), documents)
		if err != nil {
			log.Fatalf("FATAL: Failed to seed vocabulary: %v", err)
		}
	}

	log.Println("Successfully seeded database with vocabulary content.")
}
