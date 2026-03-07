# SecureSharing Hetzner Two-Server Deployment Guide

## Overview

This guide covers deploying SecureSharing on Hetzner with a two-server architecture, separating compute (application + LLM) from data (database + storage).

**Monthly Cost: ~€104/month**

---

## Architecture

```
                            Internet
                               │
                               ▼
                        ┌─────────────┐
                        │  Firewall   │
                        └─────────────┘
                               │
              ┌────────────────┴────────────────┐
              │                                 │
              ▼                                 ▼
┌─────────────────────────────┐   ┌─────────────────────────────┐
│    Server 1: COMPUTE        │   │    Server 2: DATA           │
│    (ax52.securesharing)     │   │    (ax42.securesharing)     │
│                             │   │                             │
│  ┌───────────────────────┐  │   │  ┌───────────────────────┐  │
│  │   Nginx (Reverse      │  │   │  │   PostgreSQL 18       │  │
│  │   Proxy + SSL)        │  │   │  │   Port: 5432          │  │
│  │   :80, :443           │  │   │  │   RAM: 32GB           │  │
│  └───────────────────────┘  │   │  └───────────────────────┘  │
│                             │   │                             │
│  ┌───────────────────────┐  │   │  ┌───────────────────────┐  │
│  │   SecureSharing       │  │   │  │   Garage S3           │  │
│  │   Backend             │  │   │  │   Port: 3900          │  │
│  │   Port: 4000          │  │   │  │   RAM: 16GB           │  │
│  └───────────────────────┘  │   │  └───────────────────────┘  │
│                             │   │                             │
│  ┌───────────────────────┐  │   │  ┌───────────────────────┐  │
│  │   PII Service         │  │   │  │   Automated Backups   │  │
│  │   Port: 4001          │  │   │  │   (PostgreSQL + S3)   │  │
│  └───────────────────────┘  │   │  └───────────────────────┘  │
│                             │   │                             │
│  ┌───────────────────────┐  │   └─────────────────────────────┘
│  │   Presidio NER        │  │              │
│  │   Port: 5002          │  │              │
│  └───────────────────────┘  │              │
│                             │              │
│  ┌───────────────────────┐  │   Private Network (10.0.0.0/24)
│  │   Qwen2.5-14B         │  │◄─────────────┘
│  │   (llama-server)      │  │
│  │   Port: 8080          │  │
│  │   RAM: 36GB           │  │
│  └───────────────────────┘  │
│                             │
└─────────────────────────────┘
```

---

## Server Specifications

### Server 1: Compute (AX52)

| Spec | Value |
|------|-------|
| **Model** | Hetzner AX52 |
| **CPU** | AMD Ryzen 9 5950X (16 cores / 32 threads) |
| **RAM** | 64GB DDR4 ECC |
| **Storage** | 2 x 1TB NVMe SSD (RAID 1) |
| **Network** | 1 Gbit/s |
| **Price** | €55/month |
| **Hostname** | `compute.securesharing.internal` |
| **Private IP** | `10.0.0.1` |

#### Memory Allocation

| Service | RAM | Notes |
|---------|-----|-------|
| SecureSharing Backend | 8GB | Elixir/Phoenix |
| PII Service | 8GB | Elixir/Phoenix |
| Presidio + spaCy | 8GB | Python NER |
| Qwen2.5-14B | 36GB | LLM inference |
| OS + Buffer | 4GB | Ubuntu overhead |
| **Total** | **64GB** | |

### Server 2: Data (AX42)

| Spec | Value |
|------|-------|
| **Model** | Hetzner AX42 |
| **CPU** | AMD Ryzen 7 3700X (8 cores / 16 threads) |
| **RAM** | 64GB DDR4 ECC |
| **Storage** | 2 x 2TB HDD (RAID 1) + 512GB NVMe |
| **Network** | 1 Gbit/s |
| **Price** | €49/month |
| **Hostname** | `data.securesharing.internal` |
| **Private IP** | `10.0.0.2` |

#### Memory Allocation

| Service | RAM | Notes |
|---------|-----|-------|
| PostgreSQL 18 | 32GB | shared_buffers + effective_cache |
| Garage S3 | 16GB | Object storage |
| OS + Buffer | 16GB | Backups, maintenance |
| **Total** | **64GB** | |

#### Storage Layout

