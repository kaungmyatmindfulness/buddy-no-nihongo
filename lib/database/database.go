// FILE: lib/database/database.go
// This package manages database connections with support for multiple database types.

package database

import (
	"context"
	"crypto/tls"
	"fmt"
	"log"
	"net"
	"sync"
	"time"

	"wise-owl/lib/config"

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

// ConnectDocumentDB establishes a connection specifically to AWS DocumentDB
func (mdb *MongoDatabase) ConnectDocumentDB(uri string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	// DocumentDB requires TLS
	tlsConfig := &tls.Config{
		InsecureSkipVerify: false,
	}

	// Custom dialer for DocumentDB with retries
	dialer := &net.Dialer{
		Timeout:   10 * time.Second,
		KeepAlive: 30 * time.Second,
	}

	clientOptions := options.Client().
		ApplyURI(uri).
		SetTLSConfig(tlsConfig).
		SetDialer(dialer).
		SetReplicaSet("rs0").
		SetReadPreference(readpref.SecondaryPreferred()).
		SetMaxConnIdleTime(30 * time.Second).
		SetMaxPoolSize(10).
		SetRetryWrites(false) // DocumentDB doesn't support retryable writes

	client, err := mongo.Connect(ctx, clientOptions)
	if err != nil {
		return fmt.Errorf("failed to connect to DocumentDB: %v", err)
	}

	// Test the connection with retry
	var pingErr error
	for i := 0; i < 3; i++ {
		pingCtx, pingCancel := context.WithTimeout(context.Background(), 5*time.Second)
		pingErr = client.Ping(pingCtx, readpref.SecondaryPreferred())
		pingCancel()

		if pingErr == nil {
			break
		}
		log.Printf("DocumentDB ping attempt %d failed: %v", i+1, pingErr)
		time.Sleep(time.Second)
	}

	if pingErr != nil {
		return fmt.Errorf("failed to ping DocumentDB after retries: %v", pingErr)
	}

	mdb.Client = client
	log.Println("Successfully connected to AWS DocumentDB.")
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
	log.Printf("Creating database connection - Type: %s", dbType)

	switch dbType {
	case MongoDB:
		db := &MongoDatabase{}
		err := db.Connect(uri)
		if err != nil {
			log.Printf("Failed to connect to MongoDB: %v", err)
			return nil, err
		}
		log.Println("Successfully connected to MongoDB")
		return db, nil
	case DocumentDB:
		db := &MongoDatabase{}
		err := db.ConnectDocumentDB(uri)
		if err != nil {
			log.Printf("Failed to connect to DocumentDB: %v", err)
			return nil, err
		}
		log.Println("Successfully connected to AWS DocumentDB")
		return db, nil
	default:
		log.Printf("Unsupported database type: %s, falling back to MongoDB", dbType)
		// Fallback to MongoDB for unknown types
		db := &MongoDatabase{}
		err := db.Connect(uri)
		if err != nil {
			return nil, fmt.Errorf("failed to connect to fallback MongoDB: %v", err)
		}
		log.Println("Connected to fallback MongoDB")
		return db, nil
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

// CreateDatabaseSingleton creates a singleton database instance using config
// This function maintains backward compatibility with existing code
func CreateDatabaseSingleton(cfg *config.Config) DatabaseInterface {
	dbType := DatabaseType(cfg.DB_TYPE)
	return NewDatabaseSingleton(dbType, cfg.MONGODB_URI)
}

// GetDatabaseInstance returns the singleton database instance
func GetDatabaseInstance() DatabaseInterface {
	if dbInstance == nil {
		log.Fatal("FATAL: Database has not been initialized. Call NewDatabaseSingleton() first.")
	}
	return dbInstance
}
