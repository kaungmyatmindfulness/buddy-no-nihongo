# AWS Manual Setup Guide for Wise Owl Microservices

This guide will walk you through manually setting up AWS infrastructure for the Wise Owl Japanese vocabulary learning platform. Perfect for beginners who want to understand each step!

## Prerequisites

1. AWS Account with appropriate permissions
2. AWS CLI installed and configured
3. Docker installed locally
4. Domain name (optional, can use ALB DNS initially)

## Phase 1: VPC and Networking Setup

### Step 1: Create VPC

1. Go to **AWS Console > VPC Dashboard**
2. Click **"Create VPC"**
3. Choose **"VPC and more"** (this creates everything at once)
4. Configure:
   - **Name**: `wise-owl-vpc`
   - **IPv4 CIDR**: `10.0.0.0/16`
   - **Number of AZs**: 2
   - **Number of public subnets**: 2
   - **Number of private subnets**: 2
   - **NAT gateways**: 1 per AZ
   - **VPC endpoints**: None
5. Click **"Create VPC"**

This creates:

- 1 VPC
- 2 public subnets (for load balancer)
- 2 private subnets (for your services)
- Internet Gateway
- NAT Gateways
- Route tables

### Step 2: Verify Network Setup

After creation, verify you have:

- Public subnets: `10.0.0.0/24`, `10.0.1.0/24`
- Private subnets: `10.0.128.0/24`, `10.0.129.0/24`

## Phase 2: Security Groups

### Step 3: Create Security Groups

#### ALB Security Group

1. Go to **VPC > Security Groups**
2. Click **"Create security group"**
3. Configure:
   - **Name**: `wise-owl-alb-sg`
   - **Description**: `Security group for Application Load Balancer`
   - **VPC**: Select your `wise-owl-vpc`
4. **Inbound rules**:
   - HTTP: Port 80, Source: 0.0.0.0/0
   - HTTPS: Port 443, Source: 0.0.0.0/0
5. **Outbound rules**: Keep default (All traffic)
6. Click **"Create security group"**

#### ECS Services Security Group

1. Create another security group:
   - **Name**: `wise-owl-ecs-sg`
   - **Description**: `Security group for ECS services`
   - **VPC**: Select your `wise-owl-vpc`
2. **Inbound rules**:
   - Custom TCP: Port 8081, Source: ALB security group ID
   - Custom TCP: Port 8082, Source: ALB security group ID
   - Custom TCP: Port 8083, Source: ALB security group ID
   - Custom TCP: Port 50051-50053, Source: Same security group (self)
3. **Outbound rules**: Keep default

#### DocumentDB Security Group

1. Create third security group:
   - **Name**: `wise-owl-documentdb-sg`
   - **Description**: `Security group for DocumentDB`
   - **VPC**: Select your `wise-owl-vpc`
2. **Inbound rules**:
   - Custom TCP: Port 27017, Source: ECS security group ID
3. **Outbound rules**: Keep default

## Phase 3: DocumentDB Setup

### Step 4: Create DocumentDB Subnet Group

1. Go to **Amazon DocumentDB > Subnet groups**
2. Click **"Create subnet group"**
3. Configure:
   - **Name**: `wise-owl-docdb-subnet-group`
   - **Description**: `Subnet group for Wise Owl DocumentDB`
   - **VPC**: Select your `wise-owl-vpc`
   - **Subnets**: Select both **private subnets**
4. Click **"Create"**

### Step 5: Create DocumentDB Cluster

1. Go to **Amazon DocumentDB > Clusters**
2. Click **"Create"**
3. **Configuration**:
   - **Engine version**: 4.0.0
   - **Cluster identifier**: `wise-owl-docdb-cluster`
4. **Credentials**:
   - **Master username**: `wiseowl`
   - **Master password**: Create a strong password (save it!)
5. **Connectivity**:
   - **VPC**: `wise-owl-vpc`
   - **Subnet group**: `wise-owl-docdb-subnet-group`
   - **Security groups**: `wise-owl-documentdb-sg`
6. **Additional configuration**:
   - **Backup retention**: 7 days
   - **Encryption**: Enable
7. Click **"Create cluster"**

### Step 6: Add DocumentDB Instances

1. After cluster creation, click on the cluster
2. Click **"Add instance"**
3. Configure:
   - **Instance class**: `db.t3.medium` (for learning/testing)
   - **Instance identifier**: `wise-owl-docdb-instance-1`
