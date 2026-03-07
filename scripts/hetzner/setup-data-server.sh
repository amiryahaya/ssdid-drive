#!/bin/bash
#
# SecureSharing - Data Server Setup Script
# Run this on Hetzner AX42 (Data Server)
#
# Usage: sudo ./setup-data-server.sh
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_step() { echo -e "${GREEN}▶${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }

# Check if root
if [ "$EUID" -ne 0 ]; then
    print_error "Please run as root (sudo)"
    exit 1
fi

print_header "SecureSharing Data Server Setup"

# Configuration
read -p "Enter Compute Server Private IP [10.0.0.1]: " COMPUTE_SERVER_IP
COMPUTE_SERVER_IP=${COMPUTE_SERVER_IP:-10.0.0.1}

read -p "Enter PostgreSQL password: " -s DB_PASSWORD
echo ""
if [ -z "$DB_PASSWORD" ]; then
    print_error "PostgreSQL password is required"
    exit 1
fi

# ============================================================================
# Phase 1: System Setup
# ============================================================================

print_header "Phase 1: System Setup"

print_step "Updating system..."
apt update && apt upgrade -y

print_step "Installing common packages..."
apt install -y \
    curl wget git htop tmux vim \
    ufw fail2ban \
    build-essential \
    unzip jq

print_step "Setting timezone..."
timedatectl set-timezone UTC

print_step "Setting hostname..."
hostnamectl set-hostname data.securesharing.internal

print_step "Configuring /etc/hosts..."
cat >> /etc/hosts << EOF
$COMPUTE_SERVER_IP    compute.securesharing.internal compute
10.0.0.2    data.securesharing.internal data
EOF

# ============================================================================
# Phase 2: Firewall
# ============================================================================

print_header "Phase 2: Firewall Configuration"

print_step "Configuring UFW (private network only)..."
ufw default deny incoming
ufw default allow outgoing
ufw allow from $COMPUTE_SERVER_IP to any port 22 comment 'SSH from compute'
ufw allow from $COMPUTE_SERVER_IP to any port 5432 comment 'PostgreSQL'
ufw allow from $COMPUTE_SERVER_IP to any port 3900 comment 'Garage S3 API'
ufw allow from $COMPUTE_SERVER_IP to any port 3901 comment 'Garage RPC'
ufw allow from $COMPUTE_SERVER_IP to any port 3903 comment 'Garage Admin'

print_step "Enabling firewall..."
echo "y" | ufw enable
ufw status

# ============================================================================
# Phase 3: Install PostgreSQL 18
# ============================================================================

print_header "Phase 3: Installing PostgreSQL 18"

print_step "Adding PostgreSQL repository..."
apt install -y gnupg
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | \
    gpg --dearmor -o /usr/share/keyrings/postgresql.gpg

echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] \
    http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" | \
    tee /etc/apt/sources.list.d/pgdg.list

apt update
apt install -y postgresql-18

print_step "Configuring PostgreSQL..."

# postgresql.conf
cat > /etc/postgresql/18/main/conf.d/securesharing.conf << 'EOF'
# Connection Settings
listen_addresses = '10.0.0.2'
port = 5432
max_connections = 200

# Memory (for 32GB allocated)
shared_buffers = 8GB
effective_cache_size = 24GB
maintenance_work_mem = 2GB
work_mem = 64MB

# WAL
wal_buffers = 64MB
checkpoint_completion_target = 0.9
max_wal_size = 4GB
min_wal_size = 1GB

# Query Planning
random_page_cost = 1.1
effective_io_concurrency = 200

# Logging
log_min_duration_statement = 1000
EOF

# pg_hba.conf
cat >> /etc/postgresql/18/main/pg_hba.conf << EOF

# Allow from Compute server
host    all    all    $COMPUTE_SERVER_IP/32    scram-sha-256
EOF

print_step "Restarting PostgreSQL..."
systemctl restart postgresql

print_step "Creating databases and user..."
sudo -u postgres psql << EOF
-- Create user
CREATE USER securesharing WITH PASSWORD '$DB_PASSWORD';

-- Create databases
CREATE DATABASE securesharing_prod OWNER securesharing;
CREATE DATABASE pii_service_prod OWNER securesharing;

-- Extensions for securesharing_prod
\c securesharing_prod
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Extensions for pii_service_prod
\c pii_service_prod
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE securesharing_prod TO securesharing;
GRANT ALL PRIVILEGES ON DATABASE pii_service_prod TO securesharing;
EOF

