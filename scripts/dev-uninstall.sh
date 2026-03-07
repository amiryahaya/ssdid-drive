#!/bin/bash
#
# SecureSharing Development Environment Uninstall
# ================================================
#
# This script removes the development environment and cleans up resources.
#
# Usage:
#   ./scripts/dev-uninstall.sh              # Interactive cleanup
#   ./scripts/dev-uninstall.sh --all        # Remove everything (no prompt)
#   ./scripts/dev-uninstall.sh --containers # Remove only containers/volumes
#   ./scripts/dev-uninstall.sh --deps       # Remove only build deps
#   ./scripts/dev-uninstall.sh --dry-run    # Show what would be removed
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

# Options
REMOVE_CONTAINERS=false
REMOVE_VOLUMES=false
REMOVE_DEPS=false
REMOVE_CONFIG=false
REMOVE_ALL=false
DRY_RUN=false
INTERACTIVE=true

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --all)
            REMOVE_ALL=true
            INTERACTIVE=false
            shift
            ;;
        --containers)
            REMOVE_CONTAINERS=true
            REMOVE_VOLUMES=true
            INTERACTIVE=false
            shift
            ;;
        --deps)
            REMOVE_DEPS=true
            INTERACTIVE=false
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help|-h)
            echo "SecureSharing Development Environment Uninstall"
            echo ""
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --all          Remove everything (containers, volumes, deps, config)"
            echo "  --containers   Remove only Docker containers and volumes"
            echo "  --deps         Remove only build dependencies (_build, deps, node_modules)"
            echo "  --dry-run      Show what would be removed without actually removing"
            echo "  --help, -h     Show this help message"
            echo ""
            echo "Without options, runs in interactive mode."
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
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

print_dry_run() {
    echo -e "${YELLOW}[DRY-RUN]${NC} Would: $1"
}

confirm() {
    local prompt="$1"
    local default="${2:-n}"

    if [ "$default" = "y" ]; then
        prompt="$prompt [Y/n] "
    else
        prompt="$prompt [y/N] "
    fi

    read -p "$prompt" -n 1 -r
    echo

    if [ "$default" = "y" ]; then
        [[ ! $REPLY =~ ^[Nn]$ ]]
    else
        [[ $REPLY =~ ^[Yy]$ ]]
    fi
}

# Calculate sizes
get_dir_size() {
    local dir="$1"
    if [ -d "$dir" ]; then
        du -sh "$dir" 2>/dev/null | cut -f1
    else
        echo "0"
    fi
}

# Show what will be removed
show_summary() {
    print_header "Cleanup Summary"

    local total_size=0

    echo "The following will be removed:"
    echo ""

    if [ "$REMOVE_CONTAINERS" = true ] || [ "$REMOVE_ALL" = true ]; then
        echo -e "${YELLOW}Docker Containers:${NC}"
        cd "$PROJECT_ROOT"
        docker-compose --profile all ps 2>/dev/null || echo "  (no containers running)"
        echo ""
    fi

    if [ "$REMOVE_VOLUMES" = true ] || [ "$REMOVE_ALL" = true ]; then
        echo -e "${YELLOW}Docker Volumes:${NC}"
        echo "  - securesharing_postgres_data"
        echo "  - securesharing_garage_data"
        echo "  - securesharing_garage_meta"
        echo "  - securesharing_ollama_data"
        echo "  - securesharing_redis_data"
        echo ""
    fi

    if [ "$REMOVE_DEPS" = true ] || [ "$REMOVE_ALL" = true ]; then
        echo -e "${YELLOW}Build Artifacts:${NC}"

        local securesharing_build="$PROJECT_ROOT/services/securesharing/_build"
        local securesharing_deps="$PROJECT_ROOT/services/securesharing/deps"
        local pii_build="$PROJECT_ROOT/services/pii_service/_build"
        local pii_deps="$PROJECT_ROOT/services/pii_service/deps"
        local e2e_node="$PROJECT_ROOT/services/securesharing/test/e2e/node_modules"

        [ -d "$securesharing_build" ] && echo "  - services/securesharing/_build ($(get_dir_size "$securesharing_build"))"
        [ -d "$securesharing_deps" ] && echo "  - services/securesharing/deps ($(get_dir_size "$securesharing_deps"))"
        [ -d "$pii_build" ] && echo "  - services/pii_service/_build ($(get_dir_size "$pii_build"))"
        [ -d "$pii_deps" ] && echo "  - services/pii_service/deps ($(get_dir_size "$pii_deps"))"
        [ -d "$e2e_node" ] && echo "  - services/securesharing/test/e2e/node_modules ($(get_dir_size "$e2e_node"))"
        echo ""
    fi

    if [ "$REMOVE_CONFIG" = true ] || [ "$REMOVE_ALL" = true ]; then
        echo -e "${YELLOW}Configuration Files:${NC}"
        [ -f "$PROJECT_ROOT/.env" ] && echo "  - .env"
        [ -f "$PROJECT_ROOT/config/garage.toml" ] && echo "  - config/garage.toml"
        echo ""
    fi
}

