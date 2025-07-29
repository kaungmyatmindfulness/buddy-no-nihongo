# AWS DocumentDB Migration Guide

This document outlines the migration process from MongoDB to AWS DocumentDB for the Wise Owl production environment while maintaining MongoDB for development.

## Overview

We're implementing a gradual migration approach that:

- Keeps MongoDB for development (fast, local, cost-effective)
- Uses AWS DocumentDB for production (managed, scalable, production-ready)
- Provides backward compatibility during the transition
- Allows service-by-service migration

## Architecture Changes

### Before Migration

```
Development: MongoDB (Docker) → Services
Production:  MongoDB (Docker) → Services
```

### After Migration

```
Development: MongoDB (Docker) → Services
Production:  AWS DocumentDB → Services
```

## Implementation Components

### 1. Database Abstraction Layer

- **Location**: `lib/database/`
- **Files**:
  - `database.go` - Core interfaces and MongoDB implementation
  - `factory.go` - Database creation and configuration
  - `migration.go` - Backward compatibility helpers

### 2. Configuration Updates

- **Location**: `lib/config/config.go`
- **Changes**: Added `DB_TYPE` field to support multiple database types
- **Environment Files**:
  - `.env.example` - Updated with database type configuration
  - `.env.production.example` - Production-specific DocumentDB configuration

### 3. Service Updates

- **Pattern**: Each service updated to use `MigrationHelper`
- **Backward Compatibility**: Services work with both old and new interfaces
- **Feature Flags**: Environment variables control which interface to use

## Migration Steps

### Phase 1: Infrastructure Setup

1. **Set up AWS DocumentDB**

   **Note**: The automated setup script has been temporarily removed. Set up DocumentDB manually through the AWS Console:

   - Create a DocumentDB cluster in AWS Console
   - Configure security groups and access
   - Save the connection details for the next step

2. **Update production environment file**

   ```bash
   # Copy the template
   cp .env.production.example .env.production

   # Update with your DocumentDB connection string
   # DB_TYPE=documentdb
   # MONGODB_URI=mongodb://username:password@cluster.docdb.amazonaws.com:27017/?ssl=true&replicaSet=rs0&readPreference=secondaryPreferred
   ```

3. **Download SSL Certificate**

   ```bash
   # DocumentDB requires SSL, download the certificate
   wget https://s3.amazonaws.com/rds-downloads/rds-ca-2019-root.pem

   # Add to your production environment
   ```

### Phase 2: Service Migration (Gradual)

We recommend migrating services in this order (least critical first):

1. **Quiz Service** (least critical)
2. **Content Service** (medium criticality)
3. **Users Service** (most critical)

#### Per-Service Migration Process:

1. **Enable new interface for the service**

   ```bash
   # Add to .env.production
   MIGRATE_QUIZ_SERVICE=true     # For quiz service
   MIGRATE_CONTENT_SERVICE=true  # For content service
   MIGRATE_USERS_SERVICE=true    # For users service
   ```

2. **Deploy and test**

   ```bash
   # Deploy with new configuration
   docker-compose -f docker-compose.prod.yml up -d quiz-service

   # Check logs for successful connection
   docker logs wo-quiz-service

   # Test functionality
   curl http://localhost:8080/quiz/health
   ```

3. **Monitor and verify**

   - Check application logs
   - Verify data operations
   - Monitor performance metrics
   - Test all critical functionality

4. **Rollback plan** (if needed)

   ```bash
   # Set migration flag to false
   MIGRATE_QUIZ_SERVICE=false

   # Redeploy
   docker-compose -f docker-compose.prod.yml up -d quiz-service
   ```

### Phase 3: Production Deployment

1. **Update production Docker Compose**

   - Use `docker-compose.prod.yml` (already updated)
   - MongoDB service removed
   - All services use DocumentDB

