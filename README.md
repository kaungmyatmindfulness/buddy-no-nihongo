# Wise Owl - Japanese Vocabulary Learning Platform

A modern microservices-based Japanese vocabulary learning platform built with Go, designed to help learners manage and practice Japanese vocabulary through interactive quizzes and spaced repetition.

## 🎯 Overview

Wise Owl is a scalable microservices application that provides vocabulary management, user authentication, and quiz functionalities for Japanese language learners. The platform supports comprehensive vocabulary data including kana, kanji, furigana, romaji, English, and Burmese translations.

## ✨ Key Features

- **Vocabulary Management**: 22,000+ Japanese vocabulary entries with multi-language support
- **User Authentication**: Auth0-powered JWT authentication
- **Interactive Quizzes**: Track incorrect words and enable spaced repetition learning
- **Lesson Organization**: Structured vocabulary lessons with word classifications
- **Microservices Architecture**: Independent, scalable services with clean APIs
- **Real-time Communication**: gRPC for efficient inter-service communication
- **Health Monitoring**: Built-in health checks and service monitoring

## 🏗️ Architecture

### Service Overview

| Service             | Dev Port | Prod Port | Purpose                                   | Database     |
| ------------------- | -------- | --------- | ----------------------------------------- | ------------ |
| **Users Service**   | 8081     | Internal  | User management, profiles, authentication | `users_db`   |
| **Content Service** | 8082     | Internal  | Vocabulary data, lessons management       | `content_db` |
| **Quiz Service**    | 8083     | Internal  | Quiz logic, incorrect words tracking      | `quiz_db`    |
| **API Gateway**     | 8080     | 80        | Nginx reverse proxy, routing              | -            |
| **MongoDB**         | 27017    | Internal  | Database cluster (local dev only)         | -            |

### Communication Patterns

- **External API**: HTTP REST via Nginx gateway (`/api/v1/{service}/`)
- **Internal Communication**: gRPC on dedicated ports (50051, 50052, 50053)
- **Database**: MongoDB (local dev) or AWS DocumentDB (production) with dedicated databases per service
- **Authentication**: JWT tokens validated via Auth0 (optional in development)

### Directory Structure

```text
wise-owl-golang/
├── services/                    # Independent microservices
│   ├── users/                   # User management service
│   ├── content/                 # Vocabulary content service
│   └── quiz/                    # Quiz and learning service
├── lib/                         # Shared libraries
│   ├── auth/                    # JWT authentication middleware
│   ├── config/                  # Configuration management with AWS support
│   ├── database/                # MongoDB/DocumentDB connection handling
│   └── health/                  # Health check utilities
├── proto/                       # Protocol Buffer definitions
├── gen/                         # Generated gRPC code
├── nginx/                       # API Gateway configuration
├── DOCUMENTATIONS/              # AWS deployment guides and references
├── deployment/                  # AWS deployment configurations
├── docker-compose.dev.yml       # Development environment
├── docker-compose.prod.yml      # Production environment
├── .env.local.example           # Development environment template
├── .env.aws.example             # AWS environment template
├── .env.ecs.example             # ECS-specific environment template
└── go.work                      # Go workspace configuration
```

## 🛠️ Technology Stack

- **Language**: Go 1.24+
- **Framework**: Gin (HTTP), gRPC (internal communication)
- **Database**: MongoDB (local dev) / AWS DocumentDB (production)
- **Authentication**: Auth0 JWT (optional in development)
- **Gateway**: Nginx reverse proxy
- **Containerization**: Docker & Docker Compose
- **Hot Reload**: Docker Compose watch mode (requires 2.22+)
- **AWS Integration**: ECS Fargate, DocumentDB, Secrets Manager, Parameter Store

## 🚀 Quick Start

### Prerequisites

- Go 1.24.5 or later
- Docker and Docker Compose
- Git

### Development Setup

1. **Clone the repository**

   ```bash
   git clone <repository-url>
   cd wise-owl-golang
   ```

