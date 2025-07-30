# AWS Deployment Guide for Wise Owl

This guide provides instructions for deploying the Wise Owl Japanese vocabulary learning platform to AWS using ECS Fargate, DocumentDB, and other AWS services.

## Overview

The AWS deployment consists of:

- **ECS Fargate** - Container orchestration for microservices
- **Application Load Balancer** - Traffic routing and SSL termination
- **DocumentDB** - MongoDB-compatible database
- **ECR** - Container image registry
- **Secrets Manager** - Secure configuration storage
- **CloudWatch** - Logging and monitoring
- **Route 53** - DNS management

## Prerequisites

1. **AWS CLI** installed and configured
2. **Docker** installed
3. **AWS Account** with appropriate permissions
4. **Domain name** (optional, for custom domain)

### Required AWS Permissions

Your AWS user/role needs permissions for:

- ECS (create/manage clusters, services, task definitions)
- ECR (create repositories, push/pull images)
- DocumentDB (create clusters and instances)
- Secrets Manager (create/read secrets)
- Systems Manager Parameter Store (create/read parameters)
- IAM (create roles and policies)
- VPC/EC2 (networking)
- CloudWatch (logging)
- Route 53 (if using custom domain)

## Quick Start

### 1. Environment Setup

```bash
# Set required environment variables
export AWS_ACCOUNT_ID="123456789012"
export AWS_REGION="us-east-1"
export ENVIRONMENT="production"

# Optional: Set custom domain
export DOMAIN_NAME="your-domain.com"
```

### 2. Deploy Infrastructure

Use the provided deployment script:

```bash
# Make script executable
chmod +x scripts/deploy-aws.sh

# Deploy everything (infrastructure + application)
./scripts/deploy-aws.sh deploy
```

Or deploy in stages:

```bash
# Only build and push Docker images
./scripts/deploy-aws.sh build-only

# Only update ECS services
./scripts/deploy-aws.sh update-only
```

### 3. Configure Secrets

Create the required secrets in AWS Secrets Manager:

```bash
# Create the secrets (adjust values for your setup)
aws secretsmanager create-secret \
  --name "wise-owl/production" \
  --description "Wise Owl production secrets" \
  --secret-string '{
    "MONGODB_URI": "mongodb://username:password@your-cluster.cluster-xyz.docdb.us-east-1.amazonaws.com:27017/?ssl=true&replicaSet=rs0&readPreference=secondaryPreferred",
    "JWT_SECRET": "your-super-secure-jwt-secret",
    "AUTH0_DOMAIN": "your-domain.auth0.com",
    "AUTH0_AUDIENCE": "your-auth0-audience"
  }'
```

Create parameters in Systems Manager:

```bash
# Create parameters
aws ssm put-parameter \
  --name "/wise-owl/DB_TYPE" \
  --value "documentdb" \
  --type "String"

aws ssm put-parameter \
  --name "/wise-owl/LOG_LEVEL" \
  --value "info" \
  --type "String"
```

## Manual Infrastructure Setup

If you prefer to set up infrastructure manually, follow these steps:

### 1. Create ECR Repositories

```bash
# Create repositories for each service
aws ecr create-repository --repository-name wise-owl-users
aws ecr create-repository --repository-name wise-owl-content
aws ecr create-repository --repository-name wise-owl-quiz
```

### 2. Build and Push Images

```bash
# Login to ECR
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Build and push images
docker build -t wise-owl-users:latest -f services/users/Dockerfile.aws .
docker tag wise-owl-users:latest $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/wise-owl-users:latest
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/wise-owl-users:latest

# Repeat for content and quiz services...
```

### 3. Create ECS Cluster

```bash
aws ecs create-cluster --cluster-name wise-owl-cluster
```

### 4. Register Task Definitions

```bash
# Update task definition templates with your AWS account ID and region
sed -i "s/{{AWS_ACCOUNT_ID}}/$AWS_ACCOUNT_ID/g" deployment/aws/task-definition-*.json
sed -i "s/{{AWS_REGION}}/$AWS_REGION/g" deployment/aws/task-definition-*.json

# Register task definitions
aws ecs register-task-definition --cli-input-json file://deployment/aws/task-definition-users.json
aws ecs register-task-definition --cli-input-json file://deployment/aws/task-definition-content.json
aws ecs register-task-definition --cli-input-json file://deployment/aws/task-definition-quiz.json
```

### 5. Create ECS Services