2. **Deploy to production**

   ```bash
   # Build production images
   docker build -t wo-users-service:latest -f services/users/Dockerfile .
   docker build -t wo-content-service:latest -f services/content/Dockerfile .
   docker build -t wo-quiz-service:latest -f services/quiz/Dockerfile .

   # Deploy with DocumentDB configuration
   docker-compose -f docker-compose.prod.yml up -d
   ```

## Development Environment

**No changes required** - development continues to use MongoDB:

```bash
# Development (unchanged)
docker-compose -f docker-compose.dev.yml up -d
```

## Environment Configuration

### Development (.env.local)

```bash
DB_TYPE=mongodb
MONGODB_URI=mongodb://buddy:password@mongodb:27017/?authSource=admin
```

### Production (.env.production)

```bash
DB_TYPE=documentdb
MONGODB_URI=mongodb://username:password@cluster.docdb.amazonaws.com:27017/?ssl=true&replicaSet=rs0&readPreference=secondaryPreferred
```

## Monitoring and Verification

### Health Checks

All services include health checks that work with both MongoDB and DocumentDB:

- `/health` - Basic service health
- `/health/ready` - Database connection verification

### Database Connection Logs

Look for these log messages:

```
Database connection established using new interface.  # DocumentDB
Database connection established using legacy interface.  # MongoDB
```

### Performance Monitoring

- Monitor connection times
- Check query performance
- Verify SSL connectivity for DocumentDB

## Cost Analysis

### Development

- **MongoDB (local)**: $0
- **DocumentDB**: Would add ~$200-400/month

**Recommendation**: Keep MongoDB for development

### Production

- **Current MongoDB**: Server costs + management overhead
- **DocumentDB**: ~$200-400/month + managed benefits

**Benefit**: Managed service, automated backups, monitoring, scaling

## Security Considerations

### DocumentDB Security Features

- Encryption at rest (enabled by default)
- Encryption in transit (SSL/TLS required)
- VPC isolation
- IAM integration
- Automated security patches

### SSL Configuration

DocumentDB requires SSL. The connection string includes `ssl=true` parameter.

## Troubleshooting

### Common Issues

1. **SSL Certificate Error**

   ```bash
   # Download the correct certificate
   wget https://s3.amazonaws.com/rds-downloads/rds-ca-2019-root.pem
   ```

2. **Connection Timeout**

   - Check security group allows port 27017
   - Verify VPC/subnet configuration
   - Ensure services are in same VPC as DocumentDB

3. **Authentication Error**
   - Verify username/password in connection string
   - Check DocumentDB cluster is available

### Rollback Plan

If issues occur during migration:

1. **Immediate rollback**

   ```bash
   # Set migration flags to false
   MIGRATE_USERS_SERVICE=false
   MIGRATE_CONTENT_SERVICE=false
   MIGRATE_QUIZ_SERVICE=false

   # Redeploy
   docker-compose -f docker-compose.prod.yml up -d
   ```

2. **Emergency fallback to MongoDB**
   ```bash
   # Temporarily use old docker-compose with MongoDB
   # (Keep backups of both configurations)
   ```

## Success Criteria

Migration is considered successful when:

- [ ] All services connect to DocumentDB successfully
- [ ] All API endpoints function correctly
- [ ] Performance is acceptable (similar to MongoDB)
- [ ] Monitoring shows healthy database connections
- [ ] No data corruption or loss
- [ ] SSL connections are established properly

## Next Steps

After successful migration:

1. Monitor production for 1-2 weeks
2. Remove old MongoDB containers from production
3. Update deployment scripts
4. Document lessons learned
5. Consider migrating other environments if needed

## Support and Resources

- [AWS DocumentDB Documentation](https://docs.aws.amazon.com/documentdb/)
- [MongoDB Driver Documentation](https://docs.mongodb.com/drivers/go/)
- Internal team documentation in `documents/`

---

For questions or issues during migration, refer to this guide or contact the development team.
