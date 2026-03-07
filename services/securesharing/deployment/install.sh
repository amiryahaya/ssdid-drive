#!/bin/bash
# SecureSharing Installation Script for Linux
# Supports: Ubuntu 22.04+, Debian 12+, Rocky Linux 9+, AlmaLinux 9+

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Configuration
INSTALL_DIR="/opt/securesharing"
DATA_DIR="/var/lib/securesharing"
USER="securesharing"
GROUP="securesharing"

# Detect OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    else
        log_error "Cannot detect OS. /etc/os-release not found."
        exit 1
    fi
    log_info "Detected OS: $OS $VERSION"
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Please run as root (sudo ./install.sh)"
        exit 1
    fi
}

# Install system dependencies
install_dependencies() {
    log_info "Installing system dependencies..."

    case $OS in
        ubuntu|debian)
            apt-get update
            apt-get install -y \
                curl \
                wget \
                git \
                build-essential \
                autoconf \
                libncurses5-dev \
                libssl-dev \
                libpq-dev \
                postgresql \
                postgresql-contrib \
                unzip
            ;;
        rocky|almalinux|rhel|centos)
            dnf install -y \
                curl \
                wget \
                git \
                gcc \
                gcc-c++ \
                make \
                autoconf \
                ncurses-devel \
                openssl-devel \
                libpq-devel \
                postgresql-server \
                postgresql-contrib \
                unzip

            # Initialize PostgreSQL if not done
            if [ ! -f /var/lib/pgsql/data/PG_VERSION ]; then
                postgresql-setup --initdb
            fi
            ;;
        *)
            log_error "Unsupported OS: $OS"
            exit 1
            ;;
    esac
}

# Install Erlang and Elixir via asdf
install_erlang_elixir() {
    log_info "Installing Erlang and Elixir..."

    # Install asdf if not present
    if [ ! -d "$INSTALL_DIR/.asdf" ]; then
        git clone https://github.com/asdf-vm/asdf.git "$INSTALL_DIR/.asdf" --branch v0.14.0
    fi

    # Source asdf
    export ASDF_DIR="$INSTALL_DIR/.asdf"
    . "$ASDF_DIR/asdf.sh"

    # Install plugins
    asdf plugin add erlang || true
    asdf plugin add elixir || true

    # Install versions
    log_info "Installing Erlang 27.0 (this may take a while)..."
    asdf install erlang 27.0
    asdf global erlang 27.0

    log_info "Installing Elixir 1.17.0..."
    asdf install elixir 1.17.0-otp-27
    asdf global elixir 1.17.0-otp-27
}

# Create user and directories
setup_user_and_dirs() {
    log_info "Setting up user and directories..."

    # Create user if not exists
    if ! id "$USER" &>/dev/null; then
        useradd --system --home "$INSTALL_DIR" --shell /bin/bash "$USER"
    fi

    # Create directories
    mkdir -p "$INSTALL_DIR"/{releases,tmp,logs}
    mkdir -p "$DATA_DIR"/{uploads,backups}

    # Set permissions
    chown -R "$USER:$GROUP" "$INSTALL_DIR"
    chown -R "$USER:$GROUP" "$DATA_DIR"
    chmod 750 "$INSTALL_DIR"
    chmod 750 "$DATA_DIR"
}

# Setup PostgreSQL
setup_postgresql() {
    log_info "Setting up PostgreSQL..."

    # Start and enable PostgreSQL
    systemctl start postgresql
    systemctl enable postgresql

    # Create database user and database
    sudo -u postgres psql -c "CREATE USER securesharing WITH PASSWORD 'change_this_password';" 2>/dev/null || true
    sudo -u postgres psql -c "CREATE DATABASE securesharing_prod OWNER securesharing;" 2>/dev/null || true
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE securesharing_prod TO securesharing;" 2>/dev/null || true

    log_warn "Database created with default password. Update DATABASE_URL in .env file!"
}

