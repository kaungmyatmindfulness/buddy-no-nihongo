# Wise Owl Japanese Learning Platform - Developer Guide

This guide helps AI coding agents understand and contribute effectively to the Wise Owl Golang microservices project - a backend system for a Japanese language learning mobile app based on the "Minna no Nihongo" textbook series.

## 🎯 The Big Picture: What This System Does

**Core Purpose:** Enable progressive Japanese vocabulary and grammar learning with intelligent quiz generation and progress tracking.

**Key Learning Flow:**

1. Students learn vocabulary from textbook chapters
2. Grammar unlocks only after vocabulary mastery
3. Multi-modal quizzes test retention (flashcards, meaning, word recognition)
4. Real-time progress tracking prevents data loss
5. Filtered review sessions target weak areas

## 🏗️ Architecture: Monorepo Microservices with Go Workspaces

### System Components Diagram

```
Mobile App → Nginx Gateway → [Users|Content|Quiz] Services → MongoDB Databases
                ↓              ↓         ↓        ↓
            Port 80        Port 8081  8082   8083
                              ↓         ↓        ↓
                           users_db content_db quiz_db
                                      ↑        ↑
                                      └─gRPC──┘
```

### Service Boundaries & Responsibilities

**🔐 Users Service** (`services/users/`)

- **Domain:** User identity, authentication, progress tracking
- **Dependencies:** None (foundational service)
- **Key Features:** Auth0 JWT validation, chapter completion status
- **Database:** `users_db` - user profiles, learning progress

**📚 Content Service** (`services/content/`)

- **Domain:** Static educational content from Minna no Nihongo
- **Dependencies:** None (foundational service)
- **Key Features:** Dual HTTP/gRPC servers, auto-seeding from JSON
- **Database:** `content_db` - vocabulary, lessons, structured by chapters
- **Special:** Runs both REST API (mobile) and gRPC (internal) simultaneously

**🧠 Quiz Service** (`services/quiz/`)

- **Domain:** Dynamic quiz generation and answer validation
- **Dependencies:** Content Service (via gRPC)
- **Key Features:** Multi-modal questions, real-time scoring
- **Database:** `quiz_db` - quiz sessions, user responses, performance analytics

### Data Flow: Why Services Communicate This Way

```
1. Mobile App requests quiz → Quiz Service
2. Quiz Service fetches vocabulary → Content Service (gRPC)
3. Quiz Service generates questions → Returns to mobile
4. User answers → Quiz Service saves immediately
5. Progress updates → Users Service (future enhancement)
```

**Why gRPC for Internal Communication:**

- Type-safe contracts with protobuf
- High-performance for batch vocabulary fetching
- Streaming support for future real-time features

## 🛠️ Development Workflows: The `./dev.sh` Pattern

### Critical: Always Use dev.sh Script

**Why this pattern exists:** Standardizes complex Docker Compose operations, environment management, and hot reloading across the team.

```bash
# First-time setup (creates .env.local)
./dev.sh setup

# Development mode with hot reload (MOST COMMON)
./dev.sh start    # Starts all services with Air hot reloading
./dev.sh logs     # View aggregated logs
./dev.sh stop     # Clean shutdown

# Debugging specific services
./dev.sh logs content-service  # Isolated service logs
./dev.sh restart              # Restart all without rebuilding
```

### Three Development Modes

**Mode A: Full Docker Development (Recommended)**

```bash
./dev.sh start  # Everything in containers with hot reload
```

- **Use when:** Normal development, testing integrations
- **Benefits:** Consistent environment, full service mesh, realistic networking

**Mode B: Hybrid Development**

```bash
docker-compose -f docker-compose.dev.yml up mongodb -d
cd services/content && go run cmd/main.go
```

- **Use when:** Debugging specific service with IDE breakpoints
- **Benefits:** Local debugging while maintaining service dependencies

**Mode C: Production Simulation**

```bash
docker-compose up --build -d
```

- **Use when:** Testing deployment, final integration testing
- **Benefits:** Production-like container builds and networking

### Hot Reload with Air

**Files watched:** `services/{service}`, `lib/`, `gen/`
**Triggers:** `.go`, `.json` file changes
**Build pattern:** `go build -o ./tmp/main ./services/{service}/cmd`

Each service has `.air.toml` configured to:

- Watch shared libraries for cross-service changes
- Exclude test files and vendor directory
- Use consistent build output naming

## 🔧 Go Workspace: Monorepo Magic

```go
// go.work
go 1.24.4
use (
    ./gen      // Generated protobuf code
    ./lib      // Shared libraries
    ./services/content
    ./services/quiz
    ./services/users
)
```

**Why this pattern:**

- Single `go mod tidy` updates all services
- Shared libraries automatically sync across services
- Local development feels like single project
- Avoids version conflicts between services

**Key Commands:**

```bash
go work sync    # Sync dependencies across all modules
go work vendor  # Vendor for containerized builds
```

## 🏥 Enterprise Health Check System

### Circuit Breaker Pattern Implementation

**Problem Solved:** Prevents cascading failures when services are down
**Pattern:** Quiz Service → Content Service dependency with intelligent failure handling

