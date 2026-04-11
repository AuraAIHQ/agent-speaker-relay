#!/bin/bash
# Agent Speaker Relay - Deployment Script
# Usage: ./deploy.sh [local|docker|cloudflare]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${SCRIPT_DIR}/data"
CONFIG_FILE="${SCRIPT_DIR}/strfry.conf"
RELAY_NAME="agent-speaker-relay"
RELAY_PORT=7777

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check dependencies
check_deps() {
    local deps=("docker")
    if [ "$1" == "cloudflare" ]; then
        deps+=("cloudflared")
    fi
    
    for dep in "${deps[@]}"; do
        if ! command -v $dep &> /dev/null; then
            log_error "$dep is required but not installed"
            exit 1
        fi
    done
}

# Deploy locally with Docker
deploy_local() {
    log_info "Deploying Agent Speaker Relay locally..."
    
    # Create directories
    mkdir -p "$DATA_DIR"
    
    # Create config if not exists
    if [ ! -f "$CONFIG_FILE" ]; then
        log_warn "Config not found, creating default..."
        cp "${SCRIPT_DIR}/strfry.conf.default" "$CONFIG_FILE"
    fi
    
    # Stop existing container
    if docker ps -q -f name=$RELAY_NAME | grep -q .; then
        log_info "Stopping existing container..."
        docker stop $RELAY_NAME
        docker rm $RELAY_NAME
    fi
    
    # Build image
    log_info "Building Docker image..."
    docker build -t $RELAY_NAME:latest "$SCRIPT_DIR"
    
    # Run container
    log_info "Starting relay..."
    docker run -d \
        --name $RELAY_NAME \
        --restart unless-stopped \
        -p $RELAY_PORT:$RELAY_PORT \
        -v "$DATA_DIR":/app/strfry-db \
        -v "$CONFIG_FILE":/app/strfry.conf \
        $RELAY_NAME:latest
    
    # Wait for startup
    sleep 2
    
    # Check health
    if docker ps -q -f name=$RELAY_NAME | grep -q .; then
        log_success "Relay is running!"
        log_info "Local URL: ws://localhost:$RELAY_PORT"
        log_info "To view logs: docker logs -f $RELAY_NAME"
    else
        log_error "Failed to start relay"
        docker logs $RELAY_NAME
        exit 1
    fi
}

# Deploy with Cloudflare Tunnel
deploy_cloudflare() {
    log_info "Deploying Agent Speaker Relay with Cloudflare Tunnel..."
    
    # Check if cloudflared is installed
    if ! command -v cloudflared &> /dev/null; then
        log_error "cloudflared not found. Please install first:"
        log_info "macOS: brew install cloudflared"
        log_info "Linux: https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/installation"
        exit 1
    fi
    
    # Check if already authenticated
    if [ ! -f ~/.cloudflared/cert.pem ]; then
        log_info "Please authenticate with Cloudflare first..."
        cloudflared tunnel login
    fi
    
    # Get or create tunnel
    local tunnel_id=$(cloudflared tunnel list | grep "$RELAY_NAME" | awk '{print $1}')
    
    if [ -z "$tunnel_id" ]; then
        log_info "Creating new tunnel..."
        cloudflared tunnel create $RELAY_NAME
        tunnel_id=$(cloudflared tunnel list | grep "$RELAY_NAME" | awk '{print $1}')
    else
        log_info "Using existing tunnel: $tunnel_id"
    fi
    
    # Get tunnel credentials file
    local creds_file=$(find ~/.cloudflared -name "${tunnel_id}.json" | head -1)
    if [ -z "$creds_file" ]; then
        log_error "Tunnel credentials not found"
        exit 1
    fi
    
    # Create config
    local config_dir="${SCRIPT_DIR}/cloudflare-config"
    mkdir -p "$config_dir"
    
    cat > "$config_dir/config.yml" << EOF
tunnel: ${tunnel_id}
credentials-file: ${creds_file}

ingress:
  - hostname: relay.${DOMAIN:-yourdomain.com}
    service: ws://localhost:${RELAY_PORT}
    originRequest:
      noTLSVerify: true
  - service: http_status:404
EOF
    
    log_info "Cloudflare config created at: $config_dir/config.yml"
    log_warn "Please update the hostname in the config file"
    
    # Start local relay first
    deploy_local
    
    # Add DNS route
    read -p "Enter your domain (e.g., example.com): " domain
    if [ -n "$domain" ]; then
        log_info "Adding DNS route..."
        cloudflared tunnel route dns $RELAY_NAME relay.$domain || true
        
        # Update config with domain
        sed -i.bak "s/relay.\${DOMAIN:-yourdomain.com}/relay.$domain/g" "$config_dir/config.yml"
        rm "$config_dir/config.yml.bak"
    fi
    
    # Start tunnel
    log_info "Starting Cloudflare tunnel..."
    log_info "Public URL will be: wss://relay.$domain"
    
    cloudflared tunnel --config "$config_dir/config.yml" run $RELAY_NAME &
    local tunnel_pid=$!
    
    # Save PID
    echo $tunnel_pid > "$config_dir/tunnel.pid"
    
    log_success "Tunnel started!"
    log_info "To stop: kill $(cat "$config_dir/tunnel.pid")"
}

