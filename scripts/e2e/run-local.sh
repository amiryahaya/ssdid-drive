#!/bin/bash
#
# SecureSharing E2E Test Runner
#
# Runs E2E tests locally using Podman. Handles service startup, health checks,
# test execution, and cleanup.
#
# Usage: ./scripts/e2e/run-local.sh [OPTIONS] [TEST_CATEGORY]
#
# Options:
#   --setup          Only start services (don't run tests)
#   --down           Stop all services and clean up
#   --clean          Remove all containers, volumes, and images
#   --watch          Keep services running after tests
#   --verbose        Show detailed output
#   --no-build       Skip building images
#   --timeout SECS   Service startup timeout (default: 300)
#
# Test Categories:
#   all              Run all tests (default)
#   backend          Backend API tests
#   api              API contract tests
#   pii              PII service tests
#   auth             Authentication tests
#   files            File operation tests
#   sharing          Sharing tests
#   invitations      Invitation tests
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMPOSE_FILE="$PROJECT_ROOT/podman-compose.e2e.yml"
E2E_DIR="$PROJECT_ROOT/services/securesharing/test/e2e"

# Configuration
TIMEOUT=300
VERBOSE=false
NO_BUILD=false
KEEP_RUNNING=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }
log_test() { echo -e "${CYAN}[TEST]${NC} $1"; }

# ============================================================================
# Compose Helper
# ============================================================================

compose() {
    if [ "$VERBOSE" = true ]; then
        podman-compose -f "$COMPOSE_FILE" "$@"
    else
        podman-compose -f "$COMPOSE_FILE" "$@" 2>&1
    fi
}

# ============================================================================
# Service Management
# ============================================================================

start_services() {
    log_step "Starting E2E services..."

    cd "$PROJECT_ROOT"

    # Build images if needed
    if [ "$NO_BUILD" = false ]; then
        log_info "Building images..."
        compose build
    fi

    # Start database first
    log_info "Starting PostgreSQL..."
    compose up -d postgres

    # Wait for PostgreSQL
    "$SCRIPT_DIR/wait-for-services.sh" --timeout 60 2>/dev/null || {
        log_info "Waiting for PostgreSQL to be ready..."
        sleep 10
    }

    # Start remaining services
    log_info "Starting Garage, Backend, and PII Service..."
    compose up -d garage
    compose up -d backend pii-service

    # Run database migrations
    log_info "Running database migrations..."
    compose up db-setup pii-db-setup

    # Wait for all services
    log_info "Waiting for all services to be healthy..."
    "$SCRIPT_DIR/wait-for-services.sh" --timeout "$TIMEOUT"

    log_info "All services started successfully!"
}

stop_services() {
    log_step "Stopping E2E services..."

    cd "$PROJECT_ROOT"
    compose down -v

    log_info "Services stopped and volumes removed"
}

clean_all() {
    log_step "Cleaning up all E2E resources..."

    cd "$PROJECT_ROOT"

    # Stop and remove containers
    compose down -v --rmi local 2>/dev/null || true

    # Remove orphan containers
    podman container prune -f 2>/dev/null || true

    # Remove dangling images
    podman image prune -f 2>/dev/null || true

    # Remove E2E volumes
    podman volume ls --format "{{.Name}}" | grep -E "e2e" | xargs -r podman volume rm -f 2>/dev/null || true

    log_info "Cleanup complete"
}

show_logs() {
    local SERVICE="$1"
    cd "$PROJECT_ROOT"
    if [ -n "$SERVICE" ]; then
        compose logs -f "$SERVICE"
    else
        compose logs -f
    fi
}

# ============================================================================
# Test Execution
# ============================================================================

run_tests() {
    local CATEGORY="${1:-all}"

    log_step "Running E2E tests: $CATEGORY"

    cd "$E2E_DIR"

    # Ensure dependencies are installed
    if [ ! -d "node_modules" ]; then
        log_info "Installing test dependencies..."
        npm ci
    fi

    # Build test args based on category
    local TEST_ARGS=""
    case $CATEGORY in
        all)
            TEST_ARGS=""
            ;;
        backend)
            TEST_ARGS="--project=auth --project=files --project=sharing --project=invitations"
            ;;
        api)
            TEST_ARGS="--project=api-contracts"
            ;;
        pii)
            TEST_ARGS="--project=pii"
            ;;
        auth)
            TEST_ARGS="tests/auth/"
            ;;
        files)
            TEST_ARGS="tests/files/"
            ;;
        sharing)
            TEST_ARGS="tests/sharing/"
            ;;
        invitations)
            TEST_ARGS="tests/invitations/"
            ;;
        *)
            # Assume it's a specific test file or pattern
            TEST_ARGS="$CATEGORY"
            ;;
    esac

    # Run tests
    log_test "Executing: npx playwright test $TEST_ARGS"

    local EXIT_CODE=0
    npx playwright test $TEST_ARGS \
        --reporter=html,json \
        || EXIT_CODE=$?

    # Generate report
    if [ -f "playwright-report/index.html" ]; then
        log_info "Test report: file://$E2E_DIR/playwright-report/index.html"
    fi

    return $EXIT_CODE
}