| Mount | Device | Size | Purpose |
|-------|--------|------|---------|
| `/` | NVMe | 512GB | OS + Apps |
| `/var/lib/postgresql` | HDD RAID 1 | 2TB | Database |
| `/var/lib/garage` | HDD RAID 1 | 2TB | S3 Storage |

---

## Network Configuration

### Private Network Setup (Hetzner vSwitch)

Both servers communicate via Hetzner's private vSwitch network.

```
┌─────────────────────────────────────────────────────┐
│              Hetzner vSwitch (Private)              │
│                   10.0.0.0/24                       │
├─────────────────────────────────────────────────────┤
│                                                     │
│   Compute (10.0.0.1) ◄────────► Data (10.0.0.2)    │
│                                                     │
└─────────────────────────────────────────────────────┘
```

### Firewall Rules

#### Server 1: Compute (Public)

| Port | Protocol | Source | Service |
|------|----------|--------|---------|
| 22 | TCP | Your IP | SSH |
| 80 | TCP | Any | HTTP (redirect) |
| 443 | TCP | Any | HTTPS |

#### Server 1: Compute (Private - 10.0.0.0/24)

| Port | Protocol | Source | Service |
|------|----------|--------|---------|
| 4000 | TCP | 10.0.0.0/24 | Backend |
| 4001 | TCP | 10.0.0.0/24 | PII Service |
| 5002 | TCP | localhost | Presidio |
| 8080 | TCP | localhost | LLM |

#### Server 2: Data (Private Only)

| Port | Protocol | Source | Service |
|------|----------|--------|---------|
| 22 | TCP | 10.0.0.1 | SSH (from compute only) |
| 5432 | TCP | 10.0.0.1 | PostgreSQL |
| 3900 | TCP | 10.0.0.1 | Garage S3 API |
| 3903 | TCP | 10.0.0.1 | Garage Admin |

---

## Installation Guide

### Prerequisites

Order from Hetzner:
1. AX52 Dedicated Server
2. AX42 Dedicated Server
3. vSwitch (free, request via Robot panel)

### Phase 1: Initial Server Setup

#### Both Servers

```bash
# Update system
apt update && apt upgrade -y

# Install common packages
apt install -y \
  curl wget git htop tmux vim \
  ufw fail2ban \
  build-essential

# Set timezone
timedatectl set-timezone UTC

# Configure hostname
# On Compute:
hostnamectl set-hostname compute.securesharing.internal

# On Data:
hostnamectl set-hostname data.securesharing.internal
```

#### Configure Private Network

On **Compute Server** (`/etc/netplan/60-private.yaml`):

```yaml
network:
  version: 2
  ethernets:
    enp0s31f6:  # Check actual interface name
      addresses:
        - 10.0.0.1/24
      routes:
        - to: 10.0.0.0/24
          via: 10.0.0.1
```

On **Data Server** (`/etc/netplan/60-private.yaml`):

```yaml
network:
  version: 2
  ethernets:
    enp0s31f6:  # Check actual interface name
      addresses:
        - 10.0.0.2/24
      routes:
        - to: 10.0.0.0/24
          via: 10.0.0.2
```

Apply on both:

```bash
netplan apply
```

#### Configure Firewall

On **Compute Server**:

```bash
ufw default deny incoming
ufw default allow outgoing

# Public access
ufw allow from YOUR_IP to any port 22    # SSH (replace YOUR_IP)
ufw allow 80/tcp                          # HTTP
ufw allow 443/tcp                         # HTTPS

# Private network
ufw allow from 10.0.0.0/24

ufw enable
```

On **Data Server**:

```bash
ufw default deny incoming
ufw default allow outgoing

# Only allow from Compute server
ufw allow from 10.0.0.1 to any port 22    # SSH
ufw allow from 10.0.0.1 to any port 5432  # PostgreSQL
ufw allow from 10.0.0.1 to any port 3900  # Garage S3
ufw allow from 10.0.0.1 to any port 3903  # Garage Admin

ufw enable
```

#### Configure /etc/hosts

On **both servers**, add:

```
10.0.0.1    compute.securesharing.internal compute
10.0.0.2    data.securesharing.internal data
```

---

### Phase 2: Data Server Setup

SSH to Data Server and install services.

#### Install PostgreSQL 18

```bash
# Add PostgreSQL repo
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | \
  gpg --dearmor -o /usr/share/keyrings/postgresql.gpg

echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] \
  http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" | \
  tee /etc/apt/sources.list.d/pgdg.list

apt update
apt install -y postgresql-18

# Start PostgreSQL
systemctl enable postgresql
systemctl start postgresql
```

