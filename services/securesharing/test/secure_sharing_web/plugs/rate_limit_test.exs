defmodule SecureSharingWeb.Plugs.RateLimitTest do
  @moduledoc """
  Tests for the RateLimit plug.

  Note: These tests require Hammer to be running. Tests are tagged with :rate_limit
  and excluded by default. Run with: mix test --include rate_limit
  """

  use SecureSharingWeb.ConnCase, async: false

  alias SecureSharingWeb.Plugs.RateLimit

  # Tag these tests to be excluded by default
  @moduletag :rate_limit

  setup do
    # Enable rate limiting for tests
    original = Application.get_env(:secure_sharing, :rate_limit_enabled)
    Application.put_env(:secure_sharing, :rate_limit_enabled, true)

    on_exit(fn ->
      if original do
        Application.put_env(:secure_sharing, :rate_limit_enabled, original)
      else
        Application.delete_env(:secure_sharing, :rate_limit_enabled)
      end

      # Clean up Hammer buckets
      Hammer.delete_buckets("rate_limit:127.0.0.1:/test")
      Hammer.delete_buckets("rate_limit:192.168.1.1:/test")
    end)

    :ok
  end

  describe "init/1" do
    test "sets default options" do
      opts = RateLimit.init([])

      assert opts.scale == 60_000
      assert opts.limit == 100
      assert opts.by == :ip
    end

    test "accepts custom scale" do
      opts = RateLimit.init(scale: 30_000)

      assert opts.scale == 30_000
    end

    test "accepts custom limit" do
      opts = RateLimit.init(limit: 50)

      assert opts.limit == 50
    end

    test "accepts custom rate limit strategy" do
      opts = RateLimit.init(by: :user)

      assert opts.by == :user
    end

    test "accepts all custom options" do
      opts = RateLimit.init(scale: 120_000, limit: 200, by: :user)

      assert opts.scale == 120_000
      assert opts.limit == 200
      assert opts.by == :user
    end
  end

  describe "call/2 when rate limiting is disabled" do
    setup do
      Application.put_env(:secure_sharing, :rate_limit_enabled, false)
      :ok
    end

    test "passes through without rate limiting", %{conn: conn} do
      opts = RateLimit.init(limit: 1)

      # Should pass through multiple times even with limit of 1
      conn1 =
        conn
        |> Map.put(:request_path, "/test")
        |> RateLimit.call(opts)

      refute conn1.halted

      conn2 =
        conn
        |> Map.put(:request_path, "/test")
        |> RateLimit.call(opts)

      refute conn2.halted
    end
  end

  describe "call/2 with IP-based rate limiting" do
    test "allows requests under the limit", %{conn: conn} do
      opts = RateLimit.init(scale: 60_000, limit: 5, by: :ip)

      conn =
        conn
        |> Map.put(:request_path, "/test")
        |> Map.put(:remote_ip, {127, 0, 0, 1})
        |> RateLimit.call(opts)

      refute conn.halted
    end

    test "returns 429 when limit is exceeded", %{conn: conn} do
      opts = RateLimit.init(scale: 60_000, limit: 2, by: :ip)

      base_conn =
        conn
        |> Map.put(:request_path, "/test")
        |> Map.put(:remote_ip, {192, 168, 1, 1})

      # First two requests should pass
      conn1 = RateLimit.call(base_conn, opts)
      refute conn1.halted

      conn2 = RateLimit.call(base_conn, opts)
      refute conn2.halted

      # Third request should be rate limited
      conn3 = RateLimit.call(base_conn, opts)
      assert conn3.halted
      assert conn3.status == 429
      assert get_resp_header(conn3, "retry-after") == ["60"]
    end

    test "uses x-forwarded-for header when present", %{conn: conn} do
      opts = RateLimit.init(scale: 60_000, limit: 1, by: :ip)

      conn =
        conn
        |> Map.put(:request_path, "/test-forwarded")
        |> Map.put(:remote_ip, {127, 0, 0, 1})
        |> put_req_header("x-forwarded-for", "10.0.0.1, 192.168.1.1")
        |> RateLimit.call(opts)

      refute conn.halted

      # Cleanup the forwarded IP bucket
      Hammer.delete_buckets("rate_limit:10.0.0.1:/test-forwarded")
    end
  end

  describe "call/2 with user-based rate limiting" do
    test "uses user ID when authenticated", %{conn: conn} do
      opts = RateLimit.init(scale: 60_000, limit: 2, by: :user)

      user = %{id: "user-123"}

      base_conn =
        conn
        |> Map.put(:request_path, "/test-user")
        |> Map.put(:remote_ip, {127, 0, 0, 1})
        |> assign(:current_user, user)

      # First two requests should pass
      conn1 = RateLimit.call(base_conn, opts)
      refute conn1.halted

      conn2 = RateLimit.call(base_conn, opts)
      refute conn2.halted

      # Third request should be rate limited
      conn3 = RateLimit.call(base_conn, opts)
      assert conn3.halted
      assert conn3.status == 429

      # Cleanup
      Hammer.delete_buckets("rate_limit:user-123:/test-user")
    end

    test "falls back to IP when user not authenticated", %{conn: conn} do
      opts = RateLimit.init(scale: 60_000, limit: 1, by: :user)

      conn =
        conn
        |> Map.put(:request_path, "/test-fallback")
        |> Map.put(:remote_ip, {127, 0, 0, 2})
        |> RateLimit.call(opts)

      refute conn.halted

      # Cleanup
      Hammer.delete_buckets("rate_limit:127.0.0.2:/test-fallback")
    end
  end
end