2. **Environment Configuration**

   ```bash
   # Create local environment file from template
   cp .env.local.example .env.local

   # Edit .env.local with your Auth0 credentials (optional for development)
   # AUTH0_DOMAIN=your-auth0-domain.auth0.com
   # AUTH0_AUDIENCE=your-auth0-audience
   ```

3. **Start Development Environment**

   ```bash
   # Start all services
   ./wise-owl dev start

   # Or start with hot reload (requires Docker Compose 2.22+)
   ./wise-owl dev watch
   ```

4. **Verify Installation**

   ```bash
   # Test all services
   ./wise-owl dev test

   # Access points:
   # - API Gateway: http://localhost:8080
   # - Users Service: http://localhost:8081
   # - Content Service: http://localhost:8082
   # - Quiz Service: http://localhost:8083
   ```

### Production Deployment

The project includes comprehensive AWS deployment capabilities with detailed documentation in the `DOCUMENTATIONS/` directory:

- **AWS Manual Deployment Guide**: `DOCUMENTATIONS/AWS_MANUAL_DEPLOYMENT_GUIDE.md`
- **AWS Infrastructure Setup**: `DOCUMENTATIONS/AWS_INFRASTRUCTURE_SETUP.md`
- **AWS Troubleshooting**: `DOCUMENTATIONS/AWS_TROUBLESHOOTING_GUIDE.md`
- **AWS Learning Workflow**: `DOCUMENTATIONS/AWS_LEARNING_WORKFLOW.md`

**Quick AWS Deployment Overview:**

- **ECS Fargate**: Containerized services with auto-scaling
- **DocumentDB**: MongoDB-compatible managed database
- **ALB**: Application Load Balancer with SSL
- **ECR**: Container registry for service images
- **Secrets Manager**: Centralized secret management

For local production testing:

```bash
# Use production compose file (requires .env.production)
docker-compose -f docker-compose.prod.yml up -d

# Services will be available on port 8080 via Nginx gateway
```

## 📜 Scripts Documentation

### Overview: What, Why, and How

The Wise Owl project uses a structured script system to simplify development workflows. These scripts automate complex Docker Compose operations, environment setup, and health checking.

#### **What**: Script Categories

The project organizes scripts into two main categories:

1. **Development Scripts** (`scripts/development/`): Local development environment management
2. **Utility Scripts** (`scripts/utils/`): Shared functions and common utilities

**Note**: Deployment scripts have been temporarily removed and will be added back later.

#### **Why**: The Need for Script Automation

- **Complexity Management**: Managing 5+ microservices with Docker Compose requires many commands
- **Environment Consistency**: Ensures all developers use the same setup procedures
- **Error Reduction**: Automated health checks and validation prevent common mistakes
- **Onboarding Speed**: New developers can start with a single command

#### **How**: Running the Scripts

### Main Entry Point: `./wise-owl`

The project provides a unified command interface through the main `./wise-owl` script:

```bash
# Check all available commands
./wise-owl --help

# Development commands
./wise-owl dev <command>

# Monitoring commands
./wise-owl monitor <command>
```

### Development Scripts

#### 1. Environment Setup and Management

**Initial Setup** - Creates environment files and validates prerequisites:

```bash
# What: Creates .env.local from .env.example template
# Why: Ensures consistent environment configuration
# How: Copy and customize the example environment
./wise-owl dev setup
```

**Start Development Environment** - Launches all microservices:

```bash
# What: Starts all services (nginx, users, content, quiz, mongodb)
# Why: Single command to launch the entire development stack
# How: Uses docker-compose.dev.yml with development configurations
./wise-owl dev start
```

**Hot Reload Development** - Starts with automatic code reloading:

```bash
# What: Starts services with Docker Compose watch mode
# Why: Automatically rebuilds containers when code changes
# How: Requires Docker Compose 2.22+, falls back to normal mode if unsupported
./wise-owl dev watch
```

#### 2. Service Management

**Stop Services** - Cleanly shuts down all containers:

```bash
# What: Stops all running Docker containers
# Why: Clean shutdown preserves data and prevents port conflicts
# How: Uses docker-compose down command
./wise-owl dev stop
```

**Restart Services** - Stops and starts services:

```bash
# What: Combines stop and start operations
# Why: Quick way to apply configuration changes
# How: Runs stop followed by start
./wise-owl dev restart
```

**View Logs** - Monitor service output:

```bash
# What: Shows logs from all services or specific service
# Why: Essential for debugging and monitoring
# How: Uses docker-compose logs with follow mode

# All services
./wise-owl dev logs

# Specific service
./wise-owl dev logs users-service
```

#### 3. Development Utilities

**Health Check** - Validates all services are responding:

```bash
# What: Tests HTTP endpoints on all microservices
# Why: Quickly verify that all services are healthy
# How: Curl requests to /health endpoints on each service
./wise-owl dev test
```

**Service Status** - Shows current state of containers:

```bash
# What: Displays Docker container status and resource usage
# Why: Quick overview of what's running and resource consumption
# How: Uses docker-compose ps and docker stats
./wise-owl dev status
```

**Build Services** - Rebuild containers from scratch:

```bash
# What: Rebuilds all Docker images without cache
# Why: Apply Dockerfile changes or clear build issues
# How: Uses docker-compose build --no-cache
./wise-owl dev build
```

**Clean Environment** - Complete cleanup:

```bash
# What: Stops containers, removes volumes and images
# Why: Fresh start when development environment has issues
# How: docker-compose down -v --remove-orphans
./wise-owl dev clean
```

### Direct Script Access

If you prefer to run scripts directly instead of using the unified interface:

```bash
# Development scripts
./scripts/development/dev.sh [command]          # Main development manager
./scripts/development/dev-watch.sh              # Hot reload development
./scripts/development/test-dev.sh               # Health check testing

# Utility scripts
./scripts/utils/common.sh                       # Shared functions (sourced by others)
```

### Script Requirements and Prerequisites

#### Development Requirements

- **Docker**: Version 20.10+ with Docker Compose
- **Operating System**: macOS, Linux, or Windows with WSL2
- **Ports**: 8080-8083, 27017, 50051-50053 must be available
- **Disk Space**: Minimum 2GB for Docker images and volumes

#### Deployment Requirements

**Note**: Deployment scripts have been temporarily removed and will be added back later.

For manual deployment:

- **Target Server**: Ubuntu 20.04+ or Debian 11+ recommended
- **Docker & Docker Compose**: Required on target server
- **Network**: Internet connectivity for image downloads
- **Resources**: Minimum 2GB RAM, 10GB disk space

### Environment Files

The scripts work with different environment configurations:

- **`.env.local`**: Development environment (created by `./wise-owl dev setup`)
- **`.env.local.example`**: Template file with all required variables for local development
- **`.env.aws.example`**: Template file for AWS deployment configuration
- **`.env.ecs.example`**: Template file specifically for ECS task definitions

**Note**: The project includes multiple environment templates to support different deployment scenarios.

### Troubleshooting Scripts

**Common Issues and Solutions:**

1. **Port conflicts**:

   ```bash
   # Check what's using ports
   lsof -i :8080
   ./wise-owl dev stop  # Stop services to free ports
   ```

2. **Docker permission issues**:

   ```bash
   # Add user to docker group (requires logout/login)
   sudo usermod -aG docker $USER
   ```

3. **Services not starting**:

   ```bash
   # Check service logs
   ./wise-owl dev logs

   # Rebuild containers
   ./wise-owl dev build
   ```

4. **Database issues**:

   ```bash
   # Clean restart with fresh database
   ./wise-owl dev clean
   ./wise-owl dev start
   ```

### Script Customization

The scripts are designed to be extensible. Key customization points:

- **`scripts/utils/common.sh`**: Shared functions and configuration
- **Environment variables**: Override defaults through `.env.local`
- **Docker Compose**: Modify `docker-compose.dev.yml` for development changes
- **Service ports**: Configure in individual service Docker files

## �🔧 Development Workflows