#### Configure PostgreSQL

Edit `/etc/postgresql/18/main/postgresql.conf`:

```ini
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
random_page_cost = 1.1          # SSD
effective_io_concurrency = 200  # SSD

# Logging
log_destination = 'stderr'
logging_collector = on
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d.log'
log_min_duration_statement = 1000  # Log slow queries > 1s
```

Edit `/etc/postgresql/18/main/pg_hba.conf`:

```
# Allow from Compute server
host    all    all    10.0.0.1/32    scram-sha-256
```

Create databases and users:

```bash
sudo -u postgres psql << 'EOF'
-- Create user
CREATE USER securesharing WITH PASSWORD 'YOUR_SECURE_PASSWORD_HERE';

-- Create databases
CREATE DATABASE securesharing_prod OWNER securesharing;
CREATE DATABASE pii_service_prod OWNER securesharing;

-- Extensions
\c securesharing_prod
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pgcrypto;

\c pii_service_prod
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE securesharing_prod TO securesharing;
GRANT ALL PRIVILEGES ON DATABASE pii_service_prod TO securesharing;
EOF
```

Restart PostgreSQL:

```bash
systemctl restart postgresql
```

#### Install Garage S3

```bash
# Download Garage
curl -L https://garagehq.deuxfleurs.fr/releases/v1.0.1/x86_64-unknown-linux-musl/garage \
  -o /usr/local/bin/garage
chmod +x /usr/local/bin/garage

# Create directories
mkdir -p /var/lib/garage/{data,meta}
mkdir -p /etc/garage

# Create user
useradd -r -s /bin/false garage
chown -R garage:garage /var/lib/garage
```

Create `/etc/garage/garage.toml`:

```toml
metadata_dir = "/var/lib/garage/meta"
data_dir = "/var/lib/garage/data"

db_engine = "sqlite"
replication_factor = 1

rpc_secret = "GENERATE_WITH: openssl rand -hex 32"
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
admin_token = "GENERATE_WITH: openssl rand -hex 32"
```

Create `/etc/systemd/system/garage.service`:

```ini
[Unit]
Description=Garage S3-compatible storage
After=network.target

[Service]
Type=simple
User=garage
ExecStart=/usr/local/bin/garage server
Restart=always
RestartSec=10
Environment=RUST_LOG=garage=info

[Install]
WantedBy=multi-user.target
```

Start Garage:

```bash
systemctl daemon-reload
systemctl enable garage
systemctl start garage
```

Initialize Garage (run once):

```bash
# Get node ID
garage -c /etc/garage/garage.toml status

# Set node capacity (replace NODE_ID)
garage -c /etc/garage/garage.toml layout assign -z dc1 -c 1T NODE_ID

# Apply layout
garage -c /etc/garage/garage.toml layout apply --version 1

# Create access key
garage -c /etc/garage/garage.toml key create securesharing-key

# Create bucket
garage -c /etc/garage/garage.toml bucket create securesharing-files

# Grant access
garage -c /etc/garage/garage.toml bucket allow securesharing-files \
  --read --write --owner --key securesharing-key
```

Save the access key and secret for later configuration.

---

### Phase 3: Compute Server Setup

SSH to Compute Server and install services.

#### Install Erlang & Elixir

```bash
# Add Erlang Solutions repo
wget https://packages.erlang-solutions.com/erlang-solutions_2.0_all.deb
dpkg -i erlang-solutions_2.0_all.deb
apt update

# Install Erlang and Elixir
apt install -y esl-erlang elixir

# Verify
elixir --version
```

#### Install Node.js

```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs

# Verify
node --version
npm --version
```

#### Install Python (for Presidio)

```bash
apt install -y python3 python3-pip python3-venv
```

#### Deploy SecureSharing Backend

```bash
# Create app user
useradd -r -m -s /bin/bash securesharing

# Clone repository
sudo -u securesharing git clone https://github.com/YOUR_REPO/SecureSharing.git \
  /home/securesharing/app

cd /home/securesharing/app/services/securesharing

# Install dependencies
sudo -u securesharing mix local.hex --force
sudo -u securesharing mix local.rebar --force
sudo -u securesharing MIX_ENV=prod mix deps.get --only prod
sudo -u securesharing MIX_ENV=prod mix compile
```

