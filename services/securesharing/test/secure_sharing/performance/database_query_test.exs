defmodule SecureSharing.Performance.DatabaseQueryTest do
  @moduledoc """
  Performance tests for database queries.

  Tests:
  - N+1 query detection
  - Index usage verification
  - Large dataset pagination
  - Complex query optimization
  """
  use SecureSharing.DataCase, async: false

  import SecureSharing.Factory
  import Ecto.Query

  alias SecureSharing.Repo
  alias SecureSharing.Files
  alias SecureSharing.Accounts

  @moduletag :benchmark

  # ═══════════════════════════════════════════════════════════════════════════
  # PERF-DB-001: N+1 Query Detection
  # ═══════════════════════════════════════════════════════════════════════════

  describe "PERF-DB-001: N+1 Query Detection" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)

      root = insert(:root_folder, owner_id: user.id, tenant_id: tenant.id)

      # Create 50 folders
      folders =
        for i <- 1..50 do
          insert(:folder, owner_id: user.id, tenant_id: tenant.id, parent_id: root.id)
        end

      {:ok, tenant: tenant, user: user, root: root, folders: folders}
    end

    @tag :benchmark
    test "list_user_folders avoids N+1 queries", %{user: user} do
      # Measure query count
      {query_count, folders} =
        count_queries(fn ->
          Files.list_user_folders(user, %{page: 1, per_page: 50})
          |> Repo.preload(:owner)
        end)

      # Should be constant number of queries (2-3), not 50+
      assert query_count <= 5,
             "Expected <= 5 queries, got #{query_count}. Possible N+1 issue."

      # Verify data is loaded
      assert length(folders) >= 50
      assert Enum.all?(folders, &Ecto.assoc_loaded?(&1.owner))
    end

    @tag :benchmark
    test "list_child_folders avoids N+1 queries", %{root: root} do
      {query_count, folders} =
        count_queries(fn ->
          Files.list_child_folders(root, %{page: 1, per_page: 50})
          |> Repo.preload(:owner)
        end)

      assert query_count <= 5,
             "Expected <= 5 queries, got #{query_count}. Possible N+1 issue."

      assert length(folders) >= 50
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # PERF-DB-002: Large Dataset Pagination
  # ═══════════════════════════════════════════════════════════════════════════

  describe "PERF-DB-002: Large Dataset Pagination" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)

      root = insert(:root_folder, owner_id: user.id, tenant_id: tenant.id)

      # Create 200 files (simulating larger dataset)
      _files =
        for _ <- 1..200 do
          insert(:file, owner_id: user.id, tenant_id: tenant.id, folder_id: root.id)
        end

      {:ok, user: user, root: root}
    end

    @tag :benchmark
    test "pagination queries first page efficiently", %{root: root} do
      {time_us, files} =
        :timer.tc(fn ->
          Files.list_folder_files(root, %{page: 1, per_page: 20})
        end)

      time_ms = time_us / 1000

      # First page should be fast (< 100ms)
      assert time_ms < 100,
             "First page query took #{Float.round(time_ms, 2)}ms, expected < 100ms"

      assert length(files) == 20
    end

    @tag :benchmark
    test "pagination queries last page efficiently", %{root: root} do
      {time_us, files} =
        :timer.tc(fn ->
          Files.list_folder_files(root, %{page: 10, per_page: 20})
        end)

      time_ms = time_us / 1000

      # Last page should also be fast with proper indexing
      assert time_ms < 200,
             "Last page query took #{Float.round(time_ms, 2)}ms, expected < 200ms"

      assert length(files) == 20
    end

    @tag :benchmark
    test "count query is efficient", %{root: root} do
      {time_us, count} =
        :timer.tc(fn ->
          Files.count_folder_files(root)
        end)

      time_ms = time_us / 1000

      # Count should be fast
      assert time_ms < 50,
             "Count query took #{Float.round(time_ms, 2)}ms, expected < 50ms"

      assert count == 200
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # PERF-DB-003: Index Usage Verification
  # ═══════════════════════════════════════════════════════════════════════════

  describe "PERF-DB-003: Index Usage Verification" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id, email: "test@example.com")
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      {:ok, tenant: tenant, user: user}
    end

    @tag :benchmark
    test "user lookup by email uses index", %{user: user} do
      # Warm up the query
      _warm = Accounts.get_user_by_email(user.email)

      {time_us, result} =
        :timer.tc(fn ->
          Accounts.get_user_by_email(user.email)
        end)

      time_ms = time_us / 1000

      # Email lookup should be very fast with index
      assert time_ms < 10,
             "Email lookup took #{Float.round(time_ms, 2)}ms, expected < 10ms"

      assert result.id == user.id
    end

    @tag :benchmark
    test "tenant lookup by slug uses index", %{tenant: tenant} do
      # Warm up
      _warm = Accounts.get_tenant_by_slug(tenant.slug)

      {time_us, result} =
        :timer.tc(fn ->
          Accounts.get_tenant_by_slug(tenant.slug)
        end)

      time_ms = time_us / 1000

      # Slug lookup should be fast with index
      assert time_ms < 10,
             "Slug lookup took #{Float.round(time_ms, 2)}ms, expected < 10ms"

      assert result.id == tenant.id
    end

    @tag :benchmark
    test "folder lookup by id uses index" do
      tenant = insert(:tenant)
      user = insert(:user, tenant_id: tenant.id)
      root = insert(:root_folder, owner_id: user.id, tenant_id: tenant.id)

      # Warm up
      _warm = Files.get_folder(root.id)

      {time_us, result} =
        :timer.tc(fn ->
          Files.get_folder(root.id)
        end)

      time_ms = time_us / 1000

      # ID lookup should be very fast (primary key)
      assert time_ms < 10,
             "ID lookup took #{Float.round(time_ms, 2)}ms, expected < 10ms"

      assert result.id == root.id
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # PERF-DB-004: Complex Query Optimization
  # ═══════════════════════════════════════════════════════════════════════════

  describe "PERF-DB-004: Complex Query Optimization" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      owner = insert(:user, tenant_id: tenant.id)
      grantee = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: owner.id, tenant_id: tenant.id, role: :member)
      insert(:user_tenant, user_id: grantee.id, tenant_id: tenant.id, role: :member)

      root = insert(:root_folder, owner_id: owner.id, tenant_id: tenant.id)

      # Create files and shares
      _shares =
        for _ <- 1..50 do
          file = insert(:file, owner_id: owner.id, tenant_id: tenant.id, folder_id: root.id)
          insert(:file_share, owner_id: owner.id, grantee_id: grantee.id, file_id: file.id)
        end

      {:ok, tenant: tenant, owner: owner, grantee: grantee}
    end

    @tag :benchmark
    test "received shares query is optimized", %{grantee: grantee} do
      {time_us, shares} =
        :timer.tc(fn ->
          SecureSharing.Sharing.list_received_shares(grantee.id, %{page: 1, per_page: 20})
        end)

      time_ms = time_us / 1000

      # Should be fast even with joins
      assert time_ms < 100,
             "Received shares query took #{Float.round(time_ms, 2)}ms, expected < 100ms"

      assert length(shares) == 20
    end

    @tag :benchmark
    test "created shares query is optimized", %{owner: owner} do
      {time_us, shares} =
        :timer.tc(fn ->
          SecureSharing.Sharing.list_created_shares(owner.id, %{page: 1, per_page: 20})
        end)

      time_ms = time_us / 1000

      assert time_ms < 100,
             "Created shares query took #{Float.round(time_ms, 2)}ms, expected < 100ms"

      assert length(shares) == 20
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Helper Functions
  # ═══════════════════════════════════════════════════════════════════════════

  defp count_queries(func) do
    # Use Ecto.LogEntry to count queries
    parent = self()

    # Set up telemetry handler to count queries
    handler_id = :erlang.unique_integer()

    :telemetry.attach(
      "query-counter-#{handler_id}",
      [:secure_sharing, :repo, :query],
      fn _event, _measurements, _metadata, _config ->
        send(parent, :query_executed)
      end,
      nil
    )

    result = func.()

    # Small delay to ensure all telemetry events are received
    Process.sleep(10)

    # Count received messages
    query_count = count_messages(:query_executed, 0)

    # Detach handler
    :telemetry.detach("query-counter-#{handler_id}")

    {query_count, result}
  end

  defp count_messages(msg, acc) do
    receive do
      ^msg -> count_messages(msg, acc + 1)
    after
      0 -> acc
    end
  end
end
