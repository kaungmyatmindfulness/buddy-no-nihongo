# Wise Owl Golang Microservices

This document provides instructions for AI coding agents to effectively contribute to the Wise Owl Golang microservices project.

## Architecture Overview

This is a **Japanese language learning backend** built as a monorepo microservices system using Go Workspaces. The architecture follows a domain-driven design with clear service boundaries:

- **API Gateway (Nginx):** Single entry point routing to backend services via `nginx/default.conf`
- **Microservices:** Four domain-specific services in `services/`:
  - `users`: Authentication with Auth0 JWT validation
  - `content`: Educational content (vocabulary, lessons) with JSON seeding
  - `srs`: Spaced Repetition System algorithm
  - `quiz`: Quiz generation and management
- **Shared Libraries:** Common code in `lib/` (database, config, auth middleware)
- **gRPC Communication:** Inter-service calls using protobuf definitions in `proto/`

## Go Workspace Pattern

This project uses **Go Workspaces** (`go.work`) for monorepo management. All services and libraries are defined as separate modules but work together seamlessly:

```bash
# The workspace includes: gen/, lib/, and all services/
go work use ./lib ./services/content ./services/users
```

Each service has its own `go.mod` but shares dependencies through the workspace.

## Development Workflow

### Local Development Setup

```bash
# 1. Start only MongoDB for local development
docker-compose -f docker-compose.dev.yml up -d

# 2. Run individual services locally (they auto-connect to containerized MongoDB)
cd services/content && go run cmd/main.go

# 3. Or run full stack in containers
docker-compose up --build
```

### gRPC Code Generation

When modifying `.proto` files, regenerate Go code:

```bash
# From project root
protoc --go_out=gen --go-grpc_out=gen proto/content/content.proto
```

## Key Patterns & Conventions

### Service Structure

Each service follows this exact pattern:

```
services/{service}/
├── cmd/main.go              # Entry point with dual HTTP/gRPC servers
├── internal/
│   ├── handlers/            # HTTP REST handlers
│   ├── grpc/server.go       # gRPC service implementation
│   └── models/              # MongoDB document structs
└── seed/                    # JSON seed data (content service only)
```

### Database Per Service

- Each service gets its own MongoDB database (e.g., `users_db`, `content_db`)
- Services use the shared `lib/database` singleton connection
- Models use MongoDB driver with BSON tags: `bson:"field_name"`

### Configuration Pattern

All services use `lib/config` with Viper for environment variables:

```go
// Services load config identically
cfg, err := config.LoadConfig()
// DB_NAME environment variable determines which database to use
```

### Auth0 Integration

The `lib/auth/middleware.go` provides JWT validation middleware for Gin routes:

```go
// Apply to protected routes
router.Use(auth.EnsureValidToken(cfg.Auth0Domain, cfg.Auth0Audience))
```

### Data Seeding

The content service auto-seeds from `seed/vocabulary.json` on startup - implement similar seeding patterns for other services that need initial data.

### Nginx Routing

Services are exposed through nginx upstreams. Add new services to `nginx/default.conf`:

```nginx
upstream new_service {
    server new-service:8080;
}
```

## Critical Integration Points

- **Content→Quiz:** Quiz service calls content service via gRPC to fetch vocabulary batches
- **SRS→Users:** SRS tracks user progress and learning intervals
- **All Services→MongoDB:** Shared MongoDB instance, separate databases per service
- **Mobile Client→Nginx:** All API calls go through nginx gateway on port 80
