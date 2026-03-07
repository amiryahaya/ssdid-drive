defmodule SecureSharingWeb.HealthController do
  @moduledoc """
  Health check endpoints for Kubernetes probes and load balancers.

  Provides:
  - `GET /health` - Basic liveness check
  - `GET /health/ready` - Readiness check including database connectivity
  - `GET /health/cluster` - Cluster status and connected nodes
  - `GET /health/detailed` - Full system health with metrics

  ## Kubernetes Configuration Example

  ```yaml
  livenessProbe:
    httpGet:
      path: /health
      port: 4000
    initialDelaySeconds: 10
    periodSeconds: 10

  readinessProbe:
    httpGet:
      path: /health/ready
      port: 4000
    initialDelaySeconds: 5
    periodSeconds: 5
  ```
  """
  use SecureSharingWeb, :controller

  alias SecureSharing.Repo

  @doc """
  Basic liveness check.

  Returns 200 OK if the application is running.
  Used by load balancers to determine if the instance should receive traffic.
  """
  def index(conn, _params) do
    conn
    |> put_status(:ok)
    |> json(%{
      status: "ok",
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      version: Application.spec(:secure_sharing, :vsn) |> to_string(),
      node: to_string(Node.self())
    })
  end

  @doc """
  Readiness check with dependency verification.

  Checks:
  - Database connectivity
  - ETS cache availability
  - Oban job queue status
  - Crypto provider initialization

  Returns 200 OK if all dependencies are healthy.
  Returns 503 Service Unavailable if any dependency fails.
  """
  def ready(conn, _params) do
    checks = [
      {"database", &check_database/0},
      {"cache", &check_cache/0},
      {"oban", &check_oban/0},
      {"crypto", &check_crypto/0}
    ]

    results =
      Enum.map(checks, fn {name, check_fn} ->
        try do
          case check_fn.() do
            :ok -> {name, :ok, nil}
            {:error, reason} -> {name, :error, reason}
          end
        rescue
          e -> {name, :error, Exception.message(e)}
        end
      end)

    all_healthy = Enum.all?(results, fn {_, status, _} -> status == :ok end)

    status = if all_healthy, do: :ok, else: :service_unavailable

    conn
    |> put_status(status)
    |> json(%{
      status: if(all_healthy, do: "ok", else: "unhealthy"),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      version: Application.spec(:secure_sharing, :vsn) |> to_string(),
      node: to_string(Node.self()),
      checks:
        Enum.map(results, fn {name, check_status, error} ->
          %{
            name: name,
            status: check_status,
            error: error
          }
        end)
    })
  end

  @doc """
  Cluster status endpoint.

  Returns information about the current node and connected cluster members.
  Useful for debugging cluster connectivity issues.
  """
  def cluster(conn, _params) do
    cluster_info = SecureSharing.Cluster.info()

    conn
    |> put_status(:ok)
    |> json(%{
      status: "ok",
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      cluster: %{
        self: to_string(cluster_info.node),
        connected_nodes: Enum.map(Node.list(), &to_string/1),
        total_nodes: cluster_info.node_count,
        strategy: cluster_info.strategy,
        is_clustered: cluster_info.connected
      }
    })
  end

  @doc """
  Detailed health check with system metrics.

  Includes memory usage, process count, uptime, and cluster information.
  Useful for monitoring and debugging.
  """
  def detailed(conn, _params) do
    checks = [
      {"database", &check_database/0},
      {"cache", &check_cache/0},
      {"oban", &check_oban/0},
      {"crypto", &check_crypto/0}
    ]

    results =
      Enum.map(checks, fn {name, check_fn} ->
        try do
          case check_fn.() do
            :ok -> {name, :ok, nil}
            {:error, reason} -> {name, :error, reason}
          end
        rescue
          e -> {name, :error, Exception.message(e)}
        end
      end)

    all_healthy = Enum.all?(results, fn {_, status, _} -> status == :ok end)
    memory = :erlang.memory()
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    cluster_info = SecureSharing.Cluster.info()

    conn
    |> put_status(if(all_healthy, do: :ok, else: :service_unavailable))
    |> json(%{
      status: if(all_healthy, do: "ok", else: "unhealthy"),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      version: Application.spec(:secure_sharing, :vsn) |> to_string(),
      node: to_string(Node.self()),
      checks:
        Enum.map(results, fn {name, check_status, error} ->
          %{name: name, status: check_status, error: error}
        end),
      cluster: %{
        self: to_string(cluster_info.node),
        connected_nodes: Enum.map(Node.list(), &to_string/1),
        total_nodes: cluster_info.node_count,
        strategy: cluster_info.strategy,
        is_clustered: cluster_info.connected
      },
      system: %{
        otp_release: to_string(:erlang.system_info(:otp_release)),
        elixir_version: System.version(),
        memory_mb: %{
          total: div(memory[:total], 1_048_576),
          processes: div(memory[:processes], 1_048_576),
          ets: div(memory[:ets], 1_048_576),
          binary: div(memory[:binary], 1_048_576)
        },
        process_count: :erlang.system_info(:process_count),
        process_limit: :erlang.system_info(:process_limit),
        uptime_seconds: div(uptime_ms, 1000)
      }
    })
  end

  # Private check functions

  defp check_database do
    case Repo.query("SELECT 1") do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, "Database query failed: #{inspect(reason)}"}
    end
  end

  defp check_cache do
    if Process.whereis(SecureSharing.Cache) do
      try do
        SecureSharing.Cache.stats()
        :ok
      rescue
        e -> {:error, "Cache access failed: #{Exception.message(e)}"}
      end
    else
      {:error, "Cache process not running"}
    end
  end

  defp check_oban do
    case Oban.config() do
      %Oban.Config{} -> :ok
      _ -> {:error, "Oban not configured"}
    end
  rescue
    _ -> {:error, "Oban not running"}
  end

  defp check_crypto do
    if SecureSharing.Crypto.initialized?() do
      :ok
    else
      {:error, "Crypto providers not initialized"}
    end
  rescue
    e -> {:error, "Crypto check failed: #{Exception.message(e)}"}
  end
end