# Interactive mode
run_interactive() {
    print_header "SecureSharing Development Uninstall"

    echo "This script will help you clean up the development environment."
    echo ""

    if confirm "Remove Docker containers?"; then
        REMOVE_CONTAINERS=true
        if confirm "Also remove Docker volumes (database data, S3 storage)?"; then
            REMOVE_VOLUMES=true
        fi
    fi

    if confirm "Remove build dependencies (_build, deps, node_modules)?"; then
        REMOVE_DEPS=true
    fi

    if confirm "Remove configuration files (.env, config/)?"; then
        REMOVE_CONFIG=true
    fi

    if [ "$REMOVE_CONTAINERS" = false ] && [ "$REMOVE_DEPS" = false ] && [ "$REMOVE_CONFIG" = false ]; then
        print_warning "Nothing selected for removal."
        exit 0
    fi
}

# Remove Docker containers
remove_containers() {
    print_step "Stopping Docker containers..."

    cd "$PROJECT_ROOT"

    if [ "$DRY_RUN" = true ]; then
        print_dry_run "docker-compose --profile all down"
    else
        docker-compose --profile all down 2>/dev/null || true
        print_success "Containers stopped"
    fi
}

# Remove Docker volumes
remove_volumes() {
    print_step "Removing Docker volumes..."

    local volumes=(
        "securesharing_postgres_data"
        "securesharing_garage_data"
        "securesharing_garage_meta"
        "securesharing_ollama_data"
        "securesharing_redis_data"
    )

    for vol in "${volumes[@]}"; do
        if docker volume ls -q | grep -q "^${vol}$"; then
            if [ "$DRY_RUN" = true ]; then
                print_dry_run "docker volume rm $vol"
            else
                docker volume rm "$vol" 2>/dev/null || true
                print_success "Removed volume: $vol"
            fi
        fi
    done

    # Also try with project prefix
    local project_volumes=$(docker volume ls -q | grep "^securesharing" 2>/dev/null || true)
    if [ -n "$project_volumes" ]; then
        for vol in $project_volumes; do
            if [ "$DRY_RUN" = true ]; then
                print_dry_run "docker volume rm $vol"
            else
                docker volume rm "$vol" 2>/dev/null || true
                print_success "Removed volume: $vol"
            fi
        done
    fi
}

# Remove build dependencies
remove_deps() {
    print_step "Removing build artifacts..."

    local dirs=(
        "$PROJECT_ROOT/services/securesharing/_build"
        "$PROJECT_ROOT/services/securesharing/deps"
        "$PROJECT_ROOT/services/pii_service/_build"
        "$PROJECT_ROOT/services/pii_service/deps"
        "$PROJECT_ROOT/services/securesharing/test/e2e/node_modules"
        "$PROJECT_ROOT/services/securesharing/test/e2e/test-results"
        "$PROJECT_ROOT/services/securesharing/test/e2e/playwright-report"
    )

    for dir in "${dirs[@]}"; do
        if [ -d "$dir" ]; then
            local rel_path="${dir#$PROJECT_ROOT/}"
            if [ "$DRY_RUN" = true ]; then
                print_dry_run "rm -rf $rel_path"
            else
                rm -rf "$dir"
                print_success "Removed: $rel_path"
            fi
        fi
    done

    # Remove Erlang/Elixir build caches
    local cache_dirs=(
        "$PROJECT_ROOT/services/securesharing/.elixir_ls"
        "$PROJECT_ROOT/services/pii_service/.elixir_ls"
    )

    for dir in "${cache_dirs[@]}"; do
        if [ -d "$dir" ]; then
            local rel_path="${dir#$PROJECT_ROOT/}"
            if [ "$DRY_RUN" = true ]; then
                print_dry_run "rm -rf $rel_path"
            else
                rm -rf "$dir"
                print_success "Removed: $rel_path"
            fi
        fi
    done
}

