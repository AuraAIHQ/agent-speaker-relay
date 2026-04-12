#!/bin/bash
# AASTAR Relay Deployment Script for Mac Mini
# Domain: relay.aastar.io
# Target: School Mac Mini (24/7 operation)

set -e

RELAY_DIR="${HOME}/agent-relay"
DATA_DIR="${RELAY_DIR}/data"
LOGS_DIR="${RELAY_DIR}/logs"
DOMAIN="relay.aastar.io"
TUNNEL_NAME="aastar-relay"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_requirements() {
    log_info "Checking requirements..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker not found. Please install Docker Desktop for Mac."
        exit 1
    fi
    
    # Check cloudflared
    if ! command -v cloudflared &> /dev/null; then
        log_warn "cloudflared not found. Installing..."
        brew install cloudflared || {
            log_error "Failed to install cloudflared"
            exit 1
        }
    fi
    
    # Check if Docker is running
    if ! docker info &> /dev/null; then
        log_error "Docker is not running. Please start Docker Desktop."
        exit 1
    fi
    
    log_success "All requirements met"
}

setup_directories() {
    log_info "Setting up directories..."
    
    mkdir -p "${DATA_DIR}" "${LOGS_DIR}"
    chmod 755 "${DATA_DIR}"
    
    log_success "Directories created at ${RELAY_DIR}"
}

download_configs() {
    log_info "Downloading configuration files..."
    
    cd "${RELAY_DIR}"
    
    # Download config
    if [ ! -f "strfry.aastar.conf" ]; then
        curl -fsSL -o strfry.aastar.conf \
            https://raw.githubusercontent.com/MushroomDAO/agent-speaker-relay/agent-speaker/strfry.aastar.conf
        log_success "Downloaded strfry.aastar.conf"
    else
        log_warn "strfry.aastar.conf already exists"
    fi
    
    # Download docker-compose
    if [ ! -f "docker-compose.aastar.yml" ]; then
        curl -fsSL -o docker-compose.aastar.yml \
            https://raw.githubusercontent.com/MushroomDAO/agent-speaker-relay/agent-speaker/docker-compose.aastar.yml
        log_success "Downloaded docker-compose.aastar.yml"
    else
        log_warn "docker-compose.aastar.yml already exists"
    fi
    
    # Download launchd plist
    if [ ! -f "com.aastar.relay.plist" ]; then
        curl -fsSL -o com.aastar.relay.plist \
            https://raw.githubusercontent.com/MushroomDAO/agent-speaker-relay/agent-speaker/com.aastar.relay.plist
        log_success "Downloaded com.aastar.relay.plist"
    else
        log_warn "com.aastar.relay.plist already exists"
    fi
}

setup_cloudflare_tunnel() {
    log_info "Setting up Cloudflare Tunnel..."
    
    # Check if already authenticated
    if [ ! -f ~/.cloudflared/cert.pem ]; then
        log_info "Please authenticate with Cloudflare..."
        cloudflared tunnel login
    fi
    
    # Check if tunnel exists
    local tunnel_id=$(cloudflared tunnel list 2>/dev/null | grep "${TUNNEL_NAME}" | awk '{print $1}')
    
    if [ -z "${tunnel_id}" ]; then
        log_info "Creating new tunnel: ${TUNNEL_NAME}"
        cloudflared tunnel create "${TUNNEL_NAME}"
        tunnel_id=$(cloudflared tunnel list | grep "${TUNNEL_NAME}" | awk '{print $1}')
    else
        log_info "Using existing tunnel: ${tunnel_id}"
    fi
    
    # Get credentials file
    local creds_file=$(find ~/.cloudflared -name "${tunnel_id}.json" | head -1)
    if [ -z "${creds_file}" ]; then
        log_error "Tunnel credentials not found"
        exit 1
    fi
    
    # Create config directory
    mkdir -p "${RELAY_DIR}/cloudflared"
    
    # Create tunnel config
    cat > "${RELAY_DIR}/cloudflared/config.yml" << EOF
tunnel: ${tunnel_id}
credentials-file: ${creds_file}

ingress:
  - hostname: ${DOMAIN}
    service: http://localhost:7777
    originRequest:
      noTLSVerify: true
      connectTimeout: 30s
  - service: http_status:404
EOF
    
    log_success "Tunnel config created"
    
    # Create DNS record
    log_info "Creating DNS record for ${DOMAIN}..."
    cloudflared tunnel route dns "${TUNNEL_NAME}" "${DOMAIN}" || {
        log_warn "DNS record may already exist or failed to create"
    }
    
    log_success "Cloudflare Tunnel configured"
    log_info "Tunnel ID: ${tunnel_id}"
    log_info "Domain: ${DOMAIN}"
}

start_relay() {
    log_info "Starting relay..."
    
    cd "${RELAY_DIR}"
    
    # Stop existing container if any
    docker compose -f docker-compose.aastar.yml down 2>/dev/null || true
    
    # Pull latest image
    docker pull hoytech/strfry:latest
    
    # Start relay
    docker compose -f docker-compose.aastar.yml up -d
    
    # Wait for relay to be ready
    log_info "Waiting for relay to start..."
    sleep 5
    
    local retries=0
    while [ $retries -lt 10 ]; do
        if curl -s http://localhost:7777 > /dev/null 2>&1; then
            log_success "Relay is running on localhost:7777"
            break
        fi
        retries=$((retries + 1))
        log_info "Waiting... (${retries}/10)"
        sleep 2
    done
    
    if [ $retries -eq 10 ]; then
        log_error "Relay failed to start"
        docker logs aastar-relay
        exit 1
    fi
}