```go
// Each service implements comprehensive health checks
healthChecker := health.NewHealthChecker("Quiz Service", "1.0.0", "development")
healthChecker.SetMongoClient(dbConn.Client, dbName)

// Circuit breaker automatically handles dependency failures
hc.AddDependencyWithConfig("content-service", &DependencyConfig{
    Name:         "content-service",
    URL:          "http://content-service:8080",
    Critical:     true,
    CheckType:    "http",
})
```

### Health Endpoint Strategy

**Four specialized endpoints per service:**

- `/health` - Overall status with dependency checking
- `/health/ready` - Kubernetes readiness probe
- `/health/live` - Kubernetes liveness probe
- `/health/metrics` - Circuit breaker stats, response times

**Testing health checks:**

```bash
./test-health.sh  # Comprehensive validation script
curl localhost:8083/health | jq  # Manual testing
```

## 🔗 Critical Integration Patterns

### gRPC Service-to-Service Communication

**Content Service gRPC Definition** (`proto/content/content.proto`):

```protobuf
service ContentService {
  rpc GetVocabularyBatch(GetVocabularyBatchRequest) returns (GetVocabularyBatchResponse);
}
```

**Quiz Service Integration** (`services/quiz/cmd/main.go`):

```go
// Connect to Content Service gRPC
conn, err := grpc.Dial("content-service:50052", grpc.WithTransportCredentials(insecure.NewCredentials()))
contentClient := pb_content.NewContentServiceClient(conn)
```

**Why this specific pattern:**

- Batch fetching prevents N+1 query problems
- Type safety with protobuf ensures API contracts
- gRPC health checking integrates with circuit breakers

### Database Per Service Pattern

**Logical separation with shared MongoDB:**

```yaml
# Each service gets its own database
users-service: DB_NAME=users_db
content-service: DB_NAME=content_db
quiz-service: DB_NAME=quiz_db
```

**Shared connection library** (`lib/database/database.go`):

- Singleton pattern prevents connection proliferation
- Environment-based database selection
- Consistent error handling and connection pooling

### Auth0 JWT Integration

**Middleware pattern** (`lib/auth/middleware.go`):

```go
// Protect quiz routes requiring authentication
router.Use(auth.EnsureValidToken(cfg.Auth0Domain, cfg.Auth0Audience))
```

**Environment configuration:**

```bash
AUTH0_DOMAIN=your-domain.auth0.com
AUTH0_AUDIENCE=your-api-identifier
```

## 📡 Port Allocation & Networking

**Critical Docker networking requirements:**

```yaml
# Content Service: MUST expose both ports
ports:
  - "8082:8080" # HTTP for mobile clients
  - "50052:50052" # gRPC for inter-service calls

# Other services: HTTP only
users-service: "8081:8080"
quiz-service: "8083:8080"
```

**Why dual ports for Content Service:**

- HTTP (8080): REST API for mobile app consumption
- gRPC (50052): High-performance internal API for Quiz Service

## 🚨 Common Debugging Scenarios

### Circuit Breaker Issues

```bash
# Check circuit breaker state
curl localhost:8083/health | jq '.checks."content-service".details'

# Common states:
# "closed" = healthy, requests flowing
# "open" = failing, blocking requests
# "half-open" = testing recovery
```

### gRPC Connectivity Problems

```bash
# Verify port exposure in docker-compose.dev.yml
grep -A 10 "content-service:" docker-compose.dev.yml

# Test gRPC port accessibility
docker exec quiz-service nc -zv content-service 50052
```

### Hot Reload Not Working

```bash
# Check Air configuration includes all dependencies
grep -A 5 "include_dir" services/quiz/.air.toml
# Should include: ["services/quiz", "lib", "gen"]
```

### Environment Variable Issues

```bash
# Verify .env.local exists and is loaded
./dev.sh logs content-service | grep "Configuration loaded"
# Should show: "Using database: content_db"
```

## 🔄 protobuf Code Generation

**When to regenerate:**

- After modifying `.proto` files
- Adding new gRPC methods
- Changing message structures

```bash
# From project root
protoc --go_out=gen --go-grpc_out=gen proto/content/content.proto

# Verify generation
ls gen/proto/content/
# Should see: content.pb.go, content_grpc.pb.go
```

## 📁 Project Structure Logic

```
wise-owl-golang/
├── .env.local              # Never commit - contains secrets
├── go.work                 # Workspace definition
├── proto/                  # Source of truth for gRPC contracts
├── gen/                    # Generated code (committed for consistency)
├── lib/                    # Shared libraries used by all services
│   ├── auth/               # JWT middleware
│   ├── config/             # Viper-based env loading
│   ├── database/           # MongoDB singleton
│   └── health/             # Circuit breaker health checks
├── services/               # Domain-driven service boundaries
│   ├── users/              # User management & progress
│   ├── content/            # Static curriculum content
│   └── quiz/               # Dynamic quiz generation
├── nginx/                  # Single entry point configuration
└── test-health.sh          # Health check validation tool
```

## 🎯 Production Readiness Features

**Kubernetes Integration:**

- Health check endpoints match Kubernetes probe expectations
- Container health checks use `wget --spider` for reliability
- Graceful shutdown handling in all services

**Observability:**

- Structured logging with service identification
- Circuit breaker metrics for monitoring dashboards
- Request tracing through service boundaries

**Security:**

- JWT validation on protected endpoints
- Environment-based secrets management
- No hardcoded credentials in codebase

This architecture enables rapid development while maintaining production-grade reliability and observability.