# Remove configuration files
remove_config() {
    print_step "Removing configuration files..."

    local files=(
        "$PROJECT_ROOT/.env"
        "$PROJECT_ROOT/.env.local"
    )

    for file in "${files[@]}"; do
        if [ -f "$file" ]; then
            local rel_path="${file#$PROJECT_ROOT/}"
            if [ "$DRY_RUN" = true ]; then
                print_dry_run "rm $rel_path"
            else
                rm "$file"
                print_success "Removed: $rel_path"
            fi
        fi
    done

    # Remove config directory if empty after removing files
    if [ -d "$PROJECT_ROOT/config" ]; then
        if [ "$DRY_RUN" = true ]; then
            print_dry_run "rm -rf config/"
        else
            rm -rf "$PROJECT_ROOT/config"
            print_success "Removed: config/"
        fi
    fi
}

# Remove Docker network
remove_network() {
    print_step "Removing Docker network..."

    if docker network ls -q --filter name=securesharing | grep -q .; then
        if [ "$DRY_RUN" = true ]; then
            print_dry_run "docker network rm securesharing_network"
        else
            docker network rm securesharing_network 2>/dev/null || true
            print_success "Removed network: securesharing_network"
        fi
    fi
}

# Print completion message
print_completion() {
    print_header "Cleanup Complete"

    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}This was a dry run. No changes were made.${NC}"
        echo ""
        echo "Run without --dry-run to actually remove these items."
    else
        echo -e "${GREEN}Development environment has been cleaned up.${NC}"
        echo ""

        if [ "$REMOVE_ALL" = true ] || ([ "$REMOVE_DEPS" = true ] && [ "$REMOVE_VOLUMES" = true ]); then
            echo "To set up again, run:"
            echo "  ./scripts/dev-setup.sh"
        elif [ "$REMOVE_DEPS" = true ]; then
            echo "To reinstall dependencies, run:"
            echo "  cd services/securesharing && mix deps.get"
            echo "  cd services/pii_service && mix deps.get"
        elif [ "$REMOVE_VOLUMES" = true ]; then
            echo "To recreate databases, run:"
            echo "  ./scripts/dev-setup.sh --start"
            echo "  cd services/securesharing && mix ecto.setup"
        fi
    fi
    echo ""
}

# Main execution
main() {
    print_header "SecureSharing Development Uninstall"

    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}Running in dry-run mode. No changes will be made.${NC}"
        echo ""
    fi

    # Set all flags if --all was specified
    if [ "$REMOVE_ALL" = true ]; then
        REMOVE_CONTAINERS=true
        REMOVE_VOLUMES=true
        REMOVE_DEPS=true
        REMOVE_CONFIG=true
    fi

    # Run interactive mode if no specific options
    if [ "$INTERACTIVE" = true ]; then
        run_interactive
    fi

    # Show summary
    show_summary

    # Confirm before proceeding (unless --all or specific option)
    if [ "$INTERACTIVE" = true ] && [ "$DRY_RUN" = false ]; then
        echo ""
        if ! confirm "Proceed with cleanup?" "n"; then
            print_warning "Aborted."
            exit 0
        fi
    fi

    echo ""

    # Execute cleanup
    if [ "$REMOVE_CONTAINERS" = true ]; then
        remove_containers
    fi

    if [ "$REMOVE_VOLUMES" = true ]; then
        remove_volumes
        remove_network
    fi

    if [ "$REMOVE_DEPS" = true ]; then
        remove_deps
    fi

    if [ "$REMOVE_CONFIG" = true ]; then
        remove_config
    fi

    print_completion
}

# Run main
main
