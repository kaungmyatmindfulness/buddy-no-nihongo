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
./wise-owl dev start            # Start all services in development mode
./wise-owl dev watch            # Start with hot reload (requires Docker Compose 2.22+)
./wise-owl dev test             # Quick health check of all services
./wise-owl dev status           # Show service status
```

**Alternative direct paths:**

```bash
./scripts/development/dev.sh [command]
./scripts/development/dev-watch.sh
./scripts/development/test-dev.sh
```

### Environment Setup

- Environment files: `.env.local.example` (dev template), `.env.aws.example` (AWS template)
- Use `.envrc` for direnv support with `dotenv .env.local`
- Config loaded via `lib/config.LoadConfig()` with AWS detection
- Supports both MongoDB (local) and DocumentDB (AWS) via `DB_TYPE` setting
- Auth0 integration optional (set `AUTH0_DOMAIN`, `AUTH0_AUDIENCE`)
- AWS config auto-loads from Secrets Manager and Parameter Store in AWS environments

### Service Structure Pattern

```
services/{name}/
├── cmd/main.go                    # Dual server setup (HTTP + gRPC)
├── cmd/main_aws.go               # AWS-optimized version (build tag: aws)
├── internal/
│   ├── handlers/{name}_handlers.go # HTTP REST endpoints
│   ├── grpc/{name}_grpc.go        # gRPC service implementation
│   ├── models/{name}.go           # MongoDB models
│   └── seeder/seeder.go           # Database initialization (optional)
├── Dockerfile & Dockerfile.dev    # Production & development containers
└── go.mod                         # Service-specific dependencies
```

## Critical Conventions

### Authentication & Middleware

- Use `lib/auth.EnsureValidToken(domain, audience)` for protected endpoints
- JWT validation through Auth0 (optional configuration)
- All services follow same auth pattern in `main.go`

### Database & Models

- MongoDB (local) and AWS DocumentDB (production) support via `DB_TYPE` config
- Models use `bson` tags for MongoDB, `json` for REST
- Database seeding through JSON files in `seed/` directories (content service)
- Users service creates indexes automatically (no pre-seeding needed)
- Connection via `database.CreateDatabaseSingleton(cfg)` with auto-detection
- AWS environments load credentials from Secrets Manager (`wise-owl/production`)
- Each service uses dedicated database: `{service}_db` (e.g., `content_db`, `users_db`)

### gRPC Integration

- Define services in `proto/{service}/{service}.proto`
- Generate with standard protoc tools into `gen/proto/{service}/`
- Implement in `internal/grpc/{service}_grpc.go`
- Register both HTTP and gRPC servers in `main.go`

### Health Checks & Monitoring

- Use `lib/health.NewSimpleHealthChecker()` for local development
- Use `lib/health.NewAWSEnhancedHealthChecker()` for AWS environments
- Both implement same interface: `RegisterRoutes()`, `Handler()`, `ReadyHandler()`
- Standard endpoints: `/health`, `/health/ready`, `/health/live`, `/health/deep` (AWS only)
- Docker health checks configured in compose files

## AWS Deployment & Production

### AWS Infrastructure

- **ECS Fargate**: Containerized services with auto-scaling
- **DocumentDB**: MongoDB-compatible managed database cluster
- **ECR**: Container registry for service images (`users`, `content`, `quiz`, `nginx`)
- **ALB**: Application Load Balancer with SSL termination
- **Secrets Manager**: Centralized secret management (`wise-owl/production`)
- **VPC**: Private networking with public/private subnet separation

### Deployment Approach

**Manual Learning-Focused Deployment:**

- Follow `AWS_MANUAL_DEPLOYMENT_GUIDE.md` for step-by-step AWS setup
- Use `AWS_TROUBLESHOOTING_GUIDE.md` for debugging issues
- All commands explained with what/why/how context for learning

### AWS Environment Detection

- Config automatically detects AWS via `AWS_EXECUTION_ENV=AWS_ECS_FARGATE`
- Uses `lib/config.IsAWSEnvironment()` for environment-specific logic
- Secrets loaded from AWS Secrets Manager in production
- Local development uses `.env.local`, AWS uses Secrets Manager

### Environment Variables Priority

1. **AWS**: Secrets Manager → Parameter Store → Environment variables
2. **Local**: `.env.local` → Environment variables → Defaults
3. **Detection**: `ECS_CONTAINER_METADATA_URI_V4` presence indicates AWS

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

When adding new services to the microservices architecture:

1. Create new service directory under `services/<service-name>/`
2. Follow the established structure pattern (see existing services as reference)
3. Update `go.work` to include new service: `use ./services/<service-name>`
4. Add service to `docker-compose.dev.yml` and `docker-compose.prod.yml`
5. Add Nginx routing rules in `nginx/default.conf` for `/api/v1/<service>/`
6. Define protobuf contracts if inter-service communication needed

### Testing & Debugging

- No formal test suite currently - services validated via health endpoints
- Use `./scripts/test-dev.sh` for quick service health verification
- Services expose `/health`, `/health/ready`, and `/health/live` endpoints
- gRPC services can be tested with grpcurl or similar tools
- Individual services accessible in dev: `users:8081`, `content:8082`, `quiz:8083`

## Key Files to Reference

- `lib/config/config.go` - Centralized configuration pattern with AWS support
- `lib/config/aws.go` - AWS environment detection and utilities
- `lib/database/documentdb.go` - AWS DocumentDB connection support
- `lib/health/aws.go` - Enhanced health checks for AWS deployment
- `lib/auth/middleware.go` - JWT validation implementation
- `services/content/cmd/main.go` - Example dual-server implementation
- `services/users/cmd/main_aws.go` - AWS-optimized service implementation example
- `nginx/default.conf` - API Gateway routing configuration
- `proto/content/content.proto` - Example gRPC service definition
- `docker-compose.dev.yml` - Development environment with hot reload
- `.env.local.example` - Local development environment template
- `.env.aws.example` - AWS production environment template
- `.env.ecs.example` - ECS task definition environment variables

### AWS Learning Documentation

- `AWS_MANUAL_DEPLOYMENT_GUIDE.md` - Complete step-by-step AWS deployment
- `AWS_LEARNING_WORKFLOW.md` - Structured 8-day learning approach
- `AWS_COMMAND_REFERENCE.md` - Detailed explanation of every AWS command
- `AWS_TROUBLESHOOTING_GUIDE.md` - Common issues and debugging steps
- `AWS_MANUAL_SETUP_GUIDE.md` - Manual infrastructure setup (no automation)
- `AWS_CODE_UPDATES.md` - AWS-specific code examples and patterns
- `AWS_QUICK_START.md` - Quick checklist for deployment validation