run_tests_in_container() {
    local CATEGORY="${1:-all}"

    log_step "Running E2E tests in container: $CATEGORY"

    cd "$PROJECT_ROOT"

    # Build test args
    local TEST_CMD="npx playwright test"
    if [ "$CATEGORY" != "all" ]; then
        case $CATEGORY in
            backend|api|pii|auth|files|sharing|invitations)
                TEST_CMD="npx playwright test tests/$CATEGORY/"
                ;;
            *)
                TEST_CMD="npx playwright test $CATEGORY"
                ;;
        esac
    fi

    # Run playwright container
    compose run --rm playwright $TEST_CMD --reporter=html,json

    log_info "Test results saved to: $E2E_DIR/playwright-report/"
    log_info "Test artifacts saved to: $E2E_DIR/test-results/"
}

# ============================================================================
# Usage
# ============================================================================

print_usage() {
    echo "SecureSharing E2E Test Runner"
    echo ""
    echo "Usage: $0 [OPTIONS] [TEST_CATEGORY]"
    echo ""
    echo "Options:"
    echo "  --setup          Only start services (don't run tests)"
    echo "  --down           Stop all services and clean up"
    echo "  --clean          Remove all containers, volumes, and images"
    echo "  --watch          Keep services running after tests"
    echo "  --verbose        Show detailed output"
    echo "  --no-build       Skip building images"
    echo "  --container      Run tests inside container (default: local)"
    echo "  --logs [SVC]     Show service logs (optionally filter by service)"
    echo "  --timeout SECS   Service startup timeout (default: 300)"
    echo "  --help           Show this help message"
    echo ""
    echo "Test Categories:"
    echo "  all              Run all tests (default)"
    echo "  backend          Backend API tests"
    echo "  api              API contract tests"
    echo "  pii              PII service tests"
    echo "  auth             Authentication tests"
    echo "  files            File operation tests"
    echo "  sharing          Sharing tests"
    echo "  invitations      Invitation tests"
    echo ""
    echo "Examples:"
    echo "  $0 --setup                 # Start services only"
    echo "  $0 all                     # Run all tests"
    echo "  $0 --watch pii             # Run PII tests, keep services running"
    echo "  $0 tests/auth/login.spec.ts  # Run specific test file"
    echo "  $0 --down                  # Stop all services"
}

# ============================================================================
# Main
# ============================================================================

main() {
    local ACTION="run"
    local TEST_CATEGORY="all"
    local USE_CONTAINER=false
    local LOGS_SERVICE=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --setup)
                ACTION="setup"
                shift
                ;;
            --down)
                ACTION="down"
                shift
                ;;
            --clean)
                ACTION="clean"
                shift
                ;;
            --watch)
                KEEP_RUNNING=true
                shift
                ;;
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --no-build)
                NO_BUILD=true
                shift
                ;;
            --container)
                USE_CONTAINER=true
                shift
                ;;
            --logs)
                ACTION="logs"
                LOGS_SERVICE="${2:-}"
                shift
                [[ -n "$LOGS_SERVICE" && "$LOGS_SERVICE" != --* ]] && shift
                ;;
            --timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            --help|-h)
                print_usage
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
            *)
                TEST_CATEGORY="$1"
                shift
                ;;
        esac
    done

    echo ""
    echo "=============================================="
    echo "SecureSharing E2E Test Runner"
    echo "=============================================="
    echo ""

    case $ACTION in
        setup)
            start_services
            echo ""
            echo "Services are running. Use './scripts/e2e/run-local.sh' to run tests."
            echo "Use './scripts/e2e/run-local.sh --down' to stop services."
            ;;
        down)
            stop_services
            ;;
        clean)
            clean_all
            ;;
        logs)
            show_logs "$LOGS_SERVICE"
            ;;
        run)
            # Check if services are running
            if ! curl -sf "http://localhost:4000/health" &>/dev/null; then
                log_info "Services not running, starting them..."
                start_services
            fi

            # Run tests
            local EXIT_CODE=0
            if [ "$USE_CONTAINER" = true ]; then
                run_tests_in_container "$TEST_CATEGORY" || EXIT_CODE=$?
            else
                run_tests "$TEST_CATEGORY" || EXIT_CODE=$?
            fi

            # Cleanup unless --watch
            if [ "$KEEP_RUNNING" = false ]; then
                log_info "Stopping services..."
                stop_services
            else
                log_info "Services still running (--watch mode)"
                echo "Stop with: ./scripts/e2e/run-local.sh --down"
            fi

            exit $EXIT_CODE
            ;;
    esac
}

main "$@"
