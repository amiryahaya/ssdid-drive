# Monitoring and Observability Guide

This document covers monitoring, metrics, logging, tracing, and alerting for the SecureSharing platform. It is written against the existing codebase at `services/securesharing/` and references actual modules, configurations, and endpoints.

---

## Table of Contents

1. [Built-in Health Check Endpoints](#1-built-in-health-check-endpoints)
2. [Telemetry Metrics Reference](#2-telemetry-metrics-reference)
3. [Prometheus Integration](#3-prometheus-integration)
4. [Grafana Dashboard Setup](#4-grafana-dashboard-setup)
5. [Log Aggregation](#5-log-aggregation)
6. [Alerting Rules](#6-alerting-rules)
7. [OpenTelemetry Distributed Tracing](#7-opentelemetry-distributed-tracing)
8. [Application-Level Metrics](#8-application-level-metrics)
9. [Kubernetes Probe Configuration](#9-kubernetes-probe-configuration)
10. [Recommended Monitoring Stack Options](#10-recommended-monitoring-stack-options)

---

## 1. Built-in Health Check Endpoints

The application exposes four health endpoints defined in `SecureSharingWeb.HealthController` (`lib/secure_sharing_web/controllers/health_controller.ex`). These are routed without authentication or rate limiting so that load balancers and orchestrators can probe them freely.

Router registration (from `lib/secure_sharing_web/router.ex`):

```elixir
scope "/health", SecureSharingWeb do
  pipe_through [:api]

  get "/", HealthController, :index
  get "/ready", HealthController, :ready
  get "/cluster", HealthController, :cluster
  get "/detailed", HealthController, :detailed
end
```

### GET /health -- Liveness

Returns `200 OK` if the BEAM is running and the Phoenix endpoint is accepting requests. This is the probe that load balancers and Kubernetes liveness checks should hit.

**Response example:**

```json
{
  "status": "ok",
  "timestamp": "2026-02-17T08:30:00.000000Z",
  "version": "0.1.0",
  "node": "secure_sharing@10.0.1.5"
}
```

**Failure mode:** If the BEAM process has crashed or the HTTP server is not accepting connections, no response is returned (connection refused). The probe treats this as a failure.

### GET /health/ready -- Readiness

Verifies that the application and all its critical dependencies are ready to serve user traffic. Returns `200 OK` when all checks pass; returns `503 Service Unavailable` when any check fails.

**Checks performed:**

| Check | What it verifies |
|-------|-----------------|
| `database` | Executes `SELECT 1` against PostgreSQL via `SecureSharing.Repo` |
| `cache` | Confirms the `SecureSharing.Cache` GenServer is alive and the ETS table is accessible |
| `oban` | Confirms `Oban.config()` returns a valid `%Oban.Config{}` struct |
| `crypto` | Calls `SecureSharing.Crypto.initialized?()` to verify PQC Rust NIFs loaded successfully |

**Response example (healthy):**

```json
{
  "status": "ok",
  "timestamp": "2026-02-17T08:30:00.000000Z",
  "version": "0.1.0",
  "node": "secure_sharing@10.0.1.5",
  "checks": [
    {"name": "database", "status": "ok", "error": null},
    {"name": "cache", "status": "ok", "error": null},
    {"name": "oban", "status": "ok", "error": null},
    {"name": "crypto", "status": "ok", "error": null}
  ]
}
```

**Response example (unhealthy):**

```json
{
  "status": "unhealthy",
  "timestamp": "2026-02-17T08:30:00.000000Z",
  "version": "0.1.0",
  "node": "secure_sharing@10.0.1.5",
  "checks": [
    {"name": "database", "status": "error", "error": "Database query failed: ..."},
    {"name": "cache", "status": "ok", "error": null},
    {"name": "oban", "status": "ok", "error": null},
    {"name": "crypto", "status": "ok", "error": null}
  ]
}
```

### GET /health/cluster -- Cluster Status

Returns information about the Erlang distribution cluster. Useful for debugging node discovery and connectivity. Delegates to `SecureSharing.Cluster.info/0`.

**Response example:**

```json
{
  "status": "ok",
  "timestamp": "2026-02-17T08:30:00.000000Z",
  "cluster": {
    "self": "secure_sharing@10.0.1.5",
    "connected_nodes": [
      "secure_sharing@10.0.1.6",
      "secure_sharing@10.0.1.7"
    ],
    "total_nodes": 3,
    "strategy": "kubernetes",
    "is_clustered": true
  }
}
```

The `strategy` field reflects the `CLUSTER_STRATEGY` environment variable (default `"dns"`). See `SecureSharing.Cluster` (`lib/secure_sharing/cluster.ex`) for supported strategies: `dns`, `kubernetes`, `gossip`, `epmd`, `none`.

### GET /health/detailed -- Full System Health

Combines readiness checks with BEAM system metrics. Intended for human operators and dashboards rather than automated probes.

**Response example:**

```json
{
  "status": "ok",
  "timestamp": "2026-02-17T08:30:00.000000Z",
  "version": "0.1.0",
  "node": "secure_sharing@10.0.1.5",
  "checks": [
    {"name": "database", "status": "ok", "error": null},
    {"name": "cache", "status": "ok", "error": null},
    {"name": "oban", "status": "ok", "error": null},
    {"name": "crypto", "status": "ok", "error": null}
  ],
  "cluster": {
    "self": "secure_sharing@10.0.1.5",
    "connected_nodes": ["secure_sharing@10.0.1.6"],
    "total_nodes": 2,
    "strategy": "dns",
    "is_clustered": true
  },
  "system": {
    "otp_release": "27",
    "elixir_version": "1.18.1",
    "memory_mb": {
      "total": 256,
      "processes": 128,
      "ets": 32,
      "binary": 48
    },
    "process_count": 1234,
    "process_limit": 1048576,
    "uptime_seconds": 86400
  }
}
```

---

## 2. Telemetry Metrics Reference

The telemetry supervisor is defined in `SecureSharingWeb.Telemetry` (`lib/secure_sharing_web/telemetry.ex`). It starts a `telemetry_poller` that collects periodic measurements every 10 seconds. The `metrics/0` function defines the metric specifications that reporters consume.

### Phoenix HTTP Metrics

| Metric | Type | Unit | Tags | Description |
|--------|------|------|------|-------------|
| `phoenix.endpoint.start.system_time` | Summary | ms | -- | Wall-clock time when a request was received |
| `phoenix.endpoint.stop.duration` | Summary | ms | -- | Total time to process a request through the endpoint |
| `phoenix.router_dispatch.start.system_time` | Summary | ms | `route` | Time when router dispatch began |
| `phoenix.router_dispatch.stop.duration` | Summary | ms | `route` | Time spent in the controller action (per route) |
| `phoenix.router_dispatch.exception.duration` | Summary | ms | `route` | Duration of requests that raised exceptions |

### Phoenix WebSocket / Channel Metrics

| Metric | Type | Unit | Tags | Description |
|--------|------|------|------|-------------|
| `phoenix.socket_connected.duration` | Summary | ms | -- | Time to establish a WebSocket connection |
| `phoenix.socket_drain.count` | Sum | -- | -- | Number of socket drain events (connection closures) |
| `phoenix.channel_joined.duration` | Summary | ms | -- | Time to join a Phoenix channel |
| `phoenix.channel_handled_in.duration` | Summary | ms | `event` | Time to handle an incoming channel message |

### Database (Ecto) Metrics

All database metrics use the `secure_sharing.repo.query.*` prefix, corresponding to the `SecureSharing.Repo` module.

| Metric | Type | Unit | Description |
|--------|------|------|-------------|
| `secure_sharing.repo.query.total_time` | Summary | ms | Sum of all sub-timings for a query |
| `secure_sharing.repo.query.decode_time` | Summary | ms | Time decoding result rows from Postgrex |
| `secure_sharing.repo.query.query_time` | Summary | ms | Time executing the SQL statement |
| `secure_sharing.repo.query.queue_time` | Summary | ms | Time waiting in the connection pool queue |
| `secure_sharing.repo.query.idle_time` | Summary | ms | Time the connection was idle before checkout |

**Key insight:** A rising `queue_time` indicates connection pool saturation. This is the most important database metric to alert on. See [Section 6](#6-alerting-rules) for alerting thresholds.

### BEAM VM Metrics

Collected by `telemetry_poller` every 10 seconds.

| Metric | Type | Unit | Description |
|--------|------|------|-------------|
| `vm.memory.total` | Summary | KB | Total BEAM memory usage |
| `vm.total_run_queue_lengths.total` | Summary | -- | Total work items queued across all schedulers |
| `vm.total_run_queue_lengths.cpu` | Summary | -- | CPU-bound work items queued |
| `vm.total_run_queue_lengths.io` | Summary | -- | I/O-bound work items queued |

**Key insight:** `vm.total_run_queue_lengths.total` above 0 persistently means the schedulers are overloaded. Brief spikes are normal; sustained values above the scheduler count warrant investigation.

### Periodic Measurements

The `periodic_measurements/0` function in `SecureSharingWeb.Telemetry` is currently empty. See [Section 8](#8-application-level-metrics) for recommended custom measurements to add.

---

## 3. Prometheus Integration

The existing codebase has `telemetry_metrics` and `telemetry_poller` as dependencies but does not yet include a Prometheus exporter. Two approaches are described below.

### Option A: PromEx (Recommended)

PromEx provides pre-built Grafana dashboards alongside Prometheus metrics. It auto-instruments Phoenix, Ecto, Oban, BEAM, and more.

**Step 1: Add dependency to `mix.exs`:**

```elixir
# In deps() within services/securesharing/mix.exs
{:prom_ex, "~> 1.9"}
```

**Step 2: Create the PromEx module:**

Create `lib/secure_sharing/prom_ex.ex`:

```elixir
defmodule SecureSharing.PromEx do
  use PromEx, otp_app: :secure_sharing

  alias PromEx.Plugins

  @impl true
  def plugins do
    [
      # BEAM VM metrics (memory, schedulers, atoms, etc.)
      Plugins.Beam,
      # Phoenix request metrics (duration, count, by route)
      {Plugins.Phoenix,
       router: SecureSharingWeb.Router,
       endpoint: SecureSharingWeb.Endpoint},
      # Ecto query metrics (duration, queue time, per source)
      {Plugins.Ecto, repos: [SecureSharing.Repo]},
      # Oban job metrics (queue depth, execution time, failures)
      {Plugins.Oban, oban_supervisors: [Oban]},
      # Application information (version, uptime)
      {Plugins.Application, otp_app: :secure_sharing}
    ]
  end

  @impl true
  def dashboard_assigns do
    [
      datasource_id: "prometheus",
      default_selected_interval: "30s"
    ]
  end

  @impl true
  def dashboards do
    [
      {:prom_ex, "beam.json"},
      {:prom_ex, "phoenix.json"},
      {:prom_ex, "ecto.json"},
      {:prom_ex, "oban.json"}
    ]
  end
end
```

**Step 3: Add to supervision tree in `lib/secure_sharing/application.ex`:**

```elixir
children = [
  SecureSharing.PromEx,   # <-- Add before the Endpoint
  # ... existing children ...
  SecureSharingWeb.Endpoint
]
```

**Step 4: Configure the metrics endpoint in `config/config.exs`:**

```elixir
config :secure_sharing, SecureSharing.PromEx,
  manual_metrics_start_delay: :no_delay,
  drop_metrics_groups: [],
  grafana: :disabled,         # Set to config map to auto-upload dashboards
  metrics_server: [
    port: 4021,               # Separate port for metrics scraping
    path: "/metrics",
    protocol: :http,
    pool_size: 5,
    cowboy_opts: [],
    auth_strategy: :none       # Use :bearer for token auth in prod
  ]
```

**Step 5: Prometheus scrape config:**

```yaml
# prometheus.yml
scrape_configs:
  - job_name: "securesharing"
    scrape_interval: 15s
    metrics_path: "/metrics"
    static_configs:
      - targets:
          - "securesharing-node1:4021"
          - "securesharing-node2:4021"
        labels:
          environment: "production"
          service: "securesharing"

    # For Kubernetes service discovery:
    # kubernetes_sd_configs:
    #   - role: pod
    #     namespaces:
    #       names: ["securesharing"]
    # relabel_configs:
    #   - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
    #     action: keep
    #     regex: true
    #   - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_port]
    #     action: replace
    #     target_label: __address__
    #     regex: (.+)
    #     replacement: ${1}:4021
```

### Option B: TelemetryMetricsPrometheus (Lighter Weight)

If you prefer a thinner library without Grafana dashboard generation:

**Add dependency:**

```elixir
{:telemetry_metrics_prometheus, "~> 1.1"}
```

**Add reporter to the telemetry supervisor in `lib/secure_sharing_web/telemetry.ex`:**

```elixir
@impl true
def init(_arg) do
  children = [
    {:telemetry_poller, measurements: periodic_measurements(), period: 10_000},
    {TelemetryMetricsPrometheus, metrics: metrics(), port: 4021, name: :secure_sharing_metrics}
  ]

  Supervisor.init(children, strategy: :one_for_one)
end
```

This starts a Cowboy HTTP server on port 4021 serving `/metrics` in Prometheus exposition format using the metrics already defined in `metrics/0`.

---

## 4. Grafana Dashboard Setup

### Dashboard 1: Application Overview

Create a dashboard with the following panels. All PromQL queries assume the PromEx metric naming convention.

**Request Rate (requests/sec):**

```promql
sum(rate(phoenix_endpoint_stop_duration_milliseconds_count{job="securesharing"}[5m]))
```

**Request Latency P50/P95/P99:**

```promql
histogram_quantile(0.50, sum(rate(phoenix_endpoint_stop_duration_milliseconds_bucket{job="securesharing"}[5m])) by (le))
histogram_quantile(0.95, sum(rate(phoenix_endpoint_stop_duration_milliseconds_bucket{job="securesharing"}[5m])) by (le))
histogram_quantile(0.99, sum(rate(phoenix_endpoint_stop_duration_milliseconds_bucket{job="securesharing"}[5m])) by (le))
```

**Error Rate (5xx responses):**

```promql
sum(rate(phoenix_endpoint_stop_duration_milliseconds_count{job="securesharing", status=~"5.."}[5m]))
  /
sum(rate(phoenix_endpoint_stop_duration_milliseconds_count{job="securesharing"}[5m]))
  * 100
```

**Request Duration by Route (top 10 slowest):**

```promql
topk(10,
  histogram_quantile(0.95,
    sum(rate(phoenix_router_dispatch_stop_duration_milliseconds_bucket{job="securesharing"}[5m])) by (le, route)
  )
)
```

### Dashboard 2: Database Health

**Query Duration P95:**

```promql
histogram_quantile(0.95,
  sum(rate(secure_sharing_repo_query_total_time_milliseconds_bucket[5m])) by (le)
)
```

**Connection Pool Queue Time (critical for saturation detection):**

```promql
histogram_quantile(0.95,
  sum(rate(secure_sharing_repo_query_queue_time_milliseconds_bucket[5m])) by (le)
)
```

**Query Rate:**

```promql
sum(rate(secure_sharing_repo_query_total_time_milliseconds_count[5m]))
```

**Active Database Connections (if using Ecto pool telemetry):**

```promql
secure_sharing_repo_pool_size - secure_sharing_repo_pool_idle
```

### Dashboard 3: BEAM VM

**Memory Usage by Category:**

```promql
beam_memory_bytes{job="securesharing", memory_type="total"}
beam_memory_bytes{job="securesharing", memory_type="processes"}
beam_memory_bytes{job="securesharing", memory_type="ets"}
beam_memory_bytes{job="securesharing", memory_type="binary"}
```

**Scheduler Run Queue Length:**

```promql
beam_total_run_queue_lengths_total{job="securesharing"}
```

**Process Count vs Limit:**

```promql
beam_system_info_process_count{job="securesharing"}
beam_system_info_process_limit{job="securesharing"}
```

**ETS Table Memory (for cache monitoring):**

```promql
beam_memory_bytes{job="securesharing", memory_type="ets"}
```

### Dashboard 4: Oban Background Jobs

**Jobs Processed per Second by Queue:**

```promql
sum(rate(oban_job_stop_duration_milliseconds_count{job="securesharing"}[5m])) by (queue)
```

**Job Failure Rate by Queue:**

```promql
sum(rate(oban_job_exception_duration_milliseconds_count{job="securesharing"}[5m])) by (queue)
```

**Queue Depth (available jobs waiting):**

```promql
oban_queue_available_jobs{job="securesharing"}
```

**Job Duration P95 by Worker:**

```promql
histogram_quantile(0.95,
  sum(rate(oban_job_stop_duration_milliseconds_bucket{job="securesharing"}[5m])) by (le, worker)
)
```

### Dashboard 5: Cluster Status

**Connected Nodes Count:**

Use the `/health/cluster` endpoint with a Grafana JSON data source or a custom metric (see Section 8).

**WebSocket Connections:**

```promql
sum(phoenix_socket_connected_duration_milliseconds_count{job="securesharing"})
```

**Channel Join Rate:**

```promql
sum(rate(phoenix_channel_joined_duration_milliseconds_count{job="securesharing"}[5m]))
```

### Importing PromEx Dashboards

If using PromEx with Grafana auto-upload enabled:

```elixir
# In config/prod.exs or config/runtime.exs
config :secure_sharing, SecureSharing.PromEx,
  grafana: [
    host: System.get_env("GRAFANA_HOST", "http://grafana:3000"),
    auth_token: System.get_env("GRAFANA_AUTH_TOKEN"),
    upload_dashboards_on_start: true,
    folder_name: "SecureSharing",
    annotate_app_lifecycle: true
  ]
```

Otherwise, export the JSON dashboards and import them manually:

```bash
mix prom_ex.dashboard_export --dashboard beam.json --output grafana_dashboards/
mix prom_ex.dashboard_export --dashboard phoenix.json --output grafana_dashboards/
mix prom_ex.dashboard_export --dashboard ecto.json --output grafana_dashboards/
mix prom_ex.dashboard_export --dashboard oban.json --output grafana_dashboards/
```

---

## 5. Log Aggregation

### Structured JSON Logging in Production

Replace the default text formatter with JSON output for production. This makes logs parseable by ELK, Loki, Datadog, and CloudWatch.

**Step 1: Add dependency to `mix.exs`:**

```elixir
{:logger_json, "~> 6.0"}
```

**Step 2: Configure in `config/prod.exs`:**

```elixir
import Config

config :logger, level: :info

config :logger, :default_handler,
  formatter: {LoggerJSON.Formatters.Basic, []}

config :logger, :default_formatter,
  format: {LoggerJSON.Formatters.Basic, :format},
  metadata: [
    :request_id,
    :user_id,
    :tenant_id,
    :remote_ip,
    :method,
    :path,
    :status,
    :duration
  ]
```

This produces log lines like:

```json
{
  "time": "2026-02-17T08:30:00.000Z",
  "severity": "info",
  "message": "GET /api/files/abc123",
  "metadata": {
    "request_id": "F1234567890",
    "user_id": "019...",
    "tenant_id": "019...",
    "remote_ip": "203.0.113.42",
    "method": "GET",
    "path": "/api/files/abc123",
    "status": 200,
    "duration": 45
  }
}
```

### Adding Request Metadata

The existing `SecureSharingWeb.Plugs.Authenticate` plug assigns `current_user`. Ensure the user and tenant IDs are propagated to Logger metadata. Add a plug or extend your existing pipeline:

```elixir
# In lib/secure_sharing_web/plugs/log_metadata.ex
defmodule SecureSharingWeb.Plugs.LogMetadata do
  @behaviour Plug

  import Plug.Conn
  require Logger

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    Logger.metadata(
      remote_ip: to_string(:inet_parse.ntoa(conn.remote_ip)),
      method: conn.method,
      path: conn.request_path
    )

    if user = conn.assigns[:current_user] do
      Logger.metadata(
        user_id: user.id,
        tenant_id: user.active_tenant_id
      )
    end

    register_before_send(conn, fn conn ->
      Logger.metadata(status: conn.status)
      conn
    end)
  end
end
```

### Integration with Grafana Loki

Use Promtail to ship JSON logs from the application's stdout:

```yaml
# promtail-config.yml
server:
  http_listen_port: 9080

positions:
  filename: /var/lib/promtail/positions.yaml

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  - job_name: securesharing
    static_configs:
      - targets:
          - localhost
        labels:
          job: securesharing
          environment: production
          __path__: /var/log/securesharing/*.log

    # For Kubernetes, use journal or pod log scraping:
    # kubernetes_sd_configs:
    #   - role: pod
    # relabel_configs:
    #   - source_labels: [__meta_kubernetes_namespace]
    #     target_label: namespace
    #   - source_labels: [__meta_kubernetes_pod_name]
    #     target_label: pod

    pipeline_stages:
      - json:
          expressions:
            level: severity
            message: message
            request_id: metadata.request_id
            user_id: metadata.user_id
            tenant_id: metadata.tenant_id
      - labels:
          level:
```

### Integration with ELK Stack

For Elasticsearch/Logstash/Kibana, configure Filebeat:

```yaml
# filebeat.yml
filebeat.inputs:
  - type: log
    enabled: true
    paths:
      - /var/log/securesharing/*.log
    json.keys_under_root: true
    json.add_error_key: true
    json.message_key: message
    fields:
      service: securesharing
      environment: production

output.elasticsearch:
  hosts: ["elasticsearch:9200"]
  index: "securesharing-%{+yyyy.MM.dd}"

# Or output to Logstash for additional processing:
# output.logstash:
#   hosts: ["logstash:5044"]
```

### Log Levels by Environment

The current configuration in `config/`:

| Environment | Level | File |
|-------------|-------|------|
| dev | `:debug` | `config/dev.exs` |
| test | `:warning` | `config/test.exs` |
| prod | `:info` | `config/prod.exs` |

For production debugging, you can change the log level at runtime without restarting:

```elixir
# Via remote console (bin/secure_sharing remote)
Logger.configure(level: :debug)

# Revert back
Logger.configure(level: :info)
```

---

## 6. Alerting Rules

### Prometheus Alerting Rules

Create `alerting_rules.yml` and load it into Prometheus or Alertmanager:

```yaml
groups:
  - name: securesharing.database
    rules:
      # Database connection pool saturation
      - alert: DatabasePoolQueueTimeHigh
        expr: >
          histogram_quantile(0.95,
            sum(rate(secure_sharing_repo_query_queue_time_milliseconds_bucket[5m])) by (le)
          ) > 100
        for: 5m
        labels:
          severity: warning
          service: securesharing
        annotations:
          summary: "Database connection pool queue time is high"
          description: >
            P95 database queue time is {{ $value }}ms (threshold: 100ms).
            This indicates connection pool saturation. Current pool_size is
            configured via POOL_SIZE env var (default: 10).
          runbook: "Increase POOL_SIZE or POOL_COUNT, or investigate slow queries."

      - alert: DatabasePoolQueueTimeCritical
        expr: >
          histogram_quantile(0.95,
            sum(rate(secure_sharing_repo_query_queue_time_milliseconds_bucket[5m])) by (le)
          ) > 500
        for: 2m
        labels:
          severity: critical
          service: securesharing
        annotations:
          summary: "Database connection pool is critically saturated"
          description: >
            P95 database queue time is {{ $value }}ms (threshold: 500ms).
            Queries are severely delayed waiting for connections.

      # Slow queries
      - alert: DatabaseSlowQueries
        expr: >
          histogram_quantile(0.99,
            sum(rate(secure_sharing_repo_query_query_time_milliseconds_bucket[5m])) by (le)
          ) > 1000
        for: 5m
        labels:
          severity: warning
          service: securesharing
        annotations:
          summary: "Database P99 query time exceeds 1 second"

      # Database health check failure
      - alert: DatabaseHealthCheckFailed
        expr: >
          probe_success{job="securesharing-healthcheck", endpoint="/health/ready"} == 0
        for: 1m
        labels:
          severity: critical
          service: securesharing
        annotations:
          summary: "SecureSharing readiness check is failing"

  - name: securesharing.memory
    rules:
      # BEAM memory usage
      - alert: HighMemoryUsage
        expr: >
          beam_memory_bytes{memory_type="total", job="securesharing"} > 2147483648
        for: 10m
        labels:
          severity: warning
          service: securesharing
        annotations:
          summary: "BEAM memory usage exceeds 2 GB"
          description: >
            Total BEAM memory is {{ $value | humanize1024 }}B.
            Check for memory leaks in ETS tables, binary references, or process mailboxes.

      - alert: CriticalMemoryUsage
        expr: >
          beam_memory_bytes{memory_type="total", job="securesharing"} > 4294967296
        for: 5m
        labels:
          severity: critical
          service: securesharing
        annotations:
          summary: "BEAM memory usage exceeds 4 GB -- OOM risk"

      # ETS memory growth (cache table)
      - alert: ETSMemoryHigh
        expr: >
          beam_memory_bytes{memory_type="ets", job="securesharing"} > 536870912
        for: 10m
        labels:
          severity: warning
          service: securesharing
        annotations:
          summary: "ETS memory exceeds 512 MB"
          description: >
            ETS tables are using {{ $value | humanize1024 }}B.
            The SecureSharing.Cache has a max_entries limit of 10,000
            but other ETS tables (Hammer, Phoenix PubSub) may be growing.

      # Scheduler overload
      - alert: SchedulerRunQueueHigh
        expr: >
          beam_total_run_queue_lengths_total{job="securesharing"} > 20
        for: 5m
        labels:
          severity: warning
          service: securesharing
        annotations:
          summary: "BEAM scheduler run queue is backed up"
          description: >
            Run queue length is {{ $value }}. Schedulers are overloaded.
            This may be caused by CPU-intensive crypto operations in Rust NIFs
            not yielding properly, or too many concurrent requests.

  - name: securesharing.http
    rules:
      # Error rate
      - alert: HighErrorRate
        expr: >
          (
            sum(rate(phoenix_endpoint_stop_duration_milliseconds_count{status=~"5..", job="securesharing"}[5m]))
            /
            sum(rate(phoenix_endpoint_stop_duration_milliseconds_count{job="securesharing"}[5m]))
          ) > 0.05
        for: 5m
        labels:
          severity: warning
          service: securesharing
        annotations:
          summary: "HTTP 5xx error rate exceeds 5%"
          description: >
            {{ $value | humanizePercentage }} of requests are returning 5xx errors.

      - alert: CriticalErrorRate
        expr: >
          (
            sum(rate(phoenix_endpoint_stop_duration_milliseconds_count{status=~"5..", job="securesharing"}[5m]))
            /
            sum(rate(phoenix_endpoint_stop_duration_milliseconds_count{job="securesharing"}[5m]))
          ) > 0.15
        for: 2m
        labels:
          severity: critical
          service: securesharing
        annotations:
          summary: "HTTP 5xx error rate exceeds 15%"

      # Latency
      - alert: HighRequestLatency
        expr: >
          histogram_quantile(0.95,
            sum(rate(phoenix_endpoint_stop_duration_milliseconds_bucket{job="securesharing"}[5m])) by (le)
          ) > 2000
        for: 5m
        labels:
          severity: warning
          service: securesharing
        annotations:
          summary: "P95 request latency exceeds 2 seconds"

  - name: securesharing.s3
    rules:
      # S3 storage failures
      # Requires custom metric; see Section 8
      - alert: S3OperationFailures
        expr: >
          sum(rate(secure_sharing_storage_errors_total{job="securesharing"}[5m])) > 0.1
        for: 5m
        labels:
          severity: warning
          service: securesharing
        annotations:
          summary: "S3 storage operations are failing"
          description: >
            S3 error rate is {{ $value }}/sec.
            Check connectivity to the Garage/S3 endpoint and bucket permissions.

      - alert: S3OperationFailuresCritical
        expr: >
          sum(rate(secure_sharing_storage_errors_total{job="securesharing"}[5m])) > 1
        for: 2m
        labels:
          severity: critical
          service: securesharing
        annotations:
          summary: "S3 storage operations are failing at a critical rate"

  - name: securesharing.oban
    rules:
      # Oban queue depth
      - alert: ObanQueueBacklog
        expr: >
          oban_queue_available_jobs{job="securesharing"} > 100
        for: 10m
        labels:
          severity: warning
          service: securesharing
        annotations:
          summary: "Oban queue {{ $labels.queue }} has a backlog of {{ $value }} jobs"
          description: >
            Jobs are accumulating faster than workers can process them.
            Consider increasing queue concurrency via OBAN_DEFAULT_QUEUE_SIZE.

      - alert: ObanQueueBacklogCritical
        expr: >
          oban_queue_available_jobs{job="securesharing"} > 500
        for: 5m
        labels:
          severity: critical
          service: securesharing
        annotations:
          summary: "Oban queue {{ $labels.queue }} backlog is critical ({{ $value }} jobs)"

      # Oban job failure rate
      - alert: ObanHighFailureRate
        expr: >
          (
            sum(rate(oban_job_exception_duration_milliseconds_count{job="securesharing"}[5m])) by (queue)
            /
            sum(rate(oban_job_stop_duration_milliseconds_count{job="securesharing"}[5m])) by (queue)
          ) > 0.10
        for: 10m
        labels:
          severity: warning
          service: securesharing
        annotations:
          summary: "Oban job failure rate exceeds 10% in queue {{ $labels.queue }}"

  - name: securesharing.cluster
    rules:
      # Cluster node loss
      - alert: ClusterNodeLost
        expr: >
          count(up{job="securesharing"}) < 2
        for: 5m
        labels:
          severity: warning
          service: securesharing
        annotations:
          summary: "SecureSharing cluster has fewer than 2 healthy nodes"

  - name: securesharing.crypto
    rules:
      # Crypto NIF failures (requires custom metric; see Section 8)
      - alert: CryptoOperationFailures
        expr: >
          sum(rate(secure_sharing_crypto_errors_total{job="securesharing"}[5m])) > 0
        for: 5m
        labels:
          severity: critical
          service: securesharing
        annotations:
          summary: "PQC cryptographic operations are failing"
          description: >
            Rust NIF crypto operations are returning errors.
            This could indicate NIF library corruption or resource exhaustion.
```

---

## 7. OpenTelemetry Distributed Tracing

OpenTelemetry provides end-to-end distributed tracing across the SecureSharing backend, PII service, and client applications.

### Step 1: Add Dependencies

Add to `mix.exs`:

```elixir
# OpenTelemetry
{:opentelemetry, "~> 1.4"},
{:opentelemetry_api, "~> 1.3"},
{:opentelemetry_exporter, "~> 1.7"},

# Auto-instrumentation libraries
{:opentelemetry_phoenix, "~> 1.2"},
{:opentelemetry_ecto, "~> 1.2"},
{:opentelemetry_oban, "~> 1.1"},
{:opentelemetry_bandit, "~> 0.2"},
{:opentelemetry_req, "~> 0.2"}
```

### Step 2: Configure the OTLP Exporter

In `config/runtime.exs`, within the `if config_env() == :prod do` block:

```elixir
# OpenTelemetry configuration
otlp_endpoint = System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT")

if otlp_endpoint do
  config :opentelemetry,
    span_processor: :batch,
    traces_exporter: :otlp

  config :opentelemetry_exporter,
    otlp_protocol: :http_protobuf,
    otlp_endpoint: otlp_endpoint,
    otlp_headers: [
      {"Authorization", "Bearer #{System.get_env("OTEL_EXPORTER_OTLP_TOKEN", "")}"}
    ]
else
  # Disable tracing if no endpoint is configured
  config :opentelemetry,
    traces_exporter: :none
end
```

### Step 3: Set Resource Attributes

In `config/runtime.exs`:

```elixir
config :opentelemetry, :resource, [
  service: [
    name: "securesharing",
    version: Application.spec(:secure_sharing, :vsn) |> to_string(),
    namespace: System.get_env("OTEL_SERVICE_NAMESPACE", "securesharing")
  ],
  host: [
    name: System.get_env("HOSTNAME", to_string(Node.self()))
  ],
  deployment: [
    environment: System.get_env("DEPLOYMENT_ENV", "production")
  ]
]
```

### Step 4: Initialize Auto-Instrumentation

In `lib/secure_sharing/application.ex`, add setup calls at the top of `start/2`:

```elixir
@impl true
def start(_type, _args) do
  # OpenTelemetry auto-instrumentation setup
  OpentelemetryBandit.setup()
  OpentelemetryPhoenix.setup(adapter: :bandit)
  OpentelemetryEcto.setup([:secure_sharing, :repo])
  OpentelemetryOban.setup()

  # Initialize storage provider (S3, Local, etc.)
  :ok = SecureSharing.Storage.init()

  # ... rest of supervision tree
end
```

### Step 5: Add Custom Spans for Crypto Operations

For visibility into PQC crypto operations (which run in Rust NIFs), wrap key operations:

```elixir
# Example: In lib/secure_sharing/crypto.ex or wherever crypto calls are made
require OpenTelemetry.Tracer, as: Tracer

def encrypt_dek(dek, recipient_public_key, algorithm) do
  Tracer.with_span "crypto.encrypt_dek", attributes: %{
    "crypto.algorithm" => to_string(algorithm),
    "crypto.operation" => "kem_encapsulate"
  } do
    # existing crypto logic
  end
end
```

### Step 6: Propagate Context to PII Service

When making HTTP calls to the PII service via `Req`, OpenTelemetry context is automatically propagated if `opentelemetry_req` is installed. Ensure Req calls include propagation:

```elixir
# opentelemetry_req will automatically inject W3C trace context headers
# into outgoing requests made with Req
Req.get!(url, headers: headers)
```

### Step 7: Trace Backend Options

Set `OTEL_EXPORTER_OTLP_ENDPOINT` to point at your chosen backend:

| Backend | Endpoint Example |
|---------|-----------------|
| Jaeger | `http://jaeger:4318` |
| Tempo (Grafana) | `http://tempo:4318` |
| Honeycomb | `https://api.honeycomb.io` |
| Datadog | `http://datadog-agent:4318` |
| New Relic | `https://otlp.nr-data.net` |
| Self-hosted OTEL Collector | `http://otel-collector:4318` |

---

## 8. Application-Level Metrics

The following custom metrics should be added to provide business-level observability. These extend the existing `SecureSharingWeb.Telemetry` module.

### Step 1: Define Custom Metrics

Add to the `metrics/0` function in `lib/secure_sharing_web/telemetry.ex`:

```elixir
def metrics do
  [
    # ... existing metrics ...

    # --- Application Metrics ---

    # File operations
    counter("secure_sharing.files.upload.count",
      tags: [:tenant_id],
      description: "Number of file uploads"
    ),
    counter("secure_sharing.files.download.count",
      tags: [:tenant_id],
      description: "Number of file downloads"
    ),
    summary("secure_sharing.files.upload.size_bytes",
      tags: [:tenant_id],
      description: "Size of uploaded files in bytes",
      unit: :byte
    ),

    # Sharing operations
    counter("secure_sharing.shares.created.count",
      tags: [:permission, :resource_type],
      description: "Number of shares created"
    ),
    counter("secure_sharing.shares.revoked.count",
      description: "Number of shares revoked"
    ),

    # Authentication events
    counter("secure_sharing.auth.login.count",
      tags: [:result],
      description: "Login attempts (result: success|failure|locked)"
    ),
    counter("secure_sharing.auth.register.count",
      description: "New user registrations"
    ),
    counter("secure_sharing.auth.token_refresh.count",
      tags: [:result],
      description: "Token refresh attempts"
    ),

    # Crypto operations
    summary("secure_sharing.crypto.kem_encapsulate.duration",
      tags: [:algorithm],
      unit: {:native, :millisecond},
      description: "Duration of KEM encapsulation"
    ),
    summary("secure_sharing.crypto.sign.duration",
      tags: [:algorithm],
      unit: {:native, :millisecond},
      description: "Duration of digital signature operations"
    ),
    counter("secure_sharing.crypto.errors.count",
      tags: [:operation, :algorithm],
      description: "Crypto operation failures"
    ),

    # S3 storage operations
    counter("secure_sharing.storage.operations.count",
      tags: [:operation, :result],
      description: "S3 storage operations (operation: put|get|delete, result: ok|error)"
    ),
    counter("secure_sharing.storage.errors.count",
      tags: [:operation],
      description: "S3 storage operation failures"
    ),

    # Cache metrics
    counter("secure_sharing.cache.hit.count",
      description: "Cache hits"
    ),
    counter("secure_sharing.cache.miss.count",
      description: "Cache misses"
    ),

    # Rate limiting
    counter("secure_sharing.rate_limit.blocked.count",
      tags: [:endpoint],
      description: "Requests blocked by rate limiting"
    ),

    # Invitation flows
    counter("secure_sharing.invitations.sent.count",
      description: "Invitations sent"
    ),
    counter("secure_sharing.invitations.accepted.count",
      description: "Invitations accepted"
    ),

    # Cluster metrics
    last_value("secure_sharing.cluster.node_count",
      description: "Number of connected cluster nodes"
    )
  ]
end
```

### Step 2: Emit Telemetry Events from Application Code

Add telemetry execute calls at the points where these events occur.

**File upload (in `FileController` or `Files` context):**

```elixir
:telemetry.execute(
  [:secure_sharing, :files, :upload],
  %{count: 1, size_bytes: file_size},
  %{tenant_id: tenant_id}
)
```

**Share creation (in `ShareController` or `Sharing` context):**

```elixir
:telemetry.execute(
  [:secure_sharing, :shares, :created],
  %{count: 1},
  %{permission: permission, resource_type: resource_type}
)
```

**Authentication (in `AuthController`):**

```elixir
:telemetry.execute(
  [:secure_sharing, :auth, :login],
  %{count: 1},
  %{result: :success}  # or :failure, :locked
)
```

**S3 storage (in storage provider module):**

```elixir
:telemetry.execute(
  [:secure_sharing, :storage, :operations],
  %{count: 1},
  %{operation: :put, result: :ok}
)

# On error:
:telemetry.execute(
  [:secure_sharing, :storage, :errors],
  %{count: 1},
  %{operation: :put}
)
```

### Step 3: Add Periodic Measurements

Update the `periodic_measurements/0` function in `lib/secure_sharing_web/telemetry.ex`:

```elixir
defp periodic_measurements do
  [
    # Cache statistics
    {__MODULE__, :measure_cache_stats, []},
    # Cluster node count
    {__MODULE__, :measure_cluster_nodes, []}
  ]
end

@doc false
def measure_cache_stats do
  try do
    stats = SecureSharing.Cache.stats()

    :telemetry.execute(
      [:secure_sharing, :cache, :stats],
      %{
        size: stats.size,
        memory_bytes: stats.memory_bytes,
        utilization_percent: stats.utilization_percent
      },
      %{}
    )
  rescue
    _ -> :ok
  end
end

@doc false
def measure_cluster_nodes do
  :telemetry.execute(
    [:secure_sharing, :cluster],
    %{node_count: length(Node.list()) + 1},
    %{}
  )
end
```

---

## 9. Kubernetes Probe Configuration

The health controller module doc already includes a Kubernetes example. Below is the complete, production-ready configuration.

### Pod Spec

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: securesharing
  labels:
    app: secure-sharing
spec:
  replicas: 3
  selector:
    matchLabels:
      app: secure-sharing
  template:
    metadata:
      labels:
        app: secure-sharing
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "4021"
        prometheus.io/path: "/metrics"
    spec:
      containers:
        - name: securesharing
          image: securesharing:latest
          ports:
            - name: http
              containerPort: 4000
              protocol: TCP
            - name: metrics
              containerPort: 4021
              protocol: TCP
            - name: epmd
              containerPort: 4369
              protocol: TCP

          # Liveness: Is the BEAM running?
          # Uses /health which only checks the Phoenix endpoint is up.
          # Failure restarts the pod.
          livenessProbe:
            httpGet:
              path: /health
              port: http
            initialDelaySeconds: 15
            periodSeconds: 10
            timeoutSeconds: 5
            failureThreshold: 3
            successThreshold: 1

          # Readiness: Can the pod serve traffic?
          # Uses /health/ready which checks DB, cache, Oban, and crypto.
          # Failure removes the pod from the Service endpoint list.
          readinessProbe:
            httpGet:
              path: /health/ready
              port: http
            initialDelaySeconds: 10
            periodSeconds: 5
            timeoutSeconds: 5
            failureThreshold: 3
            successThreshold: 1

          # Startup: Allow extra time for first boot.
          # NIF compilation, crypto initialization, and DB migrations
          # may take longer on first deployment.
          startupProbe:
            httpGet:
              path: /health
              port: http
            initialDelaySeconds: 5
            periodSeconds: 5
            timeoutSeconds: 5
            failureThreshold: 30   # 30 * 5s = 150s max startup time

          env:
            - name: PHX_SERVER
              value: "true"
            - name: PORT
              value: "4000"
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: securesharing-secrets
                  key: database-url
            - name: SECRET_KEY_BASE
              valueFrom:
                secretKeyRef:
                  name: securesharing-secrets
                  key: secret-key-base
            - name: PHX_HOST
              value: "api.securesharing.com"
            - name: POOL_SIZE
              value: "10"

            # Clustering via Kubernetes DNS
            - name: CLUSTER_STRATEGY
              value: "kubernetes"
            - name: KUBERNETES_SELECTOR
              value: "app=secure-sharing"
            - name: KUBERNETES_NAMESPACE
              valueFrom:
                fieldRef:
                  fieldPath: metadata.namespace

            # S3 storage
            - name: S3_BUCKET
              value: "securesharing-prod"
            - name: AWS_ACCESS_KEY_ID
              valueFrom:
                secretKeyRef:
                  name: securesharing-secrets
                  key: aws-access-key-id
            - name: AWS_SECRET_ACCESS_KEY
              valueFrom:
                secretKeyRef:
                  name: securesharing-secrets
                  key: aws-secret-access-key

            # OpenTelemetry
            - name: OTEL_EXPORTER_OTLP_ENDPOINT
              value: "http://otel-collector.monitoring:4318"

            # Redis for distributed rate limiting
            - name: REDIS_URL
              valueFrom:
                secretKeyRef:
                  name: securesharing-secrets
                  key: redis-url

          resources:
            requests:
              cpu: 500m
              memory: 512Mi
            limits:
              cpu: 2000m
              memory: 2Gi

      # RBAC for Kubernetes cluster strategy
      serviceAccountName: securesharing
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: securesharing
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: securesharing-pod-reader
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: securesharing-pod-reader
subjects:
  - kind: ServiceAccount
    name: securesharing
roleRef:
  kind: Role
  name: securesharing-pod-reader
  apiGroup: rbac.authorization.k8s.io
```

### Headless Service for Clustering

```yaml
apiVersion: v1
kind: Service
metadata:
  name: securesharing-headless
spec:
  clusterIP: None
  selector:
    app: secure-sharing
  ports:
    - name: epmd
      port: 4369
      targetPort: 4369
```

### Service for External Traffic

```yaml
apiVersion: v1
kind: Service
metadata:
  name: securesharing
spec:
  type: ClusterIP
  selector:
    app: secure-sharing
  ports:
    - name: http
      port: 80
      targetPort: 4000
    - name: metrics
      port: 4021
      targetPort: 4021
```

---

## 10. Recommended Monitoring Stack Options

### Option A: Self-Hosted (Grafana Stack)

Best for teams that want full control, are hosting on bare metal (e.g., Hetzner, Contabo), or want to avoid per-seat SaaS costs.

| Component | Tool | Purpose |
|-----------|------|---------|
| Metrics | Prometheus | Scrape and store time-series metrics |
| Dashboards | Grafana | Visualization, dashboards, alerting |
| Logs | Loki + Promtail | Log aggregation with Grafana integration |
| Traces | Tempo | Distributed tracing backend |
| Alerting | Alertmanager | Route alerts to Slack, PagerDuty, email |

**Docker Compose snippet for monitoring stack:**

```yaml
# docker-compose.monitoring.yml
services:
  prometheus:
    image: prom/prometheus:latest
    volumes:
      - ./monitoring/prometheus.yml:/etc/prometheus/prometheus.yml
      - ./monitoring/alerting_rules.yml:/etc/prometheus/alerting_rules.yml
      - prometheus_data:/prometheus
    ports:
      - "9090:9090"
    command:
      - "--config.file=/etc/prometheus/prometheus.yml"
      - "--storage.tsdb.retention.time=30d"

  grafana:
    image: grafana/grafana:latest
    volumes:
      - grafana_data:/var/lib/grafana
      - ./monitoring/grafana/provisioning:/etc/grafana/provisioning
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=changeme
      - GF_INSTALL_PLUGINS=grafana-piechart-panel

  loki:
    image: grafana/loki:latest
    ports:
      - "3100:3100"
    volumes:
      - loki_data:/loki

  promtail:
    image: grafana/promtail:latest
    volumes:
      - ./monitoring/promtail.yml:/etc/promtail/config.yml
      - /var/log:/var/log:ro
    command: -config.file=/etc/promtail/config.yml

  tempo:
    image: grafana/tempo:latest
    ports:
      - "4318:4318"   # OTLP HTTP
      - "4317:4317"   # OTLP gRPC
    volumes:
      - tempo_data:/var/tempo

  alertmanager:
    image: prom/alertmanager:latest
    volumes:
      - ./monitoring/alertmanager.yml:/etc/alertmanager/alertmanager.yml
    ports:
      - "9093:9093"

volumes:
  prometheus_data:
  grafana_data:
  loki_data:
  tempo_data:
```

**Estimated resource requirements:**

| Component | CPU | Memory | Storage |
|-----------|-----|--------|---------|
| Prometheus | 0.5 core | 1-2 GB | 20 GB / month (at 15s scrape interval, ~50 targets) |
| Grafana | 0.2 core | 256 MB | 1 GB |
| Loki | 0.5 core | 1 GB | 10-50 GB / month (depends on log volume) |
| Tempo | 0.5 core | 1 GB | 5-20 GB / month |

### Option B: Cloud-Managed (AWS)

Best for teams already on AWS who prefer managed services.

| Component | Tool | Purpose |
|-----------|------|---------|
| Metrics | Amazon Managed Prometheus (AMP) | Prometheus-compatible metrics storage |
| Dashboards | Amazon Managed Grafana (AMG) | Managed Grafana with SSO |
| Logs | CloudWatch Logs | Log aggregation |
| Traces | AWS X-Ray or Tempo via AMG | Distributed tracing |
| Alerting | CloudWatch Alarms + SNS | Alert routing |

**Configuration for Amazon Managed Prometheus:**

```yaml
# prometheus.yml remote_write config
remote_write:
  - url: https://aps-workspaces.<region>.amazonaws.com/workspaces/<workspace-id>/api/v1/remote_write
    sigv4:
      region: <region>
    queue_config:
      max_samples_per_send: 1000
      max_shards: 200
      capacity: 2500
```

### Option C: Cloud-Managed (Platform-Agnostic SaaS)

Best for teams that want zero infrastructure management.

| Component | Tool | Notes |
|-----------|------|-------|
| All-in-one | Datadog | Metrics, logs, traces, APM in one platform |
| All-in-one | New Relic | Similar to Datadog, generous free tier |
| Metrics + Dashboards | Grafana Cloud | Free tier with 10K metrics, 50 GB logs |
| Traces | Honeycomb | Excellent trace exploration UI |

**Grafana Cloud configuration (recommended for small teams):**

Set environment variables:

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=https://otlp-gateway-<zone>.grafana.net/otlp
OTEL_EXPORTER_OTLP_TOKEN=<your-grafana-cloud-token>
```

PromEx remote write to Grafana Cloud Prometheus:

```elixir
config :secure_sharing, SecureSharing.PromEx,
  grafana: [
    host: "https://<your-instance>.grafana.net",
    auth_token: System.get_env("GRAFANA_CLOUD_TOKEN"),
    upload_dashboards_on_start: true,
    folder_name: "SecureSharing",
    annotate_app_lifecycle: true
  ]
```

### Decision Matrix

| Factor | Self-Hosted | AWS Managed | SaaS |
|--------|------------|-------------|------|
| Monthly cost (small team) | $20-50 (server) | $100-300 | $0-200 (free tiers) |
| Monthly cost (enterprise) | $100-500 (servers) | $500-2000 | $500-5000+ |
| Setup effort | High | Medium | Low |
| Maintenance | You manage | AWS manages | Vendor manages |
| Data residency control | Full | AWS regions | Vendor regions |
| Customization | Full | Moderate | Limited |
| Best for SecureSharing | Hetzner/Contabo deployments | AWS deployments | Quick start, small teams |

For SecureSharing deployments that prioritize data sovereignty (which aligns with the zero-trust, zero-knowledge philosophy), self-hosted monitoring with the Grafana stack is recommended. All monitoring data stays within your infrastructure, and the open-source tools have no per-seat licensing costs.

---

## Quick Start Checklist

1. [ ] Add `prom_ex` (or `telemetry_metrics_prometheus`) to `mix.exs` dependencies
2. [ ] Create `SecureSharing.PromEx` module and add to supervision tree
3. [ ] Add `logger_json` for structured production logging
4. [ ] Add OpenTelemetry dependencies and configure `OTEL_EXPORTER_OTLP_ENDPOINT`
5. [ ] Add custom application metrics (Section 8) to `SecureSharingWeb.Telemetry`
6. [ ] Emit telemetry events from controllers and context modules
7. [ ] Deploy Prometheus + Grafana (or configure cloud provider)
8. [ ] Import PromEx dashboards into Grafana
9. [ ] Load alerting rules into Prometheus/Alertmanager
10. [ ] Configure Kubernetes probes pointing at `/health` and `/health/ready`
11. [ ] Verify the metrics endpoint is accessible at `http://<node>:4021/metrics`
12. [ ] Test alerts by simulating failures (e.g., stop database, fill connection pool)
