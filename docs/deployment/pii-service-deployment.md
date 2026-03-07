# PII Service Deployment Guide

This document describes the complete setup required to deploy the PII Service to staging and production environments.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [GitHub Configuration](#github-configuration)
- [Infrastructure Options](#infrastructure-options)
- [Environment Variables](#environment-variables)
- [Database Setup](#database-setup)
- [S3/Object Storage Setup](#s3object-storage-setup)
- [Enabling Deployments](#enabling-deployments)
- [Deployment Commands](#deployment-commands)
- [Monitoring & Observability](#monitoring--observability)
- [Troubleshooting](#troubleshooting)

---

## Overview

The PII Service CI/CD pipeline consists of two workflows:

| Workflow | File | Purpose |
|----------|------|---------|
| CI | `.github/workflows/pii-service-ci.yml` | Lint, test, build verification |
| Deploy | `.github/workflows/pii-service-deploy.yml` | Build images, deploy to environments |

### Current Status

- [x] CI pipeline (fully functional)
- [x] Docker image build & push to GHCR
- [ ] Staging environment
- [ ] Production environment
- [ ] Database provisioning
- [ ] Secrets configuration

---

## Prerequisites

### Required Tools

```bash
# Docker (for local testing)
docker --version  # >= 24.0

# GitHub CLI (for secrets management)
gh --version  # >= 2.0

# Optional: kubectl, aws-cli, flyctl depending on deployment target
```

### Required Accounts

- GitHub account with access to the repository
- Container registry access (GHCR is included with GitHub)
- Cloud provider account (AWS, GCP, Fly.io, or self-hosted)
- PostgreSQL database (managed or self-hosted)
- S3-compatible storage (AWS S3, MinIO, Cloudflare R2, etc.)

---

## GitHub Configuration

### 1. Repository Secrets

Navigate to: **Settings → Secrets and variables → Actions → Secrets**

#### Required Secrets

| Secret | Description | Example |
|--------|-------------|---------|
| `DATABASE_URL` | PostgreSQL connection string | `postgres://user:pass@host:5432/pii_service` |
| `SECRET_KEY_BASE` | Phoenix secret key (64+ chars) | Generate with `mix phx.gen.secret` |
| `JWT_SECRET` | JWT signing secret (32+ chars) | Generate with `openssl rand -hex 32` |

#### Optional Secrets (based on deployment method)

| Secret | Description | When Needed |
|--------|-------------|-------------|
| `AWS_ACCESS_KEY_ID` | AWS credentials | AWS ECS/S3 |
| `AWS_SECRET_ACCESS_KEY` | AWS credentials | AWS ECS/S3 |
| `KUBECONFIG` | Kubernetes config (base64) | Kubernetes |
| `STAGING_SSH_HOST` | SSH host for staging | Docker Compose on VM |
| `STAGING_SSH_KEY` | SSH private key | Docker Compose on VM |
| `PRODUCTION_SSH_HOST` | SSH host for production | Docker Compose on VM |
| `PRODUCTION_SSH_KEY` | SSH private key | Docker Compose on VM |
| `FLY_API_TOKEN` | Fly.io API token | Fly.io |
| `SLACK_WEBHOOK_URL` | Slack notifications | Notifications |
| `CODECOV_TOKEN` | Codecov upload token | Code coverage |

### 2. Repository Variables

Navigate to: **Settings → Secrets and variables → Actions → Variables**

| Variable | Description | Example |
|----------|-------------|---------|
| `STAGING_URL` | Staging service URL | `https://pii-staging.example.com` |
| `PRODUCTION_URL` | Production service URL | `https://pii.example.com` |

### 3. Environments

Navigate to: **Settings → Environments**

Create two environments:

#### Staging Environment

- Name: `staging`
- Protection rules: None (auto-deploy on main)
- Environment secrets: (staging-specific overrides)
- Environment variables:
  - `STAGING_URL`: `https://pii-staging.example.com`

#### Production Environment

- Name: `production`
- Protection rules:
  - [x] Required reviewers: (add team members)
  - [x] Wait timer: 5 minutes (optional)
- Deployment branches: `main` and tags matching `pii-service-v*`
- Environment secrets: (production-specific overrides)
- Environment variables:
  - `PRODUCTION_URL`: `https://pii.example.com`

---

## Infrastructure Options

Choose ONE deployment method and configure accordingly:

### Option 1: Kubernetes

```yaml
# In deploy-staging job, uncomment:
- name: Deploy to staging
  run: |
    kubectl set image deployment/pii-service \
      pii-service=${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}@${{ needs.build.outputs.image_digest }} \
      -n pii-service
```

**Required secrets:**
- `KUBECONFIG`: Base64-encoded kubeconfig file

**Setup steps:**
1. Create namespace: `kubectl create namespace pii-service`
2. Create deployment manifests (see `k8s/` directory if available)
3. Configure ingress for external access
4. Set up database connection via secrets

### Option 2: AWS ECS

```yaml
# In deploy-staging job, uncomment:
- name: Deploy to staging
  run: |
    aws ecs update-service \
      --cluster pii-service-staging \
      --service pii-service \
      --force-new-deployment
```

**Required secrets:**
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_REGION` (or set in workflow)

**Setup steps:**
1. Create ECS cluster
2. Create task definition with container image
3. Create ECS service
4. Configure ALB for load balancing
5. Set up RDS for PostgreSQL

### Option 3: Fly.io

```yaml
# In deploy-staging job, uncomment:
- name: Deploy to staging
  run: |
    flyctl deploy \
      --image ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ needs.build.outputs.image_tag }} \
      --app pii-service-staging
```

**Required secrets:**
- `FLY_API_TOKEN`

**Setup steps:**
1. Install flyctl: `curl -L https://fly.io/install.sh | sh`
2. Create app: `flyctl apps create pii-service-staging`
3. Create PostgreSQL: `flyctl postgres create`
4. Attach database: `flyctl postgres attach`
5. Set secrets: `flyctl secrets set SECRET_KEY_BASE=...`

### Option 4: Docker Compose on VM

```yaml
# In deploy-staging job, uncomment:
- name: Deploy to staging
  run: |
    ssh -i ${{ secrets.STAGING_SSH_KEY }} ${{ secrets.STAGING_SSH_HOST }} \
      "cd /app/pii-service && \
       docker-compose pull && \
       docker-compose up -d"
```

**Required secrets:**
- `STAGING_SSH_HOST`: `user@hostname`
- `STAGING_SSH_KEY`: SSH private key content

**Setup steps:**
1. Provision VM (Ubuntu 22.04+ recommended)
2. Install Docker and Docker Compose
3. Clone repository or copy docker-compose files
4. Configure `.env` file with secrets
5. Set up reverse proxy (nginx/caddy) for HTTPS

---

## Environment Variables

The PII Service requires these environment variables at runtime:

### Required

```bash
# Database
DATABASE_URL=postgres://user:password@host:5432/pii_service

# Phoenix
SECRET_KEY_BASE=<64+ character secret>
PHX_HOST=pii.example.com
PORT=4001

# Authentication
JWT_SECRET=<32+ character secret>
```

### Optional

```bash
# S3 Storage
AWS_ACCESS_KEY_ID=<access_key>
AWS_SECRET_ACCESS_KEY=<secret_key>
AWS_REGION=us-east-1
S3_BUCKET=pii-service-files
S3_ENDPOINT=https://s3.amazonaws.com  # Or MinIO/R2 endpoint

# LLM Integration
OPENAI_API_KEY=<api_key>
ANTHROPIC_API_KEY=<api_key>

# Local SLM (Ollama)
PII_LOCAL_SLM_ENABLED=true
OLLAMA_HOST=http://localhost:11434

# Presidio NER
PRESIDIO_URL=http://localhost:5002

# Monitoring
OTEL_EXPORTER_OTLP_ENDPOINT=https://otel-collector:4318
```

---

## Database Setup

### PostgreSQL Requirements

- Version: 14+ (16 recommended)
- Extensions: `uuid-ossp`, `pgcrypto`

### Managed Database Options

| Provider | Service | Notes |
|----------|---------|-------|
| AWS | RDS PostgreSQL | Production-ready, managed backups |
| GCP | Cloud SQL | Production-ready, managed backups |
| Fly.io | Fly Postgres | Easy setup with flyctl |
| Supabase | PostgreSQL | Free tier available |
| Neon | Serverless Postgres | Generous free tier |

### Connection String Format

```
postgres://USERNAME:PASSWORD@HOST:PORT/DATABASE?sslmode=require
```

### Running Migrations

```bash
# Local
mix ecto.migrate

# Docker
docker run --rm \
  -e DATABASE_URL=$DATABASE_URL \
  ghcr.io/amiryahaya/secure-sharing/pii-service:latest \
  /app/bin/pii_service eval "PiiService.Release.migrate()"

# In CI/CD (add to workflow)
- name: Run migrations
  run: |
    docker run --rm \
      -e DATABASE_URL=${{ secrets.DATABASE_URL }} \
      ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ needs.build.outputs.image_tag }} \
      /app/bin/pii_service eval "PiiService.Release.migrate()"
```

---

## S3/Object Storage Setup

The PII Service stores encrypted files in S3-compatible storage.

### Bucket Structure

```
pii-service-bucket/
├── {tenant_id}/
│   └── {user_id}/
│       ├── uploads/          # Original encrypted files
│       └── redacted/         # Redacted file versions
```

### Bucket Policy (AWS S3)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::pii-service-bucket",
        "arn:aws:s3:::pii-service-bucket/*"
      ]
    }
  ]
}
```

### Alternative: MinIO (Self-hosted)

```yaml
# docker-compose.yml addition
minio:
  image: minio/minio
  command: server /data --console-address ":9001"
  environment:
    MINIO_ROOT_USER: minioadmin
    MINIO_ROOT_PASSWORD: minioadmin
  ports:
    - "9000:9000"
    - "9001:9001"
  volumes:
    - minio_data:/data
```

---

## Enabling Deployments

Once infrastructure is ready, enable deployments:

### 1. Update Workflow File

Edit `.github/workflows/pii-service-deploy.yml`:

```yaml
# Change this:
if: false && (github.ref == 'refs/heads/main' || inputs.environment == 'staging')

# To this:
if: github.ref == 'refs/heads/main' || inputs.environment == 'staging'
```

### 2. Add Deployment Commands

Uncomment and configure the appropriate deployment option in the workflow.

### 3. Test with Manual Trigger

1. Go to **Actions → PII Service Deploy**
2. Click **Run workflow**
3. Select environment: `staging`
4. Click **Run workflow**

### 4. Monitor Deployment

Watch the workflow run and check:
- Docker image pushed successfully
- Deployment commands executed
- Health check passed

---

## Deployment Commands

### Manual Deployment

```bash
# Pull latest image
docker pull ghcr.io/amiryahaya/secure-sharing/pii-service:latest

# Run with environment variables
docker run -d \
  --name pii-service \
  -p 4001:4001 \
  -e DATABASE_URL="$DATABASE_URL" \
  -e SECRET_KEY_BASE="$SECRET_KEY_BASE" \
  -e JWT_SECRET="$JWT_SECRET" \
  -e PHX_HOST="pii.example.com" \
  ghcr.io/amiryahaya/secure-sharing/pii-service:latest
```

### Create Release Tag

```bash
# Create and push a release tag
git tag pii-service-v1.0.0
git push origin pii-service-v1.0.0
```

### Rollback

```bash
# Deploy previous version
docker pull ghcr.io/amiryahaya/secure-sharing/pii-service:sha-<previous_sha>
docker-compose up -d
```

---

## Monitoring & Observability

### Health Endpoints

| Endpoint | Purpose |
|----------|---------|
| `GET /health` | Basic health check |
| `GET /health/ready` | Readiness (includes DB) |
| `GET /health/live` | Liveness probe |

### Recommended Monitoring Stack

1. **Metrics**: Prometheus + Grafana
2. **Logs**: Loki or CloudWatch Logs
3. **Tracing**: Jaeger or AWS X-Ray
4. **Alerts**: Grafana Alerting or PagerDuty

### Phoenix LiveDashboard

Available at `/dev/dashboard` in development. For production:

```elixir
# config/runtime.exs
config :pii_service, PiiServiceWeb.Endpoint,
  live_view: [signing_salt: "..."]

# router.ex - protect with authentication
live_dashboard "/dashboard", metrics: PiiServiceWeb.Telemetry
```

---

## Troubleshooting

### Common Issues

#### Container won't start

```bash
# Check logs
docker logs pii-service

# Common causes:
# - DATABASE_URL not set or incorrect
# - SECRET_KEY_BASE not set
# - Port already in use
```

#### Database connection failed

```bash
# Test connection
psql $DATABASE_URL -c "SELECT 1"

# Check:
# - Database host is accessible from container
# - Credentials are correct
# - SSL mode is correct (require/disable)
```

#### Migrations failed

```bash
# Run migrations manually
docker exec pii-service /app/bin/pii_service eval "PiiService.Release.migrate()"

# Check for pending migrations
mix ecto.migrations
```

#### Health check failing

```bash
# Test locally
curl http://localhost:4001/health

# Check:
# - Application is running
# - Database is connected
# - Port is exposed correctly
```

### Getting Help

1. Check application logs: `docker logs pii-service`
2. Check workflow run logs in GitHub Actions
3. Review this documentation
4. Open an issue in the repository

---

## Checklist

Use this checklist when setting up a new environment:

### Initial Setup

- [ ] GitHub secrets configured
- [ ] GitHub environment created
- [ ] Database provisioned
- [ ] S3 bucket created
- [ ] Domain/DNS configured

### Deployment

- [ ] Workflow `if` condition updated
- [ ] Deployment commands uncommented
- [ ] Health check URL configured
- [ ] Test deployment successful

### Post-Deployment

- [ ] Health endpoint responding
- [ ] Logs are being collected
- [ ] Monitoring dashboards set up
- [ ] Alerts configured
- [ ] Backup strategy in place
