# Environment Configuration Guide

This project uses the standard `.env.example` naming convention for environment templates.

## 📁 File Structure

```
.env.example              # General environment template (if needed)
.env.local.example        # Local development template
.env.aws.example          # AWS deployment template  
.env.production.example   # Production environment template

.env.local               # Your actual local config (gitignored)
.env.production          # Your actual production config (gitignored)
.env.staging             # Your actual staging config (gitignored)
```

## 🚀 Quick Setup

### Local Development
```bash
# Copy template and customize
cp .env.local.example .env.local
# Edit .env.local with your values
```

### AWS Deployment
```bash
# Copy template and customize
cp .env.aws.example .env.production
# Edit .env.production with your AWS values
```

## 🔒 Security

- ✅ **`.env.*.example` files** are committed (safe templates)
- ❌ **`.env.*` actual files** are gitignored (contain secrets)

## 📝 Adding New Environment Variables

1. Add to appropriate `.env.*.example` template
2. Update this guide if needed
3. Notify team members to update their local files

## 🌍 Environment-Specific Differences

| Variable | Local (.env.local.example) | AWS (.env.aws.example) |
|----------|---------------------------|------------------------|
| `ENVIRONMENT` | `development` | `production` |
| `DB_TYPE` | `mongodb` | `documentdb` |
| `LOG_LEVEL` | `debug` | `info` |
| `MONGODB_URI` | Local Docker | AWS Secrets Manager |
| Service URLs | Docker Compose | ECS Service Discovery |

## 🛠️ Validation

Test your environment setup:
```bash
# Local development
./wise-owl dev test

# AWS deployment
./scripts/deploy-aws.sh validate
```