# Install liboqs for post-quantum cryptography
install_liboqs() {
    log_info "Installing liboqs for post-quantum cryptography..."

    # Check if already installed
    if [ -f /usr/local/lib/liboqs.so ]; then
        log_info "liboqs already installed"
        return
    fi

    # Install cmake if needed
    case $OS in
        ubuntu|debian)
            apt-get install -y cmake ninja-build
            ;;
        rocky|almalinux|rhel|centos)
            dnf install -y cmake ninja-build
            ;;
    esac

    # Build liboqs
    cd /tmp
    git clone --depth 1 --branch 0.10.1 https://github.com/open-quantum-safe/liboqs.git
    cd liboqs
    mkdir build && cd build
    cmake -GNinja -DCMAKE_INSTALL_PREFIX=/usr/local ..
    ninja
    ninja install
    ldconfig

    # Cleanup
    rm -rf /tmp/liboqs

    log_info "liboqs installed successfully"
}

# Setup environment file
setup_env() {
    log_info "Setting up environment file..."

    if [ ! -f "$INSTALL_DIR/.env" ]; then
        cp "$(dirname "$0")/env.example" "$INSTALL_DIR/.env"

        # Generate secret key
        SECRET_KEY=$(openssl rand -hex 64)
        sed -i "s/your_64_character_secret_key_here/$SECRET_KEY/" "$INSTALL_DIR/.env"

        chmod 600 "$INSTALL_DIR/.env"
        chown "$USER:$GROUP" "$INSTALL_DIR/.env"

        log_warn "Environment file created at $INSTALL_DIR/.env"
        log_warn "Please edit it to configure your deployment!"
    else
        log_info "Environment file already exists, skipping..."
    fi
}

# Install systemd service
install_service() {
    log_info "Installing systemd service..."

    cp "$(dirname "$0")/secure-sharing.service" /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable secure-sharing

    log_info "Service installed. Start with: systemctl start secure-sharing"
}

# Build release
build_release() {
    log_info "Building release..."

    # This would be run during deployment, not installation
    log_warn "To build a release, run as the securesharing user:"
    log_warn "  cd /path/to/source"
    log_warn "  MIX_ENV=prod mix deps.get --only prod"
    log_warn "  MIX_ENV=prod mix compile"
    log_warn "  MIX_ENV=prod mix release"
    log_warn "  cp -r _build/prod/rel/secure_sharing/* $INSTALL_DIR/"
}

# Print final instructions
print_instructions() {
    echo ""
    echo "=========================================="
    echo "  SecureSharing Installation Complete"
    echo "=========================================="
    echo ""
    echo "Next steps:"
    echo ""
    echo "1. Edit the environment file:"
    echo "   sudo nano $INSTALL_DIR/.env"
    echo ""
    echo "2. Update the database password in .env and PostgreSQL:"
    echo "   sudo -u postgres psql -c \"ALTER USER securesharing PASSWORD 'your_new_password';\""
    echo ""
    echo "3. Build and deploy the release:"
    echo "   cd /path/to/source/services/securesharing"
    echo "   MIX_ENV=prod mix deps.get --only prod"
    echo "   MIX_ENV=prod mix compile"
    echo "   MIX_ENV=prod mix release"
    echo "   sudo cp -r _build/prod/rel/secure_sharing/* $INSTALL_DIR/"
    echo "   sudo chown -R $USER:$GROUP $INSTALL_DIR"
    echo ""
    echo "4. Run database migrations:"
    echo "   sudo -u $USER $INSTALL_DIR/bin/secure_sharing eval \"SecureSharing.Release.migrate()\""
    echo ""
    echo "5. Start the service:"
    echo "   sudo systemctl start secure-sharing"
    echo "   sudo systemctl status secure-sharing"
    echo ""
    echo "6. (Optional) Setup nginx reverse proxy for SSL"
    echo ""
    echo "Logs: journalctl -u secure-sharing -f"
    echo ""
}

# Main installation flow
main() {
    echo "=========================================="
    echo "  SecureSharing Installation Script"
    echo "=========================================="
    echo ""

    check_root
    detect_os
    install_dependencies
    setup_user_and_dirs
    setup_postgresql
    install_liboqs
    install_erlang_elixir
    setup_env
    install_service
    print_instructions
}

# Run main function
main "$@"
