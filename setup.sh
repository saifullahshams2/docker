#!/usr/bin/env bash

# ==============================================================================
# Docker & Services Automated Setup Script for Ubuntu
# Supports: Caddy, Portainer, n8n, WG-Easy (WireGuard)
# ==============================================================================

set -euo pipefail

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
# 1. Privilege & Group Verification (Option 2: Disallow Root, Check Sudo Group)
# ------------------------------------------------------------------------------

# 1.1 Disallow running directly as root
if [ "$EUID" -eq 0 ]; then
    print_error "Do not run this script directly as root or with 'sudo ./setup.sh'."
    print_error "Please run it as a regular user: ./setup.sh"
    exit 1
fi

# 1.2 Get current username
CURRENT_USER=$(whoami)

# 1.3 Check if user belongs to 'sudo', 'wheel', or 'root' group
if ! id -nG "$CURRENT_USER" | grep -qwE "(sudo|wheel|root)"; then
    print_error "User '$CURRENT_USER' is not in the 'sudo', 'wheel', or 'root' group."
    print_error "You must be a member of an administrative group (sudo, wheel, or root) to run this script. Exiting..."
    exit 1
fi

print_success "User '$CURRENT_USER' is authorized in an administrative group."

# 1.4 Validate & cache sudo credentials upfront
print_info "Authenticating sudo access..."
if ! sudo -v; then
    print_error "Sudo authentication failed. Exiting..."
    exit 1
fi

# Keep sudo session alive in the background while the script runs
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
SUDO_KEEPALIVE_PID=$!
trap 'kill $SUDO_KEEPALIVE_PID 2>/dev/null || true' EXIT

# ------------------------------------------------------------------------------
# 2. Resolve Script Directory, Logging & Workspace Setup
# ------------------------------------------------------------------------------
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]:-}" ] && [[ "${BASH_SOURCE[0]:-}" != "/dev/fd/"* ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    SCRIPT_DIR="/opt/docker"
fi

# Ensure target directory exists and is owned by current user
sudo mkdir -p "$SCRIPT_DIR"
sudo chown -R "$CURRENT_USER:$(id -gn "$CURRENT_USER")" "$SCRIPT_DIR"
cd "$SCRIPT_DIR"

# Enable logging: saves full output to setup.log in the current directory while displaying on screen
LOG_FILE="$SCRIPT_DIR/setup.log"
exec > >(tee -a "$LOG_FILE") 2>&1
print_info "Logging all session output to $LOG_FILE"

# Ensure repository stack files exist locally (for one-liner curl / script execution)
if [ ! -d "$SCRIPT_DIR/caddy" ] || [ ! -d "$SCRIPT_DIR/portainer" ]; then
    print_info "Stack directory files not found locally. Fetching repository files..."
    curl -fsSL https://github.com/saifullahshams2/docker/archive/refs/heads/main.tar.gz | tar -xz -C "$SCRIPT_DIR" --strip-components=1
    print_success "Repository files successfully initialized at $SCRIPT_DIR."
fi

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

# Wait for background apt locks to release (e.g. unattended-upgrades on boot)
wait_for_apt_lock() {
    local max_wait=60
    local waited=0
    while sudo fuser /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock /var/lib/dpkg/lock >/dev/null 2>&1; do
        if [ "$waited" -ge "$max_wait" ]; then
            print_warning "Apt lock is still held. Attempting to continue..."
            break
        fi
        print_info "Waiting for background system updates / apt lock to release..."
        sleep 3
        waited=$((waited + 3))
    done
}

# ------------------------------------------------------------------------------
# 3. Package Update & Docker Installation
# ------------------------------------------------------------------------------
print_header "Step 1: Package Update & Docker Installation"

