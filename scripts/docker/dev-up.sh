#!/bin/bash
# SecureSharing Development Environment Startup Script
#
# Usage:
#   ./scripts/docker/dev-up.sh           # Start core services (postgres + garage)
#   ./scripts/docker/dev-up.sh pii       # Start core + PII services
#   ./scripts/docker/dev-up.sh all       # Start all services
#   ./scripts/docker/dev-up.sh -h        # Show help

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

show_help() {
    echo "SecureSharing Development Environment"
    echo ""
    echo "Usage: $0 [profile]"
    echo ""
    echo "Profiles:"
    echo "  (none)      Start core services (PostgreSQL + Garage)"
    echo "  pii         Start core + PII services (Ollama, Presidio)"
    echo "  email       Start core + MailHog for email testing"
    echo "  distributed Start core + Redis for caching"
    echo "  all         Start all services"
    echo ""
    echo "Options:"
    echo "  -h, --help  Show this help message"
    echo "  -d, --down  Stop all services"
    echo "  -r, --reset Stop and remove all data (reset)"
    echo ""
    echo "Examples:"
    echo "  $0              # Start core services"
    echo "  $0 pii          # Start with PII detection services"
    echo "  $0 -d           # Stop all services"
    echo "  $0 -r           # Reset all data"
}

cd "$PROJECT_ROOT"

case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    -d|--down)
        echo -e "${YELLOW}Stopping all services...${NC}"
        docker-compose --profile all down
        echo -e "${GREEN}All services stopped.${NC}"
        exit 0
        ;;
    -r|--reset)
        echo -e "${RED}WARNING: This will delete all data!${NC}"
        read -p "Are you sure? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}Stopping and removing all data...${NC}"
            docker-compose --profile all down -v
            echo -e "${GREEN}All data has been reset.${NC}"
        fi
        exit 0
        ;;
    pii)
        echo -e "${BLUE}Starting core + PII services...${NC}"
        echo -e "  - PostgreSQL (port 5433)"
        echo -e "  - Garage S3 (port 3900)"
        echo -e "  - Ollama (port 11434)"
        echo -e "  - Presidio (port 5002)"
        echo ""
        docker-compose --profile pii up -d
        ;;
    email)
        echo -e "${BLUE}Starting core + email services...${NC}"
        docker-compose --profile email up -d
        ;;
    distributed)
        echo -e "${BLUE}Starting core + Redis...${NC}"
        docker-compose --profile distributed up -d
        ;;
    all)
        echo -e "${BLUE}Starting ALL services...${NC}"
        docker-compose --profile all up -d
        ;;
    "")
        echo -e "${BLUE}Starting core services...${NC}"
        echo -e "  - PostgreSQL (port 5433)"
        echo -e "  - Garage S3 (port 3900)"
        echo ""
        docker-compose up -d
        ;;
    *)
        echo -e "${RED}Unknown option: $1${NC}"
        show_help
        exit 1
        ;;
esac

# Wait for services to be healthy
echo ""
echo -e "${YELLOW}Waiting for services to be healthy...${NC}"

# Check PostgreSQL
echo -n "PostgreSQL: "
for i in {1..30}; do
    if docker-compose exec -T postgres pg_isready -U securesharing > /dev/null 2>&1; then
        echo -e "${GREEN}Ready${NC}"
        break
    fi
    if [ $i -eq 30 ]; then
        echo -e "${RED}Not ready (timeout)${NC}"
    fi
    sleep 1
done

# Check Garage
echo -n "Garage: "
for i in {1..30}; do
    if curl -sf http://localhost:3903/health > /dev/null 2>&1; then
        echo -e "${GREEN}Ready${NC}"
        break
    fi
    if [ $i -eq 30 ]; then
        echo -e "${RED}Not ready (timeout)${NC}"
    fi
    sleep 1
done

# Check profile-specific services
case "${1:-}" in
    pii|all)
        echo -n "Ollama: "
        for i in {1..60}; do
            if curl -sf http://localhost:11434/api/tags > /dev/null 2>&1; then
                echo -e "${GREEN}Ready${NC}"
                break
            fi
            if [ $i -eq 60 ]; then
                echo -e "${YELLOW}Starting (models may still be downloading)${NC}"
            fi
            sleep 2
        done

        echo -n "Presidio: "
        for i in {1..90}; do
            if curl -sf http://localhost:5002/health > /dev/null 2>&1; then
                echo -e "${GREEN}Ready${NC}"
                break
            fi
            if [ $i -eq 90 ]; then
                echo -e "${YELLOW}Starting (spaCy model loading)${NC}"
            fi
            sleep 2
        done
        ;;
esac

echo ""
echo -e "${GREEN}Development environment is ready!${NC}"
echo ""
echo "Service URLs:"
echo "  PostgreSQL: localhost:5433"
echo "  Garage S3:  localhost:3900"

case "${1:-}" in
    pii|all)
        echo "  Ollama:     localhost:11434"
        echo "  Presidio:   localhost:5002"
        ;;
    email|all)
        echo "  MailHog:    localhost:8025 (Web UI)"
        ;;
    distributed|all)
        echo "  Redis:      localhost:6379"
        ;;
esac

echo ""
echo "To run PII Service locally:"
echo "  cd services/pii_service"
echo "  mix deps.get"
echo "  mix ecto.setup"
echo "  mix phx.server"
