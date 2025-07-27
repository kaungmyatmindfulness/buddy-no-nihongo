#!/bin/bash
# Script to generate a new microservice from template

set -e

if [ $# -ne 1 ]; then
    echo "Usage: $0 <service-name>"
    echo "Example: $0 notifications"
    exit 1
fi

SERVICE_NAME="$1"
SERVICE_DIR="services/$SERVICE_NAME"

if [ -d "$SERVICE_DIR" ]; then
    echo "Error: Service '$SERVICE_NAME' already exists"
    exit 1
fi

echo "🚀 Creating new service: $SERVICE_NAME"

# Copy template
cp -r templates/service-template "$SERVICE_DIR"

# Replace placeholders in all files
find "$SERVICE_DIR" -type f -name "*.go" -exec sed -i '' "s/SERVICE_NAME/$SERVICE_NAME/g" {} \;

# Update .air.toml
sed "s/SERVICE_NAME/$SERVICE_NAME/g" .air.toml.template > "$SERVICE_DIR/.air.toml"

# Create go.mod
cat > "$SERVICE_DIR/go.mod" << EOF
module wise-owl/services/$SERVICE_NAME

go 1.24

require (
    wise-owl/lib v0.0.0
    github.com/gin-gonic/gin v1.10.0
)

replace wise-owl/lib => ../../lib
EOF

echo "✅ Service '$SERVICE_NAME' created successfully!"
echo ""
echo "Next steps:"
echo "1. Add the service to docker-compose.dev.yml"
echo "2. Add to go.work: ./services/$SERVICE_NAME"
echo "3. Implement your business logic in internal/"
echo "4. Test with: cd $SERVICE_DIR && go run cmd/main.go"
