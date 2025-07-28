#!/bin/bash
# Simple VPS Setup Script for Wise Owl Deployment

set -e

# Configuration
CURRENT_USER="$(logname 2>/dev/null || echo $SUDO_USER)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    print_error "This script must be run as root"
    exit 1
fi

# ASCII Art
echo -e "${BLUE}"
cat << "EOF"
 __        ___          ___           _ 
 \ \      / (_)___  ___/ _ \__      _| |
  \ \ /\ / /| / __|/ _ \ | | \ \ /\ / / |
   \ V  V / | \__ \  __/ |_| |\ V  V /| |
    \_/\_/  |_|___/\___|\___/  \_/\_/ |_|
                                        
EOF
echo -e "${NC}"

print_info "Starting Wise Owl VPS Setup..."

# ========================================
# PHASE 1: System Updates
# ========================================
print_info "Phase 1: System Updates"

print_step "Updating package lists..."
apt update

print_step "Upgrading system packages..."
apt upgrade -y

print_step "Installing essential packages..."
apt install -y \
    curl \
    wget \
    vim \
    git \
    ufw \
    fail2ban \
    ca-certificates \
    gnupg \
    lsb-release \
    software-properties-common \
    apt-transport-https \
    jq

# ========================================
# PHASE 2: Security Setup
# ========================================
print_info "Phase 2: Security Setup"

print_step "Configuring firewall..."
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 80/tcp comment "HTTP"
ufw allow 443/tcp comment "HTTPS"
ufw --force enable

print_step "Configuring fail2ban..."
cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
systemctl enable fail2ban
systemctl restart fail2ban

# ========================================
# PHASE 3: Docker Installation
# ========================================
print_info "Phase 3: Docker Installation"

if ! command -v docker &> /dev/null; then
    print_step "Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
    print_info "Docker installed successfully"
else
    print_info "Docker already installed: $(docker --version)"
fi

print_step "Checking Docker Compose..."
if docker compose version &> /dev/null; then
    print_info "Docker Compose v2 installed: $(docker compose version)"
else
    print_warning "Docker Compose v2 not found, installing plugin..."
    DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
    mkdir -p $DOCKER_CONFIG/cli-plugins
    curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$(uname -m) -o $DOCKER_CONFIG/cli-plugins/docker-compose
    chmod +x $DOCKER_CONFIG/cli-plugins/docker-compose
    
    if docker compose version &> /dev/null; then
        print_info "Docker Compose installed successfully"
    else
        print_error "Failed to install Docker Compose"
        exit 1
    fi
fi

print_step "Adding user to docker group..."
if id "$CURRENT_USER" &>/dev/null; then
    usermod -aG docker "$CURRENT_USER"
    print_info "User '$CURRENT_USER' added to docker group"
    print_warning "Please log out and log back in for docker group changes to take effect"
else
    print_warning "Could not find user '$CURRENT_USER'. Make sure to add your user to docker group manually."
fi

# ========================================
# PHASE 4: Cloudflare Tunnel Installation
# ========================================
print_info "Phase 4: Cloudflare Tunnel Installation"

print_step "Installing Cloudflare Tunnel..."
if ! command -v cloudflared &> /dev/null; then
    # Download and install cloudflared
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) CLOUDFLARED_ARCH="amd64" ;;
        aarch64) CLOUDFLARED_ARCH="arm64" ;;
        armv7l) CLOUDFLARED_ARCH="arm" ;;
        *) print_error "Unsupported architecture: $ARCH"; exit 1 ;;
    esac
    
    wget -O cloudflared.deb "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CLOUDFLARED_ARCH}.deb"
    dpkg -i cloudflared.deb
    rm cloudflared.deb
    print_info "Cloudflare Tunnel installed successfully"
else
    print_info "Cloudflare Tunnel already installed: $(cloudflared --version)"
fi

print_step "Setting up Cloudflare Tunnel directories..."
mkdir -p /etc/cloudflared
mkdir -p /var/log/cloudflared
chown -R $CURRENT_USER:$CURRENT_USER /etc/cloudflared
chown -R $CURRENT_USER:$CURRENT_USER /var/log/cloudflared

# Create sample tunnel config
cat > /etc/cloudflared/config.yml << EOF
# Cloudflare Tunnel Configuration
# Replace with your tunnel credentials and settings

tunnel: YOUR_TUNNEL_UUID
credentials-file: /etc/cloudflared/credentials.json

# Ingress rules - update with your domains
ingress:
  # Wise Owl API Gateway
  - hostname: api.yourdomain.com
    service: http://localhost:8080
  
  # Wise Owl Frontend (if applicable)
  - hostname: app.yourdomain.com
    service: http://localhost:3000
  
  # Catch-all
  - service: http_status:404
EOF

# Create placeholder credentials file
cat > /etc/cloudflared/credentials.json << EOF
{
  "AccountTag": "your-account-tag",
  "TunnelSecret": "your-tunnel-secret", 
  "TunnelID": "your-tunnel-id"
}
EOF

chmod 600 /etc/cloudflared/credentials.json
chown $CURRENT_USER:$CURRENT_USER /etc/cloudflared/credentials.json

print_warning "To complete Cloudflare Tunnel setup:"
print_warning "1. Run: cloudflared tunnel login"
print_warning "2. Create tunnel: cloudflared tunnel create wise-owl"
print_warning "3. Update /etc/cloudflared/config.yml with your tunnel details"
print_warning "4. Install as service: cloudflared service install"

# ========================================
# COMPLETION
# ========================================
print_info "🎉 Simple VPS Setup Complete!"

echo ""
echo -e "${GREEN}=== Summary ===${NC}"
echo "✅ System updated and secured"
echo "✅ Docker installed"
echo "✅ Cloudflare Tunnel installed"
echo ""

echo -e "${BLUE}=== Quick Commands ===${NC}"
echo "View running containers: docker ps"
echo "Check system status: systemctl status cloudflared"
echo "View logs: docker logs <container-name>"
echo ""

echo -e "${YELLOW}=== Next Steps ===${NC}"
echo "1. Complete Cloudflare Tunnel setup:"
echo "   - cloudflared tunnel login"
echo "   - cloudflared tunnel create wise-owl"
echo "   - Update /etc/cloudflared/config.yml"
echo "   - cloudflared service install"
echo ""
echo "2. Create your application deployment:"
echo "   - Create docker-compose.yml for your services"
echo "   - Build and push your Docker images"
echo "   - Deploy with: docker compose up -d"
echo ""
echo "3. Configure your domain DNS to point to Cloudflare Tunnel"
echo ""

print_info "Ready for Wise Owl deployment! 🚀"
