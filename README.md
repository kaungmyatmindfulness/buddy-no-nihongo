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

| Service             | Port  | Purpose                                   | Database     |
| ------------------- | ----- | ----------------------------------------- | ------------ |
| **Users Service**   | 8081  | User management, profiles, authentication | `users_db`   |
| **Content Service** | 8082  | Vocabulary data, lessons management       | `content_db` |
| **Quiz Service**    | 8083  | Quiz logic, incorrect words tracking      | `quiz_db`    |
| **API Gateway**     | 80    | Nginx reverse proxy, routing              | -            |
| **MongoDB**         | 27017 | Database cluster                          | -            |

### Communication Patterns

- **External API**: HTTP REST via Nginx gateway (`/api/v1/{service}/`)
- **Internal Communication**: gRPC on dedicated ports (50052, 50053, etc.)
- **Database**: MongoDB with dedicated databases per service
- **Authentication**: JWT tokens validated via Auth0

### Directory Structure

```text
wise-owl-golang/
├── services/                    # Independent microservices
│   ├── users/                   # User management service
│   ├── content/                 # Vocabulary content service
│   └── quiz/                    # Quiz and learning service
├── lib/                         # Shared libraries
│   ├── auth/                    # JWT authentication middleware
│   ├── config/                  # Configuration management
│   ├── database/                # MongoDB connection handling
│   └── health/                  # Health check utilities
├── proto/                       # Protocol Buffer definitions
├── gen/                         # Generated gRPC code
├── nginx/                       # API Gateway configuration
├── templates/                   # Service generation templates
├── docker-compose.dev.yml       # Development environment
├── docker-compose.yml           # Production environment
└── go.work                      # Go workspace configuration
```

## 🛠️ Technology Stack

- **Language**: Go 1.24+
- **Framework**: Gin (HTTP), gRPC (internal communication)
- **Database**: MongoDB with Go driver
- **Authentication**: Auth0 JWT
- **Gateway**: Nginx
- **Containerization**: Docker & Docker Compose
- **Hot Reload**: Docker Compose watch mode

## 🚀 Quick Start

### Prerequisites

- Go 1.24 or later
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
   # Create local environment file
   ./dev.sh setup

   # Edit .env.local with your Auth0 credentials
   AUTH0_DOMAIN=your-auth0-domain.auth0.com
   AUTH0_AUDIENCE=your-auth0-audience
   ```

3. **Start Development Environment**

   ```bash
   # Start all services
   ./dev.sh start

   # Or start with hot reload (requires Docker Compose 2.22+)
   ./dev-watch.sh
   ```

4. **Verify Installation**

   ```bash
   # Test all services
   ./test-dev.sh

   # Access points:
   # - API Gateway: http://localhost
   # - Users Service: http://localhost:8081
   # - Content Service: http://localhost:8082
   # - Quiz Service: http://localhost:8083
   ```

### Production Deployment

```bash
# Use production compose file
docker-compose up -d

# Services will be available on port 80 via Nginx gateway
```

## 🔧 Development Workflows

### Essential Commands

```bash
# Service management
./dev.sh start          # Start all services
./dev.sh stop           # Stop all services
./dev.sh restart        # Restart all services
./dev.sh logs [service] # View logs
./dev.sh build          # Rebuild containers
./dev.sh clean          # Complete cleanup

# Hot reload development
./dev-watch.sh          # Start with hot reload

# Service generation
./generate-service.sh notifications  # Create new service
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

## ⚙️ Configuration

### Environment Variables

| Variable         | Description               | Default                     | Required |
| ---------------- | ------------------------- | --------------------------- | -------- |
| `SERVER_PORT`    | HTTP server port          | `8080`                      | ❌       |
| `MONGODB_URI`    | MongoDB connection string | `mongodb://localhost:27017` | ❌       |
| `DB_NAME`        | Database name             | `{service}_db`              | ❌       |
| `AUTH0_DOMAIN`   | Auth0 domain              | -                           | ✅       |
| `AUTH0_AUDIENCE` | Auth0 API audience        | -                           | ✅       |

### Development vs Production

- **Development**: `.env.local` with hot reload and direct service access
- **Production**: `.env.docker` with optimized builds and gateway-only access

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

1. **Generate Service Template**

   ```bash
   ./generate-service.sh notifications
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
   # Edit internal/handlers/, internal/models/, etc.
   ```

4. **Define gRPC Contracts** (if needed)

   ```bash
   # Create proto/notifications/notifications.proto
   # Generate code: protoc --go_out=gen --go-grpc_out=gen proto/notifications/*.proto
   ```

## 🤝 Contributing

### Development Guidelines

- Use the provided service template for consistency
- Follow the established patterns in existing services
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
- **Development Setup**: Use `./dev.sh` commands for consistent environment
- **Service Templates**: Use `./generate-service.sh` for new services
- **Health Monitoring**: All services provide `/health` and `/health/ready` endpoints

---

**Quick Reference**: Start with `./dev.sh setup && ./dev.sh start`, access via <http://localhost>, and check service health with `./test-dev.sh`.