Create `/home/securesharing/app/services/securesharing/.env.prod`:

```bash
# Database
DATABASE_URL=ecto://securesharing:YOUR_PASSWORD@10.0.0.2:5432/securesharing_prod

# Phoenix
SECRET_KEY_BASE=GENERATE_WITH: mix phx.gen.secret
PHX_HOST=yourdomain.com
PORT=4000

# S3 Storage (Garage)
AWS_ACCESS_KEY_ID=YOUR_GARAGE_ACCESS_KEY
AWS_SECRET_ACCESS_KEY=YOUR_GARAGE_SECRET_KEY
S3_ENDPOINT=http://10.0.0.2:3900
S3_BUCKET=securesharing-files
S3_REGION=garage

# LLM
LLM_URL=http://localhost:8080/v1
```

Create `/etc/systemd/system/securesharing.service`:

```ini
[Unit]
Description=SecureSharing Backend
After=network.target

[Service]
Type=simple
User=securesharing
WorkingDirectory=/home/securesharing/app/services/securesharing
EnvironmentFile=/home/securesharing/app/services/securesharing/.env.prod
ExecStart=/usr/local/bin/mix phx.server
Restart=always
RestartSec=10
Environment=MIX_ENV=prod

[Install]
WantedBy=multi-user.target
```

Run migrations and start:

```bash
cd /home/securesharing/app/services/securesharing
sudo -u securesharing MIX_ENV=prod mix ecto.migrate

systemctl daemon-reload
systemctl enable securesharing
systemctl start securesharing
```

#### Deploy PII Service

```bash
cd /home/securesharing/app/services/pii_service

# Install dependencies
sudo -u securesharing MIX_ENV=prod mix deps.get --only prod
sudo -u securesharing MIX_ENV=prod mix compile
```

Create `/home/securesharing/app/services/pii_service/.env.prod`:

```bash
# Database
DATABASE_URL=ecto://securesharing:YOUR_PASSWORD@10.0.0.2:5432/pii_service_prod

# Phoenix
SECRET_KEY_BASE=GENERATE_WITH: mix phx.gen.secret
PHX_HOST=yourdomain.com
PORT=4001

# Presidio
PRESIDIO_URL=http://localhost:5002

# LLM (Qwen)
OLLAMA_URL=http://localhost:8080
LLM_MODEL=qwen2.5-14b-instruct

# Main service
MAIN_SERVICE_URL=http://localhost:4000
```

Create `/etc/systemd/system/pii-service.service`:

```ini
[Unit]
Description=PII Detection Service
After=network.target securesharing.service

[Service]
Type=simple
User=securesharing
WorkingDirectory=/home/securesharing/app/services/pii_service
EnvironmentFile=/home/securesharing/app/services/pii_service/.env.prod
ExecStart=/usr/local/bin/mix phx.server
Restart=always
RestartSec=10
Environment=MIX_ENV=prod

[Install]
WantedBy=multi-user.target
```

```bash
cd /home/securesharing/app/services/pii_service
sudo -u securesharing MIX_ENV=prod mix ecto.migrate

systemctl daemon-reload
systemctl enable pii-service
systemctl start pii-service
```

#### Install Presidio

```bash
# Create virtual environment
python3 -m venv /opt/presidio
source /opt/presidio/bin/activate

# Install Presidio
pip install presidio-analyzer presidio-anonymizer
python -m spacy download en_core_web_lg

# Create service script
cat > /opt/presidio/run.py << 'EOF'
from presidio_analyzer import AnalyzerEngine
from flask import Flask, request, jsonify

app = Flask(__name__)
analyzer = AnalyzerEngine()

@app.route('/health', methods=['GET'])
def health():
    return jsonify({"status": "healthy"})

@app.route('/analyze', methods=['POST'])
def analyze():
    data = request.json
    results = analyzer.analyze(
        text=data.get('text', ''),
        language=data.get('language', 'en'),
        entities=data.get('entities')
    )
    return jsonify([r.to_dict() for r in results])

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5002)
EOF

pip install flask gunicorn
```

Create `/etc/systemd/system/presidio.service`:

```ini
[Unit]
Description=Presidio NER Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/presidio
ExecStart=/opt/presidio/bin/gunicorn -w 2 -b 127.0.0.1:5002 run:app
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

```bash
systemctl daemon-reload
systemctl enable presidio
systemctl start presidio
```

#### Install Qwen2.5-14B with llama.cpp

```bash
# Build llama.cpp
cd /opt
git clone https://github.com/ggerganov/llama.cpp
cd llama.cpp
make -j$(nproc) GGML_NATIVE=ON

