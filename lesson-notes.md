# Wise Owl Golang Microservices: Computer Science Lesson Notes

## Table of Contents

1. [System Architecture Overview](#1-system-architecture-overview)
2. [Microservices Architecture Pattern](#2-microservices-architecture-pattern)
3. [Communication Patterns & Protocols](#3-communication-patterns--protocols)
4. [Database Design & Data Management](#4-database-design--data-management)
5. [Authentication & Security](#5-authentication--security)
6. [Container Orchestration & DevOps](#6-container-orchestration--devops)
7. [Go-Specific Patterns & Idioms](#7-go-specific-patterns--idioms)
8. [Performance & Scalability Considerations](#8-performance--scalability-considerations)

---

## 1. System Architecture Overview

### High-Level Architecture

```
┌─────────────┐    ┌──────────────┐    ┌─────────────┐
│   Frontend  │────│ Nginx Gateway│────│  Services   │
│  (Client)   │    │   (Port 80)  │    │ (8081-8083) │
└─────────────┘    └──────────────┘    └─────────────┘
                           │
                   ┌───────┼───────┐
                   │       │       │
              ┌─────▼──┐ ┌─▼────┐ ┌▼─────┐
              │Users   │ │Content│ │Quiz  │
              │Service │ │Service│ │Service│
              └─────┬──┘ └─┬────┘ └┬─────┘
                    │      │gRPC   │
                    │      │:50052 │
              ┌─────▼──────▼───────▼─────┐
              │     MongoDB Cluster      │
              │  (users_db,content_db,   │
              │     quiz_db)             │
              └──────────────────────────┘
```

### Architecture Style: **Microservices with API Gateway Pattern**

**Theoretical Foundation:**

- **Conway's Law**: "Organizations design systems that mirror their communication structure"
- **Separation of Concerns**: Each service has a single responsibility
- **Domain-Driven Design (DDD)**: Services are organized around business domains

**Why This Architecture?**

1. **Scalability**: Independent scaling of services based on load
2. **Technology Diversity**: Each service can use different tech stacks
3. **Fault Isolation**: Failure in one service doesn't bring down the entire system
4. **Team Autonomy**: Different teams can work on different services
5. **Deployment Independence**: Services can be deployed separately

---

## 2. Microservices Architecture Pattern

### Core Principles Applied

#### 2.1 Service Boundaries (Domain-Driven Design)

```
Users Service:     │ Content Service:   │ Quiz Service:
- Authentication   │ - Vocabulary Data  │ - Quiz Logic
- User Profiles    │ - Lessons          │ - Progress Tracking
- User Preferences │ - Content Mgmt     │ - Spaced Repetition
```

**Bounded Context Pattern**: Each service manages its own data and business rules within clearly defined boundaries.

#### 2.2 Database per Service Pattern

```go
// Each service has its own database
users-service    → users_db
content-service  → content_db
quiz-service     → quiz_db
```

**Theory**: **Database per Service Pattern** from microservices architecture

- **Data Encapsulation**: No direct database access between services
- **Schema Evolution**: Each service can evolve its data model independently
- **Technology Choice**: Different services can use different database technologies

**Trade-offs:**

- ✅ **Loose Coupling**: Services don't share database schemas
- ✅ **Independent Deployment**: Database changes don't affect other services
- ❌ **Data Consistency**: Need to handle distributed transactions
- ❌ **Data Joining**: Cross-service queries require API calls

#### 2.3 Shared Libraries Pattern

```go
// lib/ directory contains reusable components
lib/
├── auth/        // JWT middleware
├── config/      // Configuration management
├── database/    // MongoDB connection singleton
└── health/      // Health check utilities
```

**Theory**: **Shared Kernel Pattern** from Domain-Driven Design

- **Code Reuse**: Common functionality is centralized
- **Consistency**: Uniform behavior across services
- **Maintenance**: Single place to update common logic

---

## 3. Communication Patterns & Protocols

### 3.1 Synchronous Communication

#### HTTP REST API (External Communication)

```go
// HTTP endpoints using Gin framework
apiV1 := router.Group("/api/v1")
userRoutes := apiV1.Group("/users")
userRoutes.Use(authMiddleware) // Middleware pattern
{
    userRoutes.POST("/onboarding", userHandler.OnboardUser)
    userRoutes.GET("/me/profile", userHandler.GetUserProfile)
}
```

**Theory**: **RESTful Architecture** (Representational State Transfer)

- **Stateless**: Each request contains all necessary information
- **Cacheable**: Responses can be cached for performance
- **Uniform Interface**: Standard HTTP methods (GET, POST, PATCH, DELETE)
- **Resource-Based**: URLs represent resources, not actions

#### gRPC (Internal Communication)

```protobuf
// Protocol Buffer definition
service ContentService {
  rpc GetVocabularyBatch(GetVocabularyBatchRequest)
      returns (GetVocabularyBatchResponse);
}
```

**Theory**: **Remote Procedure Call (RPC)** with Protocol Buffers

- **Type Safety**: Strong typing across service boundaries
- **Performance**: Binary serialization is faster than JSON
- **Code Generation**: Client and server code generated from .proto files
- **HTTP/2**: Multiplexing, compression, and streaming support

**Why gRPC for Internal Communication?**

1. **Performance**: 7-10x faster than REST for complex data
2. **Type Safety**: Compile-time checking of API contracts
3. **Streaming**: Support for real-time data streams
4. **Language Agnostic**: Can integrate with non-Go services

### 3.2 API Gateway Pattern

```nginx
# Nginx configuration - Single entry point
location /api/v1/users/ {
    proxy_pass http://users_service;
}
location /api/v1/content/ {
    proxy_pass http://content_service;
}
```

**Theory**: **API Gateway Pattern**

- **Single Entry Point**: All client requests go through one gateway
- **Cross-Cutting Concerns**: Authentication, logging, rate limiting
- **Protocol Translation**: Can translate between different protocols
- **Load Balancing**: Distribute requests across service instances

**Benefits:**

- **Client Simplicity**: Clients only need to know one endpoint
- **Service Evolution**: Backend services can change without affecting clients
- **Security**: Single point for implementing security policies

---

## 4. Database Design & Data Management

### 4.1 MongoDB Document Database Choice

**Why MongoDB over Relational Databases?**

```go
// MongoDB document - flexible schema
type Vocabulary struct {
    ID        primitive.ObjectID `bson:"_id,omitempty" json:"id"`
    Kana      string            `bson:"kana" json:"kana"`
    Kanji     *string           `bson:"kanji,omitempty" json:"kanji,omitempty"`
    Furigana  *string           `bson:"furigana,omitempty" json:"furigana,omitempty"`
    Romaji    string            `bson:"romaji" json:"romaji"`
    English   string            `bson:"english" json:"english"`
    Burmese   string            `bson:"burmese" json:"burmese"`
}
```

**Advantages for This Use Case:**

1. **Schema Flexibility**: Japanese vocabulary has varying field requirements
2. **JSON-like Structure**: Natural fit for REST APIs
3. **Horizontal Scaling**: Built-in sharding support
4. **Rich Query Language**: Complex queries without joins

### 4.2 Connection Management Pattern

```go
// Singleton pattern for database connections
var (
    conn *DB
    once sync.Once  // Ensures single initialization
)

func Connect(uri string) *DB {
    once.Do(func() {
        // Connection logic executed only once
        client, err := mongo.NewClient(options.Client().ApplyURI(uri))
        // ... connection setup
        conn = &DB{Client: client}
    })
    return conn
}
```

**Theory**: **Singleton Pattern** with **sync.Once**

- **Resource Management**: Single connection pool per service
- **Thread Safety**: sync.Once ensures thread-safe initialization
- **Performance**: Avoids connection overhead on each request

### 4.3 Data Seeding Strategy

```go
// services/content/internal/seeder/seeder.go
func SeedData(dbName string, client *mongo.Client) {
    // Check if data already exists
    collection := client.Database(dbName).Collection("vocabulary")
    count, _ := collection.CountDocuments(context.Background(), bson.D{})

    if count == 0 {
        // Load from JSON file and insert
        loadVocabularyFromJSON(collection)
    }
}
```

**Theory**: **Database Seeding Pattern**

- **Idempotent Operations**: Safe to run multiple times
- **Environment Consistency**: Same data across development environments
- **Testing**: Predictable data for automated tests

---

## 5. Authentication & Security

### 5.1 JSON Web Token (JWT) Authentication

```go
// JWT Middleware implementation
func EnsureValidToken(domain, audience string) gin.HandlerFunc {
    // JWKS (JSON Web Key Set) for token verification
    provider := jwks.NewCachingProvider(issuerURL, 5*time.Minute)

    jwtValidator, err := validator.New(
        provider.KeyFunc,
        validator.RS256,        // RSA with SHA-256
        issuerURL.String(),
        []string{audience},
    )
    // ...
}
```

**Theory**: **JWT (JSON Web Token) Authentication**

- **Stateless Authentication**: No server-side session storage required
- **Claims-Based**: Token contains user information and permissions
- **Cryptographic Signatures**: RS256 (RSA + SHA-256) ensures token integrity
- **Expiration**: Time-based token expiry for security

**Security Features:**

1. **JWKS Rotation**: Automatic key rotation from Auth0
2. **Clock Skew Tolerance**: Handles minor time differences
3. **Audience Validation**: Ensures token is for this application
4. **Issuer Validation**: Verifies token comes from trusted source

### 5.2 Middleware Pattern for Cross-Cutting Concerns

```go
// Middleware chain
userRoutes.Use(authMiddleware)  // Applied to all routes in group
{
    userRoutes.POST("/onboarding", userHandler.OnboardUser)
    // Auth automatically applied to all these routes
}
```

**Theory**: **Middleware Pattern** (Chain of Responsibility)

- **Cross-Cutting Concerns**: Authentication, logging, CORS
- **Composability**: Can combine multiple middleware
- **Request Pipeline**: Each middleware can modify request/response
- **Early Exit**: Authentication failure stops request processing

### 5.3 Auth0 Integration

**Theory**: **OAuth 2.0 / OpenID Connect**

- **Delegation**: Auth0 handles authentication complexity
- **Social Login**: Google, Facebook, GitHub integration
- **Multi-Factor Authentication**: Built-in security features
- **User Management**: Centralized user store

**Why External Authentication?**

1. **Security Expertise**: Auth0 specializes in authentication
2. **Compliance**: Handles GDPR, SOC2, etc.
3. **Scalability**: Handles millions of users
4. **Features**: MFA, social login, user management UI

---

## 6. Container Orchestration & DevOps

### 6.1 Multi-Stage Docker Builds

```dockerfile
# Stage 1: Build stage
FROM golang:1.24-alpine AS builder
WORKDIR /app
COPY go.work go.work.sum ./
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o /app/main ./services/content/cmd

# Stage 2: Runtime stage
FROM alpine:latest
COPY --from=builder /app/main /app/main
EXPOSE 8080
CMD ["/app/main"]
```

**Theory**: **Multi-Stage Docker Builds**

- **Size Optimization**: Final image contains only runtime dependencies
- **Security**: Smaller attack surface (no build tools in production)
- **Layer Caching**: Build dependencies cached separately

**Benefits:**

- **Production Image**: ~20MB vs ~300MB+ with build tools
- **Security**: No Go compiler or source code in production
- **Performance**: Faster container startup and deployment

### 6.2 Development vs Production Environments

#### Development (Hot Reload)

```dockerfile
FROM golang:1.24-alpine
RUN go install github.com/air-verse/air@latest
CMD ["air", "-c", "services/content/.air.toml"]
```

#### Production (Static Binary)

```dockerfile
FROM alpine:latest
COPY --from=builder /app/main /app/main
CMD ["/app/main"]
```

**Theory**: **Environment Parity** (12-Factor App Principle)

- **Development Speed**: Hot reload for rapid iteration
- **Production Efficiency**: Static binaries for performance
- **Configuration**: Environment variables for differences

### 6.3 Docker Compose Orchestration

```yaml
# Service dependencies and health checks
depends_on:
  mongodb:
    condition: service_healthy
  content-service:
    condition: service_healthy
```

**Theory**: **Service Orchestration**

- **Dependency Management**: Services start in correct order
- **Health Checks**: Ensure services are ready before dependents start
- **Network Isolation**: Services communicate through Docker networks
- **Volume Management**: Persistent data and development bind mounts

### 6.4 Go Workspaces for Monorepo Management

```go
// go.work - Multi-module workspace
go 1.24.4

use (
    ./gen      // Generated protobuf code
    ./lib      // Shared libraries
    ./services/content
    ./services/quiz
    ./services/users
)
```

**Theory**: **Monorepo Pattern** with **Go Workspaces**

- **Code Sharing**: Shared libraries across services
- **Atomic Changes**: Update multiple services in single commit
- **Dependency Management**: Consistent versions across services
- **Build Efficiency**: Shared module cache

**Benefits:**

- **Developer Experience**: Single repository clone
- **Cross-Service Refactoring**: IDE support for multi-module changes
- **Consistent Tooling**: Same linting, testing, deployment scripts

---

## 7. Go-Specific Patterns & Idioms

### 7.1 Error Handling Pattern

```go
// Go error handling idiom
func Connect(uri string) *DB {
    client, err := mongo.NewClient(options.Client().ApplyURI(uri))
    if err != nil {
        log.Fatalf("FATAL: Failed to create MongoDB client: %v", err)
    }
    // ... continue with success path
}
```

**Theory**: **Explicit Error Handling**

- **No Exceptions**: Errors are values, not exceptional control flow
- **Fail Fast**: Fatal errors terminate the program immediately
- **Error Context**: Rich error messages for debugging

### 7.2 Interface-Based Design

```go
// Protocol buffer generates interface
type ContentServiceServer interface {
    GetVocabularyBatch(context.Context, *GetVocabularyBatchRequest) (*GetVocabularyBatchResponse, error)
}

// Implementation satisfies interface
type Server struct {
    pb.UnimplementedContentServiceServer
    collection *mongo.Collection
}
```

**Theory**: **Interface Segregation** (SOLID Principles)

- **Loose Coupling**: Depend on interfaces, not concrete types
- **Testing**: Easy to create mocks for testing
- **Composition**: Embed interfaces for default implementations

### 7.3 Goroutines for Concurrent Servers

```go
// Dual server pattern - HTTP and gRPC concurrently
go func() {
    // gRPC server in goroutine
    grpcServer.Serve(lis)
}()

// HTTP server in main goroutine
httpServer.ListenAndServe()
```

**Theory**: **Concurrent Programming with Goroutines**

- **Lightweight Threads**: Goroutines are much cheaper than OS threads
- **M:N Scheduling**: Many goroutines on few OS threads
- **Channel Communication**: "Don't communicate by sharing memory; share memory by communicating"

### 7.4 Context for Request Scoping

```go
func (s *Server) GetVocabularyBatch(ctx context.Context, req *pb.GetVocabularyBatchRequest) (*pb.GetVocabularyBatchResponse, error) {
    cursor, err := s.collection.Find(ctx, filter)
    // ctx carries request deadline, cancellation, values
}
```

**Theory**: **Context Pattern** for Request Lifecycle

- **Cancellation**: Cancel downstream operations if client disconnects
- **Deadlines**: Prevent long-running operations
- **Request Values**: Carry request-scoped data (user ID, trace ID)

---

## 8. Performance & Scalability Considerations

### 8.1 Connection Pooling

```go
// MongoDB driver automatically pools connections
client, err := mongo.NewClient(options.Client().ApplyURI(uri))
// Default: 100 connections per host
```

**Theory**: **Connection Pooling**

- **Resource Efficiency**: Reuse expensive database connections
- **Latency Reduction**: No connection setup time per request
- **Concurrency**: Multiple requests share connection pool

### 8.2 Caching Strategies

```go
// JWKS caching to avoid frequent key fetches
provider := jwks.NewCachingProvider(issuerURL, 5*time.Minute)
```

**Theory**: **Caching Patterns**

- **Time-Based Expiration**: Balance security vs performance
- **Hot Data**: Frequently accessed authentication keys
- **Cache Invalidation**: Automatic refresh on expiration

### 8.3 Horizontal Scaling Considerations

#### Stateless Services

```go
// No server-side session state
claims := r.Context().Value(jwtmiddleware.ContextKey{}).(*validator.ValidatedClaims)
userID := claims.RegisteredClaims.Subject
// All user context in JWT token
```

**Theory**: **Stateless Architecture**

- **Load Balancing**: Requests can go to any server instance
- **Auto-Scaling**: Easy to add/remove server instances
- **Fault Tolerance**: Server failure doesn't lose user sessions

#### Database Scaling

```
MongoDB Replica Sets and Sharding:
Primary ←→ Secondary (Read Replicas)
    ↓
Sharding based on user ID or content type
```

**Theory**: **Database Scaling Patterns**

- **Read Replicas**: Scale read operations
- **Sharding**: Distribute data across multiple databases
- **Eventual Consistency**: Trade consistency for availability (CAP theorem)

### 8.4 Performance Monitoring

```go
// Health check endpoints for monitoring
router.GET("/health", healthChecker.Handler())
router.GET("/health/ready", healthChecker.ReadyHandler())
```

**Theory**: **Observability** (Monitoring, Logging, Tracing)

- **Health Checks**: Automated monitoring of service health
- **Structured Logging**: Machine-parseable log format
- **Distributed Tracing**: Track requests across services

---

## Conclusion: Why These Patterns Matter

### Academic Computer Science Concepts Applied

1. **Distributed Systems**: CAP theorem, eventual consistency, partition tolerance
2. **Software Engineering**: SOLID principles, design patterns, clean architecture
3. **Networks**: HTTP/2, protocol buffers, load balancing
4. **Security**: Cryptography, authentication protocols, secure communication
5. **Performance**: Caching, connection pooling, concurrent programming
6. **DevOps**: Infrastructure as code, containerization, orchestration

### Real-World Trade-offs

| Pattern       | Benefits                   | Costs                                |
| ------------- | -------------------------- | ------------------------------------ |
| Microservices | Scalability, team autonomy | Complexity, network overhead         |
| gRPC          | Performance, type safety   | Learning curve, debugging            |
| JWT Auth      | Stateless, scalable        | Token size, key rotation             |
| Docker        | Consistency, isolation     | Resource overhead, complexity        |
| MongoDB       | Flexibility, performance   | Eventual consistency, learning curve |

### Industry Relevance

This codebase demonstrates patterns used by companies like:

- **Netflix**: Microservices architecture
- **Google**: gRPC and Protocol Buffers
- **Auth0**: JWT-based authentication
- **MongoDB**: Document-based data modeling
- **Docker**: Containerization and orchestration

### Learning Path Recommendations

1. **Deep Dive into Go**: Concurrency patterns, interface design, error handling
2. **Distributed Systems Theory**: Read "Designing Data-Intensive Applications"
3. **Microservices Patterns**: Study Martin Fowler's microservices articles
4. **Container Orchestration**: Learn Kubernetes for production deployments
5. **Database Theory**: Study CAP theorem, ACID vs BASE properties
6. **Security**: Learn OAuth 2.0, OpenID Connect, JWT best practices

This architecture represents modern, production-ready patterns that balance development velocity, system reliability, and operational simplicity.
