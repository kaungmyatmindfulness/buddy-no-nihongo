# AWS Command Reference for Manual Deployment

This guide provides detailed explanations of every AWS command needed to deploy Wise Owl microservices, with the **what**, **why**, and **how** for each step.

## Understanding the Commands

### AWS CLI Command Structure

```bash
aws <service> <operation> [--parameters]
```

**What:** Every AWS CLI command follows this pattern
**Why:** Consistent interface across all AWS services
**How:** `<service>` is the AWS service name, `<operation>` is what you want to do

## ECR (Elastic Container Registry) Commands

### Get Login Token

```bash
aws ecr get-login-password --region us-east-1
```

**What:** Retrieves a temporary authentication token for Docker
**Why:** ECR requires authentication before you can push/pull images
**How:** Returns a password that's valid for 12 hours

### Login to ECR

```bash
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com
```

**What:** Authenticates Docker with your ECR registry
**Why:** Docker needs credentials to push images to ECR
**How:** Pipes the password from previous command to Docker login

### Create Repository

```bash
aws ecr create-repository --repository-name wise-owl-users --region us-east-1
```

**What:** Creates a new container repository in ECR
**Why:** You need a place to store your container images
**How:** Specify repository name and region

### List Repositories

```bash
aws ecr describe-repositories --region us-east-1
```

**What:** Shows all your ECR repositories
**Why:** Verify repositories were created and get their details
**How:** Returns JSON with repository information

## Secrets Manager Commands

### Create Secret

```bash
aws secretsmanager create-secret \
  --name wise-owl/production \
  --description "Production secrets for Wise Owl" \
  --secret-string '{
    "MONGODB_URI": "mongodb://username:password@docdb-cluster.cluster-xxx.us-east-1.docdb.amazonaws.com:27017/?ssl=true&replicaSet=rs0&readPreference=secondaryPreferred",
    "JWT_SECRET": "your-jwt-secret-here",
    "AUTH0_DOMAIN": "your-auth0-domain.auth0.com",
    "AUTH0_AUDIENCE": "your-api-identifier"
  }'
```

**What:** Creates a new secret with JSON key-value pairs
**Why:** Sensitive data like passwords shouldn't be in environment variables
**How:** Store as JSON string, reference individual keys in ECS

### Get Secret Value

```bash
aws secretsmanager get-secret-value --secret-id wise-owl/production
```

**What:** Retrieves the secret data
**Why:** Verify secret was created correctly
**How:** Returns JSON with secret string and metadata

### Update Secret

```bash
aws secretsmanager update-secret \
  --secret-id wise-owl/production \
  --secret-string '{"MONGODB_URI": "new-value"}'
```

**What:** Changes the secret value
**Why:** Update configuration without redeploying applications
**How:** Overwrites entire secret string with new JSON

## DocumentDB Commands

### Create Subnet Group

```bash
aws docdb create-db-subnet-group \
  --db-subnet-group-name wise-owl-docdb-subnet-group \
  --db-subnet-group-description "Subnet group for Wise Owl DocumentDB" \
  --subnet-ids subnet-12345 subnet-67890
```

**What:** Groups subnets where DocumentDB can run
**Why:** DocumentDB needs to know which subnets it can use
**How:** Specify subnet IDs from your VPC

### Create DocumentDB Cluster

```bash
aws docdb create-db-cluster \
  --db-cluster-identifier wise-owl-docdb-cluster \
  --engine docdb \
  --master-username wiseowl \
  --master-user-password YourSecurePassword123 \
  --db-subnet-group-name wise-owl-docdb-subnet-group \
  --vpc-security-group-ids sg-12345678
```

**What:** Creates the DocumentDB cluster (like a MongoDB replica set)
**Why:** Your applications need a database to store data
**How:** Specify identifier, credentials, networking, and security

### Add DocumentDB Instance

```bash
aws docdb create-db-instance \
  --db-instance-identifier wise-owl-docdb-instance-1 \
  --db-instance-class db.t3.medium \
  --engine docdb \
  --db-cluster-identifier wise-owl-docdb-cluster
```

**What:** Adds a compute instance to the DocumentDB cluster
**Why:** The cluster needs instances to actually run the database
**How:** Specify instance size and which cluster to join

## ECS Commands

### Create Cluster

```bash
aws ecs create-cluster --cluster-name wise-owl-cluster
```

**What:** Creates a logical grouping of compute resources
**Why:** ECS needs a cluster to run your containers
**How:** Simple command with just the cluster name

### Register Task Definition

```bash
aws ecs register-task-definition --cli-input-json file://task-definition.json
```

**What:** Defines how your container should run
**Why:** ECS needs to know resource requirements, environment variables, etc.
**How:** Use JSON file to specify all container configuration

### Create Service

```bash
aws ecs create-service \
  --cluster wise-owl-cluster \
  --service-name wise-owl-users \
  --task-definition wise-owl-users:1 \
  --desired-count 2 \
  --launch-type FARGATE \
  --network-configuration 'awsvpcConfiguration={subnets=[subnet-12345],securityGroups=[sg-12345],assignPublicIp=DISABLED}'
```

**What:** Creates a long-running service that maintains desired number of tasks
**Why:** Ensures your application stays running and can scale
**How:** Specify cluster, task definition, networking, and replica count

