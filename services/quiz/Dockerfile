# =================================================================
# Stage 1: The Builder Stage
# =================================================================
FROM golang:1.22.5-alpine AS builder

# Set the working directory inside the container.
WORKDIR /app

# Copy dependency-related files from the project root.
COPY go.work go.work.sum ./

# Copy all source code from the project root.
COPY lib ./lib
COPY services ./services
COPY gen ./gen

# Try to copy vendor directory, but continue if it doesn't exist
COPY vendor ./vendor

# If vendor doesn't exist or is incomplete, download dependencies
RUN if [ ! -f "vendor/modules.txt" ]; then \
        echo "Vendor directory incomplete, downloading dependencies..." && \
        go mod download && \
        go work vendor; \
    fi

# Build the specific service binary.
# The `-ldflags "-w -s"` strips debug information, making the binary smaller.
# CGO_ENABLED=0 and GOOS=linux are essential for creating a static, portable binary.
#
# !!! THIS IS THE ONLY LINE TO CHANGE FOR EACH SERVICE !!!
RUN CGO_ENABLED=0 GOOS=linux go build -mod=vendor -ldflags="-w -s" -o /app/main ./services/quiz/cmd


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
