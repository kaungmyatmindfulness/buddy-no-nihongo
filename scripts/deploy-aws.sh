#!/bin/bash

# AWS Deployment Script for Wise Owl
# This script builds and deploys the Wise Owl services to AWS ECS

set -e

# Configuration
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
ENVIRONMENT="${ENVIRONMENT:-production}"
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
CLUSTER_NAME="wise-owl-cluster"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is required but not installed"
        exit 1
    fi
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker is required but not installed"
        exit 1
    fi
    
    if [ -z "$AWS_ACCOUNT_ID" ]; then
        log_error "AWS_ACCOUNT_ID environment variable is required"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Login to ECR
ecr_login() {
    log_info "Logging in to Amazon ECR..."
    aws ecr get-login-password --region $AWS_REGION | \
        docker login --username AWS --password-stdin $ECR_REGISTRY
    log_success "ECR login successful"
}

# Build and push Docker images
build_and_push() {
    local service=$1
    local dockerfile=$2
    local port=$3
    
    log_info "Building and pushing $service service..."
    
    # Build image
    docker build -t wise-owl-$service:latest -f $dockerfile .
    
    # Tag for ECR
    docker tag wise-owl-$service:latest $ECR_REGISTRY/wise-owl-$service:latest
    docker tag wise-owl-$service:latest $ECR_REGISTRY/wise-owl-$service:$(git rev-parse --short HEAD)
    
    # Push to ECR
    docker push $ECR_REGISTRY/wise-owl-$service:latest
    docker push $ECR_REGISTRY/wise-owl-$service:$(git rev-parse --short HEAD)
    
    log_success "$service service image pushed successfully"
}

# Update ECS service
update_ecs_service() {
    local service=$1
    
    log_info "Updating ECS service: $service..."
    
    # Force new deployment
    aws ecs update-service \
        --cluster $CLUSTER_NAME \
        --service wise-owl-$service \
        --force-new-deployment \
        --region $AWS_REGION
    
    log_success "ECS service $service update initiated"
}

# Wait for services to stabilize
wait_for_services() {
    log_info "Waiting for services to stabilize..."
    
    for service in users content quiz; do
        log_info "Waiting for $service service to stabilize..."
        aws ecs wait services-stable \
            --cluster $CLUSTER_NAME \
            --services wise-owl-$service \
            --region $AWS_REGION
        log_success "$service service is stable"
    done
}

# Validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    # Get ALB DNS name (you might need to adjust this based on your setup)
    ALB_DNS=$(aws elbv2 describe-load-balancers \
        --names wise-owl-alb \
        --query 'LoadBalancers[0].DNSName' \
        --output text \
        --region $AWS_REGION 2>/dev/null || echo "")
    
    if [ -z "$ALB_DNS" ] || [ "$ALB_DNS" = "None" ]; then
        log_warning "Could not get ALB DNS name for validation"
        return
    fi
    
    for service in users content quiz; do
        endpoint="https://$ALB_DNS/api/v1/$service/health"
        log_info "Checking $service health endpoint: $endpoint"
        
        if curl -f -s --max-time 10 "$endpoint" > /dev/null; then
            log_success "$service service is healthy"
        else
            log_warning "$service service health check failed"
        fi
    done
}

# Main deployment process
main() {
    log_info "Starting AWS deployment for Wise Owl..."
    log_info "Environment: $ENVIRONMENT"
    log_info "AWS Region: $AWS_REGION"
    log_info "ECR Registry: $ECR_REGISTRY"
    
    check_prerequisites
    ecr_login
    
    # Build and push all services
    build_and_push "users" "services/users/Dockerfile.aws" "8081"
    build_and_push "content" "services/content/Dockerfile.aws" "8082"
    build_and_push "quiz" "services/quiz/Dockerfile.aws" "8083"
    
    # Update ECS services
    update_ecs_service "users"
    update_ecs_service "content"
    update_ecs_service "quiz"
    
    # Wait for deployment to complete
    wait_for_services
    
    # Validate deployment
    validate_deployment
    
    log_success "🎉 Deployment completed successfully!"
    log_info "Monitor your services in the AWS Console:"
    log_info "https://console.aws.amazon.com/ecs/home?region=$AWS_REGION#/clusters/$CLUSTER_NAME/services"
}

# Handle script arguments
case "${1:-deploy}" in
    "deploy")
        main
        ;;
    "build-only")
        check_prerequisites
        ecr_login
        build_and_push "users" "services/users/Dockerfile.aws" "8081"
        build_and_push "content" "services/content/Dockerfile.aws" "8082"
        build_and_push "quiz" "services/quiz/Dockerfile.aws" "8083"
        log_success "Build and push completed"
        ;;
    "update-only")
        check_prerequisites
        update_ecs_service "users"
        update_ecs_service "content"
        update_ecs_service "quiz"
        wait_for_services
        validate_deployment
        log_success "Service update completed"
        ;;
    *)
        echo "Usage: $0 [deploy|build-only|update-only]"
        echo "  deploy      - Build, push, and update services (default)"
        echo "  build-only  - Only build and push Docker images"
        echo "  update-only - Only update ECS services"
        exit 1
        ;;
esac