print_step "PostgreSQL setup complete!"

# ============================================================================
# Phase 4: Install Garage S3
# ============================================================================

print_header "Phase 4: Installing Garage S3"

print_step "Downloading Garage..."
curl -L https://garagehq.deuxfleurs.fr/releases/v1.0.1/x86_64-unknown-linux-musl/garage \
    -o /usr/local/bin/garage
chmod +x /usr/local/bin/garage

print_step "Creating directories..."
mkdir -p /var/lib/garage/{data,meta}
mkdir -p /etc/garage

print_step "Creating garage user..."
useradd -r -s /bin/false garage || true
chown -R garage:garage /var/lib/garage

# Generate secrets
RPC_SECRET=$(openssl rand -hex 32)
ADMIN_TOKEN=$(openssl rand -hex 32)

print_step "Creating Garage configuration..."
cat > /etc/garage/garage.toml << EOF
metadata_dir = "/var/lib/garage/meta"
data_dir = "/var/lib/garage/data"

db_engine = "sqlite"
replication_factor = 1

rpc_secret = "$RPC_SECRET"
rpc_bind_addr = "[::]:3901"
rpc_public_addr = "10.0.0.2:3901"

[s3_api]
s3_region = "garage"
api_bind_addr = "10.0.0.2:3900"
root_domain = ".s3.garage.localhost"

[s3_web]
bind_addr = "[::]:3902"
root_domain = ".web.garage.localhost"

[admin]
api_bind_addr = "10.0.0.2:3903"
admin_token = "$ADMIN_TOKEN"
EOF

chown root:garage /etc/garage/garage.toml
chmod 640 /etc/garage/garage.toml

print_step "Creating Garage systemd service..."
cat > /etc/systemd/system/garage.service << 'EOF'
[Unit]
Description=Garage S3-compatible storage
After=network.target

[Service]
Type=simple
User=garage
ExecStart=/usr/local/bin/garage -c /etc/garage/garage.toml server
Restart=always
RestartSec=10
Environment=RUST_LOG=garage=info

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable garage
systemctl start garage

print_step "Waiting for Garage to start..."
sleep 5

print_step "Initializing Garage cluster..."

# Get node ID
NODE_ID=$(garage -c /etc/garage/garage.toml status 2>/dev/null | grep "Local node" | awk '{print $3}' | head -1)

if [ -n "$NODE_ID" ]; then
    # Set node capacity
    garage -c /etc/garage/garage.toml layout assign -z dc1 -c 1T "$NODE_ID" || true

    # Apply layout
    garage -c /etc/garage/garage.toml layout apply --version 1 || true

    # Create access key
    print_step "Creating access key..."
    KEY_OUTPUT=$(garage -c /etc/garage/garage.toml key create securesharing-key 2>&1)
    ACCESS_KEY=$(echo "$KEY_OUTPUT" | grep "Key ID" | awk '{print $3}')
    SECRET_KEY=$(echo "$KEY_OUTPUT" | grep "Secret key" | awk '{print $3}')

    # Create bucket
    print_step "Creating bucket..."
    garage -c /etc/garage/garage.toml bucket create securesharing-files || true

    # Grant access
    garage -c /etc/garage/garage.toml bucket allow securesharing-files \
        --read --write --owner --key securesharing-key || true

    echo ""
    echo -e "${GREEN}Garage S3 Credentials:${NC}"
    echo "  Access Key: $ACCESS_KEY"
    echo "  Secret Key: $SECRET_KEY"
    echo "  Endpoint:   http://10.0.0.2:3900"
    echo "  Bucket:     securesharing-files"
    echo ""
    echo -e "${YELLOW}Save these credentials! They won't be shown again.${NC}"

    # Save to file
    cat > /root/garage-credentials.txt << EOF
Garage S3 Credentials
=====================
Access Key: $ACCESS_KEY
Secret Key: $SECRET_KEY
Endpoint:   http://10.0.0.2:3900
Bucket:     securesharing-files
Admin Token: $ADMIN_TOKEN
EOF
    chmod 600 /root/garage-credentials.txt
    echo "Credentials saved to /root/garage-credentials.txt"
else
    print_warning "Could not get node ID. Run garage-init.sh manually."
fi

# ============================================================================
# Phase 5: Backup Scripts
# ============================================================================

print_header "Phase 5: Setting Up Backups"

