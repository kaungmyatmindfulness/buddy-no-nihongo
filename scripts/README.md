# Scripts Documentation

## Overview

The Wise Owl project uses a structured approach to script organization with two main categories:

- **Development**: Scripts for local development environment management
- **Utilities**: Shared functions and utilities used by other scripts

## Quick Start

Use the main entry point script for easy access:

```bash
# Development
./wise-owl dev setup     # Initial setup
./wise-owl dev start     # Start services
./wise-owl dev watch     # Start with hot reload

# Testing
./wise-owl dev test      # Health check
./wise-owl dev status    # Service status

# Monitoring
./wise-owl monitor start # Start monitoring stack
./wise-owl monitor system # System monitoring info
```

## Directory Structure

```text
scripts/
├── development/         # Development environment scripts
│   ├── dev.sh          # Main development management script
│   ├── dev-watch.sh    # Hot reload development
│   └── test-dev.sh     # Health check and testing
├── utils/              # Shared utilities
│   └── common.sh       # Common functions and utilities
└── README.md           # This documentation
```

**Note**: Deployment scripts have been temporarily removed and will be added back later.

## Development Scripts

### dev.sh

Main development environment management script.

**Usage:**

```bash
./scripts/development/dev.sh [command]
# or
./wise-owl dev [command]
```

**Commands:**

- `setup` - Create .env.local from example
- `start` - Start all services in development mode
- `stop` - Stop all services
- `restart` - Restart all services
- `logs [service]` - Show logs (all services or specific service)
- `build` - Rebuild all development containers
- `clean` - Stop and remove all containers and volumes
- `status` - Show status of all services

**Features:**

- Validates Docker and Docker Compose installation
- Checks for required environment files
- Provides colored output for better readability
- Handles both docker-compose v1 and v2 syntax

### dev-watch.sh

Starts development environment with Docker Compose watch mode for automatic reloading.

**Usage:**

```bash
./scripts/development/dev-watch.sh
# or
./wise-owl dev watch
```

**Features:**

- Automatically detects Docker Compose watch support (requires v2.22+)
- Falls back to regular mode if watch is not supported
- Creates necessary temporary directories
- Provides real-time file change feedback

### test-dev.sh

Health check script for development environment.

**Usage:**

```bash
./scripts/development/test-dev.sh
# or
./wise-owl dev test
```

**Features:**

- Tests all microservices health endpoints
- Tests API gateway connectivity
- Provides summary of service status
- Returns appropriate exit codes for CI/CD integration

## Utility Scripts

### common.sh

Shared functions and utilities used by other scripts.

**Features:**

- Colored output functions (print_info, print_warning, print_error, etc.)
- Docker and Docker Compose compatibility checking
- Environment file validation
- Service health checking utilities
- Path and directory utilities
- ASCII art banner display

**Usage:**

```bash
# Load in other scripts
source "$(dirname "$0")/utils/common.sh"

# Use functions
print_info "Starting operation..."
check_docker || exit 1
wait_for_service "http://localhost:8080/health"
```

## Environment Files

The scripts work with different environment files:

- `.env.example` - Template with all available options
- `.env.local` - Development environment (git-ignored)

**Note**: References to `.env.docker` deployment environment have been removed as deployment scripts are temporarily unavailable.

## Error Handling

All scripts include:

- `set -e` for immediate exit on errors
- Input validation and prerequisite checking
- Meaningful error messages with suggested solutions
- Cleanup functions for graceful shutdown

## Customization

### Adding New Development Commands

Edit `scripts/development/dev.sh` and add new cases to the main switch statement.

### Adding New Utilities

Add functions to `scripts/utils/common.sh` and they'll be available to all scripts.

## Troubleshooting

### Common Issues

1. **Permission Denied**

   ```bash
   chmod +x scripts/**/*.sh
   ```

2. **Docker Not Running**

   ```bash
   sudo systemctl start docker
   ```

3. **Environment File Missing**

   ```bash
   ./wise-owl dev setup
   ```

4. **Port Conflicts**
   - Check for other services using ports 8080-8083, 27017
   - Use `docker ps` to see running containers

### Debug Mode

Enable debug output:

```bash
DEBUG=true ./wise-owl dev start
```

### Log Access

View service logs:

```bash
./wise-owl dev logs              # All services
./wise-owl dev logs mongodb      # Specific service
```

## Integration with IDEs

### VS Code Tasks

The scripts can be integrated with VS Code tasks in `.vscode/tasks.json`:

```json
{
	"version": "2.0.0",
	"tasks": [
		{
			"label": "Start Development",
			"type": "shell",
			"command": "./wise-owl dev start",
			"group": "build"
		}
	]
}
```

### Command Aliases

Add to your shell profile:

```bash
alias wo='./wise-owl'
alias wo-start='./wise-owl dev start'
alias wo-stop='./wise-owl dev stop'
alias wo-test='./wise-owl dev test'
```
