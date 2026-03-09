# SSDID Drive — Deployment Guide

Deployment guide for the SSDID Drive backend API and admin portal on a Contabo Cloud VPS using Podman.

## Prerequisites

- Contabo Cloud VPS (recommended: VPS 10 for ≤1K users, VPS 20 for 1K+)
- Ubuntu 24.04 LTS (or Debian 12)
- Domain name pointing to the VPS IP (e.g., `drive.ssdid.my`)
- SSDID Registry already running elsewhere (e.g., `https://registry.ssdid.my`)

## 1. Initial Server Setup

### 1.1 SSH Access

```bash
ssh root@<VPS_IP>
```

### 1.2 Create Non-Root User

```bash
adduser ssdid
usermod -aG sudo ssdid
su - ssdid
```

### 1.3 Update System

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl git ufw
```

### 1.4 Firewall

```bash
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

## 2. Install Podman

```bash
sudo apt install -y podman
podman --version
```

Enable Podman socket for rootless containers (auto-start on login):

```bash
systemctl --user enable --now podman.socket
loginctl enable-linger ssdid
```

## 3. Install Caddy (Reverse Proxy + Auto-TLS)

```bash
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update && sudo apt install -y caddy
```

## 4. Directory Structure

```bash
mkdir -p ~/ssdid-drive/{data/files,config,backups}
```

```
~/ssdid-drive/
├── config/
│   └── appsettings.Production.json
├── data/
│   ├── server-identity.json     # Auto-generated on first run (contains private key)
│   └── files/                   # Client-encrypted file storage (~130 GB on 150 GB VPS)
├── backups/                     # Database + identity backups
└── compose.yml                  # Podman compose file
```

## 5. Configuration

### 5.1 Production App Settings

```bash
cat > ~/ssdid-drive/config/appsettings.Production.json << 'EOF'
{
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft.AspNetCore": "Warning",
      "Microsoft.EntityFrameworkCore": "Warning"
    }
  },
  "ConnectionStrings": {
    "Default": "Host=db;Port=5432;Database=ssdid_drive;Username=ssdid_drive;Password=CHANGE_ME_STRONG_PASSWORD",
    "Redis": "redis:6379"
  },
  "Ssdid": {
    "RegistryUrl": "https://registry.ssdid.my",
    "IdentityPath": "/app/data/server-identity.json",
    "Algorithm": "KazSignVerificationKey2024",
    "ServiceUrl": "https://drive.ssdid.my",
    "PreviousIdentities": [],
    "Sessions": {
      "SessionTtlMinutes": 60,
      "ChallengeTtlMinutes": 5,
      "MaxSessions": 10000
    }
  },
  "Cors": {
    "Origins": [
      "https://drive.ssdid.my"
    ]
  }
}
EOF
```

**Important:** Replace `CHANGE_ME_STRONG_PASSWORD` with a strong password:

```bash
openssl rand -base64 32
```

### 5.2 Podman Compose File

```bash
cat > ~/ssdid-drive/compose.yml << 'EOF'
services:
  db:
    image: docker.io/postgres:17
    restart: unless-stopped
    environment:
      POSTGRES_USER: ssdid_drive
      POSTGRES_PASSWORD: CHANGE_ME_STRONG_PASSWORD
      POSTGRES_DB: ssdid_drive
    volumes:
      - pgdata:/var/lib/postgresql/data
    deploy:
      resources:
        limits:
          memory: 512M
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ssdid_drive"]
      interval: 10s
      timeout: 3s
      retries: 5
    networks:
      - backend

  redis:
    image: docker.io/redis:7-alpine
    restart: unless-stopped
    command: redis-server --maxmemory 128mb --maxmemory-policy allkeys-lru
    volumes:
      - redisdata:/data
    deploy:
      resources:
        limits:
          memory: 192M
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 3s
      retries: 5
    networks:
      - backend

  api:
    image: localhost/ssdid-drive-api:latest
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy
    environment:
      ASPNETCORE_ENVIRONMENT: Production
      ASPNETCORE_URLS: http://+:5000
      ENABLE_AUTO_MIGRATE: "true"
    volumes:
      - ./config/appsettings.Production.json:/app/appsettings.Production.json:ro
      - ./data:/app/data
    deploy:
      resources:
        limits:
          memory: 512M
    ports:
      - "127.0.0.1:5000:5000"
    healthcheck:
      test: ["CMD", "curl", "-sf", "http://localhost:5000/health"]
      interval: 15s
      timeout: 3s
      start_period: 10s
      retries: 3
    networks:
      - backend

volumes:
  pgdata:
  redisdata:

networks:
  backend:
EOF
```

**Important:** Use the same password in both `db` and `appsettings.Production.json`.

## 6. Build & Deploy

Everything is compiled on the VPS — no pre-built binaries needed (except `libkazsign.so` which is built from source).

### 6.1 Install Build Dependencies

```bash
sudo apt install -y build-essential cmake
```

### 6.2 Clone Repositories

