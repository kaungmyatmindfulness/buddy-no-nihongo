# Stage 1: Build the binary using a builder image
FROM golang:1.24-alpine AS builder

# Set the Current Working Directory inside the container
WORKDIR /app

# Copy the go.mod and go.sum files first to take advantage of Docker caching
COPY go.mod go.sum ./
RUN go mod download

# Copy the rest of the source code
COPY . .

# Build the Go app. CGO_ENABLED=0 is important for a static binary.
RUN CGO_ENABLED=0 GOOS=linux go build -o /app/main ./cmd/main.go

# Stage 2: Create the final, minimal image for production
FROM alpine:latest

WORKDIR /app

# Copy only the compiled binary from the builder stage
COPY --from=builder /app/main .

# Expose the port the service runs on
EXPOSE 8080

# The command to run when the container starts
CMD ["./main"]