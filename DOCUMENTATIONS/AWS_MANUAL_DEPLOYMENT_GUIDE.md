# AWS Manual Deployment Instructions - Step by Step Learning Guide

This guide teaches you how to manually deploy the Wise Owl microservices to AWS. Each step explains **what** you're doing, **how** to do it, and **why** it's necessary.

## Prerequisites - What You Need

Before starting, ensure you have:

- AWS CLI installed and configured with appropriate permissions
- Docker installed locally
- Go 1.21+ installed
- Your Wise Owl project ready

**Why these tools?**

- AWS CLI: Interacts with AWS services from command line
- Docker: Packages your Go applications into containers
- Go: Builds your microservices from source

## Phase 1: Understanding and Preparing Your Code

### Step 1: Test AWS Configuration Locally

**What:** Verify your enhanced AWS configuration works locally
**How:**

```bash
# Test the AWS-aware configuration loading
cd services/users
export AWS_EXECUTION_ENV=""  # Simulate local environment
go run cmd/main_aws.go
```

**Why:** This ensures your AWS-optimized code works before deploying. The `main_aws.go` file uses the new `LoadConfigAWS()` function that can fall back to local config.

**Expected behavior:**

- Should start successfully on port 8081
- Health endpoints should respond at http://localhost:8081/health
- Should connect to local MongoDB if running

### Step 2: Build and Test Docker Images Locally

**What:** Create production Docker images and test them locally
**How:**

```bash
# Build users service Docker image
docker build -t wise-owl-users:test -f services/users/Dockerfile.aws .

# Test the image locally
docker run -p 8081:8081 -e PORT=8081 -e MONGODB_URI=mongodb://host.docker.internal:27017 wise-owl-users:test
```

**Why:** Testing Docker images locally catches configuration issues before deploying to AWS. The `Dockerfile.aws` uses multi-stage builds for smaller, secure production images.

**What to verify:**

- Container starts without errors
- Health endpoint responds: `curl http://localhost:8081/health`
- Application logs show proper configuration loading

### Step 3: Understand the AWS Configuration Pattern

**What:** Learn how the new AWS configuration system works
**How:** Examine these key files:

```bash
# View the enhanced configuration
cat lib/config/config.go | grep -A 20 "LoadConfigAWS"

# View DocumentDB connection logic
cat lib/database/documentdb.go | grep -A 10 "CreateDocumentDBConnection"

# View AWS health checker
cat lib/health/aws.go | grep -A 10 "NewAWSEnhancedHealthChecker"
```

**Why each component exists:**

- `LoadConfigAWS()`: Loads secrets from AWS Secrets Manager in production
- `CreateDocumentDBConnection()`: Handles DocumentDB's TLS requirements
- `NewAWSEnhancedHealthChecker()`: Provides comprehensive health checks for ALB/ECS

## Phase 2: AWS Infrastructure Setup

### Step 4: Create ECR Repositories

**What:** Create container registries to store your Docker images
**How:**

```bash
# Get your AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Your AWS Account ID: $AWS_ACCOUNT_ID"

# Create ECR repositories for each service
aws ecr create-repository --repository-name wise-owl-users --region us-east-1
aws ecr create-repository --repository-name wise-owl-content --region us-east-1
aws ecr create-repository --repository-name wise-owl-quiz --region us-east-1

# View created repositories
aws ecr describe-repositories --region us-east-1
```

**Why ECR:**

- Secure container registry integrated with ECS
- Supports image vulnerability scanning
- Integrated with AWS IAM for access control

### Step 5: Push Docker Images to ECR

**What:** Upload your container images to AWS
**How:**

```bash
# Login to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com

# Build and push users service
docker build -t wise-owl-users:latest -f services/users/Dockerfile.aws .
docker tag wise-owl-users:latest $AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/wise-owl-users:latest
docker push $AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/wise-owl-users:latest

# Repeat for content service
docker build -t wise-owl-content:latest -f services/content/Dockerfile.aws .
docker tag wise-owl-content:latest $AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/wise-owl-content:latest
docker push $AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/wise-owl-content:latest

# Repeat for quiz service
docker build -t wise-owl-quiz:latest -f services/quiz/Dockerfile.aws .
docker tag wise-owl-quiz:latest $AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/wise-owl-quiz:latest
docker push $AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/wise-owl-quiz:latest
```