```bash
cd ~/ssdid-drive
git clone https://github.com/YOUR_ORG/ssdid-drive.git repo
git clone https://github.com/YOUR_ORG/PQC-KAZ.git pqc-kaz
```

### 6.3 Build KAZ-Sign Native Library

The API requires `libkazsign.so` for KAZ-Sign post-quantum signatures. Build from source on the VPS:

```bash
cd ~/ssdid-drive/pqc-kaz/SIGN
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)

# Verify the library was built
ls -la lib/libkazsign.so

# Copy to the correct runtime path for the VPS architecture
ARCH=$(dpkg --print-architecture)   # amd64 on Contabo, arm64 on ARM VPS
mkdir -p ~/ssdid-drive/repo/src/SsdidDrive.Api/runtimes/linux-${ARCH}/native
cp lib/libkazsign.so ~/ssdid-drive/repo/src/SsdidDrive.Api/runtimes/linux-${ARCH}/native/
```

### 6.4 Build Container Image

The .NET API is compiled inside the container (multi-stage build — SDK for build, runtime-only for deploy):

```bash
cd ~/ssdid-drive/repo
podman build -t ssdid-drive-api:latest -f src/SsdidDrive.Api/Containerfile src/SsdidDrive.Api/
```

This downloads the .NET 10 SDK (~800 MB, cached after first build), compiles the API, and produces a slim runtime image.

### 6.5 Start Services

```bash
cd ~/ssdid-drive
podman compose up -d
```

### 6.6 Verify

```bash
# Check containers are running
podman compose ps

# Check API health
curl -s http://localhost:5000/health | python3 -m json.tool

# Check server info
curl -s http://localhost:5000/api/auth/ssdid/server-info | python3 -m json.tool

# Check logs
podman compose logs api --tail 50
podman compose logs db --tail 20
```

## 7. Caddy Reverse Proxy

### 7.1 Configure Caddyfile

```bash
sudo tee /etc/caddy/Caddyfile << 'EOF'
drive.ssdid.my {
    # SSE — disable buffering (must come before generic /api/* handler)
    @sse path /api/auth/ssdid/events
    handle @sse {
        reverse_proxy localhost:5000 {
            flush_interval -1
        }
    }

    # Backend API
    handle /api/* {
        reverse_proxy localhost:5000
    }

    # Health check
    handle /health {
        reverse_proxy localhost:5000
    }

    # Redirect /admin to /admin/ (handle_path requires trailing slash)
    @admin-no-slash path /admin
    redir @admin-no-slash /admin/ permanent

    # Admin portal (React SPA) — strip /admin prefix
    handle_path /admin/* {
        root * /var/www/admin
        file_server
        try_files {path} /index.html
    }

    # Landing page (catch-all)
    handle {
        root * /var/www/landing
        file_server
        try_files {path} /index.html
    }

    # Security headers
    header {
        X-Content-Type-Options nosniff
        X-Frame-Options DENY
        Referrer-Policy strict-origin-when-cross-origin
        Strict-Transport-Security "max-age=31536000; includeSubDomains"
    }

    # File upload limit (100 MB)
    request_body {
        max_size 100MB
    }

    log {
        output file /var/log/caddy/drive.log {
            roll_size 10mb
            roll_keep 5
        }
    }
}
EOF
```

### 7.2 Deploy Static Files

```bash
sudo mkdir -p /var/www/landing /var/www/admin

# Deploy landing page
sudo cp -r ~/ssdid-drive/repo/clients/landing/* /var/www/landing/

# Deploy admin SPA (build first, then copy)
cd ~/ssdid-drive/repo/clients/admin && npm ci && npm run build
sudo cp -r dist/* /var/www/admin/
```

Or use the deploy script from your local machine:

```bash
./scripts/deploy-static.sh ssdid@<VPS_IP>
```

### 7.3 Restart Caddy

```bash
sudo systemctl restart caddy
sudo systemctl status caddy
```

Caddy automatically obtains and renews TLS certificates via Let's Encrypt.

## 8. Verify End-to-End

```bash
# Landing page
curl -s https://drive.ssdid.my/ | head -5
# Expected: <!DOCTYPE html> ...

# Admin portal (returns SPA index.html for any path)
curl -s -o /dev/null -w "%{http_code}" https://drive.ssdid.my/admin/
# Expected: 200

# API health check
curl -s https://drive.ssdid.my/health
# Expected: {"status":"ok"}

# Server info
curl -s https://drive.ssdid.my/api/auth/ssdid/server-info | python3 -m json.tool
```

## 9. Backup & Maintenance

### 9.1 Database Backup

```bash
# Manual backup
mkdir -p ~/ssdid-drive/backups
podman exec ssdid-drive-db-1 pg_dump -U ssdid_drive ssdid_drive | gzip > ~/ssdid-drive/backups/db_$(date +%Y%m%d).sql.gz

# Cron job (daily at 2 AM, keep 30 days)
crontab -e
# Add:
# 0 2 * * * podman exec ssdid-drive-db-1 pg_dump -U ssdid_drive ssdid_drive | gzip > ~/ssdid-drive/backups/db_$(date +\%Y\%m\%d).sql.gz && find ~/ssdid-drive/backups -name "db_*.sql.gz" -mtime +30 -delete
```

