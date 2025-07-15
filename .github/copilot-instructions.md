# Wise Owl Golang Microservices

This document provides instructions for AI coding agents to effectively contribute to the Wise Owl Golang microservices project.

## Architecture Overview

This project is a microservices-based application built with Go. The architecture consists of several key components:

- **Nginx API Gateway:** All incoming traffic is routed through Nginx, which acts as an API gateway. The configuration can be found in `nginx/default.conf`. It directs requests to the appropriate backend service.

- **Microservices:** The core logic is split into several Go microservices located in the `services/` directory:

  - `services/users`: Manages user authentication and data.
  - `services/content`: Handles educational content like vocabularies.
  - `services/srs`: Implements the Spaced Repetition System (SRS) for learning.
  - `services/quiz`: Manages quizzes for users.

- **Database:** All services share a single MongoDB instance for data storage. Each service manages its own database within this instance.

- **gRPC Communication:** Services communicate with each other via gRPC for efficient, strongly-typed inter-service calls. The protobuf definitions are located in `proto/`, and the generated Go code is in `gen/proto/`. When you modify a `.proto` file, you will need to regenerate the corresponding `.pb.go` and `_grpc.pb.go` files.

## Development Workflow

### Running the Application

- **Production Environment:** To run the application in a production-like environment, use the main `docker-compose.yml` file:

  ```bash
  docker-compose up --build
  ```

- **Local Development:** For local development, a separate Docker Compose file is provided to run only the essential dependencies, like the database. Use `docker-compose.dev.yml`:
  ```bash
  docker-compose -f docker-compose.dev.yml up
  ```
  This allows you to run individual services directly on your local machine for easier debugging.

### Project Structure

- `services/`: Each microservice lives in its own subdirectory here. Each service is a self-contained Go project with its own `go.mod` file.
- `proto/`: Contains all the `.proto` files that define the gRPC services and messages.
- `gen/`: Contains the Go code generated from the `.proto` files. Do not edit files in this directory manually.
- `lib/`: A shared library containing common packages used across multiple services, such as database connections (`lib/database`), configuration (`lib/config`), and authentication middleware (`lib/auth`).
- `docker-compose.yml`: Defines the services for a production environment.
- `docker-compose.dev.yml`: Defines the services for local development.

## Coding Conventions

- **Dependency Management:** Go modules are used for dependency management. Each service in `services/` has its own `go.mod` and `go.sum`. The shared `lib` also has its own module files.
- **Configuration:** Services are configured using environment variables, which are loaded via `.env.docker` or `.env.local` files as specified in the Docker Compose files. The `lib/config` package provides a standardized way to access configuration values.
- **Error Handling:** Follow standard Go error handling practices. Errors should be handled gracefully and not ignored.
- **Database Models:** Each service that interacts with the database has a `internal/models` directory containing the data structures that map to MongoDB documents.
