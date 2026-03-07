# Backup & Restore Guide

**Version**: 1.0.0
**Last Updated**: 2026-02

## 1. Overview

SecureSharing is a zero-knowledge encrypted platform. The server stores only ciphertext
and encrypted key material -- never plaintext files or user encryption keys. This means
backups capture encrypted data that is useless without client-side keys, but it also means
that losing server-side wrapped keys (stored in PostgreSQL) permanently breaks users'
ability to decrypt their files.

### What Each Store Holds

| Store | Data | Criticality |
|-------|------|-------------|
| **PostgreSQL** | Users, tenants, credentials, share grants, wrapped keys (DEK/KEK), encrypted private keys, recovery shares, audit events | Critical -- loss means total data loss |
| **Garage S3** | Encrypted file blobs (AES-256-GCM ciphertext) | Critical -- loss means file content loss |
| **Application config** | SECRET_KEY_BASE, JWT_SECRET, S3 credentials, database URL | Critical -- loss means service cannot start |

### RPO / RTO Targets

| Metric | Target | Method |
|--------|--------|--------|
| RPO (Recovery Point Objective) | 1 hour | WAL archiving + hourly S3 sync |
| RTO (Recovery Time Objective) | 4 hours | Documented recovery procedure |
| Backup retention | 30 days (daily) + 12 months (monthly) | Automated rotation |

## 2. PostgreSQL Backup

### 2.1 Automated Daily Backups with pg_dump

Create `/opt/securesharing/scripts/backup-db.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="/var/backups/securesharing/postgres"
DB_NAME="securesharing_prod"
DB_USER="securesharing"
DB_HOST="localhost"
DB_PORT="5432"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=30
BACKUP_FILE="${BACKUP_DIR}/daily/${DB_NAME}_${TIMESTAMP}.sql.gz"

mkdir -p "${BACKUP_DIR}/daily" "${BACKUP_DIR}/monthly" "${BACKUP_DIR}/wal"

# Custom-format dump (supports parallel restore and selective table restore)
pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -Fc \
  --no-owner --no-acl \
  "$DB_NAME" | gzip > "$BACKUP_FILE"

# Verify the backup is not empty
if [ ! -s "$BACKUP_FILE" ]; then
  echo "ERROR: Backup file is empty" >&2
  exit 1
fi

# Rotate daily backups older than retention period
find "${BACKUP_DIR}/daily" -name "*.sql.gz" -mtime +${RETENTION_DAYS} -delete

# On the 1st of the month, copy to monthly (kept 12 months)
if [ "$(date +%d)" = "01" ]; then
  cp "$BACKUP_FILE" "${BACKUP_DIR}/monthly/"
  find "${BACKUP_DIR}/monthly" -name "*.sql.gz" -mtime +365 -delete
fi

echo "Backup complete: ${BACKUP_FILE} ($(du -h "$BACKUP_FILE" | cut -f1))"
```

```bash
chmod +x /opt/securesharing/scripts/backup-db.sh
```

### 2.2 WAL Archiving for Point-in-Time Recovery (PITR)

Add to `postgresql.conf`:

```ini
wal_level = replica
archive_mode = on
archive_command = 'gzip < %p > /var/backups/securesharing/postgres/wal/%f.gz'
archive_timeout = 300
```

Take a base backup for PITR:

```bash
pg_basebackup -h localhost -U securesharing -D /var/backups/securesharing/postgres/basebackup \
  --format=tar --gzip --checkpoint=fast --wal-method=stream
```

### 2.3 Point-in-Time Recovery

To recover to a specific timestamp:

```bash
# 1. Stop the application
sudo systemctl stop securesharing

# 2. Stop PostgreSQL
sudo systemctl stop postgresql

# 3. Move current data directory aside
sudo mv /var/lib/postgresql/18/main /var/lib/postgresql/18/main.old

# 4. Restore base backup
sudo mkdir /var/lib/postgresql/18/main
sudo tar xzf /var/backups/securesharing/postgres/basebackup/base.tar.gz \
  -C /var/lib/postgresql/18/main

# 5. Create recovery signal and configure WAL replay
cat <<EOF | sudo tee /var/lib/postgresql/18/main/postgresql.auto.conf
restore_command = 'gunzip < /var/backups/securesharing/postgres/wal/%f.gz > %p'
recovery_target_time = '2026-02-17 14:30:00+00'
recovery_target_action = 'promote'
EOF
sudo touch /var/lib/postgresql/18/main/recovery.signal

# 6. Fix ownership and start
sudo chown -R postgres:postgres /var/lib/postgresql/18/main
sudo systemctl start postgresql

# 7. Verify recovery, then start the application
sudo -u postgres psql -d securesharing_prod -c "SELECT count(*) FROM users;"
sudo systemctl start securesharing
```

