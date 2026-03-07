#!/bin/bash
#
# SecureSharing Development Environment Setup
# ============================================
#
# This script sets up the complete development environment on macOS.
# Optimized for Apple Silicon (M4 Max) with Orbstack.
#
# Usage:
#   ./scripts/dev-setup.sh              # Full setup
#   ./scripts/dev-setup.sh --start      # Start services only
#   ./scripts/dev-setup.sh --stop       # Stop services
#   ./scripts/dev-setup.sh --reset      # Reset everything (destructive)
#   ./scripts/dev-setup.sh --status     # Show service status
#   ./scripts/dev-setup.sh --pii        # Include PII services (Ollama, Presidio)
#
# Requirements:
#   - Orbstack (brew install orbstack)
#   - Elixir 1.16+ (brew install elixir)
#   - Node.js 20+ (brew install node)
#   - jq (brew install jq)
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Configuration
COMPOSE_FILE="$PROJECT_ROOT/docker-compose.yml"
GARAGE_CONFIG="$PROJECT_ROOT/config/garage.toml"
GARAGE_ADMIN_TOKEN="securesharing-admin-token"

# Parse arguments
ACTION="setup"
INCLUDE_PII=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --start)
            ACTION="start"
            shift
            ;;
        --stop)
            ACTION="stop"
            shift
            ;;
        --reset)
            ACTION="reset"
            shift
            ;;
        --status)
            ACTION="status"
            shift
            ;;
        --pii)
            INCLUDE_PII=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--start|--stop|--reset|--status] [--pii]"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Helper functions
print_header() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_step() {
    echo -e "${BLUE}▶${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        print_error "$1 is not installed"
        return 1
    fi
    return 0
}

# Check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"

    local missing=0

    # Check Docker/Orbstack
    if check_command docker; then
        DOCKER_VERSION=$(docker --version 2>/dev/null || echo "unknown")
        print_success "Docker: $DOCKER_VERSION"

        # Check if Docker daemon is running
        if ! docker info &> /dev/null; then
            print_error "Docker daemon is not running. Start Orbstack first."
            missing=1
        fi
    else
        print_error "Docker not found. Install Orbstack: brew install orbstack"
        missing=1
    fi

    # Check docker-compose
    if check_command docker-compose; then
        print_success "docker-compose: $(docker-compose --version 2>/dev/null | head -1)"
    elif docker compose version &> /dev/null; then
        print_success "docker compose: $(docker compose version 2>/dev/null)"
        # Create alias
        alias docker-compose='docker compose'
    else
        print_error "docker-compose not found"
        missing=1
    fi

    # Check Elixir
    if check_command elixir; then
        print_success "Elixir: $(elixir --version 2>/dev/null | head -1)"
    else
        print_warning "Elixir not found. Install: brew install elixir"
        missing=1
    fi

    # Check Node.js
    if check_command node; then
        print_success "Node.js: $(node --version 2>/dev/null)"
    else
        print_warning "Node.js not found. Install: brew install node"
        missing=1
    fi

    # Check jq
    if check_command jq; then
        print_success "jq: $(jq --version 2>/dev/null)"
    else
        print_warning "jq not found. Install: brew install jq"
        missing=1
    fi

    if [ $missing -eq 1 ]; then
        echo ""
        print_error "Some prerequisites are missing. Please install them and try again."
        exit 1
    fi

    print_success "All prerequisites satisfied!"
}