mkdir -p /opt/scripts
mkdir -p /var/backups/{postgresql,garage}

print_step "Creating PostgreSQL backup script..."
cat > /opt/scripts/backup-postgres.sh << 'EOF'
#!/bin/bash
set -e

BACKUP_DIR="/var/backups/postgresql"
DATE=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=7

mkdir -p $BACKUP_DIR

echo "Starting PostgreSQL backup: $DATE"

# Backup individual databases
sudo -u postgres pg_dump securesharing_prod | gzip > "$BACKUP_DIR/securesharing_$DATE.sql.gz"
sudo -u postgres pg_dump pii_service_prod | gzip > "$BACKUP_DIR/pii_service_$DATE.sql.gz"

# Remove old backups
find $BACKUP_DIR -name "*.sql.gz" -mtime +$RETENTION_DAYS -delete

echo "Backup completed: $DATE"
ls -lh $BACKUP_DIR/*.sql.gz | tail -5
EOF
chmod +x /opt/scripts/backup-postgres.sh

print_step "Creating Garage backup script..."
cat > /opt/scripts/backup-garage.sh << 'EOF'
#!/bin/bash
set -e

BACKUP_DIR="/var/backups/garage"
DATE=$(date +%Y%m%d)
RETENTION_DAYS=7

mkdir -p $BACKUP_DIR

echo "Starting Garage backup: $DATE"

# Stop Garage for consistent backup
systemctl stop garage

# Backup metadata (data is too large for regular backup)
tar -czf "$BACKUP_DIR/garage_meta_$DATE.tar.gz" /var/lib/garage/meta

# Restart Garage
systemctl start garage

# Remove old backups
find $BACKUP_DIR -name "*.tar.gz" -mtime +$RETENTION_DAYS -delete

echo "Garage backup completed: $DATE"
EOF
chmod +x /opt/scripts/backup-garage.sh

print_step "Setting up cron jobs..."
(crontab -l 2>/dev/null || true; echo "0 2 * * * /opt/scripts/backup-postgres.sh >> /var/log/backup-postgres.log 2>&1") | crontab -
(crontab -l 2>/dev/null || true; echo "0 3 * * 0 /opt/scripts/backup-garage.sh >> /var/log/backup-garage.log 2>&1") | crontab -

# ============================================================================
# Phase 6: Health Check
# ============================================================================

print_header "Phase 6: Creating Health Check Script"

cat > /opt/scripts/healthcheck.sh << 'EOF'
#!/bin/bash

echo "=== Data Server Health Check ==="
echo ""

echo "=== Services ==="
systemctl is-active postgresql && echo "✓ PostgreSQL is running" || echo "✗ PostgreSQL is NOT running"
systemctl is-active garage && echo "✓ Garage is running" || echo "✗ Garage is NOT running"

echo ""
echo "=== PostgreSQL ==="
sudo -u postgres psql -c "SELECT version();" 2>/dev/null | head -3
sudo -u postgres psql -c "\l" 2>/dev/null | grep -E "securesharing|pii_service"

echo ""
echo "=== Garage S3 ==="
garage -c /etc/garage/garage.toml status 2>/dev/null | head -10
garage -c /etc/garage/garage.toml bucket list 2>/dev/null

echo ""
echo "=== Disk Usage ==="
df -h /var/lib/postgresql /var/lib/garage 2>/dev/null

echo ""
echo "=== Memory ==="
free -h
EOF
chmod +x /opt/scripts/healthcheck.sh

# ============================================================================
# Summary
# ============================================================================

print_header "Setup Complete!"

echo "Services installed:"
echo "  ✓ PostgreSQL 18 (port 5432)"
echo "  ✓ Garage S3 (port 3900)"
echo ""
echo "Databases created:"
echo "  ✓ securesharing_prod"
echo "  ✓ pii_service_prod"
echo ""
echo "Credentials:"
echo "  PostgreSQL: securesharing / [your password]"
echo "  Garage: See /root/garage-credentials.txt"
echo ""
echo "Backups:"
echo "  PostgreSQL: Daily at 2 AM"
echo "  Garage: Weekly on Sunday at 3 AM"
echo ""
echo "Connection from Compute server:"
echo "  PostgreSQL: psql -h 10.0.0.2 -U securesharing -d securesharing_prod"
echo "  S3: http://10.0.0.2:3900"
echo ""
echo "Health check: /opt/scripts/healthcheck.sh"
echo ""
