// FILE: lib/database/database.go

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
// It is designed to be called only once at application startup.
func Connect(uri string) *DB {
	// The sync.Once pattern ensures that the database connection logic
	// is executed exactly one time, no matter how many times Connect is called.
	// This prevents creating multiple connection pools.
	once.Do(func() {
		client, err := mongo.NewClient(options.Client().ApplyURI(uri))
		if err != nil {
			log.Fatalf("FATAL: Failed to create MongoDB client: %v", err)
		}

		// Use a context with a timeout for the connection attempt.
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		err = client.Connect(ctx)
		if err != nil {
			log.Fatalf("FATAL: Failed to connect to MongoDB: %v", err)
		}

		// Ping the primary node to verify that the connection is alive and well.
		if err := client.Ping(ctx, readpref.Primary()); err != nil {
			log.Fatalf("FATAL: Failed to ping MongoDB: %v", err)
		}

		log.Println("Successfully connected and pinged MongoDB.")
		conn = &DB{Client: client}
	})

	return conn
}

// GetDB returns the singleton database connection instance.
// Panics if Connect() has not been called first.
func GetDB() *DB {
	if conn == nil {
		log.Fatal("FATAL: Database has not been connected. Call database.Connect() first.")
	}
	return conn
}

// GetCollection is a helper function to get a handle for a specific collection
// from the connected MongoDB client.
func (db *DB) GetCollection(dbName, collectionName string) *mongo.Collection {
	return db.Client.Database(dbName).Collection(collectionName)
}