**Why this process:**

- `docker login`: Authenticates with ECR using AWS credentials
- `docker tag`: Creates ECR-compatible image names
- `docker push`: Uploads images to AWS for ECS to use

### Step 6: Create Secrets in AWS Secrets Manager

**What:** Store sensitive configuration securely
**How:**

```bash
# Create the main secret with all sensitive values
aws secretsmanager create-secret \
    --name "wise-owl/production" \
    --description "Wise Owl production secrets" \
    --secret-string '{
        "MONGODB_URI": "mongodb://username:password@your-docdb-endpoint:27017/?ssl=true&replicaSet=rs0&readPreference=secondaryPreferred",
        "JWT_SECRET": "your-jwt-secret-here",
        "AUTH0_DOMAIN": "your-auth0-domain.auth0.com",
        "AUTH0_AUDIENCE": "your-auth0-audience"
    }' \
    --region us-east-1

# Verify secret was created
aws secretsmanager describe-secret --secret-id "wise-owl/production" --region us-east-1
```

**Why Secrets Manager:**

- Encrypts sensitive data at rest and in transit
- Automatic rotation capabilities
- Fine-grained access control with IAM
- Integrates with ECS for secure environment variable injection

### Step 7: Test Configuration Loading

**What:** Verify your application can load AWS secrets
**How:**

```bash
# Create a simple test script
cat > test-aws-config.go << 'EOF'
package main

import (
    "fmt"
    "log"
    "os"
    "wise-owl/lib/config"
)

func main() {
    // Simulate AWS environment
    os.Setenv("AWS_EXECUTION_ENV", "AWS_ECS_FARGATE")

    cfg, err := config.LoadConfigAWS()
    if err != nil {
        log.Fatal(err)
    }

    fmt.Printf("Port: %s\n", cfg.Port)
    fmt.Printf("Database Type: %s\n", cfg.Database.Type)
    fmt.Printf("Has JWT Secret: %t\n", cfg.JWT.Secret != "")
}
EOF

# Run the test (requires AWS credentials)
go run test-aws-config.go

# Clean up
rm test-aws-config.go
```

**Why test this:**

- Validates your AWS credentials and permissions
- Confirms the secret is properly formatted
- Tests the configuration loading logic before ECS deployment

## Phase 3: ECS Deployment

### Step 8: Create ECS Cluster

**What:** Create a compute environment for your containers
**How:**

```bash
# Create ECS cluster
aws ecs create-cluster \
    --cluster-name wise-owl-cluster \
    --capacity-providers FARGATE \
    --default-capacity-provider-strategy capacityProvider=FARGATE,weight=1 \
    --region us-east-1

# Verify cluster creation
aws ecs describe-clusters --clusters wise-owl-cluster --region us-east-1
```

**Why Fargate:**

- Serverless container hosting (no EC2 management)
- Automatic scaling based on demand
- Pay only for resources used
- Built-in security and networking

### Step 9: Create IAM Roles for ECS

**What:** Create roles that allow ECS to access AWS services
**How:**

```bash
# Create ECS task execution role trust policy
cat > ecs-task-execution-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# Create the execution role
aws iam create-role \
    --role-name wise-owl-ecs-execution-role \
    --assume-role-policy-document file://ecs-task-execution-trust-policy.json

# Attach AWS managed policy for ECS task execution
aws iam attach-role-policy \
    --role-name wise-owl-ecs-execution-role \
    --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

# Create custom policy for accessing secrets
cat > ecs-secrets-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "ssm:GetParameter",
        "ssm:GetParameters"
      ],
      "Resource": [
        "arn:aws:secretsmanager:us-east-1:*:secret:wise-owl/*",
        "arn:aws:ssm:us-east-1:*:parameter/wise-owl/*"
      ]
    }
  ]
}
EOF

# Create and attach secrets policy
aws iam create-policy \
    --policy-name wise-owl-secrets-policy \
    --policy-document file://ecs-secrets-policy.json

aws iam attach-role-policy \
    --role-name wise-owl-ecs-execution-role \
    --policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/wise-owl-secrets-policy

# Clean up policy files
rm ecs-task-execution-trust-policy.json ecs-secrets-policy.json
```

