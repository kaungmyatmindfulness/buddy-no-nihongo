#!/bin/bash
# Quick Production Deployment Example
# This script demonstrates a complete production deployment workflow

set -e

echo "🦉 Wise Owl Production Deployment Example"
echo "========================================"

# Step 1: Environment Setup
echo ""
echo "📋 Step 1: Environment Setup"
if [ ! -f .env.docker ]; then
    echo "Creating production environment file..."
    cp .env.docker.example .env.docker
    echo "⚠️  Please edit .env.docker with your production values before continuing"
    echo "   - Update MongoDB credentials"
    echo "   - Set Auth0 configuration"
    echo "   - Review security settings"
    exit 1
else
    echo "✅ Production environment file exists"
fi

# Step 2: Pre-deployment checks
echo ""
echo "🔍 Step 2: Pre-deployment Health Check"
if docker ps -q > /dev/null 2>&1; then
    echo "✅ Docker is running"
else
    echo "❌ Docker is not running. Please start Docker first."
    exit 1
fi

# Check if containers are already running
if docker-compose ps | grep -q "Up"; then
    echo "⚠️  Some services are already running"
    read -p "Do you want to perform a rolling update? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Performing rolling update..."
        ./prod.sh deploy
    else
        echo "Deployment cancelled"
        exit 0
    fi
else
    echo "No existing services detected - performing fresh deployment"
fi

# Step 3: Start Services
echo ""
echo "🚀 Step 3: Starting Production Services"
./prod.sh start

# Step 4: Verify Deployment
echo ""
echo "✅ Step 4: Deployment Verification"
sleep 5  # Allow services time to stabilize

if ./prod.sh status > /dev/null 2>&1; then
    echo "✅ All services are healthy!"
else
    echo "⚠️  Some services may have issues. Check logs with: ./prod.sh logs"
fi

# Step 5: Create Initial Backup
echo ""
echo "💾 Step 5: Creating Initial Backup"
./backup-prod.sh create

# Step 6: Setup Monitoring
echo ""
echo "📊 Step 6: Monitoring Setup"
echo "To start continuous monitoring, run in a separate terminal:"
echo "  ./monitor-prod.sh"
echo ""
echo "For single health checks, use:"
echo "  ./monitor-prod.sh check"

# Final Summary
echo ""
echo "🎉 Deployment Complete!"
echo "====================="
echo ""
echo "🌐 Access Points:"
echo "  - API Gateway: http://localhost"
echo "  - Users API: http://localhost/api/v1/users/"
echo "  - Content API: http://localhost/api/v1/content/"
echo "  - Quiz API: http://localhost/api/v1/quiz/"
echo ""
echo "📋 Management Commands:"
echo "  - Check status: ./prod.sh status"
echo "  - View logs: ./prod.sh logs [service]"
echo "  - Create backup: ./backup-prod.sh create"
echo "  - Monitor services: ./monitor-prod.sh"
echo ""
echo "📚 For detailed documentation, see: PRODUCTION.md"
