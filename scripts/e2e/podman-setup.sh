#!/bin/bash
#
# Podman E2E Setup Script
#
# Initializes the Podman environment for E2E testing on macOS and Linux.
# This script checks prerequisites, initializes the Podman machine (macOS),
# and prepares the environment for running E2E tests.
#
# Usage: ./scripts/e2e/podman-setup.sh [--reset]
#
# Options:
#   --reset    Remove and recreate the Podman machine (macOS only)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# ============================================================================
# Prerequisites Check
# ============================================================================

check_prerequisites() {
    log_step "Checking prerequisites..."

    # Check for Podman
    if ! command -v podman &>/dev/null; then
        log_error "Podman is not installed."
        echo ""
        echo "Install Podman:"
        if [[ "$OSTYPE" == "darwin"* ]]; then
            echo "  brew install podman"
        else
            echo "  See: https://podman.io/getting-started/installation"
        fi
        exit 1
    fi
    log_info "Podman: $(podman --version)"

    # Check for podman-compose
    if ! command -v podman-compose &>/dev/null; then
        log_warn "podman-compose is not installed."
        echo ""
        echo "Install podman-compose:"
        echo "  pip3 install podman-compose"
        echo ""
        read -p "Do you want to install podman-compose now? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            pip3 install podman-compose
            log_info "podman-compose installed successfully"
        else
            log_error "podman-compose is required. Please install it manually."
            exit 1
        fi
    fi
    log_info "podman-compose: $(podman-compose --version 2>/dev/null | head -1)"

    # Check for curl (health checks)
    if ! command -v curl &>/dev/null; then
        log_error "curl is not installed. Required for health checks."
        exit 1
    fi
    log_info "curl: available"
}

# ============================================================================
# macOS Podman Machine Setup
# ============================================================================

setup_podman_machine_macos() {
    log_step "Setting up Podman machine for macOS..."

    local MACHINE_NAME="podman-machine-default"
    local RESET=${1:-false}

    # Check if machine exists
    if podman machine list --format "{{.Name}}" | grep -q "$MACHINE_NAME"; then
        if [ "$RESET" = true ]; then
            log_warn "Resetting Podman machine..."
            podman machine stop "$MACHINE_NAME" 2>/dev/null || true
            podman machine rm -f "$MACHINE_NAME"
        else
            # Check if machine is running
            if podman machine list --format "{{.Name}} {{.Running}}" | grep -q "$MACHINE_NAME true"; then
                log_info "Podman machine is already running"
                return 0
            else
                log_info "Starting existing Podman machine..."
                podman machine start "$MACHINE_NAME"
                return 0
            fi
        fi
    fi

    # Create new machine with sufficient resources for E2E tests
    log_info "Creating new Podman machine..."
    podman machine init \
        --cpus 4 \
        --memory 8192 \
        --disk-size 50 \
        "$MACHINE_NAME"

    log_info "Starting Podman machine..."
    podman machine start "$MACHINE_NAME"

    log_info "Podman machine setup complete"
}

# ============================================================================
# Linux Podman Setup
# ============================================================================

setup_podman_linux() {
    log_step "Configuring Podman for Linux..."

    # Ensure user namespaces are enabled
    if [ -f /proc/sys/user/max_user_namespaces ]; then
        local MAX_NS=$(cat /proc/sys/user/max_user_namespaces)
        if [ "$MAX_NS" -lt 1 ]; then
            log_warn "User namespaces may not be properly configured."
            echo "Run: sudo sysctl user.max_user_namespaces=15000"
        fi
    fi

    # Check if Podman socket is available
    local SOCKET_PATH="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/podman/podman.sock"
    if [ ! -S "$SOCKET_PATH" ]; then
        log_info "Starting Podman socket service..."
        systemctl --user start podman.socket 2>/dev/null || true
    fi

    log_info "Podman Linux setup complete"
}

# ============================================================================
# Verify Podman Connection
# ============================================================================

verify_podman() {
    log_step "Verifying Podman connection..."

    if ! podman info &>/dev/null; then
        log_error "Cannot connect to Podman. Please check your installation."
        exit 1
    fi

    # Test container creation
    log_info "Testing container creation..."
    if podman run --rm docker.io/alpine:latest echo "Podman is working!" &>/dev/null; then
        log_info "Container creation: OK"
    else
        log_error "Failed to create test container"
        exit 1
    fi

    log_info "Podman verification complete"
}

# ============================================================================
# Pull Required Images
# ============================================================================

pull_images() {
    log_step "Pulling required container images..."

    local IMAGES=(
        "docker.io/postgres:18-alpine"
        "docker.io/dxflrs/garage:v1.0.1"
        "docker.io/mcr.microsoft.com/playwright:v1.40.0-jammy"
    )

    for IMAGE in "${IMAGES[@]}"; do
        log_info "Pulling $IMAGE..."
        podman pull "$IMAGE" || log_warn "Failed to pull $IMAGE (may be built locally)"
    done

    log_info "Image pull complete"
}

# ============================================================================
# Create Network
# ============================================================================

create_network() {
    log_step "Creating E2E network..."

    local NETWORK_NAME="e2e_network"

    if podman network exists "$NETWORK_NAME" 2>/dev/null; then
        log_info "Network '$NETWORK_NAME' already exists"
    else
        podman network create "$NETWORK_NAME"
        log_info "Network '$NETWORK_NAME' created"
    fi
}

# ============================================================================
# Print Summary
# ============================================================================

print_summary() {
    echo ""
    echo "=============================================="
    echo -e "${GREEN}Podman E2E Environment Ready!${NC}"
    echo "=============================================="
    echo ""
    echo "Podman Version: $(podman --version)"
    echo "podman-compose: $(podman-compose --version 2>/dev/null | head -1)"
    echo ""
    echo "Next steps:"
    echo "  1. Start E2E services:"
    echo "     podman-compose -f podman-compose.e2e.yml up -d"
    echo ""
    echo "  2. Wait for services to be healthy:"
    echo "     ./scripts/e2e/wait-for-services.sh"
    echo ""
    echo "  3. Run E2E tests:"
    echo "     ./scripts/e2e/run-local.sh"
    echo ""
    echo "  4. Stop services:"
    echo "     podman-compose -f podman-compose.e2e.yml down -v"
    echo ""
}

# ============================================================================
# Main
# ============================================================================

main() {
    echo ""
    echo "=============================================="
    echo "SecureSharing E2E - Podman Setup"
    echo "=============================================="
    echo ""

    local RESET=false
    if [ "$1" = "--reset" ]; then
        RESET=true
        log_warn "Reset mode enabled - will recreate Podman machine"
    fi

    check_prerequisites

    # Platform-specific setup
    if [[ "$OSTYPE" == "darwin"* ]]; then
        setup_podman_machine_macos $RESET
    else
        setup_podman_linux
    fi

    verify_podman
    pull_images
    create_network
    print_summary
}

main "$@"
