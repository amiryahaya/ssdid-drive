#!/bin/bash
#
# Wait for E2E Services Script
#
# Waits for all E2E services to become healthy before running tests.
# Includes health checks for PostgreSQL, Backend, PII Service, and Garage.
#
# Usage: ./scripts/e2e/wait-for-services.sh [--timeout SECONDS]
#
# Options:
#   --timeout SECONDS    Maximum time to wait (default: 300)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configuration
DEFAULT_TIMEOUT=300
POLL_INTERVAL=5

# Service URLs (can be overridden by environment)
BACKEND_URL="${BACKEND_URL:-http://localhost:4000}"
PII_SERVICE_URL="${PII_SERVICE_URL:-http://localhost:4001}"
POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
POSTGRES_PORT="${POSTGRES_PORT:-5433}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_wait() { echo -e "${BLUE}[WAIT]${NC} $1"; }

# ============================================================================
# Health Check Functions
# ============================================================================

check_postgres() {
    if command -v pg_isready &>/dev/null; then
        pg_isready -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U postgres &>/dev/null
    else
        # Fallback: try to connect via TCP
        nc -z "$POSTGRES_HOST" "$POSTGRES_PORT" &>/dev/null
    fi
}

check_backend() {
    local RESPONSE
    RESPONSE=$(curl -sf "${BACKEND_URL}/health" 2>/dev/null) || return 1
    echo "$RESPONSE" | grep -qi "ok\|healthy\|success" && return 0
    return 1
}

check_pii_service() {
    local RESPONSE
    RESPONSE=$(curl -sf "${PII_SERVICE_URL}/health" 2>/dev/null) || return 1
    echo "$RESPONSE" | grep -qi "ok\|healthy\|success" && return 0
    return 1
}

check_garage() {
    curl -sf "http://localhost:3900/health" &>/dev/null
}

# ============================================================================
# Wait Functions
# ============================================================================

wait_for_service() {
    local SERVICE_NAME="$1"
    local CHECK_FUNC="$2"
    local TIMEOUT="$3"
    local ELAPSED=0

    log_wait "Waiting for $SERVICE_NAME..."

    while [ $ELAPSED -lt $TIMEOUT ]; do
        if $CHECK_FUNC; then
            log_info "$SERVICE_NAME is healthy"
            return 0
        fi

        sleep $POLL_INTERVAL
        ELAPSED=$((ELAPSED + POLL_INTERVAL))

        # Progress indicator
        local REMAINING=$((TIMEOUT - ELAPSED))
        printf "\r${BLUE}[WAIT]${NC} $SERVICE_NAME: ${ELAPSED}s elapsed, ${REMAINING}s remaining..."
    done

    echo ""
    log_error "$SERVICE_NAME failed to become healthy within ${TIMEOUT}s"
    return 1
}

# ============================================================================
# Main
# ============================================================================

main() {
    local TIMEOUT=$DEFAULT_TIMEOUT

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            --help|-h)
                echo "Usage: $0 [--timeout SECONDS]"
                echo ""
                echo "Options:"
                echo "  --timeout SECONDS    Maximum time to wait (default: $DEFAULT_TIMEOUT)"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    echo ""
    echo "=============================================="
    echo "Waiting for E2E Services"
    echo "=============================================="
    echo ""
    echo "Timeout: ${TIMEOUT}s"
    echo "Backend URL: $BACKEND_URL"
    echo "PII Service URL: $PII_SERVICE_URL"
    echo "PostgreSQL: ${POSTGRES_HOST}:${POSTGRES_PORT}"
    echo ""

    local START_TIME=$(date +%s)
    local FAILED=0

    # Wait for services in order of dependency
    echo "--- PostgreSQL ---"
    if ! wait_for_service "PostgreSQL" check_postgres $TIMEOUT; then
        FAILED=1
    fi

    echo ""
    echo "--- Garage (S3) ---"
    if ! wait_for_service "Garage" check_garage $TIMEOUT; then
        log_warn "Garage not available (may be expected if not using S3)"
    fi

    echo ""
    echo "--- Backend ---"
    if ! wait_for_service "Backend" check_backend $TIMEOUT; then
        FAILED=1
    fi

    echo ""
    echo "--- PII Service ---"
    if ! wait_for_service "PII Service" check_pii_service $TIMEOUT; then
        FAILED=1
    fi

    local END_TIME=$(date +%s)
    local TOTAL_TIME=$((END_TIME - START_TIME))

    echo ""
    echo "=============================================="

    if [ $FAILED -eq 0 ]; then
        echo -e "${GREEN}All services are healthy!${NC}"
        echo "Total wait time: ${TOTAL_TIME}s"
        echo "=============================================="
        exit 0
    else
        echo -e "${RED}Some services failed to start${NC}"
        echo "=============================================="
        echo ""
        echo "Troubleshooting:"
        echo "  1. Check container logs:"
        echo "     podman-compose -f podman-compose.e2e.yml logs"
        echo ""
        echo "  2. Check container status:"
        echo "     podman-compose -f podman-compose.e2e.yml ps"
        echo ""
        echo "  3. Restart services:"
        echo "     podman-compose -f podman-compose.e2e.yml down -v"
        echo "     podman-compose -f podman-compose.e2e.yml up -d"
        exit 1
    fi
}

main "$@"