wait_for_apt_lock
print_info "Updating package lists..."
sudo apt-get update -y

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    print_info "Docker not found. Installing Docker and Docker Compose..."
    wait_for_apt_lock
    sudo apt-get install -y ca-certificates curl gnupg lsb-release
    
    INSTALL_SUCCESS=false

    # Set up official Docker GPG key and repository
    print_info "Configuring Docker repository..."
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    UBUNTU_CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME:-$UBUNTU_CODENAME}")"
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME} stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    wait_for_apt_lock
    if sudo apt-get update -y; then
        print_info "Installing Docker CE packages (this may take 1-2 minutes)..."
        if sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
            INSTALL_SUCCESS=true
        fi
    fi
    
    # Fallback: If Docker official repository fails (e.g. unsupported distro codename), install Ubuntu native packages
    if [ "$INSTALL_SUCCESS" = false ]; then
        print_warning "Official Docker repository unavailable. Installing Ubuntu native docker.io packages..."
        sudo rm -f /etc/apt/sources.list.d/docker.list
        wait_for_apt_lock
        sudo apt-get update -y
        sudo apt-get install -y docker.io docker-compose-v2 || sudo apt-get install -y docker.io docker-compose-plugin || sudo apt-get install -y docker.io
    fi
    
    sudo systemctl enable docker || true
    sudo systemctl start docker || true
    print_success "Docker installed and started successfully."
else
    print_success "Docker is already installed ($(docker --version))."
fi

# Ensure docker compose plugin is available
if ! sudo docker compose version &> /dev/null; then
    print_info "Installing Docker Compose plugin..."
    sudo apt-get install -y docker-compose-plugin || sudo apt-get install -y docker-compose-v2 || true
fi
print_success "Docker Compose is ready: $(sudo docker compose version)"

# Ensure 'docker' group exists and add current user to it
sudo groupadd -f docker
if ! id -nG "$CURRENT_USER" | grep -qw "docker"; then
    print_info "Adding '$CURRENT_USER' to the docker group..."
    sudo usermod -aG docker "$CURRENT_USER"
    print_success "User '$CURRENT_USER' successfully added to the 'docker' group."
else
    print_success "User '$CURRENT_USER' is already a member of the 'docker' group."
fi

# ------------------------------------------------------------------------------
# 4. Network Setup
# ------------------------------------------------------------------------------
print_header "Step 2: Shared Docker Network Setup"

if ! sudo docker network inspect caddynet &> /dev/null; then
    print_info "Creating external bridge network: caddynet"
    sudo docker network create caddynet
    print_success "Network 'caddynet' created."
else
    print_success "Network 'caddynet' already exists."
fi

# ------------------------------------------------------------------------------
# 5. Interactive Configuration Prompts
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
read -rp "$(echo -e "${YELLOW}Do you want to setup Caddy Webserver (Reverse Proxy / SSL)? (y/n) [default: y]: ${NC}")" SETUP_CADDY || true
SETUP_CADDY=${SETUP_CADDY:-y}

# PORTAINER QUESTION
read -rp "$(echo -e "${YELLOW}Do you want to setup Portainer (Container Management UI)? (y/n) [default: y]: ${NC}")" SETUP_PORTAINER || true
SETUP_PORTAINER=${SETUP_PORTAINER:-y}

if [[ "$SETUP_PORTAINER" =~ ^[Yy]$ ]]; then
    if [[ "$SETUP_CADDY" =~ ^[Yy]$ ]]; then
        read -rp "$(echo -e "${YELLOW}Enter the domain for Portainer (e.g. portainer.example.com) [leave blank to skip Caddy proxy]: ${NC}")" PORTAINER_DOMAIN || true
        if [ -n "$PORTAINER_DOMAIN" ]; then
            CADDYFILE_CONTENT+="${PORTAINER_DOMAIN} {
    reverse_proxy portainer:9000
}

"
        fi
    fi
fi

# N8N QUESTION
read -rp "$(echo -e "${YELLOW}Do you want to setup n8n (Workflow Automation)? (y/n) [default: y]: ${NC}")" SETUP_N8N || true
SETUP_N8N=${SETUP_N8N:-y}

