# Quick Start Checklist for AWS Manual Deployment

## Before You Start

- [ ] AWS Account with admin access
- [ ] AWS CLI installed and configured
- [ ] Docker installed locally
- [ ] Your Wise Owl project ready

## Phase 1: Network Setup (30 minutes)

- [ ] Create VPC with public/private subnets
- [ ] Create 3 Security Groups (ALB, ECS, DocumentDB)
- [ ] Note down subnet IDs and security group IDs

## Phase 2: Database (45 minutes)

- [ ] Create DocumentDB subnet group
- [ ] Create DocumentDB cluster
- [ ] Add 2 instances to cluster
- [ ] Note down DocumentDB endpoint

## Phase 3: Container Registry (15 minutes)

- [ ] Create 4 ECR repositories (users, content, quiz, nginx)
- [ ] Note down repository URLs

## Phase 4: Secrets (10 minutes)

- [ ] Create secrets in AWS Secrets Manager
- [ ] Store DocumentDB connection string, JWT secret, Auth0 configs

## Phase 5: ECS Setup (60 minutes)

- [ ] Create ECS cluster
- [ ] Create 2 IAM roles (execution & task roles)
- [ ] Create 3 task definitions (users, content, quiz)
- [ ] Test task definitions locally first

## Phase 6: Load Balancer (30 minutes)

- [ ] Create Application Load Balancer
- [ ] Create 3 target groups
- [ ] Configure listener rules for routing

## Phase 7: Deploy & Test (45 minutes)

- [ ] Build and push Docker images to ECR
- [ ] Create 3 ECS services
- [ ] Test health endpoints
- [ ] Verify service communication

## Quick Commands

### ECR Login

```bash
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin YOUR_ACCOUNT.dkr.ecr.us-east-1.amazonaws.com
```

### Build & Push

```bash
docker build -t wise-owl-users:latest -f services/users/Dockerfile.aws .
docker tag wise-owl-users:latest YOUR_ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/wise-owl-users:latest
docker push YOUR_ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/wise-owl-users:latest
```

### Test Health

```bash
curl http://YOUR_ALB_DNS/api/v1/users/health
```

## Common Mistakes to Avoid

1. **Security Groups**: Make sure ports match your services
2. **Subnets**: ECS services go in private subnets, ALB in public
3. **Health Checks**: Use the correct health check path in target groups
4. **Environment Variables**: Set AWS_EXECUTION_ENV=AWS_ECS_FARGATE
5. **Database Connection**: Use DocumentDB endpoint, not localhost

## Estimated Costs (Monthly)

- DocumentDB: ~$300 (2 instances)
- ECS Fargate: ~$150 (6 tasks)
- ALB: ~$25
- Other services: ~$25
- **Total**: ~$500/month

## Next Steps After Basic Setup

1. Add custom domain with Route 53
2. Add SSL certificate
3. Set up CloudWatch monitoring
4. Implement blue-green deployments
5. Add auto-scaling

## Getting Help

- AWS documentation for each service
- CloudWatch logs for debugging
- ECS service events for deployment issues
- Community forums and Stack Overflow
