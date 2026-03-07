defmodule SecureSharing.Performance.ApiLatencyTest do
  @moduledoc """
  Performance tests for API latency.

  Tests:
  - Endpoint response time benchmarks
  - P95/P99 latency targets
  - Concurrent request handling
  """
  use SecureSharingWeb.ConnCase, async: false

  import SecureSharing.Factory
  alias SecureSharingWeb.Auth.Token

  # Note: async: false to avoid interference between benchmark tests

  @moduletag :benchmark

  # Target latencies in milliseconds
  @target_p95 500
  @target_p99 1000

  # ═══════════════════════════════════════════════════════════════════════════
  # PERF-API-001: Basic Endpoint Latency
  # ═══════════════════════════════════════════════════════════════════════════

  describe "PERF-API-001: Basic Endpoint Latency" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      {:ok, tenant: tenant, user: user}
    end

    @tag :benchmark
    test "GET /api/me latency", %{user: user, tenant: tenant} do
      latencies =
        measure_latencies(100, fn ->
          build_conn()
          |> authenticate(user, tenant)
          |> get(~p"/api/me")
        end)

      stats = calculate_stats(latencies)

      assert stats.p95 < @target_p95,
             "P95 latency #{stats.p95}ms exceeds target #{@target_p95}ms"

      assert stats.p99 < @target_p99,
             "P99 latency #{stats.p99}ms exceeds target #{@target_p99}ms"

      IO.puts("\n=== GET /api/me Latency Stats ===")
      IO.puts("Min: #{stats.min}ms | Max: #{stats.max}ms | Avg: #{stats.avg}ms")
      IO.puts("P50: #{stats.p50}ms | P95: #{stats.p95}ms | P99: #{stats.p99}ms")
    end

    @tag :benchmark
    test "GET /api/tenants latency", %{user: user, tenant: tenant} do
      latencies =
        measure_latencies(100, fn ->
          build_conn()
          |> authenticate(user, tenant)
          |> get(~p"/api/tenants")
        end)

      stats = calculate_stats(latencies)

      assert stats.p95 < @target_p95
      assert stats.p99 < @target_p99

      IO.puts("\n=== GET /api/tenants Latency Stats ===")
      IO.puts("Min: #{stats.min}ms | Max: #{stats.max}ms | Avg: #{stats.avg}ms")
      IO.puts("P50: #{stats.p50}ms | P95: #{stats.p95}ms | P99: #{stats.p99}ms")
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # PERF-API-002: List Endpoints with Pagination
  # ═══════════════════════════════════════════════════════════════════════════

  describe "PERF-API-002: List Endpoints with Pagination" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)

      # Create multiple folders
      root = insert(:root_folder, owner_id: user.id, tenant_id: tenant.id)

      for _ <- 1..50,
          do: insert(:folder, owner_id: user.id, tenant_id: tenant.id, parent_id: root.id)

      {:ok, tenant: tenant, user: user, root: root}
    end

    @tag :benchmark
    test "GET /api/folders latency with pagination", %{user: user, tenant: tenant} do
      latencies =
        measure_latencies(50, fn ->
          build_conn()
          |> authenticate(user, tenant)
          |> get(~p"/api/folders?page=1&page_size=20")
        end)

      stats = calculate_stats(latencies)

      assert stats.p95 < @target_p95
      assert stats.p99 < @target_p99

      IO.puts("\n=== GET /api/folders (paginated) Latency Stats ===")
      IO.puts("Min: #{stats.min}ms | Max: #{stats.max}ms | Avg: #{stats.avg}ms")
      IO.puts("P50: #{stats.p50}ms | P95: #{stats.p95}ms | P99: #{stats.p99}ms")
    end

    @tag :benchmark
    test "GET /api/folders/:id/children latency", %{user: user, tenant: tenant, root: root} do
      latencies =
        measure_latencies(50, fn ->
          build_conn()
          |> authenticate(user, tenant)
          |> get(~p"/api/folders/#{root.id}/children")
        end)

      stats = calculate_stats(latencies)

      assert stats.p95 < @target_p95
      assert stats.p99 < @target_p99

      IO.puts("\n=== GET /api/folders/:id/children Latency Stats ===")
      IO.puts("Min: #{stats.min}ms | Max: #{stats.max}ms | Avg: #{stats.avg}ms")
      IO.puts("P50: #{stats.p50}ms | P95: #{stats.p95}ms | P99: #{stats.p99}ms")
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # PERF-API-003: File Operations
  # ═══════════════════════════════════════════════════════════════════════════

  describe "PERF-API-003: File Operations" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)

      root = insert(:root_folder, owner_id: user.id, tenant_id: tenant.id)

      files =
        for _ <- 1..20,
            do: insert(:file, owner_id: user.id, tenant_id: tenant.id, folder_id: root.id)

      {:ok, tenant: tenant, user: user, root: root, files: files}
    end

    @tag :benchmark
    test "GET /api/files/:id latency", %{user: user, tenant: tenant, files: files} do
      file = hd(files)

      latencies =
        measure_latencies(100, fn ->
          build_conn()
          |> authenticate(user, tenant)
          |> get(~p"/api/files/#{file.id}")
        end)

      stats = calculate_stats(latencies)

      assert stats.p95 < @target_p95
      assert stats.p99 < @target_p99

      IO.puts("\n=== GET /api/files/:id Latency Stats ===")
      IO.puts("Min: #{stats.min}ms | Max: #{stats.max}ms | Avg: #{stats.avg}ms")
      IO.puts("P50: #{stats.p50}ms | P95: #{stats.p95}ms | P99: #{stats.p99}ms")
    end

    @tag :benchmark
    test "GET /api/folders/:id/files latency", %{user: user, tenant: tenant, root: root} do
      latencies =
        measure_latencies(50, fn ->
          build_conn()
          |> authenticate(user, tenant)
          |> get(~p"/api/folders/#{root.id}/files")
        end)

      stats = calculate_stats(latencies)

      assert stats.p95 < @target_p95
      assert stats.p99 < @target_p99

      IO.puts("\n=== GET /api/folders/:id/files Latency Stats ===")
      IO.puts("Min: #{stats.min}ms | Max: #{stats.max}ms | Avg: #{stats.avg}ms")
      IO.puts("P50: #{stats.p50}ms | P95: #{stats.p95}ms | P99: #{stats.p99}ms")
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # PERF-API-004: Authentication Latency
  # ═══════════════════════════════════════════════════════════════════════════

  describe "PERF-API-004: Authentication Latency" do
    setup do
      tenant = insert(:tenant, name: "Test Company", slug: "test-company")
      user = insert(:user_with_password, tenant_id: tenant.id, email: "user@example.com")
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      {:ok, tenant: tenant, user: user}
    end

    @tag :benchmark
    test "POST /api/auth/login latency", %{tenant: tenant, user: user} do
      params = %{
        "email" => user.email,
        "password" => "test_password_123",
        "tenant_slug" => tenant.slug
      }

      # Fewer iterations to avoid rate limiting
      latencies =
        measure_latencies(5, fn ->
          build_conn()
          |> post(~p"/api/auth/login", params)
        end)

      stats = calculate_stats(latencies)

      # Auth endpoints may be slower due to password hashing
      assert stats.p95 < @target_p95 * 2

      IO.puts("\n=== POST /api/auth/login Latency Stats ===")
      IO.puts("Min: #{stats.min}ms | Max: #{stats.max}ms | Avg: #{stats.avg}ms")
      IO.puts("P50: #{stats.p50}ms | P95: #{stats.p95}ms | P99: #{stats.p99}ms")
    end

    @tag :benchmark
    test "POST /api/auth/refresh latency", %{user: user, tenant: tenant} do
      {:ok, refresh_token} = Token.generate_refresh_token(user, tenant.id)

      latencies =
        measure_latencies(50, fn ->
          build_conn()
          |> post(~p"/api/auth/refresh", %{"refresh_token" => refresh_token})
        end)

      stats = calculate_stats(latencies)

      assert stats.p95 < @target_p95

      IO.puts("\n=== POST /api/auth/refresh Latency Stats ===")
      IO.puts("Min: #{stats.min}ms | Max: #{stats.max}ms | Avg: #{stats.avg}ms")
      IO.puts("P50: #{stats.p50}ms | P95: #{stats.p95}ms | P99: #{stats.p99}ms")
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Helper Functions
  # ═══════════════════════════════════════════════════════════════════════════

  defp authenticate(conn, user, tenant, role \\ :member) do
    {:ok, token} = Token.generate_access_token(user, tenant.id, role)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  defp measure_latencies(iterations, request_fn) do
    1..iterations
    |> Enum.map(fn _ ->
      {time_us, _result} = :timer.tc(request_fn)
      time_us / 1000
    end)
  end

  defp calculate_stats(latencies) do
    sorted = Enum.sort(latencies)
    count = length(sorted)

    %{
      min: Float.round(Enum.min(latencies), 2),
      max: Float.round(Enum.max(latencies), 2),
      avg: Float.round(Enum.sum(latencies) / count, 2),
      p50: Float.round(percentile(sorted, 50), 2),
      p95: Float.round(percentile(sorted, 95), 2),
      p99: Float.round(percentile(sorted, 99), 2)
    }
  end

  defp percentile(sorted_list, p) do
    count = length(sorted_list)
    index = round(p / 100 * count) - 1
    index = max(0, min(index, count - 1))
    Enum.at(sorted_list, index)
  end
end