if [[ "$SETUP_N8N" =~ ^[Yy]$ ]]; then
    read -rp "$(echo -e "${YELLOW}Enter the domain / Webhook URL domain for n8n (e.g. n8n.example.com): ${NC}")" N8N_DOMAIN || true
    read -rp "$(echo -e "${YELLOW}Enter timezone for n8n [default: Asia/Riyadh]: ${NC}")" INPUT_TZ || true
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
    mkdir -p "$SCRIPT_DIR/n8n/data"
    sudo chown -R 1000:1000 "$SCRIPT_DIR/n8n/data"

    cat <<EOF > "$SCRIPT_DIR/n8n/compose.yaml"
services:
  n8n:
    image: docker.n8n.io/n8nio/n8n
    container_name: n8n
    user: "1000:1000"
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
read -rp "$(echo -e "${YELLOW}Do you want to setup WG-Easy (WireGuard VPN)? (y/n) [default: y]: ${NC}")" SETUP_WGEASY || true
SETUP_WGEASY=${SETUP_WGEASY:-y}

if [[ "$SETUP_WGEASY" =~ ^[Yy]$ ]]; then
    if [[ "$SETUP_CADDY" =~ ^[Yy]$ ]]; then
        read -rp "$(echo -e "${YELLOW}Enter domain for WG-Easy Web Dashboard (e.g. wg.example.com) [leave blank to skip Caddy proxy]: ${NC}")" WG_DOMAIN || true
        if [ -n "$WG_DOMAIN" ]; then
            CADDYFILE_CONTENT+="${WG_DOMAIN} {
    reverse_proxy wg-easy:51821
}

"
        fi
    fi

    print_info "Writing wg-easy configuration..."
    mkdir -p "$SCRIPT_DIR/wgeasy"
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
    mkdir -p "$SCRIPT_DIR/caddy"
    if [ -z "$CADDYFILE_CONTENT" ]; then
        CADDYFILE_CONTENT="# Add your reverse proxy domains here\n"
    fi
    echo -e "$CADDYFILE_CONTENT" > "$SCRIPT_DIR/caddy/Caddyfile"
fi

# ------------------------------------------------------------------------------
# 6. Service Deployment
# ------------------------------------------------------------------------------
print_header "Step 4: Launching Selected Containers"

if [[ "$SETUP_CADDY" =~ ^[Yy]$ ]]; then
    print_info "Starting Caddy..."
    (cd "$SCRIPT_DIR/caddy" && sudo docker compose up -d)
    print_success "Caddy is running."
fi

if [[ "$SETUP_PORTAINER" =~ ^[Yy]$ ]]; then
    print_info "Starting Portainer..."
    (cd "$SCRIPT_DIR/portainer" && sudo docker compose up -d)
    print_success "Portainer is running."
fi

if [[ "$SETUP_N8N" =~ ^[Yy]$ ]]; then
    print_info "Starting n8n..."
    (cd "$SCRIPT_DIR/n8n" && sudo docker compose up -d)
    print_success "n8n is running."
fi

if [[ "$SETUP_WGEASY" =~ ^[Yy]$ ]]; then
    print_info "Starting WG-Easy..."
    (cd "$SCRIPT_DIR/wgeasy" && sudo docker compose up -d)
    print_success "WG-Easy is running."
fi

# ------------------------------------------------------------------------------
# 7. Final Summary
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

echo -e "  • ${CYAN}Installation Log${NC}: ${LOG_FILE}"

echo -e "\n${GREEN}All services are up and running!${NC}\n"

# ------------------------------------------------------------------------------
# 8. Optional System Reboot Prompt
# ------------------------------------------------------------------------------
REBOOT_SYSTEM="n"
read -rp "$(echo -e "${YELLOW}Do you want to reboot the system now to apply all group and kernel changes? (y/n) [default: n]: ${NC}")" REBOOT_SYSTEM || true
REBOOT_SYSTEM=${REBOOT_SYSTEM:-n}

if [[ "$REBOOT_SYSTEM" =~ ^[Yy]$ ]]; then
    print_info "Rebooting system now..."
    sudo reboot
else
    print_info "Reboot skipped. You can manually reboot anytime with: sudo reboot"
fi
