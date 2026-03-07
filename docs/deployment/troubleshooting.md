# SecureSharing Troubleshooting Guide

This guide is written for on-call engineers operating the SecureSharing platform. It covers diagnosis, resolution, and emergency procedures for the Elixir/Phoenix backend running on the Hetzner two-server architecture (compute at `10.0.0.1`, data at `10.0.0.2`).

---

## Table of Contents

1. [Quick Diagnostics](#1-quick-diagnostics)
2. [Database Issues](#2-database-issues)
3. [S3 Storage Issues](#3-s3-storage-issues)
4. [Authentication Issues](#4-authentication-issues)
5. [Crypto/NIF Issues](#5-cryptonif-issues)
6. [Background Job Issues](#6-background-job-issues)
7. [Cluster Issues](#7-cluster-issues)
8. [Performance Issues](#8-performance-issues)
9. [Secret Rotation](#9-secret-rotation)
10. [Common Error Codes](#10-common-error-codes)
11. [Emergency Procedures](#11-emergency-procedures)

---

## 1. Quick Diagnostics

Run these checks first for any production issue.

### 1.1 Health Endpoints

```bash
# Liveness check -- is the BEAM process running?
curl -s http://localhost:4000/health | jq .

# Readiness check -- database, cache, Oban, crypto all healthy?
curl -s http://localhost:4000/health/ready | jq .

# Cluster status -- are distributed nodes connected?
curl -s http://localhost:4000/health/cluster | jq .

# Full system metrics -- memory, process count, uptime, all checks
curl -s http://localhost:4000/health/detailed | jq .
```

The `/health/ready` endpoint checks four subsystems: `database`, `cache`, `oban`, and `crypto`. If any reports `"status": "error"`, the response returns HTTP 503 with the failing check's error message in the `checks` array.

### 1.2 Service Status

```bash
# Check all services on the compute server
systemctl status securesharing pii-service presidio llama-server nginx

# Check data server services (from compute)
ssh data.securesharing.internal 'systemctl status postgresql garage'
```

### 1.3 Logs

```bash
# Tail the main application log
journalctl -u securesharing -f --since "5 minutes ago"

# Tail with error filtering
journalctl -u securesharing -f --priority=err

# Search for specific request ID or user
journalctl -u securesharing --since "1 hour ago" | grep "request_id=abc123"
```

### 1.4 Remote IEx Console

Connect to a running production release node for live debugging:

```bash
# Attach a remote IEx shell to the running release
bin/secure_sharing remote

# If using systemd and the release is at /opt/securesharing:
/opt/securesharing/bin/secure_sharing remote
```

Once in the remote IEx console, run quick checks:

```elixir
# Is the application running?
Application.started_applications() |> Enum.find(fn {app, _, _} -> app == :secure_sharing end)

# What is the current node?
Node.self()

# Connected cluster nodes
Node.list()

# Quick database check
SecureSharing.Repo.query!("SELECT 1")

# Check crypto initialization
SecureSharing.Crypto.initialized?()
SecureSharing.Crypto.info()

# Check cache stats
SecureSharing.Cache.stats()

# Check Oban status
Oban.config()

# System memory summary
:erlang.memory() |> Enum.map(fn {k, v} -> {k, Float.round(v / 1_048_576, 2)} end)

# Process count vs limit
{:erlang.system_info(:process_count), :erlang.system_info(:process_limit)}

# Uptime in seconds
{uptime_ms, _} = :erlang.statistics(:wall_clock); div(uptime_ms, 1000)
```

### 1.5 Quick Health Check Script

Run the health check script from the compute server:

```bash
/opt/scripts/healthcheck.sh
```

This checks all systemd services and HTTP endpoints across both servers.

---

## 2. Database Issues

### 2.1 Connection Pool Exhaustion

**Symptoms:** API returns 503 or times out. Logs show `DBConnection.ConnectionError` or `(Postgrex.Error) connection not available`.

**Diagnose:**

```elixir
# In remote IEx: Check current pool checkout status
# Pool size is set by POOL_SIZE env var (default 10)
%{pool_size: pool_size} = SecureSharing.Repo.config() |> Keyword.get(:pool_size, 10)

# Check how many database connections exist on PostgreSQL
SecureSharing.Repo.query!("""
  SELECT state, count(*)
  FROM pg_stat_activity
  WHERE datname = 'securesharing_prod'
  GROUP BY state
""")

# Check for long-running queries
SecureSharing.Repo.query!("""
  SELECT pid, now() - pg_stat_activity.query_start AS duration, query, state
  FROM pg_stat_activity
  WHERE datname = 'securesharing_prod'
    AND state != 'idle'
  ORDER BY duration DESC
  LIMIT 10
""")
```

**Fix:**

```bash
# Increase pool size temporarily (requires restart)
# In /etc/securesharing/env or .env.prod:
POOL_SIZE=20

# For multi-core machines, also set pool count:
POOL_COUNT=2

# Restart
systemctl restart securesharing
```

If connections are legitimately exhausted, kill long-running queries from PostgreSQL:

```sql
-- On the data server
sudo -u postgres psql securesharing_prod

-- Find and kill blocking queries
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = 'securesharing_prod'
  AND state = 'active'
  AND now() - query_start > interval '5 minutes';
```

### 2.2 Migration Failures

**Symptoms:** Application fails to start after deployment. Logs show `Postgrex.Error` related to missing columns or tables.

**Diagnose:**

```bash
# Check migration status using the release eval command
bin/secure_sharing eval "SecureSharing.Release.migration_status()"
```

**Fix:**

```bash
# Run pending migrations
bin/secure_sharing eval "SecureSharing.Release.migrate()"

# If a migration is partially applied and corrupt, rollback to the version before it
bin/secure_sharing eval "SecureSharing.Release.rollback(SecureSharing.Repo, 20240215000001)"

# Then re-run migrations
bin/secure_sharing eval "SecureSharing.Release.migrate()"
```

If the migration requires manual intervention:

```bash
# Connect to PostgreSQL and check the schema_migrations table
sudo -u postgres psql securesharing_prod -c "SELECT * FROM schema_migrations ORDER BY version DESC LIMIT 10;"

# Manually remove a failed migration entry (use with extreme caution)
sudo -u postgres psql securesharing_prod -c "DELETE FROM schema_migrations WHERE version = 20240215000001;"
```

### 2.3 Deadlocks

**Symptoms:** Intermittent timeouts on write operations. PostgreSQL logs show `deadlock detected`.

**Diagnose:**

```sql
-- On the data server
sudo -u postgres psql securesharing_prod

-- Check for current locks
SELECT
  blocked_locks.pid     AS blocked_pid,
  blocked_activity.usename  AS blocked_user,
  blocking_locks.pid     AS blocking_pid,
  blocking_activity.usename AS blocking_user,
  blocked_activity.query    AS blocked_statement,
  blocking_activity.query   AS current_statement_in_blocking_process
FROM pg_catalog.pg_locks         blocked_locks
JOIN pg_catalog.pg_stat_activity blocked_activity  ON blocked_activity.pid = blocked_locks.pid
JOIN pg_catalog.pg_locks         blocking_locks
  ON blocking_locks.locktype = blocked_locks.locktype
  AND blocking_locks.database IS NOT DISTINCT FROM blocked_locks.database
  AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
  AND blocking_locks.page IS NOT DISTINCT FROM blocked_locks.page
  AND blocking_locks.tuple IS NOT DISTINCT FROM blocked_locks.tuple
  AND blocking_locks.virtualxid IS NOT DISTINCT FROM blocked_locks.virtualxid
  AND blocking_locks.transactionid IS NOT DISTINCT FROM blocked_locks.transactionid
  AND blocking_locks.classid IS NOT DISTINCT FROM blocked_locks.classid
  AND blocking_locks.objid IS NOT DISTINCT FROM blocked_locks.objid
  AND blocking_locks.objsubid IS NOT DISTINCT FROM blocked_locks.objsubid
  AND blocking_locks.pid != blocked_locks.pid
JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.granted;
```

**Fix:**

```sql
-- Terminate the blocking process if safe
SELECT pg_terminate_backend(<blocking_pid>);
```

Recurring deadlocks indicate a code-level issue (e.g., inconsistent row lock ordering). Investigate the query patterns in the application logs.

### 2.4 Slow Queries

**Symptoms:** API response times increasing. `/health/detailed` shows high uptime but slow responses.

**Diagnose:**

```sql
-- PostgreSQL slow query log is at /var/log/postgresql/
-- Queries taking >1s are logged (log_min_duration_statement = 1000)

-- Check pg_stat_statements for top queries by total time
sudo -u postgres psql securesharing_prod

-- Enable pg_stat_statements if not already
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

SELECT
  calls,
  round(total_exec_time::numeric, 2) AS total_time_ms,
  round(mean_exec_time::numeric, 2) AS mean_time_ms,
  round(max_exec_time::numeric, 2) AS max_time_ms,
  substring(query, 1, 100) AS query_snippet
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 20;
```

**Fix:**

```sql
-- Check if table statistics are stale
ANALYZE;

-- Run VACUUM ANALYZE on heavily written tables
VACUUM ANALYZE files;
VACUUM ANALYZE share_grants;
VACUUM ANALYZE audit_logs;

-- Check for missing indexes
SELECT
  schemaname, tablename, attname, n_distinct, correlation
FROM pg_stats
WHERE tablename IN ('files', 'folders', 'share_grants', 'users')
ORDER BY tablename, attname;
```

### 2.5 PostgreSQL Restart Recovery

**Symptoms:** Application loses database connectivity after PostgreSQL restart on the data server.

**Diagnose:**

```bash
# Check PostgreSQL is running on the data server
ssh data.securesharing.internal 'systemctl status postgresql'

# Verify connectivity from compute server
nc -zv 10.0.0.2 5432
```

**Fix:**

Ecto's connection pool (via DBConnection/Postgrex) will automatically reconnect. However, if connections remain broken:

```bash
# Restart the application to force new pool connections
systemctl restart securesharing

# If using release and pool is stuck, you can trigger reconnect from IEx
# (remote IEx session)
```

```elixir
# Force all pool connections to reset by restarting the Repo
Supervisor.terminate_child(SecureSharing.Supervisor, SecureSharing.Repo)
Supervisor.restart_child(SecureSharing.Supervisor, SecureSharing.Repo)
```

---

## 3. S3 Storage Issues

### 3.1 Garage Connectivity

**Symptoms:** File uploads/downloads fail. Logs show `ExAws` errors or connection refused to S3.

**Diagnose:**

```bash
# Check if Garage is running on the data server
ssh data.securesharing.internal 'systemctl status garage'

# Test S3 API connectivity from compute server
curl -s http://10.0.0.2:3900/ 2>&1
# (Expected: Garage S3 API responds, even with an error XML for missing auth)

# Check Garage admin API
curl -s -H "Authorization: Bearer YOUR_ADMIN_TOKEN" http://10.0.0.2:3903/health
```

```elixir
# In remote IEx: verify ExAws configuration
ExAws.Config.new(:s3) |> Map.take([:access_key_id, :host, :port, :scheme])

# Attempt a list objects call
ExAws.S3.list_objects("securesharing-files", max_keys: 1) |> ExAws.request()
```

**Fix:**

```bash
# If Garage is down, restart it
ssh data.securesharing.internal 'systemctl restart garage'

# Check Garage logs for errors
ssh data.securesharing.internal 'journalctl -u garage --since "10 minutes ago"'

# If disk is full, check storage
ssh data.securesharing.internal 'df -h /var/lib/garage'
```

### 3.2 Presigned URL Failures

**Symptoms:** Clients receive presigned URLs that return 403 Forbidden or SignatureDoesNotMatch when used.

**Diagnose:**

```elixir
# In remote IEx: Generate a test presigned URL and inspect it
config = ExAws.Config.new(:s3)
ExAws.S3.presigned_url(config, :get, "securesharing-files", "test-key", expires_in: 300)

# Check the S3 provider configuration
Application.get_env(:secure_sharing, SecureSharing.Storage.Providers.S3)
```

**Common causes:**

1. **Clock skew:** Presigned URLs include a timestamp. If server clocks are out of sync, signatures fail.

   ```bash
   # Check time on both servers
   date -u
   ssh data.securesharing.internal 'date -u'

   # Fix with NTP
   timedatectl set-ntp true
   ```

2. **Scheme mismatch:** Garage expects `http://` in dev but the URL was generated with `https://`.

   ```elixir
   # Check ExAws S3 config in remote IEx
   Application.get_env(:ex_aws, :s3)
   # Should show: [scheme: "http://", host: "10.0.0.2", port: 3900]
   ```

3. **Wrong region:** Garage uses `"garage"` as region. Mismatch causes signature errors.

   ```elixir
   Application.get_env(:ex_aws, :region)
   # Should match what Garage expects
   ```

### 3.3 Upload Timeouts

**Symptoms:** Large file uploads time out. Clients get gateway timeout or connection reset.

**Fix:**

```nginx
# Increase Nginx client body size and timeouts
# /etc/nginx/sites-available/securesharing

client_max_body_size 500M;

location / {
    proxy_pass http://backend;
    proxy_read_timeout 300s;
    proxy_send_timeout 300s;
    proxy_connect_timeout 60s;
    # ...
}
```

```bash
nginx -t && systemctl reload nginx
```

For direct-to-S3 uploads via presigned URLs, the timeout is on the client side. Ensure the presigned URL expiry is long enough (default is 3600 seconds / 1 hour, configured in `SecureSharing.Storage.Providers.S3`).

### 3.4 Bucket Permission Errors

**Symptoms:** S3 operations return 403 Access Denied.

**Diagnose:**

```bash
# On the data server: verify Garage key permissions
garage -c /etc/garage/garage.toml key info securesharing-key
garage -c /etc/garage/garage.toml bucket info securesharing-files
```

**Fix:**

```bash
# Re-grant permissions on the data server
garage -c /etc/garage/garage.toml bucket allow securesharing-files \
  --read --write --owner --key securesharing-key
```

---

## 4. Authentication Issues

### 4.1 JWT Verification Failures

**Symptoms:** All API requests return 401 Unauthorized. Logs show `{:error, :invalid_token}` or `{:error, [message: "Invalid token"]}`.

**Diagnose:**

```elixir
# In remote IEx: Check JWT configuration
Application.get_env(:secure_sharing, :jwt_secret) |> is_binary()
# Should return true

# Manually verify a token (paste a failing token)
token = "eyJ..."
Joken.peek_header(token)
Joken.peek_claims(token)

# Create the signer and verify
signer = Joken.Signer.create("HS256", Application.get_env(:secure_sharing, :jwt_secret))
Joken.verify(token, signer)
```

**Common causes:**

1. **JWT_SECRET changed between nodes or restarts:** All nodes must share the same `JWT_SECRET`. Tokens signed with the old secret will fail verification.
2. **Token issued by a different environment:** Dev tokens will not work in prod.
3. **Clock drift:** Token `exp` is checked against `DateTime.utc_now()`. Ensure NTP is synchronized.

### 4.2 Token Expiry Issues

**Symptoms:** Users are logged out too quickly or tokens expire unexpectedly.

**Token lifetimes (hardcoded in `SecureSharingWeb.Auth.Token`):**
- Access tokens: 15 minutes
- Refresh tokens: 7 days

```elixir
# In remote IEx: Decode a token to check its claims
token = "eyJ..."
{:ok, claims} = Joken.peek_claims(token)
# Check exp (Unix timestamp)
exp = claims["exp"]
DateTime.from_unix!(exp)
# Compare with current time
DateTime.utc_now()
```

**Fix:**

If tokens are expiring earlier than expected, check for clock skew:

```bash
# Verify system clock
timedatectl status
# Ensure NTP is active
timedatectl set-ntp true
```

### 4.3 Refresh Token Rotation

**Symptoms:** Refresh token requests fail with 401. User must re-login.

The refresh endpoint is `POST /api/auth/refresh`. It verifies the refresh token, checks the blocklist, and issues a new access/refresh token pair.

**Diagnose:**

```elixir
# In remote IEx: Check if the refresh token is blocklisted
alias SecureSharingWeb.Auth.TokenBlocklist

# Get the JTI from the token
{:ok, claims} = Joken.peek_claims("eyJ...")
jti = claims["jti"]

# Check if it's been revoked
TokenBlocklist.revoked?(jti)

# Check total blocklist size
TokenBlocklist.count()
```

**Common causes:**

1. **Token already used and rotated:** If the client retries a refresh with an already-rotated token, it may be blocklisted.
2. **Logout revoked all tokens:** `POST /api/auth/logout` revokes the current tokens.

### 4.4 Token Blocklist Issues

**Symptoms:** Logged-out users can still access APIs, or legitimate users get 401 after another session logs out.

The `TokenBlocklist` is an ETS-based in-memory store. It does NOT persist across restarts and is NOT shared across cluster nodes.

**Diagnose:**

```elixir
# In remote IEx:
alias SecureSharingWeb.Auth.TokenBlocklist

# Check blocklist size
TokenBlocklist.count()

# Check if a specific JTI is blocked
TokenBlocklist.revoked?("some-jti-uuid")

# Manually trigger cleanup of expired entries
TokenBlocklist.cleanup()
```

**Known limitation:** Because the blocklist is per-node ETS, a token revoked on node A will not be revoked on node B in a clustered deployment. For clustered deployments, consider adding Redis-backed persistence or using PubSub to broadcast revocations.

### 4.5 Argon2id / bcrypt Errors

**Symptoms:** Login fails with 500 errors. Logs show errors from `:argon2_elixir` or `:bcrypt_elixir`.

**Diagnose:**

```elixir
# In remote IEx: Test password hashing
Argon2.hash_pwd_salt("test_password")
Bcrypt.hash_pwd_salt("test_password")
```

**Common causes:**

1. **Missing system library:** Argon2 requires `libsodium` or a C compiler. Check that the NIF was compiled correctly.

   ```bash
   ls -la _build/prod/lib/argon2_elixir/priv/
   # Should contain argon2_nif.so
   ```

2. **NIF crash:** If the NIF `.so` file is corrupted or built for a different architecture:

   ```bash
   # Rebuild NIFs
   MIX_ENV=prod mix deps.compile argon2_elixir --force
   MIX_ENV=prod mix deps.compile bcrypt_elixir --force
   ```

---

## 5. Crypto/NIF Issues

The application uses four Rust NIFs for post-quantum cryptography: `KazKem`, `KazSign`, `MlKem`, `MlDsa`. These are loaded at application startup by `SecureSharing.Crypto.Initializer`.

### 5.1 Rust NIF Loading Failures

**Symptoms:** Application crashes on startup. Logs show `FATAL: Failed to initialize crypto providers` or `(ErlangError) Erlang error: :load_failed`.

**Diagnose:**

```bash
# Check that NIF shared libraries exist
ls -la _build/prod/lib/kaz_kem/priv/
ls -la _build/prod/lib/kaz_sign/priv/
ls -la _build/prod/lib/ml_kem/priv/
ls -la _build/prod/lib/ml_dsa/priv/
# Each should contain a .so file

# Check library dependencies
ldd _build/prod/lib/ml_kem/priv/libml_kem.so
# Look for "not found" entries
```

**Fix:**

```bash
# Install missing C/Rust build dependencies
apt install -y build-base libgcc musl-dev openssl-dev

# Rebuild NIFs from source
cd native/kaz_kem && make clean && make
cd ../kaz_sign && make clean && make
cd ../ml_kem && make clean && make
cd ../ml_dsa && make clean && make

# Recompile the Elixir wrappers
MIX_ENV=prod mix compile --force
```

For releases, ensure the `.so` files are included:

```bash
# Verify they're in the release
ls _build/prod/rel/secure_sharing/lib/kaz_kem-*/priv/
```

### 5.2 ML-KEM / ML-DSA Errors

**Symptoms:** Key generation, encapsulation, or signature operations fail. Logs show `{:error, :nif_error}` or `{:error, :not_initialized}`.

**Diagnose:**

```elixir
# In remote IEx:
# Check initialization status for each algorithm
SecureSharing.Crypto.info(:nist)
# => %{kem: %{initialized: true/false, ...}, sign: %{initialized: true/false, ...}}

SecureSharing.Crypto.info(:kaz)
SecureSharing.Crypto.info(:hybrid)

# Test a KEM operation
SecureSharing.Crypto.kem_keypair(:nist)
# Should return {:ok, %{public_key: <<...>>, private_key: <<...>>}}

# Test a sign operation
SecureSharing.Crypto.sign_keypair(:nist)
```

**Fix:**

```elixir
# Re-initialize crypto providers from remote IEx
SecureSharing.Crypto.init()
# Or for a specific algorithm:
SecureSharing.Crypto.init(:nist)
SecureSharing.Crypto.init(:kaz)
```

If re-initialization fails, the NIF binary is likely corrupted. Rebuild and restart.

### 5.3 KAZ Provider Issues

**Symptoms:** KAZ-KEM or KAZ-SIGN operations fail with `:invalid_level` or `:not_initialized`.

KAZ providers accept security levels `128`, `192`, or `256`. The default is `128`.

**Diagnose:**

```elixir
# In remote IEx:
KazKem.initialized?()
KazKem.get_level()
KazKem.get_sizes()

KazSign.initialized?()
```

**Fix:**

```elixir
# Re-initialize with the correct level
KazKem.init(128)
KazSign.init(128)
```

### 5.4 NIF Crash Recovery

If a NIF crashes (segfault), it will take down the BEAM process. The `SecureSharing.Crypto.Initializer` is configured as `restart: :temporary` in the supervision tree, meaning a crash during initialization will propagate upward and crash the application (this is intentional -- the app should not run without crypto).

**Recovery:**

```bash
# The systemd service has Restart=on-failure with RestartSec=5
# Check if the service auto-recovered
systemctl status securesharing

# If stuck in a crash loop, check the NIF error
journalctl -u securesharing --since "5 minutes ago" | grep -i "nif\|crypto\|FATAL"

# Potential causes:
# 1. Corrupted .so files -> rebuild NIFs
# 2. Memory corruption -> check system memory, restart server
# 3. Architecture mismatch -> rebuild on the target machine
```

---

## 6. Background Job Issues

Oban is configured with these queues (sizes configurable via env vars):

| Queue | Default Size | Purpose |
|-------|-------------|---------|
| `default` | 10 | General background work |
| `mailers` | 5 | Email delivery (Swoosh) |
| `cleanup` | 3 | Expired data cleanup |
| `storage` | 5 | S3 blob operations |
| `maintenance` | 2 | Scheduled tasks |

### 6.1 Oban Queue Backlog

**Symptoms:** Emails not sending, invitations not expiring, cleanup not running.

**Diagnose:**

```elixir
# In remote IEx:
# Check Oban is running
Oban.config()

# Check queue states
import Ecto.Query

# Count jobs by state
SecureSharing.Repo.all(
  from j in Oban.Job,
    group_by: [j.state, j.queue],
    select: {j.queue, j.state, count(j.id)},
    order_by: [desc: count(j.id)]
)

# Check for stuck executing jobs (executing longer than 5 minutes)
SecureSharing.Repo.all(
  from j in Oban.Job,
    where: j.state == "executing" and j.attempted_at < ago(5, "minute"),
    select: %{id: j.id, queue: j.queue, worker: j.worker, attempted_at: j.attempted_at}
)
```

**Fix:**

```elixir
# Retry all discarded jobs in the mailers queue
Oban.retry_all_jobs(Oban.Job |> Ecto.Query.where(queue: "mailers", state: "discarded"))

# Pause and resume a queue
Oban.pause_queue(queue: :mailers)
Oban.resume_queue(queue: :mailers)

# Scale a queue temporarily (e.g., clear backlog)
Oban.scale_queue(queue: :default, limit: 25)

# After backlog clears, scale back
Oban.scale_queue(queue: :default, limit: 10)
```

### 6.2 Stuck Jobs

**Symptoms:** Jobs stuck in `executing` state after a node crash or deployment.

Oban uses a rescue mechanism for orphaned jobs, but it can take time.

```elixir
# In remote IEx: Force rescue orphaned jobs
# Jobs from nodes that are no longer running will be rescued
Oban.cancel_all_jobs(
  Oban.Job
  |> Ecto.Query.where(state: "executing")
  |> Ecto.Query.where([j], j.attempted_at < ago(10, "minute"))
)
```

### 6.3 Email Delivery Failures

**Symptoms:** Users not receiving emails. Oban jobs in `mailers` queue are `retryable` or `discarded`.

**Diagnose:**

```elixir
# In remote IEx: Check recent email job failures
import Ecto.Query

SecureSharing.Repo.all(
  from j in Oban.Job,
    where: j.queue == "mailers" and j.state in ["retryable", "discarded"],
    order_by: [desc: j.inserted_at],
    limit: 10,
    select: %{id: j.id, args: j.args, errors: j.errors, state: j.state}
)
```

The `EmailWorker` has `max_attempts: 5` with exponential backoff.

**Common causes:**

1. **SMTP configuration error:** Check Swoosh mailer config.
2. **Rate limiting by email provider:** Check the error messages in the job's `errors` field.
3. **DNS resolution failure:** If the mail server hostname cannot be resolved.

**Fix:**

```elixir
# Retry a specific failed job
Oban.retry_job(job_id)

# Check Swoosh configuration
Application.get_env(:secure_sharing, SecureSharing.Mailer)
```

### 6.4 Job Retry Behavior

Workers have different retry configurations:

| Worker | Queue | Max Attempts | Notes |
|--------|-------|-------------|-------|
| `EmailWorker` | `mailers` | 5 | Exponential backoff |
| `ExpireInvitationsWorker` | `default` | Cron (hourly) | `0 * * * *` |
| `AuditWorker` | `default` | Default (20) | |
| `NotificationWorker` | `default` | Default (20) | |
| `BlobCleanupWorker` | `storage` | Default (20) | |

Oban prunes completed/discarded jobs older than 7 days automatically (configured via `Oban.Plugins.Pruner`).

---

## 7. Cluster Issues

SecureSharing supports multiple clustering strategies via `libcluster`: DNS, Kubernetes, Gossip, and EPMD.

### 7.1 Node Discovery Failures

**Symptoms:** `/health/cluster` shows `"connected_nodes": []` when nodes should be connected.

**Diagnose:**

```elixir
# In remote IEx:
SecureSharing.Cluster.info()
# => %{node: :"secure_sharing@host", nodes: [], node_count: 1, strategy: "dns", connected: false}

# Check what clustering strategy is configured
System.get_env("CLUSTER_STRATEGY")
System.get_env("DNS_CLUSTER_QUERY")
```

**Fix by strategy:**

**DNS strategy:**

```bash
# Verify DNS resolution
dig secure-sharing.internal
nslookup secure-sharing.internal

# Check DNS_CLUSTER_QUERY is set correctly
echo $DNS_CLUSTER_QUERY
```

**Gossip strategy:**

```bash
# Ensure GOSSIP_SECRET matches on all nodes
# Ensure UDP port 45892 (default) is open between nodes
ufw allow from 10.0.0.0/24 to any port 45892 proto udp
```

**EPMD strategy:**

```bash
# Verify EPMD is running
epmd -names
# Should list node names

# Verify nodes can reach each other
# From node A:
ping node_b_hostname

# Check that CLUSTER_NODES includes all expected nodes
echo $CLUSTER_NODES
# e.g., "secure_sharing@host1,secure_sharing@host2"
```

**Common checklist for all strategies:**

```bash
# Ensure Erlang distribution ports are open (4369 for EPMD + dynamic range)
ufw allow from 10.0.0.0/24 to any port 4369

# Ensure the Erlang cookie matches on all nodes
cat /opt/securesharing/releases/COOKIE
# Must be identical on all nodes
```

### 7.2 Split-Brain Scenarios

**Symptoms:** Two groups of nodes operating independently. Users see inconsistent data depending on which node handles their request.

**Diagnose:**

```elixir
# On each node, check what they see:
Node.list()
# If node A sees [B] but not [C], and C sees [B] but not [A], you have a split
```

**Fix:**

```bash
# Restart nodes one by one, allowing them to re-join
systemctl restart securesharing  # On node 1
# Wait 30 seconds for cluster reformation
sleep 30
systemctl restart securesharing  # On node 2 (if needed)
```

For the Hetzner two-server architecture (single compute node), split-brain is not applicable. It only matters if you scale to multiple compute nodes.

### 7.3 DNS Cluster Configuration

For the standard Hetzner deployment, clustering is typically set to `"none"` (single compute node). If scaling to multiple nodes:

```bash
# Environment variables for DNS-based clustering
CLUSTER_STRATEGY=dns
DNS_CLUSTER_QUERY=secure-sharing.internal
DNS_POLL_INTERVAL=5000
```

Ensure that the DNS query resolves to all node IPs and that the node basename matches:

```bash
KUBERNETES_NODE_BASENAME=secure_sharing
```

---

## 8. Performance Issues

### 8.1 Memory Leaks (Binary References)

**Symptoms:** Memory usage grows continuously. `/health/detailed` shows increasing `memory_mb.binary`.

The BEAM VM uses reference-counted binaries for data larger than 64 bytes. If processes hold references to large binaries (e.g., file content, encrypted blobs), memory will not be freed until the reference is garbage collected.

**Diagnose:**

```elixir
# In remote IEx:
# Check binary memory
memory = :erlang.memory()
binary_mb = div(memory[:binary], 1_048_576)
total_mb = div(memory[:total], 1_048_576)
IO.puts("Binary: #{binary_mb} MB / Total: #{total_mb} MB")

# Find top memory-consuming processes
Process.list()
|> Enum.map(fn pid ->
  info = Process.info(pid, [:memory, :binary, :current_function, :registered_name])
  {pid, info}
end)
|> Enum.sort_by(fn {_, info} -> info[:memory] end, :desc)
|> Enum.take(20)
|> Enum.each(fn {pid, info} ->
  name = info[:registered_name] || info[:current_function]
  mem_mb = Float.round(info[:memory] / 1_048_576, 2)
  IO.puts("#{inspect(pid)} #{inspect(name)}: #{mem_mb} MB")
end)
```

**Fix:**

```elixir
# Force garbage collection on the top memory-consuming processes
pid = pid(0, 123, 0)  # Replace with actual PID
:erlang.garbage_collect(pid)

# Force full GC on all processes (use sparingly -- causes latency spike)
Process.list() |> Enum.each(&:erlang.garbage_collect/1)
```

If binary memory leak is chronic, ensure file content is not being held in process state. Check that download/upload handlers stream data rather than buffering it entirely.

### 8.2 Process Accumulation

**Symptoms:** Process count grows over time. Eventually hits the process limit (default 262,144).

**Diagnose:**

```elixir
# In remote IEx:
count = :erlang.system_info(:process_count)
limit = :erlang.system_info(:process_limit)
IO.puts("Processes: #{count} / #{limit} (#{Float.round(count / limit * 100, 1)}%)")

# Find processes grouped by initial call
Process.list()
|> Enum.map(fn pid ->
  info = Process.info(pid, [:initial_call])
  info[:initial_call]
end)
|> Enum.frequencies()
|> Enum.sort_by(fn {_, count} -> count end, :desc)
|> Enum.take(20)
```

**Common causes:**

1. **WebSocket connections not closing:** Check Phoenix.Channel / Presence process counts.
2. **Spawned tasks not completing:** Look for `Task.Supervisor` processes.
3. **GenServer leaks:** A GenServer spawning children without proper supervision.

### 8.3 ETS Table Growth

**Symptoms:** ETS memory grows continuously (visible in `/health/detailed` under `memory_mb.ets`).

**Diagnose:**

```elixir
# In remote IEx:
# List all ETS tables sorted by memory
:ets.all()
|> Enum.map(fn table ->
  info = :ets.info(table)
  {table, info[:size], info[:memory] * :erlang.system_info(:wordsize)}
end)
|> Enum.sort_by(fn {_, _, mem} -> mem end, :desc)
|> Enum.take(10)
|> Enum.each(fn {table, size, mem} ->
  IO.puts("#{table}: #{size} entries, #{Float.round(mem / 1_048_576, 2)} MB")
end)

# Check the application cache specifically
SecureSharing.Cache.stats()
# Returns: %{size: N, max_entries: 10000, utilization_percent: X, memory_mb: Y}

# Check token blocklist size
SecureSharingWeb.Auth.TokenBlocklist.count()
```

**Fix:**

```elixir
# If the cache is too large, clear it (safe -- it will repopulate on demand)
SecureSharing.Cache.clear()

# If the token blocklist is too large, trigger cleanup
SecureSharingWeb.Auth.TokenBlocklist.cleanup()
```

The cache automatically enforces a max of 10,000 entries (configurable) and evicts the 100 oldest entries when the limit is reached. The token blocklist automatically cleans up expired entries every 15 minutes.

### 8.4 Slow API Responses

**Symptoms:** Specific API endpoints are slow. Overall system metrics look healthy.

**Diagnose:**

```bash
# Check which endpoints are slow with Nginx access logs
# Look for response times > 1 second
awk '$NF > 1.0 {print}' /var/log/nginx/access.log | tail -20

# Check for rate limiting issues
journalctl -u securesharing --since "5 minutes ago" | grep "rate_limit"
```

```elixir
# In remote IEx: Check Ecto query times
# Enable Ecto debug logging temporarily
Logger.configure(level: :debug)
# Make a test request, check output, then restore
Logger.configure(level: :info)
```

**Common causes:**

1. **N+1 queries:** Missing Ecto preloads causing extra database round trips.
2. **Missing indexes:** `EXPLAIN ANALYZE` slow queries in PostgreSQL.
3. **Cache misses:** Large cache eviction causing cold-start behavior.
4. **NIF operations:** PQC operations (especially hybrid mode with both KAZ and NIST) are CPU-intensive.

---

## 9. Secret Rotation

### 9.1 JWT Secret Rotation

The JWT secret (`JWT_SECRET` env var) is used by `Joken.Signer.create("HS256", secret)` to sign and verify all access and refresh tokens.

**Procedure (zero-downtime):**

There is no built-in dual-secret support. Rotation requires a brief window where existing tokens become invalid.

1. **Prepare:** Notify users of a brief re-authentication requirement.

2. **Generate new secret:**

   ```bash
   openssl rand -base64 32
   ```

3. **Update the secret on all nodes simultaneously:**

   ```bash
   # Update the environment file
   vim /etc/securesharing/env
   # Change JWT_SECRET=<new_value>
   ```

4. **Rolling restart:**

   ```bash
   # If multi-node, restart one at a time
   systemctl restart securesharing
   ```

5. **Verification:**

   ```bash
   # Confirm the new secret is loaded
   bin/secure_sharing remote
   ```

   ```elixir
   # In IEx, verify tokens work with the new secret
   alias SecureSharingWeb.Auth.Token
   {:ok, token} = Token.generate_access_token(%{id: "test", tenant_id: "test", role: :member})
   Token.verify_access_token(token)
   ```

**Impact:** All existing access tokens (15min) and refresh tokens (7 days) become invalid. Users must re-login.

### 9.2 Database Credential Rotation

1. **Create new credentials on PostgreSQL (data server):**

   ```sql
   -- On data server
   sudo -u postgres psql

   -- Create new role with same privileges
   CREATE USER securesharing_new WITH PASSWORD 'new_secure_password';
   GRANT ALL PRIVILEGES ON DATABASE securesharing_prod TO securesharing_new;

   -- Grant schema access
   \c securesharing_prod
   GRANT ALL ON ALL TABLES IN SCHEMA public TO securesharing_new;
   GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO securesharing_new;
   ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO securesharing_new;
   ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO securesharing_new;
   ```

2. **Update `DATABASE_URL` on the compute server:**

   ```bash
   # In /etc/securesharing/env
   DATABASE_URL=ecto://securesharing_new:new_secure_password@10.0.0.2:5432/securesharing_prod
   ```

3. **Restart the application:**

   ```bash
   systemctl restart securesharing
   ```

4. **Verify connectivity:**

   ```bash
   curl -s http://localhost:4000/health/ready | jq '.checks[] | select(.name == "database")'
   ```

5. **Remove old credentials:**

   ```sql
   -- After confirming new credentials work
   sudo -u postgres psql
   REVOKE ALL ON DATABASE securesharing_prod FROM securesharing;
   DROP USER securesharing;
   -- Optionally rename
   ALTER USER securesharing_new RENAME TO securesharing;
   ```

### 9.3 S3 Key Rotation

1. **Create a new Garage access key (data server):**

   ```bash
   garage -c /etc/garage/garage.toml key create securesharing-key-new
   # Note the new access key and secret

   # Grant bucket access to the new key
   garage -c /etc/garage/garage.toml bucket allow securesharing-files \
     --read --write --owner --key securesharing-key-new
   ```

2. **Update environment variables on compute server:**

   ```bash
   # In /etc/securesharing/env
   AWS_ACCESS_KEY_ID=<new_access_key>
   AWS_SECRET_ACCESS_KEY=<new_secret_key>
   ```

3. **Restart the application:**

   ```bash
   systemctl restart securesharing
   ```

4. **Verify S3 connectivity:**

   ```elixir
   # In remote IEx:
   ExAws.S3.list_objects("securesharing-files", max_keys: 1) |> ExAws.request()
   ```

5. **Revoke old key (data server):**

   ```bash
   garage -c /etc/garage/garage.toml key delete securesharing-key
   ```

### 9.4 SECRET_KEY_BASE Rotation

The `SECRET_KEY_BASE` is used by Phoenix to sign cookies and sessions (admin portal). Rotation invalidates all browser sessions.

```bash
# Generate new secret
mix phx.gen.secret
# Or: openssl rand -base64 64

# Update in environment file and restart
vim /etc/securesharing/env
systemctl restart securesharing
```

---

## 10. Common Error Codes

### HTTP Error Code Reference

| HTTP Code | API Error | Cause | Fix |
|-----------|-----------|-------|-----|
| 400 | `invalid_params` | Malformed request body or missing required fields | Check request payload against API spec |
| 401 | `invalid_token` | JWT signature verification failed | Re-authenticate; check JWT_SECRET consistency |
| 401 | `token_expired` | Access token past 15-minute TTL | Use refresh token at `POST /api/auth/refresh` |
| 401 | `token_revoked` | Token was explicitly revoked (logout) | Re-authenticate |
| 401 | `invalid_token_type` | Refresh token used where access token expected (or vice versa) | Use correct token type |
| 403 | `forbidden` | User lacks required permission level | Check share_grant permission (:read/:write/:admin/:owner) |
| 403 | `not_tenant_member` | User is not a member of the target tenant | Switch tenant or request invitation |
| 404 | `not_found` | Resource does not exist or user has no access | Verify resource ID; check sharing permissions |
| 409 | `conflict` | Duplicate resource (e.g., duplicate email, duplicate share) | Check for existing resource before creating |
| 413 | `payload_too_large` | Request body exceeds Nginx `client_max_body_size` | Increase Nginx limit or use presigned upload |
| 422 | `unprocessable_entity` | Validation errors (e.g., invalid email format) | Check `errors` field in response body |
| 429 | `rate_limited` | Too many requests (auth: 5/min, API: 100/min) | Wait and retry; check if legitimate usage |
| 500 | `internal_server_error` | Unhandled exception in controller/context | Check application logs for stack trace |
| 502 | `bad_gateway` | Nginx cannot reach Phoenix backend | Check if securesharing service is running |
| 503 | `service_unavailable` | Readiness check failing; dependency down | Run `/health/ready` to identify failing check |
| 504 | `gateway_timeout` | Phoenix did not respond within Nginx timeout | Check for slow queries or blocking operations |

### Rate Limiting Details

Rate limits are enforced by `SecureSharingWeb.Plugs.RateLimit` using Hammer:

| Endpoint Group | Limit | Window | Backend |
|---------------|-------|--------|---------|
| Auth endpoints (`/api/auth/*`) | 5 requests | 60 seconds | ETS (single node) or Redis (clustered) |
| API endpoints (`/api/*`) | 100 requests | 60 seconds | ETS (single node) or Redis (clustered) |

When `REDIS_URL` is configured, rate limiting state is shared across nodes via Redis (Hammer Redis backend). Without Redis, each node maintains its own rate limit counters.

---

## 11. Emergency Procedures

### 11.1 Rolling Restart

For a single-node Hetzner deployment:

```bash
# Graceful restart (systemd sends SIGTERM, waits for connections to drain)
systemctl restart securesharing

# Monitor the restart
journalctl -u securesharing -f
```

For multi-node deployments:

```bash
# Restart nodes one at a time with 30-second spacing
for node in node1 node2 node3; do
  echo "Restarting $node..."
  ssh $node 'systemctl restart securesharing'
  echo "Waiting 30s for $node to rejoin cluster..."
  sleep 30
  # Verify node is healthy
  ssh $node 'curl -sf http://localhost:4000/health/ready'
  echo ""
done
```

### 11.2 Emergency Maintenance Mode

To immediately stop serving traffic while keeping the application running for debugging:

**Option A: Nginx-level block**

```bash
# Create a maintenance page
cat > /var/www/maintenance.html << 'HTML'
<!DOCTYPE html>
<html><head><title>Maintenance</title></head>
<body><h1>SecureSharing is under maintenance</h1>
<p>We are performing scheduled maintenance. Please try again shortly.</p>
</body></html>
HTML

# Switch Nginx to maintenance mode
cat > /etc/nginx/sites-available/maintenance << 'NGINX'
server {
    listen 80;
    listen 443 ssl;
    server_name yourdomain.com;

    ssl_certificate /etc/letsencrypt/live/yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/yourdomain.com/privkey.pem;

    # Allow health checks through (for monitoring)
    location /health {
        proxy_pass http://127.0.0.1:4000;
    }

    # Block everything else
    location / {
        return 503;
        default_type text/html;
        root /var/www;
        try_files /maintenance.html =503;
    }
}
NGINX

# Enable maintenance mode
ln -sf /etc/nginx/sites-available/maintenance /etc/nginx/sites-enabled/securesharing
nginx -t && systemctl reload nginx
```

**Revert from maintenance mode:**

```bash
ln -sf /etc/nginx/sites-available/securesharing /etc/nginx/sites-enabled/securesharing
nginx -t && systemctl reload nginx
```

**Option B: Application-level (pause Oban and return 503)**

```elixir
# In remote IEx: Pause all background processing
Oban.pause_all_queues()

# Note: This does not stop HTTP traffic; use Nginx for that
```

### 11.3 Database Failover

The Hetzner two-server architecture uses a single PostgreSQL instance (no built-in failover). In case of data server failure:

**If the data server is unreachable:**

1. **Check connectivity:**

   ```bash
   ping 10.0.0.2
   ssh data.securesharing.internal 'systemctl status postgresql'
   ```

2. **If hardware failure, restore from backup:**

   ```bash
   # On a new or recovered data server
   # Restore the latest backup
   gunzip < /var/backups/postgresql/securesharing_YYYYMMDD_HHMMSS.sql.gz | \
     sudo -u postgres psql securesharing_prod
   ```

3. **If PostgreSQL crashed but server is up:**

   ```bash
   ssh data.securesharing.internal

   # Check PostgreSQL logs
   tail -100 /var/log/postgresql/postgresql-18-main.log

   # Restart PostgreSQL
   systemctl restart postgresql

   # Check for data corruption
   sudo -u postgres pg_isready

   # If corruption, run recovery
   sudo -u postgres pg_resetwal /var/lib/postgresql/18/main  # LAST RESORT
   ```

4. **Once database is back, restart the application:**

   ```bash
   systemctl restart securesharing
   curl -s http://localhost:4000/health/ready | jq .
   ```

### 11.4 Emergency S3 Recovery

If Garage data is lost or corrupted:

```bash
# On the data server
ssh data.securesharing.internal

# Restore from the most recent Garage backup
systemctl stop garage
tar -xzf /var/backups/garage/garage_YYYYMMDD.tar.gz -C /
systemctl start garage

# Verify Garage is healthy
garage -c /etc/garage/garage.toml status
```

### 11.5 Emergency Log Level Change

To increase logging verbosity without restarting:

```elixir
# In remote IEx:
# Set to debug for detailed logs (restore to :info after debugging)
Logger.configure(level: :debug)

# After debugging, restore
Logger.configure(level: :info)
```

### 11.6 Kill Switch for Background Processing

If a runaway background job is causing issues:

```elixir
# In remote IEx:
# Pause all Oban queues immediately
Oban.pause_all_queues()

# Cancel specific problematic jobs
Oban.cancel_all_jobs(
  Oban.Job |> Ecto.Query.where(worker: "SecureSharing.Workers.EmailWorker", state: "available")
)

# Resume after the issue is resolved
Oban.resume_all_queues()
```

### 11.7 Emergency Cache Clear

If stale cache data is causing incorrect behavior:

```elixir
# In remote IEx:
# Clear all cached data (will cause a temporary performance dip as cache repopulates)
SecureSharing.Cache.clear()

# Or clear specific entries
SecureSharing.Cache.invalidate_user("user-uuid")
SecureSharing.Cache.invalidate_tenant("tenant-uuid", "tenant-slug")
```

---

## Appendix: Log Locations

| Service | Log Location |
|---------|--------------|
| SecureSharing Backend | `journalctl -u securesharing` |
| PII Service | `journalctl -u pii-service` |
| PostgreSQL | `/var/log/postgresql/` on data server |
| Garage S3 | `journalctl -u garage` on data server |
| Nginx | `/var/log/nginx/access.log`, `/var/log/nginx/error.log` |
| Presidio | `journalctl -u presidio` |
| LLM Server | `journalctl -u llama-server` |

## Appendix: Useful IEx One-Liners

```elixir
# Full system memory breakdown (MB)
:erlang.memory() |> Enum.map(fn {k, v} -> {k, Float.round(v / 1_048_576, 2)} end) |> Enum.into(%{})

# Count of each Oban job state
import Ecto.Query
SecureSharing.Repo.all(from j in Oban.Job, group_by: j.state, select: {j.state, count(j.id)})

# List connected cluster nodes
Node.list()

# Check all crypto provider status at once
for algo <- [:kaz, :nist, :hybrid], do: {algo, SecureSharing.Crypto.info(algo)}

# Find the top 5 largest ETS tables
:ets.all() |> Enum.map(fn t -> {t, :ets.info(t, :memory) * :erlang.system_info(:wordsize)} end) |> Enum.sort_by(&elem(&1, 1), :desc) |> Enum.take(5)

# Check database pool utilization
SecureSharing.Repo.query!("SELECT state, count(*) FROM pg_stat_activity WHERE datname = current_database() GROUP BY state")

# Token blocklist size
SecureSharingWeb.Auth.TokenBlocklist.count()
```
