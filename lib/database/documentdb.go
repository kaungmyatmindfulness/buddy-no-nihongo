// FILE: lib/database/documentdb.go
// DocumentDB connection support for AWS deployment

package database

import (
	"context"
	"crypto/tls"
	"fmt"
	"net"

	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
	"go.mongodb.org/mongo-driver/mongo/readpref"
)

// CreateDocumentDBConnection creates a connection specifically configured for AWS DocumentDB
func CreateDocumentDBConnection(uri string) (*mongo.Client, error) {
	// DocumentDB requires TLS
	tlsConfig := &tls.Config{
		InsecureSkipVerify: false,
	}

	// Custom dialer for DocumentDB
	dialer := &net.Dialer{}

	clientOptions := options.Client().
		ApplyURI(uri).
		SetTLSConfig(tlsConfig).
		SetDialer(dialer).
		SetReplicaSet("rs0").
		SetReadPreference(readpref.SecondaryPreferred())

	client, err := mongo.Connect(context.TODO(), clientOptions)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to DocumentDB: %v", err)
	}

	// Test the connection
	err = client.Ping(context.TODO(), nil)
	if err != nil {
		return nil, fmt.Errorf("failed to ping DocumentDB: %v", err)
	}

	return client, nil
}

// CreateDocumentDBDatabase creates a database connection using DocumentDB-specific settings
func CreateDocumentDBDatabase(uri, dbName string) (*mongo.Database, error) {
	client, err := CreateDocumentDBConnection(uri)
	if err != nil {
		return nil, err
	}

	return client.Database(dbName), nil
}
