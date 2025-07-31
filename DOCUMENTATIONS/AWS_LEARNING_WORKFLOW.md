# AWS Learning Workflow - Understanding Through Practice

This guide provides a structured learning approach to AWS deployment, building understanding through hands-on experience with each service.

## Learning Philosophy

**Learn by Doing:** Instead of running scripts, execute each command manually to understand:

- **What** each command accomplishes
- **Why** each step is necessary
- **How** AWS services connect together

## Phase 1: Foundation Understanding (Day 1)

### Goal: Understand AWS Fundamentals

#### 1.1 Explore Your AWS Environment

```bash
# Who am I? What account am I using?
aws sts get-caller-identity
```

**Learn:** AWS accounts, IAM users, and authentication

```bash
# What regions are available?
aws ec2 describe-regions --output table
```

**Learn:** AWS global infrastructure and regional services

```bash
# What's already in my account?
aws ecs list-clusters
aws ecr describe-repositories
aws secretsmanager list-secrets
```

**Learn:** How to inventory existing resources

#### 1.2 Test Your Application Locally

```bash
# Start MongoDB locally
mongod --dbpath /tmp/mongodb

# Test AWS-aware configuration
cd services/users
export AWS_EXECUTION_ENV=""  # Force local mode
go run cmd/main_aws.go
```

**Learn:** How your application detects and adapts to different environments

#### 1.3 Build and Test Container Images

```bash
# Build production image
docker build -t wise-owl-users:local-test -f services/users/Dockerfile.aws .

# Run container locally
docker run -p 8081:8081 \
  -e PORT=8081 \
  -e MONGODB_URI=mongodb://host.docker.internal:27017 \
  wise-owl-users:local-test
```

**Learn:** Container lifecycle, networking, and environment variables

**Checkpoint Questions:**

- How does the application know it's running in AWS vs locally?
- What's the difference between the development and production Dockerfiles?
- How do containers communicate with the host system?

## Phase 2: Container Registry (Day 2)

### Goal: Understand Container Distribution

#### 2.1 Create Your First ECR Repository

```bash
# Create repository
aws ecr create-repository --repository-name wise-owl-users

# Examine what was created
aws ecr describe-repositories --repository-names wise-owl-users
```

**Learn:** Container registries, image versioning, and AWS resource naming

#### 2.2 Understand ECR Authentication

```bash
# Get login token (examine the output)
aws ecr get-login-password --region us-east-1

# Login to ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  $(aws sts get-caller-identity --query Account --output text).dkr.ecr.us-east-1.amazonaws.com
```

**Learn:** Temporary credentials, token-based authentication, and Docker registry protocols

#### 2.3 Push Your First Image

```bash
# Get your account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Account ID: $ACCOUNT_ID"

# Tag image with ECR repository URI
docker tag wise-owl-users:local-test \
  $ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/wise-owl-users:v1.0.0

# Push to ECR
docker push $ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/wise-owl-users:v1.0.0

# Verify upload
aws ecr list-images --repository-name wise-owl-users
```

**Learn:** Image tagging strategies, registry URLs, and image distribution

**Checkpoint Questions:**

- Why does ECR need temporary authentication tokens?
- How do you version container images?
- What happens if you don't tag images?

## Phase 3: Secrets Management (Day 3)

### Goal: Secure Configuration Management

#### 3.1 Understand Secrets vs Environment Variables

**What:** Create test secret with non-sensitive data first

```bash
# Create test secret
aws secretsmanager create-secret \
  --name wise-owl/test \
  --description "Test secret for learning" \
  --secret-string '{"test_key": "test_value", "another_key": "another_value"}'
```

**Learn:** JSON structure, secret naming conventions

#### 3.2 Retrieve and Examine Secrets

```bash
# Get secret metadata (no actual secret data)
aws secretsmanager describe-secret --secret-id wise-owl/test

# Get actual secret value
aws secretsmanager get-secret-value --secret-id wise-owl/test

# Parse just the secret string
aws secretsmanager get-secret-value --secret-id wise-owl/test \
  --query SecretString --output text | jq .
```

**Learn:** AWS CLI query syntax, JSON parsing, secret access patterns

#### 3.3 Create Production Secret

```bash
# Create production secret with real values
aws secretsmanager create-secret \
  --name wise-owl/production \
  --description "Production secrets for Wise Owl microservices" \
  --secret-string '{
    "MONGODB_URI": "mongodb://your-username:your-password@docdb-endpoint:27017/?ssl=true",
    "JWT_SECRET": "your-secure-jwt-secret",
    "AUTH0_DOMAIN": "your-auth0-domain.auth0.com",
    "AUTH0_AUDIENCE": "your-api-identifier"
  }'
```

**Learn:** Production secret management, connection string formats

#### 3.4 Test Secret Access from Application

```bash
# Test local secret loading
export AWS_EXECUTION_ENV="AWS_ECS_FARGATE"
cd services/users
go run cmd/main_aws.go
```