# Create config directory and files
create_config_files() {
    print_header "Creating Configuration Files"

    # Create config directory
    mkdir -p "$PROJECT_ROOT/config"

    # Create garage.toml if it doesn't exist at root
    if [ ! -f "$GARAGE_CONFIG" ]; then
        print_step "Creating $GARAGE_CONFIG"
        cat > "$GARAGE_CONFIG" << 'EOF'
# Garage Configuration for Development
# https://garagehq.deuxfleurs.fr/documentation/reference-manual/configuration/

metadata_dir = "/var/lib/garage/meta"
data_dir = "/var/lib/garage/data"

db_engine = "sqlite"

replication_factor = 1

rpc_secret = "78ec854747005c7808f8a5baa310acd6c73dfe87dd6ecf9223c080ab2b436d5c"

rpc_bind_addr = "[::]:3901"
rpc_public_addr = "127.0.0.1:3901"

[s3_api]
s3_region = "garage"
api_bind_addr = "[::]:3900"
root_domain = ".s3.garage.localhost"

[s3_web]
bind_addr = "[::]:3902"
root_domain = ".web.garage.localhost"

[admin]
api_bind_addr = "[::]:3903"
admin_token = "securesharing-admin-token"
EOF
        print_success "Created garage.toml"
    else
        print_success "garage.toml already exists"
    fi

    # Create .env file if it doesn't exist
    if [ ! -f "$PROJECT_ROOT/.env" ]; then
        print_step "Creating .env file"
        cat > "$PROJECT_ROOT/.env" << 'EOF'
# SecureSharing Development Environment Variables
# Copy to .env.local for personal overrides

# PostgreSQL
POSTGRES_USER=securesharing
POSTGRES_PASSWORD=securesharing_dev
POSTGRES_DB=securesharing_dev
POSTGRES_PORT=5433

# Garage S3 Storage
GARAGE_S3_PORT=3900
GARAGE_RPC_PORT=3901
GARAGE_WEB_PORT=3902
GARAGE_ADMIN_PORT=3903

# Ollama LLM
OLLAMA_PORT=11434

# Presidio NER
PRESIDIO_PORT=5002

# MailHog
MAILHOG_SMTP_PORT=1025
MAILHOG_WEB_PORT=8025

# Redis
REDIS_PORT=6379
EOF
        print_success "Created .env file"
    else
        print_success ".env file already exists"
    fi
}

# Start Docker services
start_services() {
    print_header "Starting Docker Services"

    cd "$PROJECT_ROOT"

    if [ "$INCLUDE_PII" = true ]; then
        print_step "Starting core + PII services (postgres, garage, ollama, presidio)..."
        docker-compose --profile pii up -d
    else
        print_step "Starting core services (postgres, garage)..."
        docker-compose up -d
    fi

    print_success "Docker services started"

    # Wait for services to be healthy
    print_step "Waiting for services to be healthy..."

    local max_wait=60
    local waited=0

    while [ $waited -lt $max_wait ]; do
        if docker-compose ps | grep -q "healthy"; then
            break
        fi
        sleep 2
        waited=$((waited + 2))
        echo -n "."
    done
    echo ""

    # Check service health
    if docker-compose ps | grep -q "(unhealthy)"; then
        print_warning "Some services are unhealthy. Check logs with: docker-compose logs"
    else
        print_success "All services are healthy"
    fi
}

# Stop Docker services
stop_services() {
    print_header "Stopping Docker Services"

    cd "$PROJECT_ROOT"
    docker-compose --profile all down

    print_success "All services stopped"
}

# Show service status
show_status() {
    print_header "Service Status"

    cd "$PROJECT_ROOT"
    docker-compose --profile all ps

    echo ""
    print_step "Port Mappings:"
    echo "  - PostgreSQL:  localhost:5433"
    echo "  - Garage S3:   localhost:3900"
    echo "  - Garage Admin: localhost:3903"

    if [ "$INCLUDE_PII" = true ] || docker ps | grep -q "ollama"; then
        echo "  - Ollama:      localhost:11434"
        echo "  - Presidio:    localhost:5002"
    fi

    if docker ps | grep -q "mailhog"; then
        echo "  - MailHog SMTP: localhost:1025"
        echo "  - MailHog Web:  localhost:8025"
    fi
}

# Initialize Garage (buckets and keys)
init_garage() {
    print_header "Initializing Garage S3 Storage"

    local GARAGE_ADMIN_API="http://localhost:3903"

    # Wait for Garage to be ready
    print_step "Waiting for Garage admin API..."
    local max_wait=30
    local waited=0

    while [ $waited -lt $max_wait ]; do
        if curl -sf "$GARAGE_ADMIN_API/health" > /dev/null 2>&1; then
            break
        fi
        sleep 1
        waited=$((waited + 1))
    done

    if [ $waited -ge $max_wait ]; then
        print_error "Garage admin API not responding. Check: docker-compose logs garage"
        return 1
    fi

    print_success "Garage is ready"

    # Run the garage init script
    if [ -f "$SCRIPT_DIR/garage-init.sh" ]; then
        print_step "Running garage initialization..."
        bash "$SCRIPT_DIR/garage-init.sh"
    else
        print_warning "garage-init.sh not found. Skipping Garage bucket setup."
    fi
}

