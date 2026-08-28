#!/usr/bin/env bash

# ==============================================================================
# Docker & Services Automated Setup Script for Ubuntu
# Supports: Caddy, Portainer, n8n, WG-Easy (WireGuard)
# ==============================================================================

set -e

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Helper print functions
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "\n${CYAN}=====================================================${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}=====================================================${NC}\n"
}

# Attach stdin to terminal for interactive prompts if script is piped (e.g. curl | bash)
if [ ! -t 0 ] && [ -e /dev/tty ]; then
    exec < /dev/tty
fi

# ------------------------------------------------------------------------------
# 1. Privilege Verification & Elevation (Root / Sudo)
# ------------------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
    if ! command -v sudo &> /dev/null; then
        print_error "This script requires superuser privileges and 'sudo' was not found."
        print_error "Please install sudo or run this script as root directly."
        exit 1
    fi
    print_info "Superuser privileges required. Elevating with sudo..."
    if [ -f "${BASH_SOURCE[0]}" ] && [[ "${BASH_SOURCE[0]}" != "/dev/fd/"* ]]; then
        exec sudo -E bash "${BASH_SOURCE[0]}" "$@"
    else
        exec sudo -E bash -c "$(curl -fsSL https://raw.githubusercontent.com/saifullahshams2/docker/main/setup.sh)" -- "$@"
    fi
fi

