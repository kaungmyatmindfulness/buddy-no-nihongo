# Wise Owl Golang Microservices

This document provides instructions for AI coding agents to effectively contribute to the Wise Owl Golang microservices project.

## Architecture Overview

This is a **Japanese language learning backend** built as a monorepo microservices system using Go Workspaces. The architecture follows a domain-driven design with clear service boundaries:

- **API Gateway (Nginx):** Single entry point routing to backend services via `nginx/default.conf`
- **Microservices:** Three domain-specific services in `services/`:
  - `users`: Authentication with Auth0 JWT validation
  - `content`: Educational content (vocabulary, lessons) with JSON seeding, runs dual HTTP/gRPC servers
  - `quiz`: Quiz generation and management
- **Shared Libraries:** Common code in `lib/` (database, config, auth middleware)
- **gRPC Communication:** Inter-service calls using protobuf definitions in `proto/`

## Go Workspace Pattern

This project uses **Go Workspaces** (`go.work`) for monorepo management. All services and libraries are defined as separate modules but work together seamlessly:

```bash
# The workspace includes: gen/, lib/, and all services/
go work use ./gen ./lib ./services/content ./services/users ./services/quiz
```

Each service has its own `go.mod` but shares dependencies through the workspace.

## Development Workflow

### Required: Use dev.sh Script

**ALWAYS use the `./dev.sh` script** for development operations. Never run Docker commands directly:

```bash
# Setup environment (first time only)
./dev.sh setup

# Start full development stack with hot reload
./dev.sh start

# View logs (all services or specific service)
./dev.sh logs
./dev.sh logs content-service

# Stop/restart services
./dev.sh stop
./dev.sh restart

# Clean rebuild after Dockerfile changes
./dev.sh build
```

### Alternative Development Options

```bash
# 1. MongoDB only (run services locally with go run)
docker-compose -f docker-compose.dev.yml up -d mongodb
cd services/content && go run cmd/main.go

# 2. Full containerized stack with hot reload (recommended)
./dev.sh start
```

### gRPC Code Generation

When modifying `.proto` files, regenerate Go code:

```bash
# From project root - regenerates files in gen/proto/
protoc --go_out=gen --go-grpc_out=gen proto/content/content.proto
```

### Hot Reload System

Development uses **Air** for hot reloading with service-specific `.air.toml` configs:

- Watches `services/{service}`, `lib/`, and `gen/` directories
- Auto-rebuilds on `.go`, `.json` file changes
- Excludes `_test.go` files and `vendor/` directory
- Build artifacts go to `tmp/` directory

## Key Patterns & Conventions

### Service Structure

Each service follows this exact pattern:

```
services/{service}/
├── cmd/main.go              # Entry point, content service runs dual HTTP+gRPC
├── internal/
│   ├── handlers/            # HTTP REST handlers for Gin
│   ├── grpc/server.go       # gRPC service implementation (content only)
│   └── models/              # MongoDB document structs with bson tags
├── seed/                    # JSON seed data (content service only)
├── .air.toml                # Hot reload configuration
└── Dockerfile.dev           # Development container with Air
```

### Environment Configuration

**Critical:** Each service requires specific environment variables:

- `DB_NAME`: Determines MongoDB database (e.g., `users_db`, `content_db`)
- `SERVER_PORT`: Service port (default 8080)
- `MONGODB_URI`: Connection string to MongoDB
- `AUTH0_DOMAIN` & `AUTH0_AUDIENCE`: For JWT validation

Use `.env.local` file (created by `./dev.sh setup`) - **never commit this file**.

### Database Per Service

- Each service gets its own MongoDB database via `DB_NAME` env var
- Services use shared `lib/database` singleton connection
- Models use MongoDB driver with BSON tags: `bson:"field_name,omitempty"`

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

Services are exposed through nginx upstreams in `nginx/default.conf`. Add new services:

```nginx
upstream new_service {
    server new-service:8080;
}

location /api/v1/new/ {
    proxy_pass http://new_service;
    # Standard proxy headers are pre-configured
}
```

### Dual Server Pattern (Content Service)

Content service runs **both HTTP and gRPC servers** concurrently:

- HTTP (port 8080): REST API for mobile clients
- gRPC (port 50052): Internal service communication
- Shared database connection and models between both servers

## Critical Integration Points

- **Content→Quiz:** Quiz service calls content service via gRPC to fetch vocabulary batches
- **Quiz→Users:** Quiz service tracks user progress and performance
- **All Services→MongoDB:** Shared MongoDB instance, separate databases per service
- **Mobile Client→Nginx:** All API calls go through nginx gateway on port 80
