# SecureSharing Single Server Deployment Guide

**Version**: 1.0.0
**Target**: Ubuntu 22.04 LTS
**Architecture**: Single server MVP deployment

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Server Setup](#2-server-setup)
3. [Install Dependencies](#3-install-dependencies)
4. [Database Setup](#4-database-setup)
5. [Object Storage Setup](#5-object-storage-setup)
6. [Build Application](#6-build-application)
7. [Deploy Application](#7-deploy-application)
8. [Configure Nginx](#8-configure-nginx)
9. [SSL Certificate](#9-ssl-certificate)
10. [Systemd Services](#10-systemd-services)
11. [Verification](#11-verification)
12. [Maintenance](#12-maintenance)
13. [Troubleshooting](#13-troubleshooting)

---

## 1. Prerequisites

### 1.1 Server Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| CPU | 2 vCPU | 4 vCPU |
| RAM | 4 GB | 8 GB |
| Storage | 40 GB SSD | 100 GB SSD |
| OS | Ubuntu 22.04 LTS | Ubuntu 22.04 LTS |

### 1.2 Domain & DNS

- Domain name pointing to server IP (e.g., `api.securesharing.example.com`)
- DNS A record configured

### 1.3 Local Development Machine

Ensure you can build the release locally:
```bash
# Verify Elixir/Erlang installed
elixir --version
mix --version
```

---

## 2. Server Setup

### 2.1 Initial Server Access

```bash
# SSH into server
ssh root@your-server-ip

# Or with key
ssh -i ~/.ssh/your-key root@your-server-ip
```

### 2.2 Create Deploy User

```bash
# Create user
adduser securesharing --disabled-password --gecos ""

# Add to sudo group (optional, for maintenance)
usermod -aG sudo securesharing

# Create SSH directory
mkdir -p /home/securesharing/.ssh
cp ~/.ssh/authorized_keys /home/securesharing/.ssh/
chown -R securesharing:securesharing /home/securesharing/.ssh
chmod 700 /home/securesharing/.ssh
chmod 600 /home/securesharing/.ssh/authorized_keys
```

### 2.3 Update System

```bash
apt update && apt upgrade -y
```

### 2.4 Install Essential Tools

```bash
apt install -y \
  curl \
  wget \
  git \
  build-essential \
  unzip \
  htop \
  ufw \
  fail2ban
```

### 2.5 Configure Firewall

```bash
# Allow SSH
ufw allow 22/tcp

# Allow HTTP/HTTPS
ufw allow 80/tcp
ufw allow 443/tcp

# Enable firewall
ufw enable

# Verify
ufw status
```

### 2.6 Configure Fail2ban

```bash
# Start and enable
systemctl enable fail2ban
systemctl start fail2ban
```

---

## 3. Install Dependencies

### 3.1 Install Erlang/OTP 27

```bash
# Add Erlang Solutions repository
apt install -y software-properties-common
wget https://packages.erlang-solutions.com/erlang-solutions_2.0_all.deb
dpkg -i erlang-solutions_2.0_all.deb
apt update

# Install Erlang
apt install -y esl-erlang

# Verify
erl -version
```

### 3.2 Install Elixir 1.18

```bash
# Install Elixir
apt install -y elixir

# Verify
elixir --version
```

**Alternative - Using asdf (Recommended for version management):**

```bash
# Install asdf
git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.14.0
echo '. "$HOME/.asdf/asdf.sh"' >> ~/.bashrc
source ~/.bashrc

# Install plugins
asdf plugin add erlang
asdf plugin add elixir

# Install versions
asdf install erlang 27.0.1
asdf install elixir 1.18.2-otp-27

# Set global versions
asdf global erlang 27.0.1
asdf global elixir 1.18.2-otp-27
```

### 3.3 Install Node.js (for assets)

```bash
# Install Node.js 20 LTS
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs

# Verify
node --version
npm --version
```

---

## 4. Database Setup

### 4.1 Install PostgreSQL 16

```bash
# Add PostgreSQL repository
sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
apt update

# Install PostgreSQL
apt install -y postgresql-16 postgresql-contrib-16

# Start and enable
systemctl enable postgresql
systemctl start postgresql
```

### 4.2 Create Database and User

```bash
# Switch to postgres user
sudo -u postgres psql

# In psql:
CREATE USER securesharing WITH PASSWORD 'your-secure-password-here';
CREATE DATABASE securesharing_prod OWNER securesharing;
GRANT ALL PRIVILEGES ON DATABASE securesharing_prod TO securesharing;

# Enable required extensions
\c securesharing_prod
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

# Exit
\q
```

### 4.3 Configure PostgreSQL

Edit `/etc/postgresql/16/main/postgresql.conf`:

```ini
# Performance tuning (adjust based on server RAM)
shared_buffers = 1GB              # 25% of RAM
effective_cache_size = 3GB        # 75% of RAM
maintenance_work_mem = 256MB
checkpoint_completion_target = 0.9
wal_buffers = 64MB
default_statistics_target = 100
random_page_cost = 1.1
effective_io_concurrency = 200
min_wal_size = 1GB
max_wal_size = 4GB
```

Edit `/etc/postgresql/16/main/pg_hba.conf` (add line):

```
local   securesharing_prod   securesharing   scram-sha-256
```

Restart PostgreSQL:

```bash
systemctl restart postgresql
```

### 4.4 Test Connection

```bash
psql -U securesharing -d securesharing_prod -h localhost
# Enter password when prompted
```

---

## 5. Object Storage Setup

### 5.1 Option A: Garage (Self-hosted S3)

```bash
# Download Garage
wget https://garagehq.deuxfleurs.fr/_releases/v1.0.1/x86_64-unknown-linux-musl/garage
chmod +x garage
mv garage /usr/local/bin/

# Create directories
mkdir -p /var/lib/garage/data
mkdir -p /var/lib/garage/meta
mkdir -p /etc/garage

# Create config
cat > /etc/garage/garage.toml << 'EOF'
metadata_dir = "/var/lib/garage/meta"
data_dir = "/var/lib/garage/data"
db_engine = "sqlite"

replication_factor = 1

[rpc]
bind_addr = "[::]:3901"
secret = "$(openssl rand -hex 32)"

[s3_api]
s3_region = "garage"
api_bind_addr = "[::]:3900"
root_domain = ".s3.garage.localhost"

[s3_web]
bind_addr = "[::]:3902"
root_domain = ".web.garage.localhost"

[admin]
api_bind_addr = "[::]:3903"
admin_token = "$(openssl rand -hex 32)"
EOF
```

Create systemd service `/etc/systemd/system/garage.service`:

```ini
[Unit]
Description=Garage S3-compatible object storage
After=network.target

[Service]
Type=simple
User=securesharing
ExecStart=/usr/local/bin/garage server
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Start Garage:

```bash
systemctl daemon-reload
systemctl enable garage
systemctl start garage

# Initialize cluster (first time only)
garage layout assign -z dc1 -c 10G $(garage node id -q)
garage layout apply --version 1

# Create bucket
garage bucket create securesharing-files

# Create access key
garage key create securesharing-app-key
garage bucket allow securesharing-files --read --write --key securesharing-app-key
```

### 5.2 Option B: MinIO

```bash
# Download MinIO
wget https://dl.min.io/server/minio/release/linux-amd64/minio
chmod +x minio
mv minio /usr/local/bin/

# Create directories
mkdir -p /var/lib/minio/data

# Create systemd service
cat > /etc/systemd/system/minio.service << 'EOF'
[Unit]
Description=MinIO Object Storage
After=network.target

[Service]
Type=simple
User=securesharing
Environment="MINIO_ROOT_USER=minioadmin"
Environment="MINIO_ROOT_PASSWORD=your-secure-password"
ExecStart=/usr/local/bin/minio server /var/lib/minio/data --console-address ":9001"
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Start MinIO
systemctl daemon-reload
systemctl enable minio
systemctl start minio
```

Create bucket via MinIO Console (http://server-ip:9001) or CLI:

```bash
# Install mc client
wget https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc
mv mc /usr/local/bin/

# Configure and create bucket
mc alias set local http://localhost:9000 minioadmin your-secure-password
mc mb local/securesharing-files
```

---

## 6. Build Application

### 6.1 Build on Local Machine

```bash
# On your development machine
cd /path/to/SecureSharing/services/securesharing

# Get dependencies
mix deps.get --only prod

# Compile
MIX_ENV=prod mix compile

# Build assets (if applicable)
MIX_ENV=prod mix assets.deploy

# Build release
MIX_ENV=prod mix release
```

### 6.2 Transfer Release to Server

```bash
# Create tarball
cd _build/prod/rel
tar -czvf securesharing.tar.gz secure_sharing

# Transfer to server
scp securesharing.tar.gz securesharing@your-server-ip:/home/securesharing/
```

---

## 7. Deploy Application

### 7.1 Setup Application Directory

```bash
# On server, as securesharing user
ssh securesharing@your-server-ip

# Create directories
mkdir -p /home/securesharing/app
mkdir -p /home/securesharing/releases

# Extract release
cd /home/securesharing/app
tar -xzvf /home/securesharing/securesharing.tar.gz
```

### 7.2 Create Environment File

Create `/home/securesharing/app/.env`:

```bash
# Database
DATABASE_URL=ecto://securesharing:your-db-password@localhost:5432/securesharing_prod

# Phoenix
SECRET_KEY_BASE=generate-with-mix-phx-gen-secret-at-least-64-chars
PHX_HOST=api.securesharing.example.com
PHX_SERVER=true
PORT=4000

# JWT
JWT_SECRET=generate-another-secure-random-string-at-least-32-chars

# S3 Storage (Garage)
S3_BUCKET=securesharing-files
S3_ENDPOINT=http://localhost:3900
S3_ACCESS_KEY_ID=your-garage-access-key
S3_SECRET_ACCESS_KEY=your-garage-secret-key
S3_REGION=garage

# Or for MinIO:
# S3_ENDPOINT=http://localhost:9000
# S3_ACCESS_KEY_ID=minioadmin
# S3_SECRET_ACCESS_KEY=your-minio-password
# S3_REGION=us-east-1

# Logging
LOG_LEVEL=info
```

Generate secrets:

```bash
# On local machine with Elixir installed
mix phx.gen.secret  # For SECRET_KEY_BASE
openssl rand -base64 32  # For JWT_SECRET
```

### 7.3 Run Database Migrations

```bash
cd /home/securesharing/app/secure_sharing

# Load environment
export $(cat /home/securesharing/app/.env | xargs)

# Run migrations
./bin/secure_sharing eval "SecureSharing.Release.migrate()"
```

### 7.4 Test Application

```bash
# Start in foreground to test
./bin/secure_sharing start

# In another terminal, test health endpoint
curl http://localhost:4000/health

# Stop with Ctrl+C
```

---

## 8. Configure Nginx

### 8.1 Install Nginx

```bash
apt install -y nginx
systemctl enable nginx
```

### 8.2 Create Site Configuration

Create `/etc/nginx/sites-available/securesharing`:

```nginx
upstream securesharing {
    server 127.0.0.1:4000;
}

server {
    listen 80;
    server_name api.securesharing.example.com;

    # Redirect HTTP to HTTPS
    location / {
        return 301 https://$server_name$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name api.securesharing.example.com;

    # SSL certificates (will be configured by Certbot)
    ssl_certificate /etc/letsencrypt/live/api.securesharing.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.securesharing.example.com/privkey.pem;

    # SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Logging
    access_log /var/log/nginx/securesharing_access.log;
    error_log /var/log/nginx/securesharing_error.log;

    # Max upload size
    client_max_body_size 100M;

    # API endpoints
    location / {
        proxy_pass http://securesharing;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    # WebSocket support for Phoenix channels
    location /socket {
        proxy_pass http://securesharing;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 3600s;
    }

    # Health check (no logging)
    location /health {
        proxy_pass http://securesharing;
        access_log off;
    }
}
```

### 8.3 Enable Site

```bash
# Enable site
ln -s /etc/nginx/sites-available/securesharing /etc/nginx/sites-enabled/

# Remove default site
rm /etc/nginx/sites-enabled/default

# Test configuration
nginx -t

# Reload (don't restart yet - need SSL cert first)
# systemctl reload nginx
```

---

## 9. SSL Certificate

### 9.1 Install Certbot

```bash
apt install -y certbot python3-certbot-nginx
```

### 9.2 Obtain Certificate

```bash
# Temporarily allow HTTP for certificate verification
# First, create a simple HTTP-only config

cat > /etc/nginx/sites-available/securesharing-temp << 'EOF'
server {
    listen 80;
    server_name api.securesharing.example.com;

    location / {
        root /var/www/html;
    }
}
EOF

ln -sf /etc/nginx/sites-available/securesharing-temp /etc/nginx/sites-enabled/securesharing
systemctl reload nginx

# Get certificate
certbot --nginx -d api.securesharing.example.com

# Restore full config
ln -sf /etc/nginx/sites-available/securesharing /etc/nginx/sites-enabled/securesharing
systemctl reload nginx
```

### 9.3 Auto-Renewal

Certbot automatically sets up renewal. Verify:

```bash
certbot renew --dry-run
```

---

## 10. Systemd Services

### 10.1 SecureSharing Service

Create `/etc/systemd/system/securesharing.service`:

```ini
[Unit]
Description=SecureSharing API
After=network.target postgresql.service

[Service]
Type=simple
User=securesharing
Group=securesharing
WorkingDirectory=/home/securesharing/app/secure_sharing
EnvironmentFile=/home/securesharing/app/.env
ExecStart=/home/securesharing/app/secure_sharing/bin/secure_sharing start
ExecStop=/home/securesharing/app/secure_sharing/bin/secure_sharing stop
Restart=on-failure
RestartSec=5
SyslogIdentifier=securesharing

# Security hardening
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=/home/securesharing/app
PrivateTmp=true

[Install]
WantedBy=multi-user.target
```

### 10.2 Enable and Start Services

```bash
# Reload systemd
systemctl daemon-reload

# Enable services
systemctl enable securesharing
systemctl enable garage  # or minio

# Start services
systemctl start garage  # or minio
systemctl start securesharing

# Check status
systemctl status securesharing
systemctl status garage
```

---

## 11. Verification

### 11.1 Check All Services

```bash
# Check service status
systemctl status postgresql
systemctl status garage  # or minio
systemctl status securesharing
systemctl status nginx

# Check ports
ss -tlnp | grep -E '(5432|3900|4000|80|443)'
```

### 11.2 Test Endpoints

```bash
# Health check (local)
curl http://localhost:4000/health

# Health check (via nginx)
curl https://api.securesharing.example.com/health

# API test
curl https://api.securesharing.example.com/api/health
```

### 11.3 Check Logs

```bash
# Application logs
journalctl -u securesharing -f

# Nginx logs
tail -f /var/log/nginx/securesharing_access.log
tail -f /var/log/nginx/securesharing_error.log

# PostgreSQL logs
tail -f /var/log/postgresql/postgresql-16-main.log
```

---

## 12. Maintenance

### 12.1 Deploying Updates

```bash
# On local machine: build new release
MIX_ENV=prod mix release

# Create tarball and upload
cd _build/prod/rel
tar -czvf securesharing.tar.gz secure_sharing
scp securesharing.tar.gz securesharing@your-server-ip:/home/securesharing/

# On server: deploy
ssh securesharing@your-server-ip

# Backup current release
mv /home/securesharing/app/secure_sharing /home/securesharing/releases/secure_sharing_$(date +%Y%m%d_%H%M%S)

# Extract new release
cd /home/securesharing/app
tar -xzvf /home/securesharing/securesharing.tar.gz

# Run migrations
export $(cat /home/securesharing/app/.env | xargs)
./secure_sharing/bin/secure_sharing eval "SecureSharing.Release.migrate()"

# Restart service
sudo systemctl restart securesharing

# Verify
curl http://localhost:4000/health
```

### 12.2 Database Backup

```bash
# Create backup script
cat > /home/securesharing/scripts/backup_db.sh << 'EOF'
#!/bin/bash
BACKUP_DIR=/home/securesharing/backups
DATE=$(date +%Y%m%d_%H%M%S)
mkdir -p $BACKUP_DIR

pg_dump -U securesharing securesharing_prod | gzip > $BACKUP_DIR/securesharing_$DATE.sql.gz

# Keep only last 7 days
find $BACKUP_DIR -name "*.sql.gz" -mtime +7 -delete
EOF

chmod +x /home/securesharing/scripts/backup_db.sh

# Add to crontab (daily at 2 AM)
echo "0 2 * * * /home/securesharing/scripts/backup_db.sh" | crontab -
```

### 12.3 Restore Database

```bash
# Restore from backup
gunzip -c /home/securesharing/backups/securesharing_YYYYMMDD_HHMMSS.sql.gz | psql -U securesharing securesharing_prod
```

### 12.4 Log Rotation

Create `/etc/logrotate.d/securesharing`:

```
/var/log/nginx/securesharing_*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 0640 www-data adm
    sharedscripts
    postrotate
        [ -f /var/run/nginx.pid ] && kill -USR1 `cat /var/run/nginx.pid`
    endscript
}
```

---

## 13. Troubleshooting

### 13.1 Application Won't Start

```bash
# Check logs
journalctl -u securesharing -n 100 --no-pager

# Common issues:
# - DATABASE_URL incorrect
# - Missing environment variables
# - Port already in use

# Test database connection
psql $DATABASE_URL -c "SELECT 1"

# Check port
ss -tlnp | grep 4000
```

### 13.2 Database Connection Issues

```bash
# Check PostgreSQL is running
systemctl status postgresql

# Check connection
psql -U securesharing -d securesharing_prod -h localhost

# Check pg_hba.conf
cat /etc/postgresql/16/main/pg_hba.conf | grep securesharing
```

### 13.3 S3 Storage Issues

```bash
# Test Garage
curl http://localhost:3900

# Test MinIO
curl http://localhost:9000/minio/health/live

# Check bucket exists
garage bucket list
# or
mc ls local/
```

### 13.4 Nginx Issues

```bash
# Test configuration
nginx -t

# Check error log
tail -f /var/log/nginx/error.log

# Check upstream connection
curl -v http://localhost:4000/health
```

### 13.5 SSL Certificate Issues

```bash
# Check certificate
certbot certificates

# Renew manually
certbot renew

# Check certificate dates
echo | openssl s_client -servername api.securesharing.example.com -connect api.securesharing.example.com:443 2>/dev/null | openssl x509 -noout -dates
```

---

## Quick Reference

### Service Commands

```bash
# Start/Stop/Restart
sudo systemctl start securesharing
sudo systemctl stop securesharing
sudo systemctl restart securesharing

# View logs
journalctl -u securesharing -f

# Check status
systemctl status securesharing
```

### Important Paths

| Path | Description |
|------|-------------|
| `/home/securesharing/app/` | Application directory |
| `/home/securesharing/app/.env` | Environment variables |
| `/home/securesharing/backups/` | Database backups |
| `/etc/nginx/sites-available/securesharing` | Nginx config |
| `/etc/systemd/system/securesharing.service` | Systemd service |
| `/var/log/nginx/securesharing_*.log` | Nginx logs |

### Important Ports

| Port | Service |
|------|---------|
| 22 | SSH |
| 80 | HTTP (redirects to HTTPS) |
| 443 | HTTPS |
| 4000 | SecureSharing (internal) |
| 5432 | PostgreSQL (internal) |
| 3900 | Garage S3 (internal) |
| 9000 | MinIO S3 (internal) |

---

*Document Version: 1.0.0 | Last Updated: February 2026*
