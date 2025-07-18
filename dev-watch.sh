#!/bin/bash

# Wise Owl Development with Hot Reload
# This script starts all services with Docker Compose watch mode for automatic reloading

echo "🦉 Starting Wise Owl Development Environment with Hot Reload..."

# Check if Docker Compose supports watch (requires Docker Compose 2.22+)
if ! docker compose version --format json | jq -r '.version' | grep -E '^2\.(2[2-9]|[3-9][0-9])' >/dev/null 2>&1; then
    echo "⚠️  Warning: Docker Compose watch requires version 2.22 or higher"
    echo "   Falling back to regular development mode..."
    docker-compose -f docker-compose.dev.yml up --build
    exit 0
fi

# Create necessary directories
mkdir -p tmp

# Start services with watch mode for automatic rebuilds on file changes
echo "🔄 Starting services with file watching enabled..."
echo "   - Changes to service code will trigger automatic rebuilds"
echo "   - Changes to shared lib/ or gen/ will sync automatically"
echo "   - Changes to go.work will trigger full rebuilds"
echo ""

# Use Docker Compose watch mode
docker compose -f docker-compose.dev.yml watch

echo "🦉 Wise Owl Development Environment stopped."