**Learn:** How applications load secrets in AWS environments

**Checkpoint Questions:**

- Why use Secrets Manager instead of environment variables?
- How often do secret access tokens expire?
- What happens if secret retrieval fails?

## Phase 4: Database Setup (Day 4)

### Goal: Understand Managed Database Services

#### 4.1 Create DocumentDB Subnet Group

**What:** DocumentDB needs to know which subnets it can use

```bash
# First, find your VPC and subnets
aws ec2 describe-vpcs
aws ec2 describe-subnets --filters "Name=vpc-id,Values=vpc-xxxxxxxx"

# Create subnet group
aws docdb create-db-subnet-group \
  --db-subnet-group-name wise-owl-docdb-subnet-group \
  --db-subnet-group-description "Subnet group for Wise Owl DocumentDB" \
  --subnet-ids subnet-xxxxxxxx subnet-yyyyyyyy
```

**Learn:** VPC networking, subnet organization, database placement

#### 4.2 Create DocumentDB Cluster

```bash
# Create cluster
aws docdb create-db-cluster \
  --db-cluster-identifier wise-owl-docdb-cluster \
  --engine docdb \
  --master-username wiseowl \
  --master-user-password "YourSecurePassword123!" \
  --db-subnet-group-name wise-owl-docdb-subnet-group \
  --vpc-security-group-ids sg-xxxxxxxx

# Monitor cluster creation
aws docdb describe-db-clusters --db-cluster-identifier wise-owl-docdb-cluster
```

**Learn:** Database clusters vs instances, master credentials, security groups

#### 4.3 Add Database Instance

```bash
# Add instance to cluster
aws docdb create-db-instance \
  --db-instance-identifier wise-owl-docdb-instance-1 \
  --db-instance-class db.t3.medium \
  --engine docdb \
  --db-cluster-identifier wise-owl-docdb-cluster

# Wait for instance to be available
aws docdb wait db-instance-available --db-instance-identifier wise-owl-docdb-instance-1
```

**Learn:** Database scaling, instance types, cluster vs instance roles

#### 4.4 Update Secret with Database Connection

```bash
# Get DocumentDB endpoint
DOCDB_ENDPOINT=$(aws docdb describe-db-clusters \
  --db-cluster-identifier wise-owl-docdb-cluster \
  --query 'DBClusters[0].Endpoint' --output text)

echo "DocumentDB Endpoint: $DOCDB_ENDPOINT"

# Update secret with real connection string
aws secretsmanager update-secret \
  --secret-id wise-owl/production \
  --secret-string "{
    \"MONGODB_URI\": \"mongodb://wiseowl:YourSecurePassword123!@$DOCDB_ENDPOINT:27017/?ssl=true&replicaSet=rs0&readPreference=secondaryPreferred\",
    \"JWT_SECRET\": \"your-secure-jwt-secret\",
    \"AUTH0_DOMAIN\": \"your-auth0-domain.auth0.com\",
    \"AUTH0_AUDIENCE\": \"your-api-identifier\"
  }"
```

**Learn:** Connection string formats, SSL requirements, DocumentDB specifics

**Checkpoint Questions:**

- Why does DocumentDB require SSL connections?
- What's the difference between a cluster and an instance?
- How do you scale DocumentDB?

## Phase 5: ECS Container Orchestration (Day 5-6)

### Goal: Understand Container Orchestration

#### 5.1 Create ECS Cluster

```bash
# Create cluster
aws ecs create-cluster --cluster-name wise-owl-cluster

# Examine cluster details
aws ecs describe-clusters --clusters wise-owl-cluster
```

**Learn:** Container orchestration concepts, cluster management

#### 5.2 Create IAM Roles for ECS

**What:** ECS needs permissions to pull images and access secrets

```bash
# Create execution role trust policy
cat > ecs-execution-trust-policy.json << EOF
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

# Create execution role
aws iam create-role \
  --role-name wise-owl-ecs-execution-role \
  --assume-role-policy-document file://ecs-execution-trust-policy.json

# Attach AWS managed policy
aws iam attach-role-policy \
  --role-name wise-owl-ecs-execution-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
```

**Learn:** IAM roles, trust policies, service-linked permissions

#### 5.3 Create Task Definition

**What:** Define how your container should run

```bash
# Create task definition JSON
cat > users-task-definition.json << EOF
{
  "family": "wise-owl-users",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512",
  "memory": "1024",
  "executionRoleArn": "arn:aws:iam::$ACCOUNT_ID:role/wise-owl-ecs-execution-role",
  "taskRoleArn": "arn:aws:iam::$ACCOUNT_ID:role/wise-owl-ecs-task-role",
  "containerDefinitions": [
    {
      "name": "users-service",
      "image": "$ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/wise-owl-users:v1.0.0",
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
          "name": "AWS_EXECUTION_ENV",
          "value": "AWS_ECS_FARGATE"
        }
      ],
      "secrets": [
        {
          "name": "MONGODB_URI",
          "valueFrom": "arn:aws:secretsmanager:us-east-1:$ACCOUNT_ID:secret:wise-owl/production:MONGODB_URI::"
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
      "essential": true
    }
  ]
}
EOF

# Register task definition
aws ecs register-task-definition --cli-input-json file://users-task-definition.json
```