### Update Service

```bash
aws ecs update-service \
  --cluster wise-owl-cluster \
  --service wise-owl-users \
  --force-new-deployment
```

**What:** Triggers a new deployment of the service
**Why:** Deploy new code or restart unhealthy tasks
**How:** Forces ECS to start new tasks with latest task definition

### Check Service Status

```bash
aws ecs describe-services --cluster wise-owl-cluster --services wise-owl-users
```

**What:** Shows current status of your service
**Why:** Monitor deployment progress and health
**How:** Returns JSON with service details, task status, events

## Load Balancer Commands

### Create Application Load Balancer

```bash
aws elbv2 create-load-balancer \
  --name wise-owl-alb \
  --subnets subnet-12345 subnet-67890 \
  --security-groups sg-12345678
```

**What:** Creates an Application Load Balancer for HTTP traffic
**Why:** Distributes traffic across multiple ECS tasks
**How:** Specify public subnets and security groups

### Create Target Group

```bash
aws elbv2 create-target-group \
  --name wise-owl-users-tg \
  --protocol HTTP \
  --port 8081 \
  --vpc-id vpc-12345678 \
  --target-type ip \
  --health-check-path /health/ready
```

**What:** Creates a group that tracks which targets are healthy
**Why:** ALB needs to know where to send traffic
**How:** Specify protocol, port, health check endpoint

### Create Listener

```bash
aws elbv2 create-listener \
  --load-balancer-arn arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/wise-owl-alb/1234567890123456 \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=forward,TargetGroupArn=arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/wise-owl-users-tg/1234567890123456
```

**What:** Defines how the load balancer handles incoming requests
**Why:** Routes HTTP requests to the appropriate target group
**How:** Specify load balancer, protocol, port, and routing rules

## Monitoring and Debugging Commands

### View ECS Logs

```bash
aws logs describe-log-groups --log-group-name-prefix /ecs/wise-owl
```

**What:** Lists CloudWatch log groups for your ECS services
**Why:** Find where your application logs are stored
**How:** Filter by log group prefix

### Get Log Events

```bash
aws logs get-log-events \
  --log-group-name /ecs/wise-owl \
  --log-stream-name ecs/users-service/task-id-here
```

**What:** Retrieves actual log messages from your application
**Why:** Debug application issues and errors
**How:** Specify exact log group and stream

### Check Task Health

```bash
aws ecs describe-tasks --cluster wise-owl-cluster --tasks task-arn-here
```

**What:** Shows detailed information about a specific task
**Why:** Understand why a task stopped or is unhealthy
**How:** Use task ARN from service description

## Security and IAM Commands

### Create IAM Role

```bash
aws iam create-role \
  --role-name wise-owl-ecs-execution-role \
  --assume-role-policy-document file://trust-policy.json
```

**What:** Creates an IAM role that ECS can assume
**Why:** ECS needs permissions to pull images and access secrets
**How:** Specify role name and trust policy (who can use this role)

### Attach Policy to Role

```bash
aws iam attach-role-policy \
  --role-name wise-owl-ecs-execution-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
```

**What:** Gives the role specific permissions
**Why:** The role needs permissions to do its job
**How:** Attach AWS managed policies or custom policies

## Understanding AWS Resource Relationships

```
VPC
├── Public Subnets (ALB lives here)
├── Private Subnets (ECS tasks live here)
├── Security Groups (firewall rules)
└── DocumentDB Subnet Group

ECS Cluster
├── Services (maintain desired task count)
├── Task Definitions (blueprint for containers)
└── Tasks (running container instances)

Application Load Balancer
├── Listeners (handle incoming requests)
├── Target Groups (track healthy targets)
└── Rules (route traffic based on path/host)

Secrets Manager
└── wise-owl/production (JSON with all secrets)
```

**Why this structure matters:**

- ALB in public subnets can receive internet traffic
- ECS tasks in private subnets are protected but can reach internet via NAT
- Security groups control which services can talk to each other
- DocumentDB in private subnets is only accessible from ECS tasks

## Common Command Patterns

### Getting Resource ARNs

Many AWS commands need ARNs (Amazon Resource Names). Get them like this:

```bash
# Get cluster ARN
aws ecs describe-clusters --clusters wise-owl-cluster --query 'clusters[0].clusterArn' --output text

# Get service ARN
aws ecs describe-services --cluster wise-owl-cluster --services wise-owl-users --query 'services[0].serviceArn' --output text

# Get ALB ARN
aws elbv2 describe-load-balancers --names wise-owl-alb --query 'LoadBalancers[0].LoadBalancerArn' --output text
```

### Waiting for Operations

AWS operations are often asynchronous. Use wait commands:

```bash
# Wait for service to stabilize after deployment
aws ecs wait services-stable --cluster wise-owl-cluster --services wise-owl-users

# Wait for load balancer to be available
aws elbv2 wait load-balancer-available --load-balancer-arns arn:aws:elasticloadbalancing:...
```

**What:** Wait commands block until operations complete
**Why:** Ensures next commands don't run on incomplete resources
**How:** AWS CLI polls the service until desired state is reached

This reference helps you understand not just what commands to run, but why each step is necessary and how AWS services work together.