**Why these roles:**

- **Execution Role**: Allows ECS to pull images from ECR and access secrets
- **Task Role**: Allows your application to access AWS services
- **Least Privilege**: Each role has only necessary permissions

### Step 10: Create ECS Task Definition

**What:** Define how your container should run
**How:**

```bash
# Create task definition for users service
cat > users-task-definition.json << EOF
{
  "family": "wise-owl-users",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512",
  "memory": "1024",
  "executionRoleArn": "arn:aws:iam::$AWS_ACCOUNT_ID:role/wise-owl-ecs-execution-role",
  "taskRoleArn": "arn:aws:iam::$AWS_ACCOUNT_ID:role/wise-owl-ecs-execution-role",
  "containerDefinitions": [
    {
      "name": "users-service",
      "image": "$AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/wise-owl-users:latest",
      "portMappings": [
        {
          "containerPort": 8081,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {
          "name": "PORT",
          "value": "8081"
        },
        {
          "name": "GRPC_PORT",
          "value": "50051"
        },
        {
          "name": "AWS_EXECUTION_ENV",
          "value": "AWS_ECS_FARGATE"
        },
        {
          "name": "DB_TYPE",
          "value": "documentdb"
        }
      ],
      "secrets": [
        {
          "name": "MONGODB_URI",
          "valueFrom": "arn:aws:secretsmanager:us-east-1:$AWS_ACCOUNT_ID:secret:wise-owl/production:MONGODB_URI::"
        },
        {
          "name": "JWT_SECRET",
          "valueFrom": "arn:aws:secretsmanager:us-east-1:$AWS_ACCOUNT_ID:secret:wise-owl/production:JWT_SECRET::"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/wise-owl",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "users"
        }
      },
      "healthCheck": {
        "command": [
          "CMD-SHELL",
          "curl -f http://localhost:8081/health/ready || exit 1"
        ],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 60
      },
      "essential": true
    }
  ]
}
EOF

# Create CloudWatch log group first
aws logs create-log-group --log-group-name /ecs/wise-owl --region us-east-1

# Register the task definition
aws ecs register-task-definition \
    --cli-input-json file://users-task-definition.json \
    --region us-east-1

# Verify task definition
aws ecs describe-task-definition \
    --task-definition wise-owl-users \
    --region us-east-1

# Clean up
rm users-task-definition.json
```

**Why each component:**

- **CPU/Memory**: Resource allocation for Fargate
- **Environment Variables**: Non-sensitive configuration
- **Secrets**: Secure injection from Secrets Manager
- **Health Check**: ECS monitors application health
- **Log Configuration**: Centralized logging in CloudWatch

## Phase 4: Testing and Verification

### Step 11: Test ECS Task

**What:** Run your task to verify it works
**How:**

