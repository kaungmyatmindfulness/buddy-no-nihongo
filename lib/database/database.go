// FILE: lib/database/database.go
// This package manages the singleton connection to MongoDB.

package database

import (
	"context"
	"log"
	"sync"
	"time"

	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
	"go.mongodb.org/mongo-driver/mongo/readpref"
)

// DB holds the singleton instance of our MongoDB client.
type DB struct {
	Client *mongo.Client
}

var (
	// conn holds the single database connection instance.
	conn *DB
	// once ensures the Connect function is only ever called once.
	once sync.Once
)

// Connect establishes a connection to MongoDB and initializes the singleton.
// The sync.Once pattern ensures this logic is executed exactly one time.
func Connect(uri string) *DB {
	once.Do(func() {
		client, err := mongo.NewClient(options.Client().ApplyURI(uri))
		if err != nil {
			log.Fatalf("FATAL: Failed to create MongoDB client: %v", err)
		}

		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		err = client.Connect(ctx)
		if err != nil {
			log.Fatalf("FATAL: Failed to connect to MongoDB: %v", err)
		}

		if err := client.Ping(ctx, readpref.Primary()); err != nil {
			log.Fatalf("FATAL: Failed to ping MongoDB: %v", err)
		}

		log.Println("Successfully connected and pinged MongoDB.")
		conn = &DB{Client: client}
	})

	return conn
}

// GetDB returns the singleton database connection instance.
func GetDB() *DB {
	if conn == nil {
		log.Fatal("FATAL: Database has not been connected. Call database.Connect() first.")
	}
	return conn
}

// GetCollection is a helper function to get a handle for a specific collection.
func (db *DB) GetCollection(dbName, collectionName string) *mongo.Collection {
	return db.Client.Database(dbName).Collection(collectionName)
}
