#!/bin/bash
# SecureSharing Deployment Script
# Run this script to deploy a new version

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Configuration
INSTALL_DIR="/opt/securesharing"
SOURCE_DIR="${1:-$(pwd)}"
USER="securesharing"
GROUP="securesharing"
SERVICE="secure-sharing"

# Verify we're in the right directory
if [ ! -f "$SOURCE_DIR/mix.exs" ]; then
    log_error "mix.exs not found. Please run from the securesharing service directory"
    log_error "Usage: ./deployment/deploy.sh [source_directory]"
    exit 1
fi

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log_error "Please run as root (sudo ./deploy.sh)"
    exit 1
fi

log_info "Starting deployment from $SOURCE_DIR"

# Backup current release
backup_release() {
    if [ -d "$INSTALL_DIR/lib" ]; then
        BACKUP_NAME="backup_$(date +%Y%m%d_%H%M%S)"
        log_info "Backing up current release to $INSTALL_DIR/backups/$BACKUP_NAME"
        mkdir -p "$INSTALL_DIR/backups"
        cp -r "$INSTALL_DIR/lib" "$INSTALL_DIR/bin" "$INSTALL_DIR/releases" "$INSTALL_DIR/backups/$BACKUP_NAME/" 2>/dev/null || true
    fi
}

# Build the release
build_release() {
    log_info "Building release..."
    cd "$SOURCE_DIR"

    # Clean previous build
    rm -rf _build/prod/rel

    # Get dependencies
    sudo -u nobody MIX_ENV=prod mix local.hex --force
    sudo -u nobody MIX_ENV=prod mix local.rebar --force
    sudo -u nobody MIX_ENV=prod mix deps.get --only prod

    # Compile
    sudo -u nobody MIX_ENV=prod mix compile

    # Build release
    sudo -u nobody MIX_ENV=prod mix release

    log_info "Release built successfully"
}

# Stop service
stop_service() {
    log_info "Stopping service..."
    systemctl stop $SERVICE 2>/dev/null || true
    sleep 2
}

# Deploy release
deploy_release() {
    log_info "Deploying release..."

    # Copy release files
    cp -r "$SOURCE_DIR/_build/prod/rel/secure_sharing/"* "$INSTALL_DIR/"

    # Set permissions
    chown -R "$USER:$GROUP" "$INSTALL_DIR"
    chmod +x "$INSTALL_DIR/bin/"*

    log_info "Release deployed to $INSTALL_DIR"
}

# Run migrations
run_migrations() {
    log_info "Running database migrations..."
    sudo -u "$USER" "$INSTALL_DIR/bin/secure_sharing" eval "SecureSharing.Release.migrate()"
    log_info "Migrations completed"
}

# Start service
start_service() {
    log_info "Starting service..."
    systemctl start $SERVICE
    sleep 3

    if systemctl is-active --quiet $SERVICE; then
        log_info "Service started successfully"
    else
        log_error "Service failed to start. Check logs: journalctl -u $SERVICE -n 50"
        exit 1
    fi
}

# Health check
health_check() {
    log_info "Running health check..."
    sleep 5

    # Get port from env file
    PORT=$(grep "^PORT=" "$INSTALL_DIR/.env" | cut -d'=' -f2)
    PORT=${PORT:-4000}

    RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$PORT/health" 2>/dev/null || echo "000")

    if [ "$RESPONSE" = "200" ]; then
        log_info "Health check passed!"
    else
        log_warn "Health check returned: $RESPONSE"
        log_warn "Service may still be starting. Check: curl http://localhost:$PORT/health"
    fi
}

# Cleanup old backups (keep last 5)
cleanup_backups() {
    log_info "Cleaning up old backups..."
    cd "$INSTALL_DIR/backups" 2>/dev/null || return
    ls -t | tail -n +6 | xargs -r rm -rf
}

# Main deployment flow
main() {
    echo "=========================================="
    echo "  SecureSharing Deployment"
    echo "=========================================="
    echo ""

    backup_release
    build_release
    stop_service
    deploy_release
    run_migrations
    start_service
    health_check
    cleanup_backups

    echo ""
    echo "=========================================="
    echo "  Deployment Complete!"
    echo "=========================================="
    echo ""
    echo "Service status: systemctl status $SERVICE"
    echo "View logs: journalctl -u $SERVICE -f"
    echo ""
}

main "$@"
