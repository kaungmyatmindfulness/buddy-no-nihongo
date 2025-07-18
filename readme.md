# wise-owl-golang

[](https://example.com)
[](https://go.dev/)
[](https://example.com)

`wise-owl-golang` is the backend system for a Japanese language learning mobile application. It is specifically designed as a study companion for students using the "Minna no Nihongo" textbook series. The system provides a set of microservices to handle curriculum content, user progress, and learning features for vocabulary and grammar retention.

---

## Table of Contents

1. [Core Features](https://www.google.com/search?q=%23core-features)
2. [Architecture & System Design](https://www.google.com/search?q=%23architecture--system-design)
   - [Architectural Pattern](https://www.google.com/search?q=%23architectural-pattern)
   - [Component Diagram](https://www.google.com/search?q=%23component-diagram)
   - [Service Breakdown](https://www.google.com/search?q=%23service-breakdown)
   - [Database Design](https://www.google.com/search?q=%23database-design)
   - [Service-to-Service Communication](https://www.google.com/search?q=%23service-to-service-communication)
   - [Configuration Strategy](https://www.google.com/search?q=%23configuration-strategy)
3. [Technology Stack](https://www.google.com/search?q=%23technology-stack)
4. [Project Structure](https://www.google.com/search?q=%23project-structure)
5. [Local Development Setup](https://www.google.com/search?q=%23local-development-setup)
   - [Prerequisites](https://www.google.com/search?q=%23prerequisites)
   - [First-Time Setup](https://www.google.com/search?q=%23first-time-setup)
   - [Development Workflows](https://www.google.com/search?q=%23development-workflows)
6. [API Documentation](https://www.google.com/search?q=%23api-documentation)

---

## Core Features

- **Curriculum-Based Content:** Learning content is structured to mirror the chapters of the "Minna no Nihongo" textbooks.
- **Progression System:** A chapter's grammar is unlocked only after its vocabulary is learned. A manual "Mark as Complete" option is available for users to control their own progression.
- **Multi-Mode Quizzing:** Quiz sessions dynamically generate different question types (Flashcards, Meaning Quiz, Word Quiz) to test knowledge thoroughly.
- **Filtered Review Sessions:** Users can start highly-focused study sessions by filtering items based on specific chapters, difficulty ratings, or both.
- **Real-Time Progress Saving:** Each answer in a review session is saved immediately, ensuring no progress is lost.

## Architecture & System design

This project is built using a **Monorepo Microservices Architecture**, managed with Go's native tooling.

### Architectural Pattern

- **Monorepo with Go Workspaces:** A single Git repository holds all services and shared libraries. Go Workspaces (`go.work`) are used for a seamless local development experience across multiple Go modules.
- **API Gateway:** An Nginx reverse proxy is the single entry point for all mobile client traffic, routing requests to the appropriate backend service.
- **Containerization:** Each service is containerized using its own self-contained `Dockerfile`. The entire stack is orchestrated locally with Docker Compose.

### Component Diagram

```text
+-------------+      HTTPS       +-------------------------+
| Mobile App  |----------------->|   Nginx Reverse Proxy   |
+-------------+   (Port 80)      |    (API Gateway)        |
                                 +-----+-------------+-----+
                                       |             |
                                       | HTTP        | HTTP
               Docker's Virtual Network|             |
                                       |             |
           +-----------------------------v-------------v------------------------------------+
           |                                                                                 |
           |  +-----------------+                     +-----------------+     +------------+ |
           |  |  users-service  |                     | content-service |---->| content_db | |
           |  +-------+---------+                     +-----------------+     | (MongoDB)  | |
           |          |                                        |              +------------+ |
           |  +-------v---------+     gRPC           +-----------------+     +-------------+ |
           |  |     users_db    |     50052          |   quiz-service  |---->|   quiz_db   | |
           |  |   (MongoDB)     |<-------------------|   (standalone)  |     | (MongoDB)   | |
           |  +-----------------+                    +-----------------+     +-------------+ |
           |                                                                                 |
           +---------------------------------------------------------------------------------+
```

### Service Breakdown

- **Users Service:** Manages user identity, profiles, and chapter completion/unlock status. Provides REST API endpoints for user management and authentication via Auth0.
- **Content Service:** A dual-purpose service that provides both REST API endpoints for mobile clients and gRPC endpoints for internal service communication. Delivers static learning content from the "Minna no Nihongo" textbooks with automatic data seeding.
- **Quiz Service:** Handles quiz generation and management for testing user knowledge. Currently runs as a standalone service and communicates with the content service via gRPC to fetch vocabulary data.

### Database Design

We follow the **Database per Service** pattern. A single MongoDB container runs multiple, logically separate databases (`users_db`, `content_db`, `quiz_db`). Each service has credentials to access only its own database, ensuring loose coupling. Database connection is handled by the shared `lib/database` package.

### Service-to-Service Communication

All internal, synchronous communication between services is handled via **gRPC**. This provides a high-performance, strongly-typed contract for internal APIs. For example, the `quiz-service` calls the `content-service` to fetch vocabulary batches for quiz generation.

### Configuration Strategy

The application follows the **Twelve-Factor App** methodology for configuration. All configuration (ports, database credentials) is injected via **environment variables**. We use separate `.env` files for different development workflows (`.env.docker`, `.env.local`) to avoid conflicts.

## Technology Stack

| Category                     | Technology                                |
| ---------------------------- | ----------------------------------------- |
| **Backend**                  | Go (Golang) 1.24+, Gin                    |
| **Database**                 | MongoDB                                   |
| **API & Communication**      | REST, gRPC, Protocol Buffers (Protobuf)   |
| **Build & Development**      | Go Workspaces, Docker & Docker Compose    |
| **Infrastructure & Gateway** | Nginx                                     |
| **Authentication**           | Auth0 (via JWTs)                          |
| **Configuration**            | Viper (for reading environment variables) |

## Project Structure

```
wise-owl-golang/
├── .envrc               # direnv configuration for environment variables
├── .env.example         # A template for environment variables
├── .gitignore
├── go.work              # Defines the Go workspace for local development
├── go.work.sum          # Go workspace dependencies checksum
├── readme.md
├── lib/                 # Shared Go libraries
│   ├── go.mod
│   ├── auth/            # Auth0 JWT validation middleware
│   ├── config/          # Configuration management with Viper
│   └── database/        # MongoDB connection singleton
├── gen/                 # Generated protobuf Go code
│   ├── go.mod
│   └── proto/content/   # Generated gRPC stubs for content service
├── proto/               # Protobuf definitions for gRPC
│   └── content/         # Content service protobuf schema
├── services/            # Contains all microservices
│   ├── users/
│   │   ├── Dockerfile   # Self-contained Dockerfile for this service
│   │   ├── cmd/main.go  # Entry point with HTTP server
│   │   ├── go.mod
│   │   └── internal/    # Handlers and models
│   ├── content/
│   │   ├── Dockerfile   # Self-contained Dockerfile for this service
│   │   ├── cmd/main.go  # Entry point with dual HTTP/gRPC servers
│   │   ├── go.mod
│   │   ├── internal/    # Handlers, gRPC server, and models
│   │   └── seed/        # JSON seed data for vocabulary
│   └── quiz/
│       ├── cmd/main.go  # Entry point with HTTP server and gRPC client
│       ├── go.mod
│       └── internal/    # Handlers and models
├── nginx/
│   └── default.conf     # Nginx reverse proxy configuration
├── docker-compose.yml       # Main orchestration file for the full stack
├── docker-compose.dev.yml   # Orchestration file for MongoDB only
└── vendor/              # Vendored dependencies for containerized builds
```

## Local Development Setup

Follow these steps to get the entire application running on your local machine.

### Prerequisites

- **Go 1.24+**
- **Docker & Docker Compose**

### First-Time Setup

1. **Clone the repository:**

   ```bash
   git clone <repository_url>
   cd wise-owl-golang
   ```

2. **Quick Start (Recommended):**

   ```bash
   # Set up environment variables
   ./dev.sh setup

   # Edit .env.local with your values (Auth0 domain, audience, MongoDB credentials)
   # At minimum, set:
   # - MONGO_INITDB_ROOT_USERNAME=admin
   # - MONGO_INITDB_ROOT_PASSWORD=password
   # - AUTH0_DOMAIN=your-domain.auth0.com
   # - AUTH0_AUDIENCE=your-api-identifier

   # Start all services with hot reload
   ./dev.sh start
   ```

   Your services will be running at:

   - API Gateway: <http://localhost>
   - Users Service: <http://localhost:8081>
   - Content Service: <http://localhost:8082>
   - Quiz Service: <http://localhost:8083>

### Development Workflows

You have **three primary ways** to run the application, each suited for different development needs:

#### **Workflow A: Full Development Environment (Docker with Hot Reload) - RECOMMENDED**

**Best for:** Active development with automatic code reloading and consistent environment.

1. **Initial Setup:**

   ```bash
   # Copy environment template and configure
   ./dev.sh setup
   # Edit .env.local with your specific values (Auth0, MongoDB credentials, etc.)
   ```

2. **Start All Services with Hot Reload:**

   ```bash
   # Start everything with hot reloading
   ./dev.sh start
   ```

   This starts:

   - Nginx reverse proxy (port 80)
   - Users service with hot reload (port 8081)
   - Content service with hot reload (port 8082)
   - Quiz service with hot reload (port 8083)
   - MongoDB database (port 27017)

3. **Development Commands:**

   ```bash
   # View logs for all services
   ./dev.sh logs

   # View logs for specific service
   ./dev.sh logs content-service

   # Restart all services
   ./dev.sh restart

   # Stop all services
   ./dev.sh stop

   # Rebuild containers (after Dockerfile changes)
   ./dev.sh build

   # Clean up everything (containers, volumes, images)
   ./dev.sh clean
   ```

   **Code changes** in any service will automatically trigger rebuilds and restarts thanks to Air hot reloading.

#### **Workflow B: Hybrid Development (Local + Docker)**

**Best for:** When you need to debug specific services locally while keeping others containerized.

1. **Start Infrastructure Only:**

   ```bash
   docker-compose -f docker-compose.dev.yml up mongodb -d
   ```

2. **Run Specific Services Locally:**

   ```bash
   # In separate terminals, run services you want to debug locally:
   cd services/content && go run cmd/main.go
   cd services/users && go run cmd/main.go
   cd services/quiz && go run cmd/main.go
   ```

#### **Workflow C: Production Simulation (Full Docker)**

**Best for:** Testing production-like deployment and final integration testing.

1. **Sync & Vendor Dependencies:**

   ```bash
   go work sync
   go work vendor
   ```

2. **Build & Run Production Stack:**

   ```bash
   docker-compose up --build -d
   ```

### Access Points

When running the full development environment:

- **API Gateway (Nginx):** <http://localhost>
- **Direct Service Access:**
  - Users Service: <http://localhost:8081>
  - Content Service: <http://localhost:8082>
  - Quiz Service: <http://localhost:8083>
- **Database:** `mongodb://localhost:27017`

### Hot Reloading

The development setup uses [Air](https://github.com/air-verse/air) for automatic Go code reloading:

- **File Watching:** Monitors `.go` files in all service directories
- **Fast Rebuilds:** Only rebuilds the specific service that changed
- **Automatic Restart:** Services restart immediately after successful compilation
- **Build Logs:** Compilation errors are shown in real-time via `./dev.sh logs`

## API Documentation

The system exposes a versioned RESTful API for the mobile client.

- **Base URL:** `http://localhost/api/v1` (when running behind Nginx)
- **Authentication:** All endpoints expect a `Bearer <token>` in the `Authorization` header.
- **Detailed Endpoints:** A complete list of all endpoints and their schemas can be found in a separate `API.md` document or a shared Postman collection.