# Download Qwen2.5-14B
mkdir -p /opt/models
cd /opt/models
wget https://huggingface.co/Qwen/Qwen2.5-14B-Instruct-GGUF/resolve/main/qwen2.5-14b-instruct-q4_k_m.gguf
```

Create `/etc/systemd/system/llama-server.service`:

```ini
[Unit]
Description=LLaMA.cpp Server (Qwen2.5-14B)
After=network.target

[Service]
Type=simple
User=root
ExecStart=/opt/llama.cpp/llama-server \
  -m /opt/models/qwen2.5-14b-instruct-q4_k_m.gguf \
  --host 127.0.0.1 \
  --port 8080 \
  -c 4096 \
  -t 12 \
  --parallel 2
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

```bash
systemctl daemon-reload
systemctl enable llama-server
systemctl start llama-server
```

#### Install Nginx

```bash
apt install -y nginx certbot python3-certbot-nginx
```

Create `/etc/nginx/sites-available/securesharing`:

```nginx
upstream backend {
    server 127.0.0.1:4000;
}

upstream pii_service {
    server 127.0.0.1:4001;
}

server {
    listen 80;
    server_name yourdomain.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name yourdomain.com;

    # SSL (managed by Certbot)
    ssl_certificate /etc/letsencrypt/live/yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/yourdomain.com/privkey.pem;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # Main API
    location / {
        proxy_pass http://backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # PII Service API
    location /pii/ {
        rewrite ^/pii/(.*) /$1 break;
        proxy_pass http://pii_service;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # WebSocket for Phoenix LiveView
    location /live {
        proxy_pass http://backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 86400;
    }

    # Health check
    location /health {
        proxy_pass http://backend/health;
    }
}
```

```bash
ln -s /etc/nginx/sites-available/securesharing /etc/nginx/sites-enabled/
rm /etc/nginx/sites-enabled/default

# Get SSL certificate
certbot --nginx -d yourdomain.com

nginx -t
systemctl reload nginx
```

---

## Backup Strategy

### PostgreSQL Backup (Data Server)

Create `/opt/scripts/backup-postgres.sh`:

```bash
#!/bin/bash
set -e

BACKUP_DIR="/var/backups/postgresql"
DATE=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=7

mkdir -p $BACKUP_DIR

# Backup all databases
sudo -u postgres pg_dumpall | gzip > "$BACKUP_DIR/all_databases_$DATE.sql.gz"

# Backup individual databases
sudo -u postgres pg_dump securesharing_prod | gzip > "$BACKUP_DIR/securesharing_$DATE.sql.gz"
sudo -u postgres pg_dump pii_service_prod | gzip > "$BACKUP_DIR/pii_service_$DATE.sql.gz"

# Remove old backups
find $BACKUP_DIR -name "*.sql.gz" -mtime +$RETENTION_DAYS -delete

echo "Backup completed: $DATE"
```

Add to crontab:

```bash
chmod +x /opt/scripts/backup-postgres.sh

# Run daily at 2 AM
echo "0 2 * * * /opt/scripts/backup-postgres.sh >> /var/log/backup.log 2>&1" | crontab -
```

### Garage S3 Backup (Data Server)

Garage data is stored in `/var/lib/garage`. For backup:

```bash
#!/bin/bash
# /opt/scripts/backup-garage.sh

BACKUP_DIR="/var/backups/garage"
DATE=$(date +%Y%m%d)

mkdir -p $BACKUP_DIR

# Stop Garage briefly for consistent backup
systemctl stop garage
tar -czf "$BACKUP_DIR/garage_$DATE.tar.gz" /var/lib/garage
systemctl start garage

# Keep 7 days
find $BACKUP_DIR -name "*.tar.gz" -mtime +7 -delete
```

---

## Monitoring

### Install Node Exporter (Both Servers)

```bash
# Download
wget https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz
tar xzf node_exporter-1.7.0.linux-amd64.tar.gz
mv node_exporter-1.7.0.linux-amd64/node_exporter /usr/local/bin/

# Create service
cat > /etc/systemd/system/node-exporter.service << 'EOF'
[Unit]
Description=Node Exporter

[Service]
ExecStart=/usr/local/bin/node_exporter
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable node-exporter
systemctl start node-exporter
```

