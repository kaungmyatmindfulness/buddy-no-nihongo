#!/bin/bash
# filepath: scripts/utils/common.sh
# Shared utilities and functions for Wise Owl scripts

# Colors for output
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export PURPLE='\033[0;35m'
export CYAN='\033[0;36m'
export WHITE='\033[1;37m'
export NC='\033[0m' # No Color

# Print functions
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_debug() {
    if [ "${DEBUG:-false}" = "true" ]; then
        echo -e "${PURPLE}[DEBUG]${NC} $1"
    fi
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if file exists and is readable
file_exists() {
    [ -f "$1" ] && [ -r "$1" ]
}

# Check if directory exists
dir_exists() {
    [ -d "$1" ]
}

# Get script directory
get_script_dir() {
    cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
}

# Get project root directory
get_project_root() {
    local script_dir=$(get_script_dir)
    # Assumes scripts are in scripts/ subdirectory
    cd "$script_dir/.." && pwd
}

# Check if running in Docker
in_docker() {
    [ -f /.dockerenv ] || grep -q docker /proc/1/cgroup 2>/dev/null
}

# Check if port is available
port_available() {
    local port=$1
    ! lsof -i ":$port" >/dev/null 2>&1
}

# Wait for service to be ready
wait_for_service() {
    local url=$1
    local timeout=${2:-60}
    local interval=${3:-2}
    
    print_info "Waiting for service at $url to be ready..."
    
    for i in $(seq 1 $((timeout / interval))); do
        if curl -s "$url" >/dev/null 2>&1; then
            print_success "Service is ready!"
            return 0
        fi
        sleep $interval
    done
    
    print_error "Service at $url failed to become ready within ${timeout}s"
    return 1
}

# Check Docker and Docker Compose
check_docker() {
    if ! command_exists docker; then
        print_error "Docker is not installed. Please install Docker first."
        return 1
    fi
    
    if ! command_exists "docker compose" && ! command_exists docker-compose; then
        print_error "Docker Compose is not installed. Please install Docker Compose first."
        return 1
    fi
    
    if ! docker info >/dev/null 2>&1; then
        print_error "Docker daemon is not running. Please start Docker first."
        return 1
    fi
    
    return 0
}

# Get Docker Compose command (handles both v1 and v2)
get_docker_compose_cmd() {
    if command_exists "docker compose"; then
        echo "docker compose"
    elif command_exists docker-compose; then
        echo "docker-compose"
    else
        print_error "Neither 'docker compose' nor 'docker-compose' found"
        return 1
    fi
}

# Check if Docker Compose supports watch mode
supports_watch() {
    local compose_cmd=$(get_docker_compose_cmd)
    if [ "$compose_cmd" = "docker compose" ]; then
        $compose_cmd version --format json 2>/dev/null | \
            jq -r '.version' 2>/dev/null | \
            grep -E '^2\.(2[2-9]|[3-9][0-9])' >/dev/null 2>&1
    else
        return 1
    fi
}

# Cleanup function for traps
cleanup() {
    print_info "Cleaning up..."
    # Add any cleanup logic here
}

# Set up trap for cleanup
trap cleanup EXIT INT TERM

# Validate environment file
check_env_file() {
    local env_file=$1
    
    if ! file_exists "$env_file"; then
        print_error "Environment file $env_file not found"
        return 1
    fi
    
    # Check for required variables (customize as needed)
    local required_vars=("MONGO_INITDB_ROOT_USERNAME" "MONGO_INITDB_ROOT_PASSWORD")
    
    for var in "${required_vars[@]}"; do
        if ! grep -q "^${var}=" "$env_file"; then
            print_warning "Required variable $var not found in $env_file"
        fi
    done
    
    return 0
}

# Show ASCII art banner
show_banner() {
    local title=${1:-"Wise Owl"}
    
    echo -e "${GREEN}"
    cat << "EOF"
 _       _____              ____          __
| |     / (_)_______      / __ \_      _/ /
| | /| / / / ___/ _ \    / / / / | /| / / / 
| |/ |/ / (__  )  __/   / /_/ /| |/ |/ / /  
|__/|__/_/____/\___/    \____/ |__/|__/_/   
EOF
    echo -e "${WHITE}${title}${NC}"
    echo -e "${NC}"
}