# Setup Elixir projects
setup_elixir_projects() {
    print_header "Setting Up Elixir Projects"

    # SecureSharing Backend
    print_step "Setting up SecureSharing backend..."
    cd "$PROJECT_ROOT/services/securesharing"

    if [ ! -d "deps" ]; then
        mix local.hex --force
        mix local.rebar --force
        mix deps.get
    else
        print_success "Dependencies already installed"
    fi

    # Compile
    print_step "Compiling..."
    mix compile

    # Setup database
    print_step "Setting up database..."
    mix ecto.create 2>/dev/null || true
    mix ecto.migrate

    print_success "SecureSharing backend ready"

    # PII Service
    if [ -d "$PROJECT_ROOT/services/pii_service" ]; then
        print_step "Setting up PII service..."
        cd "$PROJECT_ROOT/services/pii_service"

        if [ ! -d "deps" ]; then
            mix deps.get
        fi

        mix compile
        mix ecto.create 2>/dev/null || true
        mix ecto.migrate

        print_success "PII service ready"
    fi
}

# Run E2E seed data
run_seed_data() {
    print_header "Loading Seed Data"

    cd "$PROJECT_ROOT/services/securesharing"

    print_step "Running E2E seed script..."
    MIX_ENV=dev mix run priv/repo/seeds/e2e_seed.exs

    print_success "Seed data loaded"
}

# Setup E2E test environment
setup_e2e() {
    print_header "Setting Up E2E Test Environment"

    cd "$PROJECT_ROOT/services/securesharing/test/e2e"

    if [ ! -d "node_modules" ]; then
        print_step "Installing npm dependencies..."
        npm install
    else
        print_success "npm dependencies already installed"
    fi

    print_step "Installing Playwright browsers..."
    npx playwright install --with-deps chromium

    print_success "E2E environment ready"
}

# Reset everything
reset_all() {
    print_header "Resetting Development Environment"

    print_warning "This will delete all data and volumes!"
    read -p "Are you sure? (y/N) " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_step "Aborted"
        return
    fi

    cd "$PROJECT_ROOT"

    print_step "Stopping and removing containers..."
    docker-compose --profile all down -v

    print_step "Removing build artifacts..."
    rm -rf services/securesharing/_build
    rm -rf services/securesharing/deps
    rm -rf services/pii_service/_build
    rm -rf services/pii_service/deps
    rm -rf services/securesharing/test/e2e/node_modules

    print_success "Environment reset complete"
    print_step "Run ./scripts/dev-setup.sh to set up again"
}

# Print final instructions
print_instructions() {
    print_header "Development Environment Ready!"

    echo -e "${GREEN}Services running:${NC}"
    echo "  - PostgreSQL:     localhost:5433"
    echo "  - Garage S3:      localhost:3900"
    echo "  - Garage Admin:   localhost:3903"

    if [ "$INCLUDE_PII" = true ]; then
        echo "  - Ollama LLM:     localhost:11434"
        echo "  - Presidio NER:   localhost:5002"
    fi

    echo ""
    echo -e "${GREEN}To start the backend:${NC}"
    echo "  cd services/securesharing"
    echo "  mix phx.server"
    echo ""
    echo -e "${GREEN}To start the PII service:${NC}"
    echo "  cd services/pii_service"
    echo "  mix phx.server"
    echo ""
    echo -e "${GREEN}To run E2E tests:${NC}"
    echo "  cd services/securesharing/test/e2e"
    echo "  npx playwright test --project=api-contracts"
    echo ""
    echo -e "${GREEN}Test Credentials:${NC}"
    echo "  Admin:  admin@securesharing.test / AdminTestPassword123!"
    echo "  User1:  user1@e2e-test.local / TestUserPassword123!"
    echo "  User2:  user2@e2e-test.local / TestUserPassword123!"
    echo ""
    echo -e "${GREEN}Useful commands:${NC}"
    echo "  ./scripts/dev-setup.sh --status   # Check service status"
    echo "  ./scripts/dev-setup.sh --stop     # Stop all services"
    echo "  ./scripts/dev-setup.sh --pii      # Start with PII services"
    echo "  docker-compose logs -f            # View logs"
    echo ""
}

# Main execution
main() {
    print_header "SecureSharing Development Setup"
    echo "Platform: $(uname -s) $(uname -m)"
    echo "Action: $ACTION"
    if [ "$INCLUDE_PII" = true ]; then
        echo "PII Services: Enabled"
    fi

    case $ACTION in
        setup)
            check_prerequisites
            create_config_files
            start_services
            init_garage
            setup_elixir_projects
            run_seed_data
            setup_e2e
            print_instructions
            ;;
        start)
            start_services
            show_status
            ;;
        stop)
            stop_services
            ;;
        status)
            show_status
            ;;
        reset)
            reset_all
            ;;
    esac
}

# Run main
main