```bash
# Get default VPC and subnet (for testing)
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query 'Vpcs[0].VpcId' --output text --region us-east-1)
SUBNET_ID=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[0].SubnetId' --output text --region us-east-1)

echo "Using VPC: $VPC_ID"
echo "Using Subnet: $SUBNET_ID"

# Create security group for testing
SECURITY_GROUP_ID=$(aws ec2 create-security-group \
    --group-name wise-owl-test-sg \
    --description "Test security group for Wise Owl" \
    --vpc-id $VPC_ID \
    --query 'GroupId' \
    --output text \
    --region us-east-1)

# Allow inbound HTTP traffic
aws ec2 authorize-security-group-ingress \
    --group-id $SECURITY_GROUP_ID \
    --protocol tcp \
    --port 8081 \
    --cidr 0.0.0.0/0 \
    --region us-east-1

# Run the task
TASK_ARN=$(aws ecs run-task \
    --cluster wise-owl-cluster \
    --task-definition wise-owl-users \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_ID],securityGroups=[$SECURITY_GROUP_ID],assignPublicIp=ENABLED}" \
    --query 'tasks[0].taskArn' \
    --output text \
    --region us-east-1)

echo "Task started: $TASK_ARN"

# Wait for task to start
echo "Waiting for task to start..."
aws ecs wait tasks-running --cluster wise-owl-cluster --tasks $TASK_ARN --region us-east-1

# Get task details and public IP
TASK_DETAILS=$(aws ecs describe-tasks --cluster wise-owl-cluster --tasks $TASK_ARN --region us-east-1)
PUBLIC_IP=$(echo $TASK_DETAILS | jq -r '.tasks[0].attachments[0].details[] | select(.name=="networkInterfaceId") | .value' | xargs -I {} aws ec2 describe-network-interfaces --network-interface-ids {} --query 'NetworkInterfaces[0].Association.PublicIp' --output text --region us-east-1)

echo "Task public IP: $PUBLIC_IP"
```

**Why this test:**

- Validates your task definition works
- Tests network configuration
- Confirms health checks pass
- Provides public IP for direct testing

### Step 12: Verify Application Health

**What:** Test your running application
**How:**

```bash
# Test health endpoints (replace $PUBLIC_IP with actual IP from previous step)
curl http://$PUBLIC_IP:8081/health
curl http://$PUBLIC_IP:8081/health/ready
curl http://$PUBLIC_IP:8081/health/live
curl http://$PUBLIC_IP:8081/health/deep

# Check CloudWatch logs
aws logs tail /ecs/wise-owl --follow --region us-east-1
```

**What to look for:**

- Health endpoints return 200 status
- Logs show successful configuration loading
- Database connection established (if DocumentDB is configured)
- No error messages in CloudWatch logs

### Step 13: Clean Up Test Resources

**What:** Remove test resources to avoid charges
**How:**

```bash
# Stop the test task
aws ecs stop-task --cluster wise-owl-cluster --task $TASK_ARN --region us-east-1

# Delete security group
aws ec2 delete-security-group --group-id $SECURITY_GROUP_ID --region us-east-1

echo "Test resources cleaned up"
```

**Why clean up:**

- Avoid unnecessary AWS charges
- Prevent resource limit issues
- Keep environment clean for production deployment

## Phase 5: Understanding What You've Built

### Architecture Overview

**What you've created:**

1. **ECR Repositories**: Secure container storage
2. **ECS Cluster**: Serverless container orchestration
3. **Task Definitions**: Container runtime specifications
4. **IAM Roles**: Security and access control
5. **Secrets Manager**: Secure configuration storage
6. **CloudWatch Logs**: Centralized logging

**How it all connects:**

- ECS pulls container images from ECR
- Task definitions specify how containers run
- IAM roles provide secure access to AWS services
- Secrets Manager injects sensitive configuration
- CloudWatch captures application logs and metrics

### Next Steps for Production

1. **Set up DocumentDB** (following AWS_MANUAL_SETUP_GUIDE.md)
2. **Create Application Load Balancer** for traffic distribution
3. **Set up proper VPC with private subnets** for security
4. **Configure auto-scaling** based on demand
5. **Add monitoring and alerting** with CloudWatch

### Cost Optimization Tips

- Use Fargate Spot for non-critical workloads
- Right-size CPU and memory allocations
- Set up CloudWatch billing alerts
- Use reserved capacity for predictable workloads
- Clean up unused resources regularly

### Security Best Practices

- Use private subnets for application containers
- Implement least-privilege IAM policies
- Enable VPC Flow Logs for network monitoring
- Use AWS WAF with Application Load Balancer
- Regularly rotate secrets and credentials

This manual approach gives you deep understanding of each AWS service and how they work together. You can now confidently deploy, monitor, and troubleshoot your microservices on AWS!