start_tunnel() {
    log_info "Starting Cloudflare Tunnel..."
    
    # Check if tunnel is already running
    if pgrep -f "cloudflared.*${TUNNEL_NAME}" > /dev/null; then
        log_warn "Tunnel appears to be already running"
        return
    fi
    
    # Start tunnel in background
    cd "${RELAY_DIR}"
    nohup cloudflared tunnel --config "${RELAY_DIR}/cloudflared/config.yml" run "${TUNNEL_NAME}" > \
        "${LOGS_DIR}/tunnel.log" 2>&1 &
    
    local tunnel_pid=$!
    echo $tunnel_pid > "${RELAY_DIR}/cloudflared/tunnel.pid"
    
    log_info "Tunnel starting (PID: ${tunnel_pid})..."
    sleep 5
    
    # Check if tunnel is healthy
    if kill -0 $tunnel_pid 2>/dev/null; then
        log_success "Tunnel is running"
        log_info "Public URL: wss://${DOMAIN}"
    else
        log_error "Tunnel failed to start"
        cat "${LOGS_DIR}/tunnel.log"
        exit 1
    fi
}

setup_launchd() {
    log_info "Setting up LaunchDaemon for auto-start..."
    
    # Update plist with correct user
    sed -i '' "s|/Users/aastar|${HOME}|g" "${RELAY_DIR}/com.aastar.relay.plist"
    
    # Copy to LaunchAgents (user level, no sudo needed)
    cp "${RELAY_DIR}/com.aastar.relay.plist" ~/Library/LaunchAgents/
    
    # Load the service
    launchctl unload ~/Library/LaunchAgents/com.aastar.relay.plist 2>/dev/null || true
    launchctl load ~/Library/LaunchAgents/com.aastar.relay.plist
    
    log_success "LaunchDaemon configured"
    log_info "Relay will auto-start on login"
}

create_control_scripts() {
    log_info "Creating control scripts..."
    
    # Start script
    cat > "${RELAY_DIR}/start.sh" << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
docker compose -f docker-compose.aastar.yml up -d
nohup cloudflared tunnel --config ./cloudflared/config.yml run aastar-relay > ./logs/tunnel.log 2>&1 &
echo $! > ./cloudflared/tunnel.pid
echo "Relay started"
EOF
    
    # Stop script
    cat > "${RELAY_DIR}/stop.sh" << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
docker compose -f docker-compose.aastar.yml down
if [ -f ./cloudflared/tunnel.pid ]; then
    kill $(cat ./cloudflared/tunnel.pid) 2>/dev/null || true
    rm ./cloudflared/tunnel.pid
fi
echo "Relay stopped"
EOF
    
    # Status script
    cat > "${RELAY_DIR}/status.sh" << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
echo "=== Relay Status ==="
docker compose -f docker-compose.aastar.yml ps
echo ""
echo "=== Tunnel Status ==="
if [ -f ./cloudflared/tunnel.pid ]; then
    if kill -0 $(cat ./cloudflared/tunnel.pid) 2>/dev/null; then
        echo "Tunnel: Running (PID: $(cat ./cloudflared/tunnel.pid))"
    else
        echo "Tunnel: Not running"
    fi
else
    echo "Tunnel: Not running"
fi
echo ""
echo "=== Recent Logs ==="
tail -20 ./logs/relay.log 2>/dev/null || echo "No relay logs yet"
EOF
    
    chmod +x "${RELAY_DIR}"/*.sh
    log_success "Control scripts created"
}

print_summary() {
    echo ""
    echo "==============================================="
    echo "  AASTAR Relay Deployment Complete!"
    echo "==============================================="
    echo ""
    echo "📡 Relay URL: wss://${DOMAIN}"
    echo "📊 Local URL: http://localhost:7777"
    echo "📁 Data Dir:  ${DATA_DIR}"
    echo "📋 Logs Dir:  ${LOGS_DIR}"
    echo ""
    echo "🎮 Control Commands:"
    echo "   ${RELAY_DIR}/start.sh   - Start relay"
    echo "   ${RELAY_DIR}/stop.sh    - Stop relay"
    echo "   ${RELAY_DIR}/status.sh  - Check status"
    echo ""
    echo "🧰 Useful Commands:"
    echo "   docker logs -f aastar-relay     # View relay logs"
    echo "   tail -f ${LOGS_DIR}/tunnel.log  # View tunnel logs"
    echo ""
    echo "⚙️  Environment Variable for Clients:"
    echo "   export AGENT_RELAY='wss://${DOMAIN}'"
    echo ""
    echo "==============================================="
}

# Main
main() {
    echo "==============================================="
    echo "  AASTAR Relay Deployer"
    echo "  Domain: ${DOMAIN}"
    echo "==============================================="
    echo ""
    
    check_requirements
    setup_directories
    download_configs
    setup_cloudflare_tunnel
    start_relay
    start_tunnel
    setup_launchd
    create_control_scripts
    print_summary
}

main "$@"
