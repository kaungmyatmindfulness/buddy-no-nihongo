# Wise Owl Golang Microservices - AI Coding Agent Instructions

## Architecture Overview

This is a **Japanese vocabulary learning platform** built as microservices with Go, following a specific modular pattern:

- **API Gateway**: Nginx routes `/api/v1/{service}/` to respective services
- **Services**: Independent microservices (`users`, `content`, `quiz`) with HTTP + gRPC APIs
- **Shared Libraries**: `lib/` contains reusable auth, config, database, health modules
- **Protocol Buffers**: `proto/` defines gRPC contracts, generated code in `gen/`
- **Go Workspace**: Uses `go.work` to manage multiple modules

### Service Communication Patterns

- **External**: HTTP REST APIs via Nginx gateway (port 8080 in dev, 80 in prod)
- **Internal**: gRPC on unique ports (`content`: 50052, `quiz`: 50053, etc.)
- **Database**: Each service has dedicated MongoDB database (`{service}_db`)

## Development Workflow

### Core Commands (use these, not manual docker/go commands)

```bash
./scripts/dev.sh start          # Start all services in development mode
./scripts/dev-watch.sh          # Start with hot reload (requires Docker Compose 2.22+)
./scripts/generate-service.sh   # Create new service from template
./scripts/test-dev.sh           # Quick health check of all services
```

### Environment Setup

- Environment files: `.env.local` (dev), `.env.docker` (production), `.env.example` (template)
- Use `.envrc` for direnv support with `dotenv .env.local`
- Config loaded via `lib/config.LoadConfig()` with defaults
- Auth0 integration optional (set `AUTH0_DOMAIN`, `AUTH0_AUDIENCE`)

### Service Structure Pattern

```
services/{name}/
├── cmd/main.go                    # Dual server setup (HTTP + gRPC)
├── internal/
│   ├── handlers/{name}_handlers.go # HTTP REST endpoints
│   ├── grpc/{name}_grpc.go        # gRPC service implementation
│   ├── models/{name}.go           # MongoDB models
│   └── seeder/seeder.go           # Database initialization
├── Dockerfile & Dockerfile.dev    # Production & development containers
└── go.mod                         # Service-specific dependencies
```

## Critical Conventions

### Authentication & Middleware

- Use `lib/auth.EnsureValidToken()` for protected endpoints
- JWT validation through Auth0 (optional configuration)
- All services follow same auth pattern in `main.go`

### Database & Models

- MongoDB with collection per model type
- Models use `bson` tags for MongoDB, `json` for REST
- Database seeding through JSON files in `seed/` directories
- Connection via `lib/database.Connect()`

### gRPC Integration

- Define services in `proto/{service}/{service}.proto`
- Generate with standard protoc tools into `gen/proto/{service}/`
- Implement in `internal/grpc/{service}_grpc.go`
- Register both HTTP and gRPC servers in `main.go`

### Health Checks & Monitoring

- Use `lib/health.NewSimpleHealthChecker()`
- Standard endpoints: `/health/ready`, `/health/live`
- Docker health checks configured in compose files

## Service-Specific Knowledge

### Content Service (Vocabulary Management)

- Primary data: Japanese vocabulary with kana, kanji, furigana, romaji, English, Burmese
- Structure: lesson-based organization with word types/classes
- Seeding: Massive JSON file (`22k+ entries`) loaded on first startup
- gRPC: `GetVocabularyBatch` for inter-service communication

### Development Gotchas

- Services have both HTTP (8080) and gRPC (505x) servers running concurrently
- Docker volumes exclude `tmp/` and `vendor/` for performance
- Hot reload requires Docker Compose watch mode (version 2.22+)
- Use `go.work` commands from project root, not individual service directories

### Adding New Services

1. Run `./scripts/generate-service.sh <service-name>`
2. Update `go.work` to include new service: `use ./services/<service-name>`
3. Add service to `docker-compose.dev.yml` and `docker-compose.yml`
4. Add Nginx routing rules in `nginx/default.conf` for `/api/v1/<service>/`
5. Define protobuf contracts if inter-service communication needed

### Testing & Debugging

- No formal test suite currently - services validated via health endpoints
- Use `./scripts/test-dev.sh` for quick service health verification
- Services expose `/health`, `/health/ready`, and `/health/live` endpoints
- gRPC services can be tested with grpcurl or similar tools
- Individual services accessible in dev: `users:8081`, `content:8082`, `quiz:8083`

## Key Files to Reference

- `lib/config/config.go` - Centralized configuration pattern
- `lib/auth/middleware.go` - JWT validation implementation
- `templates/service-template/cmd/main.go` - Service template structure
- `services/content/cmd/main.go` - Example dual-server implementation
- `nginx/default.conf` - API Gateway routing configuration
- `proto/content/content.proto` - Example gRPC service definition
- `docker-compose.dev.yml` - Development environment with hot reload
