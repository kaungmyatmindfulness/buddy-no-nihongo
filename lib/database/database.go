// FILE: lib/database/database.go
// This package manages database connections with support for multiple database types.

package database

import (
	"context"
	"fmt"
	"log"
	"sync"
	"time"

	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
	"go.mongodb.org/mongo-driver/mongo/readpref"
)

// DatabaseType represents the type of database service being used
type DatabaseType string

const (
	MongoDB    DatabaseType = "mongodb"
	DocumentDB DatabaseType = "documentdb"
)

// DatabaseInterface defines the contract for database operations
type DatabaseInterface interface {
	Connect(uri string) error
	GetClient() interface{}
	GetCollection(dbName, collectionName string) CollectionInterface
	Close() error
	Ping(ctx context.Context) error
}

// CollectionInterface defines the contract for collection operations
type CollectionInterface interface {
	// Basic CRUD operations that all database implementations should support
	Find(ctx context.Context, filter interface{}, opts ...*options.FindOptions) (*mongo.Cursor, error)
	FindOne(ctx context.Context, filter interface{}, opts ...*options.FindOneOptions) *mongo.SingleResult
	InsertOne(ctx context.Context, document interface{}, opts ...*options.InsertOneOptions) (*mongo.InsertOneResult, error)
	UpdateOne(ctx context.Context, filter, update interface{}, opts ...*options.UpdateOptions) (*mongo.UpdateResult, error)
	DeleteOne(ctx context.Context, filter interface{}, opts ...*options.DeleteOptions) (*mongo.DeleteResult, error)
	CountDocuments(ctx context.Context, filter interface{}, opts ...*options.CountOptions) (int64, error)
}

// MongoCollection wraps mongo.Collection to implement CollectionInterface
type MongoCollection struct {
	*mongo.Collection
}

// Ensure MongoCollection implements CollectionInterface
var _ CollectionInterface = (*MongoCollection)(nil)

// MongoDatabase implements DatabaseInterface for MongoDB/DocumentDB
type MongoDatabase struct {
	Client *mongo.Client
}

// Connect establishes a connection to MongoDB/DocumentDB
func (mdb *MongoDatabase) Connect(uri string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	client, err := mongo.Connect(ctx, options.Client().ApplyURI(uri))
	if err != nil {
		return err
	}

	if err := client.Ping(ctx, readpref.Primary()); err != nil {
		return err
	}

	mdb.Client = client
	log.Println("Successfully connected and pinged database.")
	return nil
}

// GetClient returns the underlying mongo client
func (mdb *MongoDatabase) GetClient() interface{} {
	return mdb.Client
}

// GetCollection returns a collection handle wrapped in our interface
func (mdb *MongoDatabase) GetCollection(dbName, collectionName string) CollectionInterface {
	collection := mdb.Client.Database(dbName).Collection(collectionName)
	return &MongoCollection{Collection: collection}
}

// Close closes the database connection
func (mdb *MongoDatabase) Close() error {
	if mdb.Client != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		return mdb.Client.Disconnect(ctx)
	}
	return nil
}

// Ping checks if the database connection is alive
func (mdb *MongoDatabase) Ping(ctx context.Context) error {
	if mdb.Client != nil {
		return mdb.Client.Ping(ctx, readpref.Primary())
	}
	return nil
}

// Ensure MongoDatabase implements DatabaseInterface
var _ DatabaseInterface = (*MongoDatabase)(nil)

var (
	// dbInstance holds the database interface instance
	dbInstance DatabaseInterface
	// onceNew ensures the NewDatabase function is only ever called once.
	onceNew sync.Once
)

// NewDatabase creates a new database instance based on the database type
func NewDatabase(dbType DatabaseType, uri string) (DatabaseInterface, error) {
	switch dbType {
	case MongoDB, DocumentDB:
		db := &MongoDatabase{}
		err := db.Connect(uri)
		if err != nil {
			return nil, err
		}
		return db, nil
	default:
		log.Printf("Unsupported database type: %s", dbType)
		return nil, fmt.Errorf("unsupported database type: %s", dbType)
	}
}

// NewDatabaseSingleton creates a singleton database instance
func NewDatabaseSingleton(dbType DatabaseType, uri string) DatabaseInterface {
	onceNew.Do(func() {
		db, err := NewDatabase(dbType, uri)
		if err != nil {
			log.Fatalf("FATAL: Failed to create database instance: %v", err)
		}
		dbInstance = db
	})
	return dbInstance
}

// GetDatabaseInstance returns the singleton database instance
func GetDatabaseInstance() DatabaseInterface {
	if dbInstance == nil {
		log.Fatal("FATAL: Database has not been initialized. Call NewDatabaseSingleton() first.")
	}
	return dbInstance
}