# Resolve Script Directory
if [ -n "${BASH_SOURCE[0]}" ] && [ -f "${BASH_SOURCE[0]}" ] && [[ "${BASH_SOURCE[0]}" != "/dev/fd/"* ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    SCRIPT_DIR="/opt/docker"
fi
mkdir -p "$SCRIPT_DIR"
cd "$SCRIPT_DIR"

# Ensure repository stack files exist locally (for curl | bash one-liner support)
if [ ! -d "$SCRIPT_DIR/caddy" ] || [ ! -d "$SCRIPT_DIR/portainer" ]; then
    print_info "Stack directory files not found locally. Fetching repository files..."
    apt-get update -y && apt-get install -y git curl
    TMP_CLONE_DIR="$(mktemp -d)"
    git clone https://github.com/saifullahshams2/docker.git "$TMP_CLONE_DIR"
    cp -r "$TMP_CLONE_DIR/"* "$SCRIPT_DIR/"
    rm -rf "$TMP_CLONE_DIR"
    print_success "Repository files successfully initialized at $SCRIPT_DIR."
fi

print_header "Step 1: Package Update & Docker Installation"

print_info "Updating package lists..."
apt-get update -y

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    print_info "Docker not found. Installing Docker and Docker Compose..."
    apt-get install -y ca-certificates curl gnupg lsb-release
    
    # Use official Docker install script
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm -f get-docker.sh
    
    systemctl enable docker
    systemctl start docker
    print_success "Docker installed and started successfully."
else
    print_success "Docker is already installed ($(docker --version))."
fi

# Ensure docker compose plugin is available
if ! docker compose version &> /dev/null; then
    print_info "Installing Docker Compose plugin..."
    apt-get install -y docker-compose-plugin
fi
print_success "Docker Compose is ready: $(docker compose version)"

# ------------------------------------------------------------------------------
# 2. Network Setup
# ------------------------------------------------------------------------------
print_header "Step 2: Shared Docker Network Setup"

if ! docker network inspect caddynet &> /dev/null; then
    print_info "Creating external bridge network: caddynet"
    docker network create caddynet
    print_success "Network 'caddynet' created."
else
    print_success "Network 'caddynet' already exists."
fi

# ------------------------------------------------------------------------------
# 3. Interactive Configuration Prompts
# ------------------------------------------------------------------------------
print_header "Step 3: Service Configuration"

SETUP_CADDY="n"
SETUP_PORTAINER="n"
SETUP_N8N="n"
SETUP_WGEASY="n"

PORTAINER_DOMAIN=""
N8N_DOMAIN=""
N8N_TIMEZONE="Asia/Riyadh"
WG_DOMAIN=""

# Initialize Caddyfile buffer
CADDYFILE_CONTENT=""

# CADDY QUESTION
read -rp "$(echo -e "${YELLOW}Do you want to setup Caddy Webserver (Reverse Proxy / SSL)? (y/n) [default: y]: ${NC}")" SETUP_CADDY
SETUP_CADDY=${SETUP_CADDY:-y}

# PORTAINER QUESTION
read -rp "$(echo -e "${YELLOW}Do you want to setup Portainer (Container Management UI)? (y/n) [default: y]: ${NC}")" SETUP_PORTAINER
SETUP_PORTAINER=${SETUP_PORTAINER:-y}

if [[ "$SETUP_PORTAINER" =~ ^[Yy]$ ]]; then
    if [[ "$SETUP_CADDY" =~ ^[Yy]$ ]]; then
        read -rp "$(echo -e "${YELLOW}Enter the domain for Portainer (e.g. portainer.example.com) [leave blank to skip Caddy proxy]: ${NC}")" PORTAINER_DOMAIN
        if [ -n "$PORTAINER_DOMAIN" ]; then
            CADDYFILE_CONTENT+="${PORTAINER_DOMAIN} {
    reverse_proxy portainer:9000
}

"
        fi
    fi
fi

# N8N QUESTION
read -rp "$(echo -e "${YELLOW}Do you want to setup n8n (Workflow Automation)? (y/n) [default: y]: ${NC}")" SETUP_N8N
SETUP_N8N=${SETUP_N8N:-y}

if [[ "$SETUP_N8N" =~ ^[Yy]$ ]]; then
    read -rp "$(echo -e "${YELLOW}Enter the domain / Webhook URL domain for n8n (e.g. n8n.example.com): ${NC}")" N8N_DOMAIN
    read -rp "$(echo -e "${YELLOW}Enter timezone for n8n [default: Asia/Riyadh]: ${NC}")" INPUT_TZ
    if [ -n "$INPUT_TZ" ]; then
        N8N_TIMEZONE="$INPUT_TZ"
    fi

    # Update n8n compose.yaml
    if [ -n "$N8N_DOMAIN" ]; then
        WEBHOOK_VAL="https://${N8N_DOMAIN}/"
    else
        WEBHOOK_VAL="http://localhost:5678/"
    fi

    print_info "Writing n8n configuration..."
    cat <<EOF > "$SCRIPT_DIR/n8n/compose.yaml"
services:
  n8n:
    image: docker.n8n.io/n8nio/n8n
    container_name: n8n
    ports:
      - "127.0.0.1:5678:5678"
    environment:
      - WEBHOOK_URL=${WEBHOOK_VAL}
      - GENERIC_TIMEZONE=${N8N_TIMEZONE}
      - N8N_PROTOCOL=https
    volumes:
      - ./data:/home/node/.n8n
    restart: always
    networks:
      - n8nnet
      - caddynet

networks:
  n8nnet:
    driver: bridge
    name: n8nnet 
  caddynet:
    driver: bridge
    external: true
EOF

    if [[ "$SETUP_CADDY" =~ ^[Yy]$ ]] && [ -n "$N8N_DOMAIN" ]; then
        CADDYFILE_CONTENT+="${N8N_DOMAIN} {
    reverse_proxy n8n:5678
}

"
    fi
fi

# WG-EASY QUESTION
read -rp "$(echo -e "${YELLOW}Do you want to setup WG-Easy (WireGuard VPN)? (y/n) [default: y]: ${NC}")" SETUP_WGEASY
SETUP_WGEASY=${SETUP_WGEASY:-y}

if [[ "$SETUP_WGEASY" =~ ^[Yy]$ ]]; then
    if [[ "$SETUP_CADDY" =~ ^[Yy]$ ]]; then
        read -rp "$(echo -e "${YELLOW}Enter domain for WG-Easy Web Dashboard (e.g. wg.example.com) [leave blank to skip Caddy proxy]: ${NC}")" WG_DOMAIN
        if [ -n "$WG_DOMAIN" ]; then
            CADDYFILE_CONTENT+="${WG_DOMAIN} {
    reverse_proxy wg-easy:51821
}

"
        fi
    fi

    print_info "Writing wg-easy configuration..."
    cat <<EOF > "$SCRIPT_DIR/wgeasy/compose.yaml"
