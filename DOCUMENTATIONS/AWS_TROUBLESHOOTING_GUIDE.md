# AWS Deployment Troubleshooting Guide

This guide helps you diagnose and solve common issues when manually deploying Wise Owl microservices to AWS.

## Common Configuration Issues

### Issue: Application Won't Start in ECS

**Symptoms:**

- ECS task stops immediately after starting
- Health checks fail
- No logs in CloudWatch

**Diagnosis Commands:**

```bash
# Check task status
aws ecs describe-tasks --cluster wise-owl-cluster --tasks TASK_ARN

# Check stopped tasks and reasons
aws ecs list-tasks --cluster wise-owl-cluster --desired-status STOPPED

# View task definition
aws ecs describe-task-definition --task-definition wise-owl-users
```

**Common Causes & Solutions:**

1. **Missing or incorrect secrets**

   ```bash
   # Verify secret exists
   aws secretsmanager get-secret-value --secret-id wise-owl/production

   # Check secret format (should be valid JSON)
   aws secretsmanager get-secret-value --secret-id wise-owl/production --query SecretString --output text | jq .
   ```

2. **IAM permission issues**

   ```bash
   # Check if task role can access secrets
   aws iam simulate-principal-policy \
     --policy-source-arn arn:aws:iam::ACCOUNT:role/wise-owl-ecs-execution-role \
     --action-names secretsmanager:GetSecretValue \
     --resource-arns arn:aws:secretsmanager:us-east-1:ACCOUNT:secret:wise-owl/production
   ```

3. **Image pull failures**

   ```bash
   # Verify image exists in ECR
   aws ecr describe-images --repository-name wise-owl-users

   # Check ECR permissions
   aws ecr get-repository-policy --repository-name wise-owl-users
   ```

### Issue: Health Checks Failing

**Symptoms:**

- ALB shows unhealthy targets
- ECS tasks restart frequently
- 503 errors from load balancer

**Diagnosis:**

```bash
# Test health endpoint directly on task
PUBLIC_IP=$(aws ecs describe-tasks --cluster wise-owl-cluster --tasks TASK_ARN --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' --output text | xargs aws ec2 describe-network-interfaces --network-interface-ids {} --query 'NetworkInterfaces[0].Association.PublicIp' --output text)

curl -v http://$PUBLIC_IP:8081/health/ready
```

**Solutions:**

1. **Increase health check timeout in task definition**
2. **Check application logs for startup issues**
3. **Verify health endpoint implementation**

### Issue: Database Connection Problems

**Symptoms:**

- Application starts but health checks show database disconnected
- MongoDB/DocumentDB connection errors in logs

**Diagnosis:**

```bash
# Check DocumentDB cluster status
aws docdb describe-db-clusters --db-cluster-identifier wise-owl-docdb-cluster

# Verify DocumentDB security group allows ECS access
aws ec2 describe-security-groups --group-ids DOCDB_SECURITY_GROUP_ID
```

**Solutions:**

1. **Check DocumentDB endpoint and port in secrets**
2. **Verify security group rules allow port 27017**
3. **Ensure ECS tasks are in correct subnets**

## Network and Security Issues

### Issue: Cannot Access Application

**Symptoms:**

- Tasks start successfully but application unreachable
- Timeout errors when accessing ALB

**Diagnosis:**

```bash
# Check security group rules
aws ec2 describe-security-groups --group-ids SECURITY_GROUP_ID

# Verify ALB target health
aws elbv2 describe-target-health --target-group-arn TARGET_GROUP_ARN

# Check route tables and subnets
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=VPC_ID"
```

### Issue: Service Discovery Problems

**Symptoms:**

- Services can't communicate with each other
- gRPC calls fail between services

**Solutions:**

1. **Use ECS Service Discovery for internal communication**
2. **Configure proper security group rules for inter-service traffic**
3. **Use private subnets with NAT Gateway for egress**

## Performance and Scaling Issues

### Issue: Application Running Slowly

**Diagnosis:**

```bash
# Check CloudWatch metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name CPUUtilization \
  --dimensions Name=ServiceName,Value=wise-owl-users Name=ClusterName,Value=wise-owl-cluster \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average
```

**Solutions:**

1. **Increase CPU/memory allocation in task definition**
2. **Optimize Go application for container environment**
3. **Add auto-scaling policies**

## Cost Optimization Issues

### Issue: Unexpected High Costs

**Diagnosis Commands:**