4. Repeat to create a second instance for high availability

## Phase 4: ECR Repositories

### Step 7: Create ECR Repositories

1. Go to **Amazon ECR > Repositories**
2. Create repositories for each service:
   - Click **"Create repository"**
   - **Repository name**: `wise-owl-users`
   - **Image tag mutability**: Mutable
   - **Scan on push**: Enable
   - Click **"Create repository"**
3. Repeat for:
   - `wise-owl-content`
   - `wise-owl-quiz`
   - `wise-owl-nginx`

## Phase 5: Secrets Manager

### Step 8: Store Sensitive Configuration

1. Go to **AWS Secrets Manager > Secrets**
2. Click **"Store a new secret"**
3. **Secret type**: Other type of secret
4. **Key/value pairs**:
   ```
   MONGODB_URI: mongodb://wiseowl:YOUR_PASSWORD@YOUR_DOCDB_ENDPOINT:27017/?ssl=true&replicaSet=rs0&readPreference=secondaryPreferred
   JWT_SECRET: your-jwt-secret-here
   AUTH0_DOMAIN: your-auth0-domain (optional)
   AUTH0_AUDIENCE: your-auth0-audience (optional)
   ```
5. **Secret name**: `wise-owl/production`
6. Click through to create

## Phase 6: ECS Cluster and Task Definitions

### Step 9: Create ECS Cluster

1. Go to **Amazon ECS > Clusters**
2. Click **"Create cluster"**
3. Configure:
   - **Cluster name**: `wise-owl-cluster`
   - **Infrastructure**: AWS Fargate (serverless)
4. Click **"Create"**

### Step 10: Create IAM Roles

#### ECS Task Execution Role

1. Go to **IAM > Roles**
2. Click **"Create role"**
3. **Trusted entity**: AWS service → Elastic Container Service → Elastic Container Service Task
4. **Permissions**: `AmazonECSTaskExecutionRolePolicy`
5. **Role name**: `wise-owl-ecs-execution-role`

#### ECS Task Role (for accessing AWS services)

1. Create another role:
2. **Trusted entity**: AWS service → Elastic Container Service → Elastic Container Service Task
3. Create custom policy with these permissions:
   ```json
   {
   	"Version": "2012-10-17",
   	"Statement": [
   		{
   			"Effect": "Allow",
   			"Action": [
   				"secretsmanager:GetSecretValue",
   				"ssm:GetParameter",
   				"ssm:GetParameters",
   				"kms:Decrypt"
   			],
   			"Resource": "*"
   		}
   	]
   }
   ```
4. **Role name**: `wise-owl-ecs-task-role`

### Step 11: Create Task Definitions

For each service (users, content, quiz), create a task definition:

1. Go to **Amazon ECS > Task definitions**
2. Click **"Create new task definition"**
3. Configure:

   - **Task definition family**: `wise-owl-users`
   - **Launch type**: AWS Fargate
   - **CPU**: 0.5 vCPU
   - **Memory**: 1 GB
   - **Task role**: `wise-owl-ecs-task-role`
   - **Task execution role**: `wise-owl-ecs-execution-role`

4. **Container definition**:

   - **Container name**: `users-service`
   - **Image**: `YOUR_ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/wise-owl-users:latest`
   - **Port mappings**: 8081 (HTTP), 50051 (gRPC)
   - **Environment variables**:
     - `PORT`: 8081
     - `GRPC_PORT`: 50051
     - `AWS_EXECUTION_ENV`: AWS_ECS_FARGATE
     - `DB_TYPE`: documentdb
   - **Secrets** (from Secrets Manager):
     - `MONGODB_URI`: wise-owl/production:MONGODB_URI::
     - `JWT_SECRET`: wise-owl/production:JWT_SECRET::

5. **Health check**:
   - **Command**: `CMD-SHELL,curl -f http://localhost:8081/health/ready || exit 1`
   - **Interval**: 30 seconds
   - **Timeout**: 5 seconds
   - **Retries**: 3

Repeat similar configurations for `content` (port 8082/50052) and `quiz` (port 8083/50053).

## Phase 7: Application Load Balancer

### Step 12: Create Application Load Balancer