### 2.4 Backup Verification

Add to `/opt/securesharing/scripts/verify-db-backup.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

LATEST=$(ls -t /var/backups/securesharing/postgres/daily/*.sql.gz | head -1)
VERIFY_DB="securesharing_verify_$(date +%s)"

echo "Verifying: ${LATEST}"

# Restore to a temporary database
createdb -U securesharing "$VERIFY_DB"
gunzip < "$LATEST" | pg_restore -U securesharing -d "$VERIFY_DB" --no-owner --no-acl 2>/dev/null

# Check critical tables exist and have data
for table in users tenants files folders share_grants credentials recovery_shares; do
  COUNT=$(psql -U securesharing -d "$VERIFY_DB" -tAc "SELECT count(*) FROM ${table};" 2>/dev/null || echo "MISSING")
  echo "  ${table}: ${COUNT} rows"
done

# Drop temporary database
dropdb -U securesharing "$VERIFY_DB"
echo "Verification complete."
```

## 3. S3/Garage Object Storage Backup

### 3.1 Cross-Site Replication (Garage)

For multi-node Garage deployments, configure replication in `garage.toml`:

```toml
[replication]
mode = "3"          # 3 copies across nodes
```

For single-node deployments, sync to a remote backup location:

```bash
#!/usr/bin/env bash
# /opt/securesharing/scripts/backup-s3.sh
set -euo pipefail

REMOTE_BACKUP="s3://securesharing-backup-dr"
LOCAL_ENDPOINT="http://localhost:3900"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Sync all buckets to remote backup using rclone
rclone sync garage:securesharing-files backup-remote:${REMOTE_BACKUP}/files \
  --transfers 8 --checkers 16 --log-file /var/log/securesharing/s3-backup.log

echo "${TIMESTAMP} S3 backup sync complete" >> /var/log/securesharing/backup.log
```

Configure rclone remotes in `~/.config/rclone/rclone.conf`:

```ini
[garage]
type = s3
provider = Other
endpoint = http://localhost:3900
access_key_id = YOUR_GARAGE_ACCESS_KEY
secret_access_key = YOUR_GARAGE_SECRET_KEY

[backup-remote]
type = s3
provider = AWS
region = ap-southeast-1
access_key_id = YOUR_BACKUP_ACCESS_KEY
secret_access_key = YOUR_BACKUP_SECRET_KEY
```

### 3.2 Backup Verification

```bash
#!/usr/bin/env bash
# Compare object counts between primary and backup
PRIMARY_COUNT=$(rclone size garage:securesharing-files --json | jq '.count')
BACKUP_COUNT=$(rclone size backup-remote:securesharing-backup-dr/files --json | jq '.count')

if [ "$PRIMARY_COUNT" != "$BACKUP_COUNT" ]; then
  echo "WARNING: Object count mismatch. Primary=${PRIMARY_COUNT} Backup=${BACKUP_COUNT}"
  exit 1
fi
echo "S3 backup verified: ${PRIMARY_COUNT} objects in sync."
```

## 4. Application State Backup

### 4.1 Configuration and Secrets

Back up the environment file that contains all runtime secrets:

```bash
#!/usr/bin/env bash
# /opt/securesharing/scripts/backup-secrets.sh
set -euo pipefail

BACKUP_DIR="/var/backups/securesharing/secrets"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
mkdir -p "$BACKUP_DIR"

# Encrypt the env file with a GPG key before storing
gpg --encrypt --recipient ops@yourcompany.com \
  --output "${BACKUP_DIR}/env_${TIMESTAMP}.gpg" \
  /etc/securesharing/env

# Keep only last 5 encrypted copies
ls -t "${BACKUP_DIR}"/env_*.gpg | tail -n +6 | xargs -r rm
```

The following secrets are in `/etc/securesharing/env` and must be backed up:

| Secret | Impact if Lost |
|--------|---------------|
| `SECRET_KEY_BASE` | All Phoenix sessions invalidated; LiveView tokens break |
| `JWT_SECRET` | All issued JWTs become invalid; all users forced to re-login |
| `DATABASE_URL` | Cannot connect to database |
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | Cannot access S3/Garage storage |

### 4.2 Encryption Keys and Wrapped Key Material

In SecureSharing's zero-knowledge architecture, the server stores wrapped (encrypted)
key material in PostgreSQL. These are backed up as part of the database backup:

- `users.encrypted_private_keys` -- PQC private keys encrypted by the user's Master Key
- `users.vault_encrypted_master_key` -- Master Key encrypted by vault password derivative
- `credentials.encrypted_master_key` -- Master Key encrypted by WebAuthn PRF
- `folders.owner_key_access`, `folders.wrapped_kek` -- Folder KEKs
- `files.wrapped_dek` -- Per-file DEKs wrapped by folder KEK
- `share_grants.wrapped_key`, `share_grants.kem_ciphertexts` -- Shared keys
- `recovery_shares.encrypted_share` -- Shamir recovery shares

If these rows are lost and no database backup exists, affected users permanently
lose access to their files. There is no server-side recovery path because the
server never holds plaintext keys.

### 4.3 Oban Job Queue State

Oban stores jobs in the `oban_jobs` table in PostgreSQL, so they are covered by
the database backup. After a database restore, pending and scheduled jobs will
resume automatically when the application starts.

To check job state after restore:

```bash
./bin/secure_sharing eval '
  import Ecto.Query
  repo = SecureSharing.Repo

  for state <- ["available", "scheduled", "executing", "retryable"] do
    count = repo.aggregate(
      from(j in "oban_jobs", where: j.state == ^state),
      :count
    )
    IO.puts("#{state}: #{count} jobs")
  end
'
```

## 5. Disaster Recovery

### 5.1 Full System Recovery (Step-by-Step)

**Precondition**: A fresh server with Ubuntu 22.04 and the latest backups available.

```
Step 1 -- Install dependencies
  $ apt update && apt install -y postgresql-18 nginx certbot
  $ # Install Erlang/OTP 27, Elixir 1.18 (via asdf or package manager)
  $ # Install Garage binary (https://garagehq.deuxfleurs.fr/download/)

Step 2 -- Restore secrets
  $ mkdir -p /etc/securesharing
  $ gpg --decrypt /path/to/env_LATEST.gpg > /etc/securesharing/env
  $ chmod 600 /etc/securesharing/env

Step 3 -- Restore PostgreSQL
  $ sudo -u postgres createdb securesharing_prod
  $ gunzip < /path/to/daily/securesharing_prod_LATEST.sql.gz \
    | pg_restore -U securesharing -d securesharing_prod --no-owner --no-acl

Step 4 -- Run any pending migrations
  $ /opt/securesharing/bin/secure_sharing eval "SecureSharing.Release.migrate()"

Step 5 -- Restore Garage data
  $ # Start Garage, then sync from backup
  $ rclone sync backup-remote:securesharing-backup-dr/files garage:securesharing-files

Step 6 -- Deploy application release
  $ # Copy or build the release, place in /opt/securesharing/
  $ sudo systemctl start securesharing

Step 7 -- Verify
  $ curl -f http://localhost:4000/health
  $ curl -f http://localhost:4000/health/ready
```

Estimated time: 2-4 hours depending on data volume.

### 5.2 Database-Only Recovery

When PostgreSQL data is corrupted but S3 storage is intact:

```bash
sudo systemctl stop securesharing
sudo -u postgres dropdb securesharing_prod
sudo -u postgres createdb securesharing_prod
gunzip < /var/backups/securesharing/postgres/daily/LATEST.sql.gz \
  | pg_restore -U securesharing -d securesharing_prod --no-owner --no-acl
/opt/securesharing/bin/secure_sharing eval "SecureSharing.Release.migrate()"
sudo systemctl start securesharing
```

### 5.3 Storage-Only Recovery

When Garage data is lost but PostgreSQL is intact. File metadata in PostgreSQL
references `blob_storage_key` values that must exist in S3:

```bash
# Restore from backup
rclone sync backup-remote:securesharing-backup-dr/files garage:securesharing-files

# Verify that all blob_storage_keys in the DB exist in S3
/opt/securesharing/bin/secure_sharing eval '
  import Ecto.Query
  keys = SecureSharing.Repo.all(from f in "files", select: f.blob_storage_key, where: is_nil(f.deleted_at))
  missing = Enum.filter(keys, fn key ->
    case ExAws.S3.head_object("securesharing-files", key) |> ExAws.request() do
      {:ok, _} -> false
      _ -> true
    end
  end)
  IO.puts("Missing blobs: #{length(missing)} / #{length(keys)}")
  Enum.each(Enum.take(missing, 10), &IO.puts("  - #{&1}"))
'
```

### 5.4 Partial Data Recovery (Single Table)

pg_dump custom format supports selective restore:

```bash
# List available tables in backup
pg_restore --list /path/to/backup.dump | grep "TABLE DATA"

# Restore only share_grants
pg_restore -U securesharing -d securesharing_prod \
  --data-only --table=share_grants /path/to/backup.dump
```

## 6. Backup Automation

### 6.1 Cron Jobs

