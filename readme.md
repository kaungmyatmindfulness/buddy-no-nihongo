# buddy-no-nihongo

`buddy-no-nihongo` is the backend system for a Japanese language learning mobile application designed to be a study companion for the "Minna no Nihongo" textbook series. It provides a set of microservices to handle content delivery, user progress, and a Spaced Repetition System (SRS) for long-term vocabulary retention.

---

## Table of Contents

1. [Core Features](https://www.google.com/search?q=%23core-features)
2. [Architecture &amp; System Design](https://www.google.com/search?q=%23architecture--system-design)
3. [Technology Stack](https://www.google.com/search?q=%23technology-stack)
4. [Project Structure](https://www.google.com/search?q=%23project-structure)
5. [Local Development Setup](https://www.google.com/search?q=%23local-development-setup)
6. [API Documentation](https://www.google.com/search?q=%23api-documentation)

---

## Core Features

- **Curriculum-Based Content:** All learning content (vocabulary, grammar) is structured to mirror the chapters of the "Minna no Nihongo" textbooks.
- **Progression System:** Users unlock a chapter's grammar content only after completing the vocabulary, with a manual override option for experienced users.
- **Spaced Repetition System (SRS):** A powerful review engine to ensure long-term retention of learned items.
- **Flexible Quizzing:** SRS sessions include multiple quiz modes (Flashcards, Meaning Quiz, Word Quiz) to test knowledge from different angles.
- **Filtered Review Sessions:** Users can start study sessions based on specific chapters, difficulty ratings, or a combination of filters.
- **User Profile & Progress Tracking:** Manages user data, authentication, and detailed learning statistics.

## Architecture & System Design

This project is built using a **Monorepo Microservices Architecture** . All services live within a single Git repository for simplified dependency management and refactoring, but are designed to be deployed and scaled independently.

### Architectural Pattern

- **Monorepo:** A single Git repository holds the code for all services and shared libraries.
- **Microservices:** The application is broken down into small, independent services, each with a single responsibility.
- **API Gateway:** An Nginx reverse proxy acts as the single entry point for all mobile client traffic, routing requests to the appropriate backend service.
- **Development Environment:** Go Workspaces are used for a simple, native Go development experience. Docker & Docker Compose are used for containerization and local orchestration.

### Component Diagram

```
+-------------+         HTTPS          +-------------------------+
| Mobile App  |----------------------->|   Nginx Reverse Proxy   |
+-------------+      (api.buddy...)    |    (API Gateway)        |
                                       +-----+-------------+-----+
                                             |             |
                                             | HTTP        | HTTP
                     Docker's Virtual Network|             |
                     (Service Discovery)     |             |
           +---------------------------------v-------------v----------------------------------+
           |                                                                                   |
           |  +-----------------+      gRPC Call      +-----------------+      +-------------+ |
           |  |   srs-service   |-------------------->|  users-service  |----->|  users_db   | |
           |  +-------+---------+      (GetUsers)     +-------+---------+      +-------------+ |
           |          |                                       |                                |
           |          |                                       |                                |
           |  +-------v---------+                     +-------v---------+                      |
           |  |     srs_db      |                     |      (Gin)      |                      |
           |  +-----------------+                     +-----------------+                      |
           |                                                                                   |
           |  +-----------------+                     +-----------------+                      |
           |  | content-service |-------------------->|  content_db     |                      |
           |  +-----------------+                     +-----------------+                      |
           |                                                                                   |
           +-----------------------------------------------------------------------------------+
```

### Service Breakdown

- **Users Service:** Manages user identity, profiles, authentication concerns, and high-level progress tracking (e.g., chapter completion status). It is the source of truth for user data.
- **Content Service:** A read-only service that delivers the static learning content from the "Minna no Nihongo" textbooks, including chapter data, vocabulary lists, and grammar points.
- **SRS Service:** The core learning engine. It manages the user's personal review deck, schedules items based on the SRS algorithm, and generates filtered quiz sessions.

### Database Design

We follow the **Database per Service** pattern to ensure loose coupling and independent scalability.

- **Approach:** A single PostgreSQL server instance is run in Docker.
- **Implementation:** Inside the instance, we create **multiple, logically separate databases** (`users_db`, `srs_db`, `content_db`). Each service has credentials to access _only_ its own database.
- **Schema Management:** Database migrations are handled using a dedicated tool like `golang-migrate/migrate`. Schema changes are written in `.sql` files and version-controlled alongside the application code.

### Service-to-Service Communication

- **Pattern:** For synchronous internal communication, we use **gRPC** .
- **Example:** When the `srs-service` needs user details to enrich its API response, it makes a gRPC call to the `users-service`'s `GetUsers` endpoint rather than accessing the `users_db` directly. This maintains strict service boundaries.

## Technology Stack

| **Category**                 | **Technology**                  | **Purpose**                                                                   |
| ---------------------------- | ------------------------------- | ----------------------------------------------------------------------------- |
| **Backend**                  | **Go (Golang)**                 | Primary language for building high-performance services.                      |
|                              | **Gin**                         | HTTP web framework for building external REST APIs.                           |
|                              | **GORM**                        | ORM for interacting with the PostgreSQL database.                             |
| **Database**                 | **PostgreSQL**                  | Primary relational database for all services.                                 |
|                              | **Redis**                       | In-memory data store for caching sessions or hot data.                        |
| **API & Communication**      | **REST**                        | Architectural style for the public-facing mobile API.                         |
|                              | **gRPC**                        | RPC framework for high-performance internal service-to-service communication. |
|                              | **Protocol Buffers (Protobuf)** | Schema definition language for gRPC.                                          |
| **Build & Development**      | **Go Workspaces**               | Native Go tooling for managing the monorepo locally.                          |
|                              | **Docker & Docker Compose**     | Containerization and local orchestration of all services.                     |
| **Infrastructure & Gateway** | **Nginx**                       | High-performance reverse proxy and API Gateway.                               |
|                              | **Auth0**                       | Identity-as-a-Service for handling user authentication (JWTs).                |
| **Configuration**            | **Viper**                       | Configuration management from files, env vars, etc.                           |

## Project Structure

The project is a Go Workspaces monorepo. Each service and library is its own Go module.

```
buddy-no-nihongo/
├── go.work             # Defines the Go workspace for local development
├── lib/                # Shared Go libraries (e.g., config loading)
│   └── go.mod
├── services/           # Contains all microservices
│   ├── users/          # Users Service
│   │   ├── Dockerfile
│   │   ├── cmd/main.go
│   │   └── go.mod
│   ├── srs/            # SRS Service
│   │   ├── Dockerfile
│   │   └── go.mod
│   └── content/        # Content Service
│       ├── Dockerfile
│       └── go.mod
├── proto/              # Protobuf definitions for gRPC
│   └── user/v1/user.proto
├── gen/                # Generated Go code from .proto files
├── docker-compose.yml  # Local orchestration file
└── nginx/              # Nginx configuration
    └── nginx.conf
```

## Local Development Setup

Follow these steps to get the entire application running on your local machine.

### Prerequisites

- **Go 1.18+:** Required for Go Workspaces support.
- **Docker & Docker Compose:** Required to run the containerized services.

### Configuration

1. **Clone the repository:**
   **Bash**

   ```
   git clone <repository_url>
   cd buddy-no-nihongo
   ```

2. **Configuration Files:** Each service in `services/*` looks for a `configs/config.yml` file. You may need to create these from an example template if they contain secrets.

### Running the Application

The entire stack (all Go services, PostgreSQL, Nginx) is managed by Docker Compose.

1. From the **root directory** of the project, run the following command:

   **Bash**

   ```
   # The --build flag tells Docker Compose to build the images from their Dockerfiles.
   # The -d flag runs the containers in detached mode (in the background).
   docker-compose up --build -d
   ```

2. **To check the status** of your running containers:

   **Bash**

   ```
   docker-compose ps
   ```

3. **To view logs** from all services:

   **Bash**

   ```
   docker-compose logs -f
   ```

4. **To stop the application:**

   **Bash**

   ```
   docker-compose down
   ```

### Testing the Setup

Once the application is running, you can hit the Nginx gateway at `http://localhost`. You can test a service's health check endpoint, for example: `http://localhost/api/v1/users/health` (assuming you add a health check endpoint to the `users` service).

## API Documentation

The system exposes a versioned RESTful API for the mobile client.

- **Base URL:** `http://localhost/api/v1`
- **Authentication:** All endpoints expect a `Bearer <token>` in the `Authorization` header.
- **Detailed Endpoints:** Please refer to the Postman collection or Swagger/OpenAPI documentation for a full list of available endpoints and their request/response schemas.