```bash
# Check running tasks
aws ecs list-tasks --cluster wise-owl-cluster

# View Fargate usage
aws ce get-dimension-values \
  --dimension SERVICE \
  --time-period Start=2024-01-01,End=2024-01-31 \
  --search-string Fargate

# Check DocumentDB usage
aws docdb describe-db-clusters --query 'DBClusters[].{Name:DBClusterIdentifier,Status:Status,Engine:Engine}'
```

**Cost Reduction Strategies:**

1. **Right-size Fargate CPU/memory allocations**
2. **Use Fargate Spot for non-critical workloads**
3. **Implement auto-scaling to reduce idle capacity**
4. **Schedule non-critical services to run only during business hours**

## Debugging Workflow

### Step 1: Check Application Logs

```bash
# View recent logs
aws logs tail /ecs/wise-owl --follow

# Search for specific errors
aws logs filter-log-events \
  --log-group-name /ecs/wise-owl \
  --filter-pattern "ERROR"
```

### Step 2: Verify AWS Resources

```bash
# Quick resource check script
echo "=== ECS Cluster ==="
aws ecs describe-clusters --clusters wise-owl-cluster --query 'clusters[0].status'

echo "=== Running Tasks ==="
aws ecs list-tasks --cluster wise-owl-cluster --desired-status RUNNING

echo "=== ECR Images ==="
aws ecr describe-repositories --query 'repositories[].repositoryName'

echo "=== Secrets ==="
aws secretsmanager list-secrets --query 'SecretList[?starts_with(Name, `wise-owl`)].Name'
```

### Step 3: Test Local vs AWS Configuration

```bash
# Test AWS config loading locally (requires AWS credentials)
export AWS_EXECUTION_ENV=AWS_ECS_FARGATE
go run services/users/cmd/main_aws.go

# Compare with local config
unset AWS_EXECUTION_ENV
go run services/users/cmd/main.go
```

## Emergency Procedures

### Rollback Deployment

```bash
# List task definition revisions
aws ecs list-task-definitions --family-prefix wise-owl-users

# Update service to previous revision
aws ecs update-service \
  --cluster wise-owl-cluster \
  --service wise-owl-users \
  --task-definition wise-owl-users:PREVIOUS_REVISION
```

### Scale Down for Cost Control

```bash
# Scale service to 0 instances
aws ecs update-service \
  --cluster wise-owl-cluster \
  --service wise-owl-users \
  --desired-count 0

# Stop all running tasks
aws ecs list-tasks --cluster wise-owl-cluster --query 'taskArns' --output text | \
xargs -I {} aws ecs stop-task --cluster wise-owl-cluster --task {}
```

### Enable Debug Logging

```bash
# Update task definition with debug environment variables
# Add to containerDefinitions.environment:
{
  "name": "LOG_LEVEL",
  "value": "debug"
}

# Register new task definition and update service
```

## Prevention Strategies

### Monitoring Setup

```bash
# Create CloudWatch dashboard for monitoring
aws cloudwatch put-dashboard \
  --dashboard-name WiseOwl-Health \
  --dashboard-body file://dashboard-config.json

# Set up billing alerts
aws cloudwatch put-metric-alarm \
  --alarm-name wise-owl-cost-alert \
  --alarm-description "Alert when costs exceed threshold" \
  --metric-name EstimatedCharges \
  --namespace AWS/Billing \
  --statistic Maximum \
  --period 86400 \
  --threshold 100 \
  --comparison-operator GreaterThanThreshold
```

### Automated Health Checks

```bash
# Create health check script
cat > health-check.sh << 'EOF'
#!/bin/bash
ALB_DNS="your-alb-dns-name"
for service in users content quiz; do
  response=$(curl -s -o /dev/null -w "%{http_code}" http://$ALB_DNS/api/v1/$service/health)
  if [ $response -eq 200 ]; then
    echo "✅ $service healthy"
  else
    echo "❌ $service unhealthy (HTTP $response)"
  fi
done
EOF

chmod +x health-check.sh
```

### Regular Maintenance Tasks

```bash
# Clean up old task definitions (keep last 5 revisions)
aws ecs list-task-definitions --family-prefix wise-owl-users --sort DESC | \
jq -r '.taskDefinitionArns[5:][]' | \
xargs -I {} aws ecs deregister-task-definition --task-definition {}

# Clean up old ECR images (keep last 10 images)
aws ecr list-images --repository-name wise-owl-users --query 'imageIds[10:]' | \
xargs -I {} aws ecr batch-delete-image --repository-name wise-owl-users --image-ids {}
```

This troubleshooting guide helps you systematically diagnose and resolve issues during your AWS deployment learning journey!