```bash
# Create services (you'll need to provide VPC/subnet/security group IDs)
aws ecs create-service \
  --cluster wise-owl-cluster \
  --service-name wise-owl-users \
  --task-definition wise-owl-users \
  --desired-count 2 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[subnet-12345],securityGroups=[sg-12345],assignPublicIp=DISABLED}"
```

## Configuration

### Environment Variables

The application automatically detects AWS environment and loads configuration from:

1. **Environment Variables** (highest priority)
2. **AWS Secrets Manager** (`wise-owl/production`)
3. **AWS Parameter Store** (`/wise-owl/*`)
4. **Default values** (lowest priority)

### Local Development vs AWS

The application uses different configurations based on environment:

#### Local Development

- Uses `.env.local` file
- Connects to local MongoDB
- Simple health checks
- No AWS API calls

#### AWS Production

- Detects AWS environment via `AWS_EXECUTION_ENV`
- Loads secrets from AWS Secrets Manager
- Connects to DocumentDB
- Enhanced health checks for ALB
- CloudWatch logging

### Service Communication

#### Local Development

- Services communicate via Docker Compose network
- Uses service names: `content-service:50052`

#### AWS Production

- Services communicate via ECS Service Discovery
- Uses service discovery DNS: `content-service.wise-owl-cluster.local:50052`

## Monitoring and Troubleshooting

### Health Checks

Each service exposes multiple health check endpoints:

- `/health` - Basic health status
- `/health/ready` - Readiness probe (for ALB)
- `/health/live` - Liveness probe (for ECS)
- `/health/deep` - Detailed health status (AWS only)

### Logs

View logs in CloudWatch:

```bash
# View service logs
aws logs get-log-events \
  --log-group-name "/ecs/wise-owl" \
  --log-stream-name "users/users-service/$(date +%s)"
```

### Common Issues

1. **ECS Service Won't Start**

   - Check task definition JSON for syntax errors
   - Verify ECR image URLs are correct
   - Check IAM roles have necessary permissions

2. **DocumentDB Connection Issues**

   - Verify VPC security groups allow traffic on port 27017
   - Check DocumentDB connection string in secrets
   - Ensure services are in same VPC as DocumentDB

3. **Health Check Failures**
   - Check service logs for startup errors
   - Verify database connectivity
   - Ensure health check endpoints are accessible

## Cost Optimization

### Estimated Monthly Costs (us-east-1)

- **ECS Fargate**: ~$150-300 (depending on CPU/memory allocation)
- **DocumentDB**: ~$200-400 (2x db.t3.medium instances)
- **ALB**: ~$20-30
- **CloudWatch**: ~$10-20
- **Other services**: ~$20-50

**Total**: ~$400-800/month

### Cost Savings Tips

1. **Use Fargate Spot** for non-production workloads (70% savings)
2. **Right-size instances** based on actual usage
3. **Use Reserved Capacity** for predictable workloads
4. **Enable CloudWatch log retention** policies
5. **Use lifecycle policies** for ECR images

## Security Best Practices

1. **Least Privilege IAM** - Grant minimal necessary permissions
2. **Secrets Management** - Never hardcode secrets in images
3. **Network Security** - Use private subnets for services
4. **Image Scanning** - Enable ECR vulnerability scanning
5. **TLS Encryption** - Use HTTPS/TLS for all communications
6. **Regular Updates** - Keep base images and dependencies updated

## Scaling

### Horizontal Scaling

```bash
# Scale a service
aws ecs update-service \
  --cluster wise-owl-cluster \
  --service wise-owl-users \
  --desired-count 4
```

### Auto Scaling

Set up auto scaling based on CPU/memory utilization:

```bash
# Create auto scaling target
aws application-autoscaling register-scalable-target \
  --service-namespace ecs \
  --resource-id service/wise-owl-cluster/wise-owl-users \
  --scalable-dimension ecs:service:DesiredCount \
  --min-capacity 2 \
  --max-capacity 10
```

## Backup and Disaster Recovery

### DocumentDB Backups

- Automated backups enabled by default
- 7-day retention period
- Point-in-time recovery available

### Multi-Region Deployment

- Deploy to multiple AWS regions for high availability
- Use Route 53 health checks for failover
- Replicate DocumentDB across regions

## Support

For deployment issues:

1. Check the [troubleshooting guide](../TROUBLESHOOTING.md)
2. Review CloudWatch logs
3. Verify AWS resource configurations
4. Check IAM permissions

## Next Steps

After successful deployment:

1. Set up monitoring dashboards
2. Configure alerts and notifications
3. Implement CI/CD pipeline
4. Set up backup and disaster recovery
5. Configure auto scaling policies
