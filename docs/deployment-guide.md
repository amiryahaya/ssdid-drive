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
mkdir -p ~/ssdid-drive/{data,config}
```

```
~/ssdid-drive/
├── config/
│   └── appsettings.Production.json
├── data/
│   ├── server-identity.json     # Auto-generated on first run (contains private key)
│   └── files/                   # Client-encrypted file storage
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
    "Default": "Host=db;Port=5432;Database=ssdid_drive;Username=ssdid_drive;Password=CHANGE_ME_STRONG_PASSWORD"
  },
  "Ssdid": {
    "RegistryUrl": "https://registry.ssdid.my",
    "IdentityPath": "/app/data/server-identity.json",
    "Algorithm": "KazSignVerificationKey2024",
    "ServiceUrl": "https://drive.ssdid.my",
    "PreviousIdentities": []
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
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ssdid_drive"]
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
    environment:
      ASPNETCORE_ENVIRONMENT: Production
      ASPNETCORE_URLS: http://+:5000
      ENABLE_AUTO_MIGRATE: "true"
    volumes:
      - ./config/appsettings.Production.json:/app/appsettings.Production.json:ro
      - ./data:/app/data
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

networks:
  backend:
EOF
```

**Important:** Use the same password in both `db` and `appsettings.Production.json`.

## 6. Build & Deploy

### 6.1 Clone Repository

```bash
cd ~/ssdid-drive
git clone https://github.com/YOUR_ORG/ssdid-drive.git repo
```

### 6.2 Build Container Image

```bash
cd ~/ssdid-drive/repo
podman build -t ssdid-drive-api:latest -f src/SsdidDrive.Api/Containerfile src/SsdidDrive.Api/
```

### 6.3 Start Services

```bash
cd ~/ssdid-drive
podman compose up -d
```

### 6.4 Verify

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

# Deploy admin SPA build artifacts here later
# sudo cp -r ~/ssdid-drive/repo/clients/admin/dist/* /var/www/admin/
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
podman exec ssdid-drive-db-1 pg_dump -U ssdid_drive ssdid_drive | gzip > ~/backups/ssdid_drive_$(date +%Y%m%d).sql.gz

# Cron job (daily at 2 AM)
mkdir -p ~/backups
crontab -e
# Add: 0 2 * * * podman exec ssdid-drive-db-1 pg_dump -U ssdid_drive ssdid_drive | gzip > ~/backups/ssdid_drive_$(date +\%Y\%m\%d).sql.gz && find ~/backups -name "*.sql.gz" -mtime +30 -delete
```

### 9.2 Server Identity Backup

The file `~/ssdid-drive/data/server-identity.json` contains the server's private key. **Back it up securely** — losing it means all issued Verifiable Credentials become unverifiable.

```bash
cp ~/ssdid-drive/data/server-identity.json ~/backups/server-identity.json.bak
chmod 600 ~/backups/server-identity.json.bak
```

### 9.3 Update Deployment

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

### 9.4 View Logs

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
- [ ] UFW firewall enabled (only 22, 80, 443 open)
- [ ] Caddy TLS active (check `https://` works)
- [ ] PostgreSQL not exposed externally (port bound to container network only)
- [ ] API only listens on `127.0.0.1:5000` (Caddy proxies external traffic)
- [ ] CORS origins restricted to actual domains
- [ ] Regular backups configured for database and server identity
- [ ] SSH key-only auth (disable password auth in `/etc/ssh/sshd_config`)

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
│ ssdid-drive API │     │  PostgreSQL 17   │
│ :5000 (Podman)  │────▶│  :5432 (Podman)  │
└─────────────────┘     └──────────────────┘
         │
         ▼
┌───────────────────────┐
│  SSDID Registry       │
│  registry.ssdid.my    │
└───────────────────────┘
```

## Troubleshooting

| Problem | Check |
|---------|-------|
| API won't start | `podman compose logs api` — look for DB connection or native lib errors |
| `libkazsign.so` not found | Verify `LD_LIBRARY_PATH` in Containerfile matches actual runtime path |
| DB connection refused | `podman compose ps` — is `db` healthy? Check password matches |
| Caddy 502 | Is API running? `curl localhost:5000/health` |
| SSE not working | Caddy must have `flush_interval -1` for the events endpoint |
| Server identity lost | Restore from backup; re-register DID at registry if needed |
| Certificate not issuing | DNS A record must point to VPS IP; check `sudo caddy validate` |