### 9.2 Server Identity Backup

The file `~/ssdid-drive/data/server-identity.json` contains the server's private key. **Back it up securely** — losing it means all issued Verifiable Credentials become unverifiable.

```bash
cp ~/ssdid-drive/data/server-identity.json ~/ssdid-drive/backups/server-identity.json.bak
chmod 600 ~/ssdid-drive/backups/server-identity.json.bak
```

### 9.3 File Storage Backup

Client-encrypted files are stored at `~/ssdid-drive/data/files/`. Back up periodically:

```bash
# Incremental backup with rsync (daily at 3 AM)
# Add to crontab:
# 0 3 * * * rsync -a ~/ssdid-drive/data/files/ ~/ssdid-drive/backups/files/
```

For off-site backup, use `rsync` or `rclone` to push to a remote server or object storage.

### 9.4 Disk Usage Monitoring

Monitor file storage usage to avoid filling the disk:

```bash
# Check current usage
du -sh ~/ssdid-drive/data/files/

# Alert if usage exceeds 80% of disk (add to crontab, runs daily at 6 AM)
# 0 6 * * * df -h / | awk 'NR==2 {gsub(/%/,"",$5); if ($5 > 80) print "DISK WARNING: "$5"% used"}' | mail -s "SSDID Drive Disk Alert" admin@example.com 2>/dev/null
```

### 9.5 Update Deployment

```bash
cd ~/ssdid-drive/repo
git pull

# Rebuild image
podman build -t ssdid-drive-api:latest -f src/SsdidDrive.Api/Containerfile src/SsdidDrive.Api/

# Rolling restart
cd ~/ssdid-drive
podman compose down api
podman compose up -d api

# Verify
podman compose logs api --tail 20
curl -s https://drive.ssdid.my/health
```

### 9.6 View Logs

```bash
# API logs
podman compose logs api -f

# Database logs
podman compose logs db -f

# Caddy logs
sudo tail -f /var/log/caddy/drive.log
```

## 10. Security Checklist

- [ ] Change default PostgreSQL password from `CHANGE_ME_STRONG_PASSWORD`
- [ ] Verify `server-identity.json` is not world-readable (`chmod 600`)
- [ ] Verify `data/files/` directory permissions (`chmod 700`)
- [ ] UFW firewall enabled (only 22, 80, 443 open)
- [ ] Caddy TLS active (check `https://` works)
- [ ] PostgreSQL not exposed externally (port bound to container network only)
- [ ] Redis not exposed externally (container network only, no port mapping)
- [ ] API only listens on `127.0.0.1:5000` (Caddy proxies external traffic)
- [ ] CORS origins restricted to actual domains
- [ ] Regular backups configured for database, server identity, and file storage
- [ ] SSH key-only auth (disable password auth in `/etc/ssh/sshd_config`)
- [ ] Disk usage monitoring configured

## Architecture Overview

```
Internet
   │
   ▼
┌──────────────────────────────────────────────────┐
│  Caddy :443 (auto-TLS)                          │
│                                                  │
│  drive.ssdid.my/          → /var/www/landing/    │
│  drive.ssdid.my/admin/*   → /var/www/admin/      │
│  drive.ssdid.my/api/*     → localhost:5000       │
│  drive.ssdid.my/health    → localhost:5000       │
└──────────────────────────────────────────────────┘
         │                         │
         ▼                         ▼
┌─────────────────┐     ┌──────────────────┐
│ ssdid-drive API │────▶│  PostgreSQL 17   │
│ :5000 (Podman)  │     │  :5432 (512 MB)  │
│ (512 MB limit)  │     └──────────────────┘
│                 │     ┌──────────────────┐
│                 │────▶│  Redis 7         │
└─────────────────┘     │  :6379 (192 MB)  │
         │              └──────────────────┘
         ▼
┌───────────────────────┐     ┌──────────────────┐
│  SSDID Registry       │     │  Local Disk      │
│  registry.ssdid.my    │     │  ~/data/files/   │
└───────────────────────┘     │  (~130 GB)       │
                              └──────────────────┘
```

## Troubleshooting

| Problem | Check |
|---------|-------|
| API won't start | `podman compose logs api` — look for DB connection or native lib errors |
| `libkazsign.so` not found | Verify `LD_LIBRARY_PATH` in Containerfile matches VPS arch (`linux-amd64` for x86_64, `linux-arm64` for ARM) |
| DB connection refused | `podman compose ps` — is `db` healthy? Check password matches |
| Caddy 502 | Is API running? `curl localhost:5000/health` |
| SSE not working | Caddy must have `flush_interval -1` for the events endpoint |
| Server identity lost | Restore from backup; re-register DID at registry if needed |
| Certificate not issuing | DNS A record must point to VPS IP; check `sudo caddy validate` |
| Disk full | Check `du -sh ~/ssdid-drive/data/files/` and clean old backups |
| Redis OOM | Check `podman compose logs redis` — memory limit is 128 MB with LRU eviction |
