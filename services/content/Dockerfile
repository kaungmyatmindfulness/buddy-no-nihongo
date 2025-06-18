# =================================================================
# Stage 1: The Builder Stage
# =================================================================
FROM golang:1.24-alpine AS builder

# Set the working directory inside the container.
WORKDIR /app

# Copy dependency-related files from the project root.
# `go work sync` should be run before the build to ensure these files exist.
COPY go.work go.work.sum ./
COPY vendor ./vendor

# Copy all source code from the project root.
COPY lib ./lib
COPY services ./services

# Build the specific service binary.
# The `-ldflags "-w -s"` strips debug information, making the binary smaller.
# CGO_ENABLED=0 and GOOS=linux are essential for creating a static, portable binary.
#
# !!! THIS IS THE ONLY LINE TO CHANGE FOR EACH SERVICE !!!
RUN CGO_ENABLED=0 GOOS=linux go build -mod=vendor -ldflags="-w -s" -o /app/main ./services/content/cmd


# =================================================================
# Stage 2: The Final Stage
# =================================================================
FROM alpine:latest

WORKDIR /app

# Copy only the compiled binary from the 'builder' stage.
COPY --from=builder /app/main .

# Expose the port the service runs on.
EXPOSE 8080

# The command that will be executed when the container starts.
CMD ["./main"]