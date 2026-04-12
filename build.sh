#!/bin/bash
# AASTAR Relay Build Script
# Supports both Alpine (official, smaller) and Ubuntu (larger, familiar) builds

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="mushroomdao/agent-speaker-relay"
IMAGE_TAG="latest"

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

usage() {
    echo "Usage: $0 [alpine|ubuntu]"
    echo ""
    echo "Options:"
    echo "  alpine  - Use Alpine Linux (smaller ~50MB, official approach)"
    echo "  ubuntu  - Use Ubuntu (larger ~200MB, more familiar)"
    echo ""
    echo "Default: alpine (recommended)"
    exit 1
}

# Parse arguments
BUILD_TYPE="${1:-alpine}"
case "$BUILD_TYPE" in
    alpine|ubuntu)
        ;;
    -h|--help)
        usage
        ;;
    *)
        log_error "Unknown option: $BUILD_TYPE"
        usage
        ;;
esac

if [ "$BUILD_TYPE" == "alpine" ]; then
    DOCKERFILE="Dockerfile.agent-speaker"
    log_info "Using Alpine Linux build (official, smaller)"
else
    DOCKERFILE="Dockerfile.ubuntu"
    log_info "Using Ubuntu build (larger, more familiar)"
fi

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! docker --version &> /dev/null; then
        log_error "Docker not found. Please install Docker."
        exit 1
    fi
    log_info "Docker: $(docker --version)"
    
    if [ ! -f "$DOCKERFILE" ]; then
        log_error "Dockerfile not found: $DOCKERFILE"
        exit 1
    fi
    
    log_success "Prerequisites OK"
}

clear_cache() {
    log_info "Clearing Docker cache..."
    
    if docker ps -a 2>/dev/null | grep -q "aastar-relay"; then
        log_warn "Stopping existing containers..."
        docker stop aastar-relay 2>/dev/null || true
        docker rm aastar-relay 2>/dev/null || true
    fi
    
    if docker images 2>/dev/null | grep -q "${IMAGE_NAME}"; then
        log_warn "Removing existing image..."
        docker rmi "${IMAGE_NAME}:${IMAGE_TAG}" 2>/dev/null || true
    fi
    
    docker builder prune -f 2>/dev/null || true
    log_success "Cache cleared"
}

init_submodules() {
    log_info "Initializing git submodules..."
    
    if [ ! -f ".gitmodules" ]; then
        log_error ".gitmodules not found"
        exit 1
    fi
    
    if [ -f "golpe/rules.mk" ] && [ -f "external/negentropy/cpp/negentropy.h" ]; then
        log_success "Submodules already initialized"
        return
    fi
    
    git submodule update --init --recursive
    
    if [ ! -f "golpe/rules.mk" ]; then
        log_error "Failed to initialize golpe submodule"
        exit 1
    fi
    
    log_success "Submodules initialized"
}

build_image() {
    log_info "Building Docker image using $DOCKERFILE..."
    log_info "This may take 5-10 minutes..."
    echo ""
    
    cd "${SCRIPT_DIR}"
    
    docker build \
        --no-cache \
        -f "$DOCKERFILE" \
        -t "${IMAGE_NAME}:${IMAGE_TAG}" \
        .
    
    if [ $? -eq 0 ]; then
        log_success "Build completed successfully!"
    else
        log_error "Build failed!"
        exit 1
    fi
}

verify_build() {
    log_info "Verifying build..."
    
    if ! docker images 2>/dev/null | grep -q "${IMAGE_NAME}"; then
        log_error "Image not found after build"
        exit 1
    fi
    
    log_success "Build verification complete!"
    echo ""
    echo "Image: ${IMAGE_NAME}:${IMAGE_TAG}"
    echo "Size: $(docker images --format "{{.Size}}" "${IMAGE_NAME}:${IMAGE_TAG}")"
}

print_next_steps() {
    echo ""
    echo "=============================================="
    echo "  Build Complete! ($BUILD_TYPE)"
    echo "=============================================="
    echo ""
    echo "Next steps:"
    echo ""
    echo "1. Start the relay:"
    echo "   docker-compose -f docker-compose.aastar.yml up -d"
    echo ""
    echo "2. Test:"
    echo "   curl http://localhost:7777"
    echo ""
    echo "=============================================="
}

main() {
    echo "=============================================="
    echo "  AASTAR Relay Builder"
    echo "=============================================="
    echo ""
    
    cd "${SCRIPT_DIR}"
    
    check_prerequisites
    clear_cache
    init_submodules
    build_image
    verify_build
    print_next_steps
}

main "$@"
