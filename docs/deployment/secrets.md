# Secrets Management

All secrets are stored in **GitHub Actions Secrets** (per-environment) and injected into deployments via SSH environment files.

## Required Secrets

### Per-Environment (staging / production)

| Secret | Description | Example |
|--------|-------------|---------|
| `SSH_HOST` | Deployment server hostname | `staging.securesharing.app` |
| `SSH_USER` | SSH user for deployment | `deploy` |
| `SSH_KEY` | SSH private key (Ed25519) | `-----BEGIN OPENSSH PRIVATE KEY-----...` |
| `DATABASE_URL` | PostgreSQL connection string | `ecto://user:pass@localhost:5432/securesharing` |
| `SECRET_KEY_BASE` | Phoenix secret key (64+ chars) | Generate via `mix phx.gen.secret` |
| `GARAGE_ACCESS_KEY` | Garage S3 access key | API key from Garage admin |
| `GARAGE_SECRET_KEY` | Garage S3 secret key | Secret from Garage admin |
| `ONESIGNAL_APP_ID` | OneSignal push notification app ID | UUID from OneSignal dashboard |
| `ONESIGNAL_API_KEY` | OneSignal REST API key | From OneSignal dashboard |

### PII Service (if deployed)

| Secret | Description |
|--------|-------------|
| `PII_DATABASE_URL` | PostgreSQL connection for PII service |
| `PII_SECRET_KEY_BASE` | Phoenix secret key for PII service |
| `OLLAMA_URL` | Ollama LLM endpoint (if using local LLM) |

### GitHub Repository Secrets (shared)

| Secret | Description |
|--------|-------------|
| `GITHUB_TOKEN` | Auto-provided by GitHub Actions |

## Generating Secrets

```bash
# Generate SECRET_KEY_BASE
mix phx.gen.secret

# Generate SSH key pair for deployment
ssh-keygen -t ed25519 -f deploy_key -N "" -C "github-actions-deploy"

# Generate Garage API keys (on Garage admin node)
garage key create securesharing-app
```

## Server Environment File

On each deployment server, create `/opt/securesharing/.env`:

```env
# Application
MIX_ENV=prod
PHX_HOST=staging.securesharing.app
PORT=4000
SECRET_KEY_BASE=<from-github-secrets>

# Database
DATABASE_URL=ecto://securesharing:password@localhost:5432/securesharing_prod

# Storage (Garage S3)
GARAGE_ENDPOINT=http://localhost:3900
GARAGE_ACCESS_KEY_ID=<key>
GARAGE_SECRET_ACCESS_KEY=<secret>
GARAGE_BUCKET=securesharing-files
GARAGE_REGION=garage

# Push Notifications
ONESIGNAL_APP_ID=<app-id>
ONESIGNAL_API_KEY=<api-key>

# Oban (background jobs)
OBAN_DEFAULT_QUEUE_SIZE=10
OBAN_MAILER_QUEUE_SIZE=5
OBAN_CLEANUP_QUEUE_SIZE=3
OBAN_STORAGE_QUEUE_SIZE=5
OBAN_MAINTENANCE_QUEUE_SIZE=2

# CORS
CORS_ORIGINS=https://app.securesharing.app,tauri://localhost
```

## Secret Rotation

1. Generate new secret value
2. Update in GitHub Actions Secrets
3. Update `/opt/securesharing/.env` on server
4. Restart service: `docker compose restart`

For `SECRET_KEY_BASE` rotation, note that existing sessions will be invalidated.

## Security Notes

- Never commit secrets to the repository
- Use environment-specific secrets (staging vs production)
- SSH keys should be Ed25519 and dedicated to deployment (no human access)
- Rotate secrets at least annually or after team member departure
- The `.env` file on servers should be readable only by the service user:
  ```bash
  chown securesharing:securesharing /opt/securesharing/.env
  chmod 600 /opt/securesharing/.env
  ```