**Learn:** Task definitions, resource allocation, environment vs secrets

#### 5.4 Run a Test Task

```bash
# Run single task to test
aws ecs run-task \
  --cluster wise-owl-cluster \
  --task-definition wise-owl-users \
  --launch-type FARGATE \
  --network-configuration 'awsvpcConfiguration={subnets=[subnet-xxxxxxxx],securityGroups=[sg-xxxxxxxx],assignPublicIp=ENABLED}'

# Monitor task
aws ecs list-tasks --cluster wise-owl-cluster
aws ecs describe-tasks --cluster wise-owl-cluster --tasks task-arn-here
```

**Learn:** Task vs service differences, networking configuration, troubleshooting

**Checkpoint Questions:**

- What's the difference between execution role and task role?
- Why does Fargate need VPC configuration?
- How do you debug a failed task startup?

## Phase 6: Load Balancing (Day 7)

### Goal: Understand Traffic Distribution

#### 6.1 Create Application Load Balancer

```bash
# Create ALB
aws elbv2 create-load-balancer \
  --name wise-owl-alb \
  --subnets subnet-xxxxxxxx subnet-yyyyyyyy \
  --security-groups sg-xxxxxxxx

# Get ALB ARN and DNS name
aws elbv2 describe-load-balancers --names wise-owl-alb
```

**Learn:** Load balancer types, public vs private load balancers

#### 6.2 Create Target Groups

```bash
# Create target group for users service
aws elbv2 create-target-group \
  --name wise-owl-users-tg \
  --protocol HTTP \
  --port 8081 \
  --vpc-id vpc-xxxxxxxx \
  --target-type ip \
  --health-check-path /health/ready \
  --health-check-interval-seconds 30 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 3
```

**Learn:** Target groups, health checks, target types

#### 6.3 Create Listeners and Rules

```bash
# Create listener
aws elbv2 create-listener \
  --load-balancer-arn arn:aws:elasticloadbalancing:... \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=fixed-response,FixedResponseConfig='{MessageBody=Not Found,StatusCode=404}'

# Add routing rule
aws elbv2 create-rule \
  --listener-arn arn:aws:elasticloadbalancing:... \
  --priority 100 \
  --conditions Field=path-pattern,Values='/api/v1/users/*' \
  --actions Type=forward,TargetGroupArn=arn:aws:elasticloadbalancing:...
```

**Learn:** Listeners, routing rules, request routing

## Phase 7: Production Deployment (Day 8)

### Goal: Create Production Services

#### 7.1 Create ECS Service

```bash
# Create service
aws ecs create-service \
  --cluster wise-owl-cluster \
  --service-name wise-owl-users \
  --task-definition wise-owl-users \
  --desired-count 2 \
  --launch-type FARGATE \
  --network-configuration 'awsvpcConfiguration={subnets=[subnet-xxxxxxxx],securityGroups=[sg-xxxxxxxx],assignPublicIp=DISABLED}' \
  --load-balancers targetGroupArn=arn:aws:elasticloadbalancing:...,containerName=users-service,containerPort=8081

# Monitor deployment
aws ecs describe-services --cluster wise-owl-cluster --services wise-owl-users
```

**Learn:** Services vs tasks, desired state, rolling deployments

#### 7.2 Test End-to-End

```bash
# Get ALB DNS name
ALB_DNS=$(aws elbv2 describe-load-balancers --names wise-owl-alb \
  --query 'LoadBalancers[0].DNSName' --output text)

# Test health endpoint
curl http://$ALB_DNS/api/v1/users/health

# Check target health
aws elbv2 describe-target-health --target-group-arn arn:aws:elasticloadbalancing:...
```

**Learn:** End-to-end testing, target health monitoring

## Learning Checkpoints

After each phase, ask yourself:

1. **What did I create?** - Can you explain each AWS resource
2. **Why was it necessary?** - Understand the purpose of each step
3. **How do they connect?** - Map the relationships between services
4. **What would break if...?** - Think about failure scenarios
5. **How would I debug...?** - Practice troubleshooting workflows

## Common Learning Mistakes

1. **Rushing through setup** - Take time to understand each command
2. **Ignoring error messages** - Read and understand AWS error responses
3. **Not cleaning up resources** - Practice deleting resources to understand dependencies
4. **Skipping verification steps** - Always verify each step worked before moving on
5. **Not taking notes** - Document what you learn for future reference

This learning approach builds deep understanding through hands-on practice with each AWS service.
