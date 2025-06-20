# wise-owl

[](https://example.com)
[](https://go.dev/)
[](https://example.com)

`wise-owl` is the backend system for a Japanese language learning mobile application. It is specifically designed as a study companion for students using the "Minna no Nihongo" textbook series. The system provides a set of microservices to handle curriculum content, user progress, and a powerful Spaced Repetition System (SRS) for long-term vocabulary and grammar retention.

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
- **Spaced Repetition System (SRS):** An intelligent review engine schedules items to ensure long-term retention.
- **Multi-Mode Quizzing:** SRS sessions dynamically generate different question types (Flashcards, Meaning Quiz, Word Quiz) to test knowledge thoroughly.
- **Filtered Review Sessions:** Users can start highly-focused study sessions by filtering items based on specific chapters, difficulty ratings, or both.
- **Real-Time Progress Saving:** Each answer in a review session is saved immediately, ensuring no progress is lost.

## Architecture & System design

This project is built using a **Monorepo Microservices Architecture**, managed with Go's native tooling.

### Architectural Pattern

- **Monorepo with Go Workspaces:** A single Git repository holds all services and shared libraries. Go Workspaces (`go.work`) are used for a seamless local development experience across multiple Go modules.
- **API Gateway:** An Nginx reverse proxy is the single entry point for all mobile client traffic, routing requests to the appropriate backend service.
- **Containerization:** Each service is containerized using its own self-contained `Dockerfile`. The entire stack is orchestrated locally with Docker Compose.

### Component Diagram

```
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
           |  +-----------------+    Internal gRPC    +-----------------+     +------------+ |
           |  |   srs-service   |-------------------->|  users-service  |---->|  users_db  | |
           |  +-------+---------+   (GetUsers Call)   +-----------------+     +------------+ |
           |          |                                                                      |
           |  +-------v---------+                     +-----------------+     +-------------+  |
           |  |     srs_db      |                     | content-service |---->|  content_db |  |
           |  +-----------------+                     +-----------------+     +-------------+  |
           |                                                                                 |
           +---------------------------------------------------------------------------------+
```

### Service Breakdown

- **Users Service:** Manages user identity, profiles, and chapter completion/unlock status. It acts as the gRPC server for providing user data internally.
- **Content Service:** A read-only service that delivers the static learning content from the "Minna no Nihongo" textbooks.
- **SRS Service:** The core learning engine that manages the user's review deck, schedules items via SRS algorithms, and generates quiz sessions. It acts as a gRPC client to fetch user data when needed.

### Database Design

We follow the **Database per Service** pattern. A single PostgreSQL container runs multiple, logically separate databases (`users_db`, `srs_db`, `content_db`). Each service has credentials to access only its own database, ensuring loose coupling. Database creation is handled automatically on first launch by an `init.sql` script.

### Service-to-Service Communication

All internal, synchronous communication between services is handled via **gRPC**. This provides a high-performance, strongly-typed contract for internal APIs. For example, `srs-service` calls the `users-service` to fetch user details.

### Configuration Strategy

The application follows the **Twelve-Factor App** methodology for configuration. All configuration (ports, database credentials) is injected via **environment variables**. We use separate `.env` files for different development workflows (`.env.docker`, `.env.local`) to avoid conflicts.

## Technology Stack

| Category                     | Technology                                |
| ---------------------------- | ----------------------------------------- |
| **Backend**                  | Go (Golang) 1.18+, Gin, GORM              |
| **Database**                 | PostgreSQL                                |
| **API & Communication**      | REST, gRPC, Protocol Buffers (Protobuf)   |
| **Build & Development**      | Go Workspaces, Docker & Docker Compose    |
| **Infrastructure & Gateway** | Nginx                                     |
| **Authentication**           | Auth0 (via JWTs)                          |
| **Configuration**            | Viper (for reading environment variables) |

## Project Structure

```
wise-owl/
├── .env.docker         # Environment variables for the full Docker stack
├── .env.local          # Environment variables for running Go code on the host
├── .env.example        # A template for environment variables
├── .gitignore
├── go.work             # Defines the Go workspace for local development
├── lib/                # Shared Go libraries
│   └── go.mod
├── services/           # Contains all microservices
│   ├── users/
│   │   ├── Dockerfile  # Self-contained Dockerfile for this service
│   │   ├── cmd/main.go
│   │   └── go.mod
│   ├── srs/
│   │   └── ...
│   └── content/
│       └── ...
├── proto/              # Protobuf definitions for gRPC
├── docker-compose.yml  # Main orchestration file for the full stack
└── docker-compose.dev.yml # Orchestration file for backing services only
```

## Local Development Setup

Follow these steps to get the entire application running on your local machine.

### Prerequisites

- **Go 1.18+**
- **Docker & Docker Compose**

### First-Time Setup

1. **Clone the repository:**

   ```bash
   git clone <repository_url>
   cd wise-owl
   ```

2. **Create Environment Files:**
   Copy the example template to create your two local development environment files.

   ```bash
   cp .env.example .env.docker
   cp .env.example .env.local
   ```

3. **Configure for Host Development:**
   Open the `.env.local` file and change the `DB_HOST` to point to `localhost`.

   ```ini
   # In .env.local
   DB_HOST=localhost
   ```

   The `.env.docker` file should keep `DB_HOST=db`.

### Development Workflows

You have two primary ways to run the application, each suited for different tasks.

#### **Workflow A: The Full Simulation (Docker-Based)**

Use this to test the entire system in a production-like environment.

1. **Sync & Vendor Dependencies:** From the project root, run these two commands to prepare for the build.

   ```bash
   go work sync
   go work vendor
   ```

2. **Build & Run:** Use Docker Compose to build and start all containers.

   ```bash
   docker-compose up --build -d
   ```

#### **Workflow B: The Fast / Hybrid Workflow (Host-Based)**

Use this for active, day-to-day coding for a much faster feedback loop.

1. **Start Backing Services:** In one terminal, start just the database using the dev-specific compose file.

   ```bash
   docker-compose -f docker-compose.dev.yml up
   ```

2. **Run Go Services Directly:** In separate terminals, run each Go service directly on your host. Your `.env.local` file must be sourced (tools like `direnv` are highly recommended for this).

   ```bash
   # In Terminal 2 (assuming .env.local is sourced)
   go run ./services/users/cmd/main.go

   # In Terminal 3
   go run ./services/srs/cmd/main.go
   ```

## API Documentation

The system exposes a versioned RESTful API for the mobile client.

- **Base URL:** `http://localhost/api/v1` (when running behind Nginx)
- **Authentication:** All endpoints expect a `Bearer <token>` in the `Authorization` header.
- **Detailed Endpoints:** A complete list of all endpoints and their schemas can be found in a separate `API.md` document or a shared Postman collection.
