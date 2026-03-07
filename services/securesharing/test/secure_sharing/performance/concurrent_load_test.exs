defmodule SecureSharing.Performance.ConcurrentLoadTest do
  @moduledoc """
  Performance tests for concurrent load handling.

  Tests:
  - Parallel request handling
  - Connection pool behavior
  - Resource contention
  """
  use SecureSharingWeb.ConnCase, async: false

  import SecureSharing.Factory
  alias SecureSharingWeb.Auth.Token

  @moduletag :benchmark

  # ═══════════════════════════════════════════════════════════════════════════
  # PERF-LOAD-001: Parallel Request Handling
  # ═══════════════════════════════════════════════════════════════════════════

  describe "PERF-LOAD-001: Parallel Request Handling" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      {:ok, tenant: tenant, user: user}
    end

    @tag :benchmark
    test "handles 50 concurrent requests", %{user: user, tenant: tenant} do
      # Create 50 concurrent tasks
      tasks =
        1..50
        |> Enum.map(fn _ ->
          Task.async(fn ->
            {time_us, conn} =
              :timer.tc(fn ->
                build_conn()
                |> authenticate(user, tenant)
                |> get(~p"/api/me")
              end)

            %{status: conn.status, time_ms: time_us / 1000}
          end)
        end)

      results = Task.await_many(tasks, 30_000)

      # All requests should succeed
      success_count = Enum.count(results, &(&1.status == 200))
      error_count = Enum.count(results, &(&1.status >= 500))

      assert error_count == 0, "#{error_count} requests resulted in server errors"
      assert success_count >= 45, "Only #{success_count}/50 requests succeeded"

      # Calculate stats
      times = Enum.map(results, & &1.time_ms)
      avg_time = Enum.sum(times) / length(times)
      max_time = Enum.max(times)

      IO.puts("\n=== 50 Concurrent Requests Stats ===")
      IO.puts("Success: #{success_count}/50 | Errors: #{error_count}")
      IO.puts("Avg Time: #{Float.round(avg_time, 2)}ms | Max Time: #{Float.round(max_time, 2)}ms")
    end

    @tag :benchmark
    test "handles 100 concurrent requests", %{user: user, tenant: tenant} do
      tasks =
        1..100
        |> Enum.map(fn _ ->
          Task.async(fn ->
            {time_us, conn} =
              :timer.tc(fn ->
                build_conn()
                |> authenticate(user, tenant)
                |> get(~p"/api/me")
              end)

            %{status: conn.status, time_ms: time_us / 1000}
          end)
        end)

      results = Task.await_many(tasks, 60_000)

      success_count = Enum.count(results, &(&1.status == 200))
      rate_limited = Enum.count(results, &(&1.status == 429))
      error_count = Enum.count(results, &(&1.status >= 500))

      # No server errors
      assert error_count == 0, "#{error_count} requests resulted in server errors"

      # High success rate (some may be rate limited)
      assert success_count + rate_limited >= 90

      times = Enum.map(results, & &1.time_ms)
      avg_time = Enum.sum(times) / length(times)
      max_time = Enum.max(times)

      IO.puts("\n=== 100 Concurrent Requests Stats ===")

      IO.puts(
        "Success: #{success_count} | Rate Limited: #{rate_limited} | Errors: #{error_count}"
      )

      IO.puts("Avg Time: #{Float.round(avg_time, 2)}ms | Max Time: #{Float.round(max_time, 2)}ms")
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # PERF-LOAD-002: Mixed Workload
  # ═══════════════════════════════════════════════════════════════════════════

  describe "PERF-LOAD-002: Mixed Workload" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)

      root = insert(:root_folder, owner_id: user.id, tenant_id: tenant.id)

      files =
        for _ <- 1..10,
            do: insert(:file, owner_id: user.id, tenant_id: tenant.id, folder_id: root.id)

      {:ok, tenant: tenant, user: user, root: root, files: files}
    end

    @tag :benchmark
    test "handles mixed read workload", %{user: user, tenant: tenant, root: root, files: files} do
      file_ids = Enum.map(files, & &1.id)

      # Mix of different read operations
      operations = [
        fn -> build_conn() |> authenticate(user, tenant) |> get(~p"/api/me") end,
        fn -> build_conn() |> authenticate(user, tenant) |> get(~p"/api/tenants") end,
        fn -> build_conn() |> authenticate(user, tenant) |> get(~p"/api/folders") end,
        fn -> build_conn() |> authenticate(user, tenant) |> get(~p"/api/folders/#{root.id}") end,
        fn ->
          build_conn() |> authenticate(user, tenant) |> get(~p"/api/folders/#{root.id}/files")
        end,
        fn ->
          file_id = Enum.random(file_ids)
          build_conn() |> authenticate(user, tenant) |> get(~p"/api/files/#{file_id}")
        end
      ]

      # Create 60 tasks with random operations
      tasks =
        1..60
        |> Enum.map(fn _ ->
          Task.async(fn ->
            op = Enum.random(operations)

            {time_us, conn} = :timer.tc(op)

            %{status: conn.status, time_ms: time_us / 1000}
          end)
        end)

      results = Task.await_many(tasks, 60_000)

      success_count = Enum.count(results, &(&1.status == 200))
      error_count = Enum.count(results, &(&1.status >= 500))

      assert error_count == 0
      assert success_count >= 55

      times = Enum.map(results, & &1.time_ms)

      IO.puts("\n=== Mixed Workload (60 requests) Stats ===")
      IO.puts("Success: #{success_count}/60 | Errors: #{error_count}")

      IO.puts(
        "Min: #{Float.round(Enum.min(times), 2)}ms | Max: #{Float.round(Enum.max(times), 2)}ms"
      )

      IO.puts("Avg: #{Float.round(Enum.sum(times) / length(times), 2)}ms")
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # PERF-LOAD-003: Sustained Load
  # ═══════════════════════════════════════════════════════════════════════════

  describe "PERF-LOAD-003: Sustained Load" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      {:ok, tenant: tenant, user: user}
    end

    @tag :benchmark
    @tag timeout: 120_000
    test "handles sustained load over time", %{user: user, tenant: tenant} do
      # 5 waves of 20 concurrent requests with small delays
      waves = 5
      requests_per_wave = 20
      wave_delay_ms = 500

      all_results =
        1..waves
        |> Enum.flat_map(fn wave ->
          tasks =
            1..requests_per_wave
            |> Enum.map(fn _ ->
              Task.async(fn ->
                {time_us, conn} =
                  :timer.tc(fn ->
                    build_conn()
                    |> authenticate(user, tenant)
                    |> get(~p"/api/me")
                  end)

                %{wave: wave, status: conn.status, time_ms: time_us / 1000}
              end)
            end)

          results = Task.await_many(tasks, 30_000)

          # Delay between waves
          if wave < waves, do: Process.sleep(wave_delay_ms)

          results
        end)

      # Analyze per-wave performance
      for wave <- 1..waves do
        wave_results = Enum.filter(all_results, &(&1.wave == wave))
        success = Enum.count(wave_results, &(&1.status == 200))
        times = Enum.map(wave_results, & &1.time_ms)
        avg = Enum.sum(times) / length(times)

        IO.puts(
          "Wave #{wave}: #{success}/#{requests_per_wave} success, avg #{Float.round(avg, 2)}ms"
        )
      end

      total_success = Enum.count(all_results, &(&1.status == 200))
      total_errors = Enum.count(all_results, &(&1.status >= 500))
      total_requests = waves * requests_per_wave

      IO.puts("\n=== Sustained Load Summary ===")
      IO.puts("Total: #{total_success}/#{total_requests} success | Errors: #{total_errors}")

      assert total_errors == 0
      assert total_success >= total_requests * 0.9
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # PERF-LOAD-004: Multi-User Concurrent Access
  # ═══════════════════════════════════════════════════════════════════════════

  describe "PERF-LOAD-004: Multi-User Concurrent Access" do
    setup do
      tenant = insert(:tenant, name: "Test Company")

      # Create 10 users
      users =
        for i <- 1..10 do
          user = insert(:user, tenant_id: tenant.id, email: "user#{i}@example.com")
          insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
          user
        end

      {:ok, tenant: tenant, users: users}
    end

    @tag :benchmark
    test "handles concurrent access from multiple users", %{tenant: tenant, users: users} do
      # Each user makes 5 requests concurrently
      tasks =
        users
        |> Enum.flat_map(fn user ->
          1..5
          |> Enum.map(fn _ ->
            Task.async(fn ->
              {time_us, conn} =
                :timer.tc(fn ->
                  build_conn()
                  |> authenticate(user, tenant)
                  |> get(~p"/api/me")
                end)

              %{user_id: user.id, status: conn.status, time_ms: time_us / 1000}
            end)
          end)
        end)

      results = Task.await_many(tasks, 60_000)

      # Check per-user results
      for user <- users do
        user_results = Enum.filter(results, &(&1.user_id == user.id))
        success = Enum.count(user_results, &(&1.status == 200))
        assert success >= 4, "User #{user.email} only had #{success}/5 successful requests"
      end

      total_success = Enum.count(results, &(&1.status == 200))
      total_errors = Enum.count(results, &(&1.status >= 500))

      IO.puts("\n=== Multi-User Concurrent Access ===")
      IO.puts("10 users × 5 requests = 50 total")
      IO.puts("Success: #{total_success} | Errors: #{total_errors}")

      assert total_errors == 0
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Helper Functions
  # ═══════════════════════════════════════════════════════════════════════════

  defp authenticate(conn, user, tenant, role \\ :member) do
    {:ok, token} = Token.generate_access_token(user, tenant.id, role)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end
end