# Deploy with docker-compose
deploy_compose() {
    log_info "Deploying with Docker Compose..."
    
    # Create docker-compose.yml
    cat > "${SCRIPT_DIR}/docker-compose.yml" << 'EOF'
version: '3.8'

services:
  relay:
    build: .
    container_name: agent-speaker-relay
    restart: unless-stopped
    ports:
      - "7777:7777"
    volumes:
      - ./data:/app/strfry-db
      - ./strfry.conf:/app/strfry.conf
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:7777/health"]
      interval: 30s
      timeout: 3s
      retries: 3
    
  tunnel:
    image: cloudflare/cloudflared:latest
    container_name: agent-speaker-tunnel
    restart: unless-stopped
    command: tunnel run
    environment:
      - TUNNEL_TOKEN=${TUNNEL_TOKEN}
    depends_on:
      - relay
    profiles:
      - tunnel
EOF
    
    # Start services
    docker-compose up -d relay
    
    log_success "Relay started with docker-compose"
    log_info "To start with tunnel: docker-compose --profile tunnel up -d"
}

# Show status
show_status() {
    log_info "Checking relay status..."
    
    if docker ps -q -f name=$RELAY_NAME | grep -q .; then
        log_success "Relay is running"
        docker ps -f name=$RELAY_NAME
        
        echo ""
        log_info "Recent logs:"
        docker logs --tail 20 $RELAY_NAME
    else
        log_warn "Relay is not running"
        docker ps -a -f name=$RELAY_NAME
    fi
}

# Stop relay
stop_relay() {
    log_info "Stopping relay..."
    
    docker stop $RELAY_NAME 2>/dev/null || true
    docker rm $RELAY_NAME 2>/dev/null || true
    
    # Stop tunnel if running
    if [ -f "${SCRIPT_DIR}/cloudflare-config/tunnel.pid" ]; then
        kill $(cat "${SCRIPT_DIR}/cloudflare-config/tunnel.pid") 2>/dev/null || true
    fi
    
    log_success "Relay stopped"
}

# Backup data
backup_data() {
    local backup_dir="${SCRIPT_DIR}/backups"
    mkdir -p "$backup_dir"
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="${backup_dir}/relay-${timestamp}.tar.gz"
    
    log_info "Creating backup: $backup_file"
    
    tar -czf "$backup_file" -C "$DATA_DIR" .
    
    # Keep only last 7 backups
    ls -t "${backup_dir}"/*.tar.gz | tail -n +8 | xargs rm -f 2>/dev/null || true
    
    log_success "Backup created: $backup_file"
}

# Main
main() {
    case "${1:-local}" in
        local)
            check_deps
            deploy_local
            ;;
        docker)
            check_deps
            deploy_compose
            ;;
        cloudflare)
            check_deps cloudflare
            deploy_cloudflare
            ;;
        status)
            show_status
            ;;
        stop)
            stop_relay
            ;;
        backup)
            backup_data
            ;;
        help|--help|-h)
            echo "Agent Speaker Relay Deployment Script"
            echo ""
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  local       Deploy locally with Docker (default)"
            echo "  docker      Deploy with Docker Compose"
            echo "  cloudflare  Deploy with Cloudflare Tunnel"
            echo "  status      Show relay status"
            echo "  stop        Stop the relay"
            echo "  backup      Backup relay data"
            echo "  help        Show this help"
            ;;
        *)
            log_error "Unknown command: $1"
            echo "Run '$0 help' for usage"
            exit 1
            ;;
    esac
}

main "$@"