### Essential Commands

```bash
# Service management
./wise-owl dev start          # Start all services
./wise-owl dev stop           # Stop all services
./wise-owl dev restart        # Restart all services
./wise-owl dev logs [service] # View logs
./wise-owl dev build          # Rebuild containers
./wise-owl dev clean          # Complete cleanup

# Hot reload development
./wise-owl dev watch          # Start with hot reload

# Testing and monitoring
./wise-owl dev test           # Health check all services
./wise-owl dev status         # Show service status

# Monitoring commands (if monitoring stack is configured)
./wise-owl monitor start      # Start monitoring stack
./wise-owl monitor stop       # Stop monitoring stack
./wise-owl monitor status     # Show monitoring status
```

### Working with Services

```bash
# Navigate to project root for go.work commands
cd wise-owl-golang

# Build specific service
go build -C services/users/cmd

# Run tests (from service directory)
cd services/users && go test ./...

# Generate protobuf code
protoc --go_out=gen --go-grpc_out=gen proto/content/*.proto
```

## 📱 API Documentation

### Users Service (`/api/v1/users/`)

| Endpoint      | Method | Description         | Auth Required |
| ------------- | ------ | ------------------- | ------------- |
| `/onboarding` | POST   | Create user profile | ✅            |
| `/me/profile` | GET    | Get user profile    | ✅            |
| `/me/profile` | PATCH  | Update profile      | ✅            |
| `/me`         | DELETE | Delete account      | ✅            |

### Content Service (`/api/v1/content/`)

| Endpoint       | Method | Description        | Auth Required |
| -------------- | ------ | ------------------ | ------------- |
| `/lessons`     | GET    | List all lessons   | ❌            |
| `/lessons/:id` | GET    | Get lesson content | ❌            |

### Quiz Service (`/api/v1/quiz/`)

| Endpoint           | Method | Description           | Auth Required |
| ------------------ | ------ | --------------------- | ------------- |
| `/incorrect-words` | POST   | Record incorrect word | ✅            |
| `/incorrect-words` | GET    | Get incorrect words   | ✅            |
| `/incorrect-words` | DELETE | Clear incorrect words | ✅            |

### Health Endpoints (All Services)

| Endpoint        | Description                   |
| --------------- | ----------------------------- |
| `/health`       | Basic health status           |
| `/health/ready` | Readiness check (includes DB) |
| `/health/live`  | Liveness check for containers |
| `/health/deep`  | Detailed health (AWS only)    |

## ⚙️ Configuration

### Environment Variables

| Variable              | Description                          | Default                     | Required |
| --------------------- | ------------------------------------ | --------------------------- | -------- |
| `SERVER_PORT`         | HTTP server port                     | `8080`                      | ❌       |
| `GRPC_PORT`           | gRPC server port                     | `50051`                     | ❌       |
| `MONGODB_URI`         | MongoDB connection string            | `mongodb://localhost:27017` | ❌       |
| `DB_NAME`             | Database name                        | `{service}_db`              | ❌       |
| `DB_TYPE`             | Database type (mongodb/documentdb)   | `mongodb`                   | ❌       |
| `LOG_LEVEL`           | Application log level                | `info`                      | ❌       |
| `ENVIRONMENT`         | Environment name                     | `development`               | ❌       |
| `AUTH0_DOMAIN`        | Auth0 domain                         | -                           | ❌       |
| `AUTH0_AUDIENCE`      | Auth0 API audience                   | -                           | ❌       |
| `JWT_SECRET`          | JWT secret for local development     | -                           | ❌       |
| `AWS_EXECUTION_ENV`   | AWS environment detection            | -                           | ❌       |
| `CONTENT_SERVICE_URL` | Content service gRPC URL (quiz only) | `content-service:50052`     | ❌       |
| `USERS_SERVICE_URL`   | Users service gRPC URL               | `users-service:50051`       | ❌       |

### Development vs Production

- **Development**: `.env.local` with hot reload and direct service access
- **Production**: `.env.production` with optimized builds and gateway-only access

