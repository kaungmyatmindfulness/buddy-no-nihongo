#!/bin/bash
# Production Management Script for Wise Owl Golang Microservices

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
print_usage() {
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  start     - Start all services in production mode"
    echo "  stop      - Stop all services"
    echo "  restart   - Restart all services"
    echo "  status    - Show service status and health"
    echo "  logs      - Show logs for all services"
    echo "  logs [service] - Show logs for specific service (nginx, users-service, content-service, quiz-service, mongodb)"
    echo "  deploy    - Deploy updates (use --pull for registry images)"
    echo "  backup    - Create database backup"
    echo "  scale [service] [count] - Scale a service to specified number of instances"
    echo ""
}

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_status() {
    echo -e "${BLUE}[STATUS]${NC} $1"
}

check_env() {
    if [ ! -f .env.docker ]; then
        print_error ".env.docker not found. Please create production environment file."
        echo "You can copy from .env.docker.example if available."
        exit 1
    fi
}

# Health check function with retry logic
health_check() {
    local service=$1
    local port=$2
    local retries=30
    local count=0
    
    print_status "Checking health for $service on port $port..."
    
    while [ $count -lt $retries ]; do
        if curl -s -f "http://localhost:$port/health/ready" > /dev/null 2>&1; then
            echo -e "  ${GREEN}✅ $service is healthy${NC}"
            return 0
        fi
        count=$((count + 1))
        sleep 2
        echo -n "."
    done
    
    echo -e "  ${RED}❌ $service failed health check${NC}"
    return 1
}

# Check all services health
check_all_health() {
    print_info "Performing health checks..."
    local all_healthy=true
    
    # Define services and their health check ports
    # Note: Services expose internal port 8080, but nginx is on port 80
    local services=(
        "nginx:80"
        "users-service:8081"
        "content-service:8082" 
        "quiz-service:8083"
    )
    
    for service_info in "${services[@]}"; do
        IFS=':' read -r service port <<< "$service_info"
        
        if ! health_check "$service" "$port"; then
            all_healthy=false
        fi
    done
    
    if [ "$all_healthy" = true ]; then
        print_info "All services are healthy! 🎉"
        echo ""
        echo "🌐 Access points:"
        echo "  - API Gateway: http://localhost"
        echo "  - Users API: http://localhost/api/v1/users/"
        echo "  - Content API: http://localhost/api/v1/content/"
        echo "  - Quiz API: http://localhost/api/v1/quiz/"
    else
        print_warning "Some services failed health checks. Check logs for details."
        print_info "Run '$0 logs [service]' to debug issues"
        return 1
    fi
}

# Create backup
create_backup() {
    print_info "Creating production backup..."
    
    if ! docker-compose ps | grep -q wo-mongodb; then
        print_error "MongoDB container is not running!"
        exit 1
    fi
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir="backups/$timestamp"
    
    mkdir -p "$backup_dir"
    
    # Backup each database
    local databases=("users_db" "content_db" "quiz_db")
    
    for db in "${databases[@]}"; do
        print_status "Backing up $db..."
        
        # Create dump
        docker-compose exec -T mongodb \
            mongodump --db="$db" --archive="/tmp/$db.archive" --quiet 2>/dev/null
        
        # Copy from container
        docker cp "$(docker-compose ps -q mongodb):/tmp/$db.archive" "$backup_dir/$db.archive"
        
        # Compress
        gzip "$backup_dir/$db.archive"
        
        echo -e "  ${GREEN}✅ $db backed up${NC}"
    done
    
    # Create manifest
    echo "Backup created: $timestamp" > "$backup_dir/manifest.txt"
    echo "Databases: ${databases[*]}" >> "$backup_dir/manifest.txt"
    echo "Size: $(du -sh $backup_dir | cut -f1)" >> "$backup_dir/manifest.txt"
    
    print_info "Backup completed in $backup_dir"
}

case "$1" in
    "start")
        check_env
        print_info "Starting all services in production mode..."
        docker-compose up -d
        
        # Wait a moment for containers to start
        sleep 5
        
        check_all_health
        ;;
    
    "stop")
        print_info "Stopping all services..."
        docker-compose down
        ;;
    
    "restart")
        check_env
        print_info "Restarting all services..."
        docker-compose down
        docker-compose up -d
        
        sleep 5
        check_all_health
        ;;
    
    "status")
        print_info "Checking service status..."
        docker-compose ps
        echo ""
        
        # Check if containers are running before health checks
        if docker-compose ps | grep -q "Up"; then
            check_all_health
        else
            print_warning "No services are currently running"
        fi
        ;;
    
    "logs")
        if [ -n "$2" ]; then
            print_info "Showing logs for $2..."
            docker-compose logs -f "$2"
        else
            print_info "Showing logs for all services..."
            docker-compose logs -f
        fi
        ;;
    
    "deploy")
        check_env
        print_info "Deploying production update..."
        
        # Pull latest images if requested
        if [ "$2" = "--pull" ]; then
            print_info "Pulling latest images..."
            docker-compose pull
        fi
        
        # Perform rolling update
        print_info "Performing rolling deployment..."
        docker-compose up -d --no-deps --build
        
        # Wait for services to stabilize
        sleep 10
        
        if check_all_health; then
            print_info "Deployment successful! 🚀"
        else
            print_error "Deployment health checks failed!"
            print_warning "Consider rolling back or checking logs"
            exit 1
        fi
        ;;
    
    "backup")
        create_backup
        ;;
    
    "scale")
        if [ -z "$2" ] || [ -z "$3" ]; then
            print_error "Usage: $0 scale [service] [count]"
            echo "Example: $0 scale users-service 3"
            exit 1
        fi
        
        check_env
        print_info "Scaling $2 to $3 instances..."
        docker-compose up -d --scale "$2=$3"
        
        sleep 5
        print_info "Current service status:"
        docker-compose ps "$2"
        ;;
    
    *)
        print_usage
        exit 1
        ;;
esac