1. Go to **EC2 > Load Balancers**
2. Click **"Create Load Balancer"**
3. Choose **"Application Load Balancer"**
4. Configure:
   - **Name**: `wise-owl-alb`
   - **Scheme**: Internet-facing
   - **VPC**: `wise-owl-vpc`
   - **Availability Zones**: Select both public subnets
   - **Security groups**: `wise-owl-alb-sg`

### Step 13: Create Target Groups

For each service, create a target group:

1. Go to **EC2 > Target Groups**
2. Click **"Create target group"**
3. Configure:
   - **Target type**: IP addresses
   - **Target group name**: `wise-owl-users-tg`
   - **Protocol**: HTTP
   - **Port**: 8081
   - **VPC**: `wise-owl-vpc`
   - **Health check path**: `/api/v1/users/health/ready`
4. Click **"Create"**

Repeat for content (port 8082) and quiz (port 8083).

### Step 14: Configure ALB Listeners

1. Go back to your Load Balancer
2. **Listeners tab** > **Add listener**
3. **HTTP:80** → Redirect to HTTPS:443
4. **HTTPS:443** → Default action: Return fixed response (404)
5. **Add rules** for each service:
   - Path pattern: `/api/v1/users/*` → Forward to `wise-owl-users-tg`
   - Path pattern: `/api/v1/content/*` → Forward to `wise-owl-content-tg`
   - Path pattern: `/api/v1/quiz/*` → Forward to `wise-owl-quiz-tg`

## Phase 8: Build and Deploy

### Step 15: Build and Push Docker Images

```bash
# Login to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin YOUR_ACCOUNT.dkr.ecr.us-east-1.amazonaws.com

# Build production images
docker build -t wise-owl-users:latest -f services/users/Dockerfile.aws .
docker build -t wise-owl-content:latest -f services/content/Dockerfile.aws .
docker build -t wise-owl-quiz:latest -f services/quiz/Dockerfile.aws .

# Tag and push
for service in users content quiz; do
    docker tag wise-owl-$service:latest YOUR_ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/wise-owl-$service:latest
    docker push YOUR_ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/wise-owl-$service:latest
done
```

### Step 16: Create ECS Services

For each service:

1. Go to **ECS > Clusters > wise-owl-cluster**
2. **Services tab** > **Create**
3. Configure:
   - **Launch type**: Fargate
   - **Task definition**: `wise-owl-users`
   - **Service name**: `wise-owl-users`
   - **Number of tasks**: 2
   - **VPC**: `wise-owl-vpc`
   - **Subnets**: Select private subnets
   - **Security groups**: `wise-owl-ecs-sg`
   - **Auto-assign public IP**: Disabled
   - **Load balancer**: Application Load Balancer
   - **Target group**: `wise-owl-users-tg`

## Phase 9: Testing and Monitoring

### Step 17: Test Your Deployment

1. Get ALB DNS name from EC2 console
2. Test endpoints:
   ```bash
   curl http://YOUR_ALB_DNS/api/v1/users/health
   curl http://YOUR_ALB_DNS/api/v1/content/health
   curl http://YOUR_ALB_DNS/api/v1/quiz/health
   ```

### Step 18: Set Up CloudWatch (Optional)

1. Go to **CloudWatch > Dashboards**
2. Create custom dashboard to monitor:
   - ALB request count and latency
   - ECS CPU and memory usage
   - DocumentDB connections

## Cost Optimization Tips for Beginners

1. **Start Small**: Use `db.t3.medium` for DocumentDB and 0.5 vCPU for ECS
2. **Single AZ**: For learning, you can use single AZ to reduce NAT Gateway costs
3. **Scheduled Scaling**: Scale down services during off-hours
4. **CloudWatch**: Set up billing alerts to monitor costs

## Troubleshooting Common Issues

### Service Won't Start

- Check CloudWatch logs in ECS task details
- Verify security group allows traffic on correct ports
- Ensure DocumentDB connection string is correct

### Health Checks Failing

- Test health endpoints locally first
- Check if service is binding to 0.0.0.0, not localhost
- Verify health check path matches your service

### Can't Connect to DocumentDB

- Ensure ECS tasks are in private subnets
- Check security group allows port 27017
- Verify DocumentDB endpoint is correct

## Next Steps

Once everything is working:

1. Set up a custom domain with Route 53
2. Add SSL certificate with ACM
3. Implement blue-green deployments
4. Add monitoring and alerting
5. Set up automated backups

This manual approach helps you understand each AWS service and how they work together. Once comfortable, you can later move to Infrastructure as Code for automation!