## 🧪 Testing

### Running Tests

```bash
# Test individual service
cd services/users
go test ./...

# Test all services
for service in users content quiz; do
  echo "Testing $service..."
  cd services/$service && go test ./...
  cd ../..
done

# Integration testing
./test-dev.sh  # Tests service health and connectivity
```

### Health Check Testing

```bash
# Individual service health
curl http://localhost:8081/health

# Gateway health
curl http://localhost/health-check

# Service readiness
curl http://localhost:8081/health/ready
```

## 🏛️ Project Structure & Patterns

### Service Structure (Standard Pattern)

```text
services/{name}/
├── cmd/main.go                 # Entry point with dual HTTP+gRPC servers
├── internal/
│   ├── handlers/               # HTTP REST endpoint handlers
│   ├── grpc/                   # gRPC service implementations
│   ├── models/                 # MongoDB data models
│   └── seeder/                 # Database initialization
├── Dockerfile & Dockerfile.dev # Container configurations
└── go.mod                      # Service dependencies
```

### Key Architectural Decisions

- **Go Workspaces**: Single repository with multiple modules
- **Dual Servers**: Each service runs both HTTP (external) and gRPC (internal) servers
- **Database per Service**: Each service owns its data (microservices pattern)
- **Shared Libraries**: Common functionality in `lib/` (auth, config, database, health)
- **Generated Code**: Protocol buffers generate gRPC client/server code

### Authentication Flow

1. Frontend authenticates with Auth0
2. JWT token passed in `Authorization: Bearer <token>` header
3. `lib/auth.EnsureValidToken()` middleware validates token
4. User ID extracted and available in request context

### Inter-service Communication

- **Content → Quiz**: gRPC `GetVocabularyBatch` for vocabulary details
- **Services → Database**: Direct MongoDB connections with dedicated databases
- **External → Services**: HTTP REST via Nginx gateway routing

## 🔄 Adding New Services

1. **Create Service Structure**

   ```bash
   # Create service directory following existing pattern
   mkdir -p services/notifications/{cmd,internal/{handlers,models,grpc,seeder}}

   # Create go.mod for the service
   cd services/notifications
   go mod init wise-owl/services/notifications
   ```

2. **Update Configuration**

   ```bash
   # Add to go.work
   echo "./services/notifications" >> go.work

   # Add to docker-compose.dev.yml
   # Add to nginx/default.conf for routing
   ```

3. **Implement Business Logic**

   ```bash
   cd services/notifications
   # Create cmd/main.go following existing service patterns
   # Edit internal/handlers/, internal/models/, etc.
   ```

4. **Define gRPC Contracts** (if needed)

   ```bash
   # Create proto/notifications/notifications.proto
   # Generate code: protoc --go_out=gen --go-grpc_out=gen proto/notifications/*.proto
   ```

## 🤝 Contributing

### Development Guidelines

- Follow the established patterns in existing services (see `services/content` as reference)
- Write tests for new functionality
- Update documentation for API changes
- Use conventional commit messages

### Code Style

- Follow Go conventions and `gofmt` formatting
- Use meaningful variable and function names
- Add comments for exported functions and complex logic
- Handle errors appropriately with proper HTTP status codes

### Pull Request Process

1. Create feature branch from `main`
2. Implement changes following project patterns
3. Add/update tests as needed
4. Ensure all services pass health checks
5. Update documentation if needed

## 📄 License

This project is licensed under the MIT License. See LICENSE file for details.

## 🆘 Support & Resources

- **Issues**: Create GitHub issues for bugs or feature requests
- **Development Setup**: Use `./wise-owl dev` commands for consistent environment
- **Service Reference**: Use existing services like `content` as patterns for new services
- **Health Monitoring**: All services provide `/health`, `/health/ready`, `/health/live`, and `/health/deep` (AWS) endpoints

---

**Quick Reference**: Start with `./wise-owl dev setup && ./wise-owl dev start`, access via <http://localhost:8080>, and check service health with `./wise-owl dev test`.