services:
  wg-easy:
    environment:
      - PORT=51821
      - HOST=0.0.0.0
      - INSECURE=false
      - DISABLE_IPV6=true
    image: ghcr.io/wg-easy/wg-easy:15.4.0
    container_name: wg-easy
    networks:
      - wg
      - caddynet
    volumes:
      - ./etc:/etc/wireguard
      - /lib/modules:/lib/modules:ro
    ports:
      - "51820:51820/udp"
      - "127.0.0.1:51821:51821/tcp"
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv4.conf.all.src_valid_mark=1
      - net.ipv6.conf.all.disable_ipv6=1

networks:
  wg:
    driver: bridge
    name: wg
  caddynet:
    driver: bridge
    external: true
EOF
fi

# Write Caddyfile if Caddy is enabled
if [[ "$SETUP_CADDY" =~ ^[Yy]$ ]]; then
    print_info "Writing caddy/Caddyfile..."
    if [ -z "$CADDYFILE_CONTENT" ]; then
        CADDYFILE_CONTENT="# Add your reverse proxy domains here\n"
    fi
    echo -e "$CADDYFILE_CONTENT" > "$SCRIPT_DIR/caddy/Caddyfile"
fi

# ------------------------------------------------------------------------------
# 4. Service Deployment
# ------------------------------------------------------------------------------
print_header "Step 4: Launching Selected Containers"

if [[ "$SETUP_CADDY" =~ ^[Yy]$ ]]; then
    print_info "Starting Caddy..."
    (cd "$SCRIPT_DIR/caddy" && docker compose up -d)
    print_success "Caddy is running."
fi

if [[ "$SETUP_PORTAINER" =~ ^[Yy]$ ]]; then
    print_info "Starting Portainer..."
    (cd "$SCRIPT_DIR/portainer" && docker compose up -d)
    print_success "Portainer is running."
fi

if [[ "$SETUP_N8N" =~ ^[Yy]$ ]]; then
    print_info "Starting n8n..."
    (cd "$SCRIPT_DIR/n8n" && docker compose up -d)
    print_success "n8n is running."
fi

if [[ "$SETUP_WGEASY" =~ ^[Yy]$ ]]; then
    print_info "Starting WG-Easy..."
    (cd "$SCRIPT_DIR/wgeasy" && docker compose up -d)
    print_success "WG-Easy is running."
fi

# ------------------------------------------------------------------------------
# 5. System Upgrade (Ran at the end)
# ------------------------------------------------------------------------------
print_header "Step 5: System Package Upgrade"
print_info "Running system upgrade..."
apt-get upgrade -y
print_success "System upgrade completed."

# ------------------------------------------------------------------------------
# 6. Final Summary
# ------------------------------------------------------------------------------
print_header "Deployment Complete!"

echo -e "${GREEN}The selected services have been successfully configured and deployed:${NC}\n"

if [[ "$SETUP_CADDY" =~ ^[Yy]$ ]]; then
    echo -e "  • ${CYAN}Caddy Reverse Proxy${NC}: Ports 80 & 443 active"
fi

if [[ "$SETUP_PORTAINER" =~ ^[Yy]$ ]]; then
    if [ -n "$PORTAINER_DOMAIN" ]; then
        echo -e "  • ${CYAN}Portainer UI${NC}: https://${PORTAINER_DOMAIN} (or http://127.0.0.1:9000)"
    else
        echo -e "  • ${CYAN}Portainer UI${NC}: http://127.0.0.1:9000"
    fi
fi

if [[ "$SETUP_N8N" =~ ^[Yy]$ ]]; then
    if [ -n "$N8N_DOMAIN" ]; then
        echo -e "  • ${CYAN}n8n Automation${NC}: https://${N8N_DOMAIN} (or http://127.0.0.1:5678)"
    else
        echo -e "  • ${CYAN}n8n Automation${NC}: http://127.0.0.1:5678"
    fi
fi

if [[ "$SETUP_WGEASY" =~ ^[Yy]$ ]]; then
    echo -e "  • ${CYAN}WireGuard VPN Tunnel${NC}: Port 51820/udp active"
    if [ -n "$WG_DOMAIN" ]; then
        echo -e "  • ${CYAN}WG-Easy Web UI${NC}: https://${WG_DOMAIN} (or http://127.0.0.1:51821)"
    else
        echo -e "  • ${CYAN}WG-Easy Web UI${NC}: http://127.0.0.1:51821"
    fi
fi

echo -e "\n${GREEN}All services are up and running!${NC}\n"
