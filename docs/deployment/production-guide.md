# SecureSharing Production Deployment Guide

This guide covers deploying SecureSharing to production environments.

## Prerequisites

- Elixir 1.18+ and Erlang/OTP 27+
- PostgreSQL 14+
- AWS S3 (or S3-compatible storage)
- Domain with SSL certificate
- (Optional) Redis for rate limiting and caching

## Architecture Overview

```
                    ┌─────────────┐
                    │   Load      │
                    │  Balancer   │
                    │   (SSL)     │
                    └──────┬──────┘
                           │
              ┌────────────┼────────────┐
              │            │            │
        ┌─────▼────┐ ┌─────▼────┐ ┌─────▼────┐
        │  Node 1  │ │  Node 2  │ │  Node 3  │
        │ Phoenix  │ │ Phoenix  │ │ Phoenix  │
        └─────┬────┘ └─────┬────┘ └─────┬────┘
              │            │            │
              └────────────┼────────────┘
                           │
              ┌────────────┼────────────┐
              │            │            │
        ┌─────▼────┐ ┌─────▼────┐ ┌─────▼────┐
        │PostgreSQL│ │   S3     │ │  Redis   │
        │ Primary  │ │  Bucket  │ │ (opt.)   │
        └──────────┘ └──────────┘ └──────────┘
```

## Environment Variables

### Required Variables

```bash
# Database
DATABASE_URL="ecto://user:pass@host:5432/securesharing_prod"

# Phoenix
SECRET_KEY_BASE="generate-with-mix-phx-gen-secret"
PHX_HOST="api.yourdomain.com"
PHX_SERVER=true
PORT=4000

# JWT Authentication
JWT_SECRET="generate-secure-random-32-bytes-minimum"

# S3 Storage
S3_BUCKET="securesharing-prod-files"
AWS_REGION="us-east-1"
AWS_ACCESS_KEY_ID="AKIA..."
AWS_SECRET_ACCESS_KEY="..."
```

### Optional Variables

```bash
# Rate Limiting (optional - defaults to ETS backend)
REDIS_URL="redis://localhost:6379"

# Logging
LOG_LEVEL="info"

# Metrics
OTEL_EXPORTER_OTLP_ENDPOINT="https://otel-collector:4317"

# Pool sizes (tune for your load)
POOL_SIZE=10
```

## Generating Secrets

```bash
# Generate SECRET_KEY_BASE
mix phx.gen.secret

# Generate JWT_SECRET (minimum 32 bytes)
openssl rand -base64 32
```

## Building the Release

### 1. Clone and Setup

```bash
git clone https://github.com/your-org/securesharing.git
cd securesharing

# Install dependencies
mix deps.get --only prod
MIX_ENV=prod mix compile
```

### 2. Build the Release

```bash
MIX_ENV=prod mix release
```

The release will be created in `_build/prod/rel/secure_sharing/`.

### 3. Docker Build (Alternative)

```dockerfile
# Dockerfile
FROM hexpm/elixir:1.18.2-erlang-27.0.1-alpine-3.18.4 as build

# Install build dependencies
RUN apk add --no-cache build-base git

WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force && mix local.rebar --force

# Set build ENV
ENV MIX_ENV=prod

# Install mix dependencies
COPY mix.exs mix.lock ./
COPY config config
RUN mix deps.get --only $MIX_ENV
RUN mix deps.compile

# Copy native files
COPY native native

# Compile native code
RUN cd native/kaz_kem && make
RUN cd native/ml_kem && make
RUN cd native/ml_dsa && make

# Copy application code
COPY lib lib
COPY priv priv
COPY assets assets

# Compile and build release
RUN mix compile
RUN mix assets.deploy
RUN mix release

# Runtime image
FROM alpine:3.18.4

RUN apk add --no-cache libstdc++ openssl ncurses-libs

WORKDIR /app

COPY --from=build /app/_build/prod/rel/secure_sharing ./

ENV HOME=/app
ENV PORT=4000

EXPOSE 4000

CMD ["bin/secure_sharing", "start"]
```

Build with:

```bash
docker build -t securesharing:latest .
```

## Database Setup

### 1. Create Database

```sql
CREATE USER securesharing WITH PASSWORD 'secure_password';
CREATE DATABASE securesharing_prod OWNER securesharing;
GRANT ALL PRIVILEGES ON DATABASE securesharing_prod TO securesharing;

-- Enable required extensions
\c securesharing_prod
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
```

### 2. Run Migrations

```bash
# Using release
./bin/secure_sharing eval "SecureSharing.Release.migrate()"

# Or using convenience script
./bin/migrate
```

### 3. Verify Migration Status

```bash
./bin/secure_sharing eval "SecureSharing.Release.migration_status()"
```

## S3 Configuration

### 1. Create S3 Bucket

```bash
aws s3 mb s3://securesharing-prod-files --region us-east-1
```

