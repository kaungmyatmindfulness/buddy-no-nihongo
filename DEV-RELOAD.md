# Development Hot Reload Setup

## Quick Start

```bash
# Option 1: Full Docker development stack with hot reload
docker-compose -f docker-compose.dev.yml up --build

# Option 2: Services only (without nginx)
docker-compose -f docker-compose.dev.yml up --build mongodb users-service content-service quiz-service

# Option 3: MongoDB only, run services locally
docker-compose -f docker-compose.dev.yml up -d mongodb
# Then run each service locally:
cd services/users && go run cmd/main.go
cd services/content && go run cmd/main.go
cd services/quiz && go run cmd/main.go
```

## 🔧 How Hot Reload Works

### Air Hot Reload Configuration

Each service uses [Air](https://github.com/air-verse/air) with custom `.air.toml` files:

- **File Locations:**

  - `services/users/.air.toml` - Users service config
  - `services/content/.air.toml` - Content service config
  - `services/quiz/.air.toml` - Quiz service config

- **Watched Directories:** `services/{service}/`, `lib/`, `gen/`
- **File Extensions:** `.go`, `.json`, `.html`, `.tmpl`
- **Excluded:** `tmp/`, `vendor/`, `testdata/`, `.git/`

### Docker Volume Mounts

```yaml
volumes:
  - ".:/app" # Mount entire project
  - "/app/tmp" # Exclude tmp directory
  - "/app/vendor" # Exclude vendor for performance
  - "go-mod-cache:/go/pkg/mod" # Cache Go modules
```

## 🌐 Service Access

- **API Gateway (Nginx):** http://localhost:80
- **Users Service:** http://localhost:8081 (direct access)
- **Content Service:** http://localhost:8082 (direct access)
- **Quiz Service:** http://localhost:8083 (direct access)
- **MongoDB:** localhost:27017

## 📝 Development Workflow

1. **Start Services:** `docker-compose -f docker-compose.dev.yml up --build`
2. **Edit Code:** Make changes to any `.go` files in `services/`, `lib/`, or `gen/`
3. **Auto Reload:** Air detects changes and rebuilds/restarts automatically (~1-3 seconds)
4. **View Logs:** Watch terminal output for build status and runtime logs
5. **Test Changes:** Services are immediately available with your changes

## Auto-Reload Features

### What Gets Auto-Reloaded

- **Service Code Changes**: Any changes to `services/*/` will trigger automatic rebuild and restart
- **Shared Library Changes**: Changes to `lib/` are synced immediately
- **Generated Code Changes**: Changes to `gen/` are synced immediately
- **Workspace Changes**: Changes to `go.work` trigger full rebuilds

### File Watching Details

- **Air Hot Reload**: Each service uses Air for fast Go rebuilds on file changes
- **Docker Compose Watch**: Modern watch mode for efficient file syncing
- **Module Cache**: Shared Go module cache for faster builds
- **Polling**: Enabled for better compatibility with different file systems

### Performance Optimizations

- Excluded directories: `tmp/`, `vendor/`, `testdata/`, `.git/`
- Go module caching between containers
- Efficient file syncing vs full rebuilds
- Fast process restart with proper signal handling

## 🛠 Troubleshooting

### Services Not Starting

```bash
# Check individual service logs
docker-compose -f docker-compose.dev.yml logs users-service
docker-compose -f docker-compose.dev.yml logs content-service
docker-compose -f docker-compose.dev.yml logs quiz-service
```

### Hot Reload Not Working

1. Ensure changes are in watched directories (`services/`, `lib/`, `gen/`)
2. Check file extensions (`.go`, `.json`, etc.)
3. Verify volume mounts: `docker-compose -f docker-compose.dev.yml exec users-service ls -la`

### Build Errors

```bash
# Rebuild specific service
docker-compose -f docker-compose.dev.yml build users-service
docker-compose -f docker-compose.dev.yml up users-service
```

### Complete Reset

```bash
# Stop everything
docker-compose -f docker-compose.dev.yml down

# Remove volumes and rebuild
docker-compose -f docker-compose.dev.yml down -v
docker-compose -f docker-compose.dev.yml up --build
```

If hot reload isn't working:

1. **Check Docker Compose version**: Watch mode requires 2.22+

   ```bash
   docker compose version
   ```

2. **Fall back to standard mode**:

   ```bash
   ./dev.sh start
   ```

## 📦 Go Workspace Integration

This project uses Go Workspaces for monorepo management:

```bash
# Sync workspace dependencies
go work sync

# Add new module to workspace
go work use ./new-service
```

All services and libraries work together seamlessly through the workspace configuration.

3. **Manual rebuild**:

   ```bash
   ./dev.sh build
   ```

4. **Check logs**:

   ```bash
   ./dev.sh logs [service-name]
   ```