Add to `/etc/cron.d/securesharing-backup`:

```cron
# PostgreSQL daily backup at 02:00 UTC
0 2 * * * securesharing /opt/securesharing/scripts/backup-db.sh >> /var/log/securesharing/backup-db.log 2>&1

# S3 sync every hour
0 * * * * securesharing /opt/securesharing/scripts/backup-s3.sh >> /var/log/securesharing/backup-s3.log 2>&1

# Secrets backup weekly (Sunday 03:00 UTC)
0 3 * * 0 securesharing /opt/securesharing/scripts/backup-secrets.sh >> /var/log/securesharing/backup-secrets.log 2>&1

# Verify DB backup daily at 04:00 UTC
0 4 * * * securesharing /opt/securesharing/scripts/verify-db-backup.sh >> /var/log/securesharing/backup-verify.log 2>&1
```

### 6.2 Monitoring Backup Health

Create `/opt/securesharing/scripts/check-backup-health.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ERRORS=0

# Check DB backup exists and is recent (< 26 hours old)
LATEST_DB=$(find /var/backups/securesharing/postgres/daily -name "*.sql.gz" -mmin -1560 | head -1)
if [ -z "$LATEST_DB" ]; then
  echo "CRITICAL: No database backup in the last 26 hours"
  ERRORS=$((ERRORS + 1))
else
  SIZE=$(du -h "$LATEST_DB" | cut -f1)
  echo "OK: Latest DB backup ${LATEST_DB} (${SIZE})"
fi

# Check S3 backup log for errors
if grep -q "ERROR\|FATAL" /var/log/securesharing/backup-s3.log 2>/dev/null; then
  echo "WARNING: Errors in S3 backup log"
  ERRORS=$((ERRORS + 1))
fi

# Check WAL archive directory is growing
WAL_COUNT=$(find /var/backups/securesharing/postgres/wal -name "*.gz" -mmin -60 | wc -l)
if [ "$WAL_COUNT" -eq 0 ]; then
  echo "WARNING: No WAL files archived in the last hour"
  ERRORS=$((ERRORS + 1))
fi

exit $ERRORS
```

### 6.3 Alert on Backup Failures

Integrate with your monitoring stack. Example with a simple webhook:

```bash
# Add to the end of each backup script:
if [ $? -ne 0 ]; then
  curl -X POST "https://hooks.slack.com/services/YOUR/WEBHOOK/URL" \
    -H 'Content-Type: application/json' \
    -d "{\"text\": \"BACKUP FAILED: $(hostname) - $(basename $0) at $(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"
fi
```

For Prometheus-based monitoring, expose backup metrics:

```bash
# Write a metrics file after each backup
cat > /var/lib/node_exporter/textfile/backup_db.prom <<EOF
securesharing_backup_db_last_success_timestamp $(date +%s)
securesharing_backup_db_size_bytes $(stat -c%s "$BACKUP_FILE")
EOF
```

## 7. Testing Recovery

### 7.1 Recovery Drill Schedule

| Drill | Frequency | Duration | Owner |
|-------|-----------|----------|-------|
| Database restore to test environment | Monthly | 1 hour | DBA / DevOps |
| Full system recovery (staging) | Quarterly | 4 hours | DevOps team |
| S3 restore verification | Monthly | 30 min | DevOps |
| Secrets restore test | Quarterly | 30 min | Security team |

### 7.2 Verification Checklist

After every recovery drill, verify:

- [ ] Application starts and `/health` returns 200
- [ ] `/health/ready` returns 200 (database connected)
- [ ] User count matches expected (compare with pre-backup count)
- [ ] A test user can log in and list their files
- [ ] File download works (blob exists in S3, decryption succeeds on client)
- [ ] Share grants are intact (shared files accessible by grantees)
- [ ] Recovery shares table has correct row counts
- [ ] Audit events table is populated
- [ ] Oban jobs resume (check for scheduled/retryable jobs)
- [ ] WAL replay reached the target timestamp (if PITR was tested)

### 7.3 DR Testing Environment

Maintain a staging environment that mirrors production infrastructure:

```bash
# Provision a DR test server (example with Hetzner CLI)
hcloud server create --name securesharing-dr-test \
  --type cx31 --image ubuntu-22.04 --location fsn1

# Run the full recovery procedure (Section 5.1) against this server
# After verification, tear down
hcloud server delete securesharing-dr-test
```

Document every drill result in a shared log:

```
Date: 2026-02-17
Drill: Monthly database restore
Backup used: securesharing_prod_20260216_020005.sql.gz
Restore time: 12 minutes
Row counts verified: users=847, files=12340, share_grants=2156
Result: PASS
Notes: None
```
