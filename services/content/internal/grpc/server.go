// FILE: services/content/internal/grpc/server.go

package grpc

import (
	"context"

	pb "wise-owl/gen/proto/content/v1"
	"wise-owl/services/content/internal/models"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
)

// Server implements the gRPC ContentServiceServer interface.
type Server struct {
	pb.UnimplementedContentServiceServer
	collection *mongo.Collection
}

// NewServer creates a new gRPC server with its database dependency.
func NewServer(db *mongo.Database) *Server {
	return &Server{
		collection: db.Collection("vocabulary"),
	}
}

// GetVocabularyBatch fetches vocabulary details for a list of provided IDs.
func (s *Server) GetVocabularyBatch(ctx context.Context, req *pb.GetVocabularyBatchRequest) (*pb.GetVocabularyBatchResponse, error) {
	// Convert the slice of string IDs from the request into MongoDB ObjectIDs.
	var objectIDs []primitive.ObjectID
	for _, idStr := range req.VocabularyIds {
		id, err := primitive.ObjectIDFromHex(idStr)
		if err == nil {
			objectIDs = append(objectIDs, id)
		}
	}

	// Query the database for all documents with an _id in our list.
	filter := bson.M{"_id": bson.M{"$in": objectIDs}}
	cursor, err := s.collection.Find(ctx, filter)
	if err != nil {
		return nil, err
	}

	var results []models.Vocabulary
	if err = cursor.All(ctx, &results); err != nil {
		return nil, err
	}

	// Convert the database models to protobuf messages and put them in a map.
	responseItems := make(map[string]*pb.Vocabulary)
	for _, vocab := range results {
		pbVocab := &pb.Vocabulary{
			Id:        vocab.ID.Hex(),
			Kana:      vocab.Kana,
			Romaji:    vocab.Romaji,
			English:   vocab.English,
			Burmese:   vocab.Burmese,
			Lesson:    vocab.Lesson,
			Type:      vocab.Type,
			WordClass: vocab.WordClass,
		}
		if vocab.Kanji != nil {
			pbVocab.Kanji = *vocab.Kanji
		}
		if vocab.Furigana != nil {
			pbVocab.Furigana = *vocab.Furigana
		}
		responseItems[pbVocab.Id] = pbVocab
	}

	return &pb.GetVocabularyBatchResponse{Items: responseItems}, nil
}