### Health Check Script

Create `/opt/scripts/healthcheck.sh` on Compute server:

```bash
#!/bin/bash

check_service() {
    if systemctl is-active --quiet $1; then
        echo "✓ $1 is running"
        return 0
    else
        echo "✗ $1 is NOT running"
        return 1
    fi
}

check_http() {
    if curl -sf "$1" > /dev/null 2>&1; then
        echo "✓ $2 is responding"
        return 0
    else
        echo "✗ $2 is NOT responding"
        return 1
    fi
}

echo "=== Service Status ==="
check_service securesharing
check_service pii-service
check_service presidio
check_service llama-server
check_service nginx

echo ""
echo "=== HTTP Endpoints ==="
check_http "http://localhost:4000/health" "Backend"
check_http "http://localhost:4001/health" "PII Service"
check_http "http://localhost:5002/health" "Presidio"
check_http "http://localhost:8080/health" "LLM Server"

echo ""
echo "=== Data Server ==="
check_http "http://10.0.0.2:3903/health" "Garage S3"
nc -z 10.0.0.2 5432 && echo "✓ PostgreSQL is reachable" || echo "✗ PostgreSQL is NOT reachable"
```

---

## Maintenance Commands

### Service Management

```bash
# Restart all services (Compute)
systemctl restart securesharing pii-service presidio llama-server nginx

# View logs
journalctl -u securesharing -f
journalctl -u pii-service -f
journalctl -u llama-server -f

# Check status
systemctl status securesharing pii-service presidio llama-server
```

### Database Maintenance (Data Server)

```bash
# Connect to database
sudo -u postgres psql securesharing_prod

# Vacuum (run weekly)
sudo -u postgres vacuumdb --all --analyze

# Check database size
sudo -u postgres psql -c "SELECT pg_database.datname, pg_size_pretty(pg_database_size(pg_database.datname)) FROM pg_database;"
```

### Update Application

```bash
# On Compute server
cd /home/securesharing/app
sudo -u securesharing git pull

# Backend
cd services/securesharing
sudo -u securesharing MIX_ENV=prod mix deps.get
sudo -u securesharing MIX_ENV=prod mix compile
sudo -u securesharing MIX_ENV=prod mix ecto.migrate
systemctl restart securesharing

# PII Service
cd ../pii_service
sudo -u securesharing MIX_ENV=prod mix deps.get
sudo -u securesharing MIX_ENV=prod mix compile
sudo -u securesharing MIX_ENV=prod mix ecto.migrate
systemctl restart pii-service
```

---

## Troubleshooting

### Common Issues

| Issue | Check | Solution |
|-------|-------|----------|
| Backend won't start | `journalctl -u securesharing` | Check DATABASE_URL, SECRET_KEY_BASE |
| LLM slow/timeout | `htop` on compute | Reduce parallel requests, check RAM |
| Database connection refused | `ufw status` on data | Verify firewall allows 10.0.0.1 |
| S3 upload fails | Garage logs | Check bucket permissions, access key |
| SSL certificate error | `certbot renew --dry-run` | Renew certificate |

### Log Locations

| Service | Log Location |
|---------|--------------|
| SecureSharing | `journalctl -u securesharing` |
| PII Service | `journalctl -u pii-service` |
| PostgreSQL | `/var/log/postgresql/` |
| Nginx | `/var/log/nginx/` |
| Garage | `journalctl -u garage` |

---

## Security Checklist

- [ ] SSH key-only authentication (disable password)
- [ ] Fail2ban configured
- [ ] UFW firewall enabled
- [ ] PostgreSQL only accessible from private network
- [ ] Garage only accessible from private network
- [ ] SSL/TLS configured with strong ciphers
- [ ] Regular security updates (`unattended-upgrades`)
- [ ] Secrets stored in environment files (not in code)
- [ ] Database backups encrypted and tested
- [ ] Monitoring alerts configured

---

## Cost Summary

| Item | Monthly Cost |
|------|--------------|
| AX52 (Compute) | €55 |
| AX42 (Data) | €49 |
| vSwitch | Free |
| Backup Storage (optional) | €5 |
| **Total** | **€104-109** |

---

## Support

For issues:
1. Check logs: `journalctl -u <service-name> -f`
2. Run health check: `/opt/scripts/healthcheck.sh`
3. Review this documentation
4. Contact: your-support@email.com