### 2. Configure Bucket Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::ACCOUNT_ID:user/securesharing"
      },
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::securesharing-prod-files/*"
    }
  ]
}
```

### 3. Configure CORS (for direct uploads)

```json
{
  "CORSRules": [
    {
      "AllowedOrigins": ["https://app.yourdomain.com"],
      "AllowedMethods": ["GET", "PUT"],
      "AllowedHeaders": ["*"],
      "ExposeHeaders": ["ETag"],
      "MaxAgeSeconds": 3600
    }
  ]
}
```

## Running the Server

### Systemd Service

Create `/etc/systemd/system/securesharing.service`:

```ini
[Unit]
Description=SecureSharing API
After=network.target postgresql.service

[Service]
Type=simple
User=securesharing
Group=securesharing
WorkingDirectory=/opt/securesharing
ExecStart=/opt/securesharing/bin/secure_sharing start
ExecStop=/opt/securesharing/bin/secure_sharing stop
Restart=on-failure
RestartSec=5

# Environment
Environment=MIX_ENV=prod
Environment=PORT=4000
Environment=PHX_SERVER=true
EnvironmentFile=/etc/securesharing/env

# Security
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/log/securesharing

[Install]
WantedBy=multi-user.target
```

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable securesharing
sudo systemctl start securesharing
```

### Docker Compose

```yaml
version: '3.8'

services:
  app:
    image: securesharing:latest
    ports:
      - "4000:4000"
    environment:
      DATABASE_URL: ecto://user:pass@db:5432/securesharing
      SECRET_KEY_BASE: ${SECRET_KEY_BASE}
      PHX_HOST: api.yourdomain.com
      PHX_SERVER: "true"
      JWT_SECRET: ${JWT_SECRET}
      S3_BUCKET: securesharing-prod-files
      AWS_REGION: us-east-1
      AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID}
      AWS_SECRET_ACCESS_KEY: ${AWS_SECRET_ACCESS_KEY}
    depends_on:
      - db
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  db:
    image: postgres:14-alpine
    volumes:
      - postgres_data:/var/lib/postgresql/data
    environment:
      POSTGRES_USER: securesharing
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: securesharing

volumes:
  postgres_data:
```

## Load Balancer Configuration

### Nginx Configuration

```nginx
upstream securesharing {
    server 127.0.0.1:4000;
    server 127.0.0.1:4001;
    server 127.0.0.1:4002;
}

server {
    listen 443 ssl http2;
    server_name api.yourdomain.com;

    ssl_certificate /etc/ssl/certs/api.yourdomain.com.pem;
    ssl_certificate_key /etc/ssl/private/api.yourdomain.com.key;

    # SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;

    location / {
        proxy_pass http://securesharing;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
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
        proxy_read_timeout 3600s;
    }
}
```

## Monitoring

### Health Checks

```bash
# Basic health check
curl http://localhost:4000/health

# Readiness check (includes database)
curl http://localhost:4000/health/ready
```

### Metrics

The application exposes metrics via Phoenix's built-in telemetry. For production, consider using:

- **Prometheus + Grafana**: Use `prom_ex` or `telemetry_metrics_prometheus`
- **DataDog**: Use `spandex_datadog`
- **OpenTelemetry**: Use `opentelemetry_exporter`

### Logging

Logs are output in JSON format in production:

```bash
# View logs with journalctl
journalctl -u securesharing -f

# Docker logs
docker logs -f securesharing_app_1
```

## Backup & Recovery

### Database Backups

```bash
# Create backup
pg_dump -h localhost -U securesharing securesharing_prod > backup.sql

# Restore backup
psql -h localhost -U securesharing securesharing_prod < backup.sql
```

### S3 Backup (Cross-region replication)

Enable cross-region replication on the S3 bucket for disaster recovery.

## Scaling

### Horizontal Scaling

SecureSharing is stateless and supports horizontal scaling:

1. Add more application nodes behind the load balancer
2. Ensure `SECRET_KEY_BASE` is the same across all nodes
3. Use Redis for distributed rate limiting if needed

### Database Scaling

- Use PostgreSQL read replicas for read-heavy workloads
- Consider PgBouncer for connection pooling
- Monitor query performance with `pg_stat_statements`

## Security Checklist

- [ ] All traffic over HTTPS/TLS 1.2+
- [ ] `SECRET_KEY_BASE` is securely generated and stored
- [ ] `JWT_SECRET` is securely generated and stored
- [ ] Database credentials are not in version control
- [ ] S3 bucket is not publicly accessible
- [ ] Rate limiting is enabled
- [ ] CORS is properly configured
- [ ] Security headers are set (HSTS, X-Frame-Options, etc.)
- [ ] PostgreSQL is not exposed to the internet
- [ ] Application runs as non-root user
- [ ] Dependencies are regularly updated

## Troubleshooting

### Application Won't Start

1. Check environment variables are set
2. Verify database connectivity
3. Check logs: `journalctl -u securesharing -n 100`

### Database Connection Issues

```bash
# Test database connection
./bin/secure_sharing eval "IO.inspect(SecureSharing.Repo.query!(\"SELECT 1\"))"
```

### S3 Access Issues

```bash
# Test S3 access
aws s3 ls s3://securesharing-prod-files/
```

### Performance Issues

1. Check database query times with `EXPLAIN ANALYZE`
2. Monitor Erlang VM with `:observer.start()` in remote console
3. Review application logs for slow requests
