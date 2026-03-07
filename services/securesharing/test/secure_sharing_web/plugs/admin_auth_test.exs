defmodule SecureSharingWeb.Plugs.AdminAuthTest do
  @moduledoc """
  Tests for the AdminAuth plug.

  Tests admin authentication via session and token.
  """

  use SecureSharingWeb.ConnCase, async: true

  import SecureSharing.Factory

  alias SecureSharingWeb.Plugs.AdminAuth
  alias SecureSharingWeb.Auth.Token

  # Helper to setup a conn with session and flash
  defp setup_conn_with_session(conn) do
    # Set up secret_key_base for cookie session
    conn
    |> Map.put(:secret_key_base, String.duplicate("a", 64))
    |> Plug.Conn.fetch_cookies()
    |> Plug.Session.call(
      Plug.Session.init(store: :cookie, key: "_test_key", signing_salt: "test")
    )
    |> Plug.Conn.fetch_session()
    |> Phoenix.Controller.fetch_flash([])
  end

  describe "init/1" do
    test "returns opts unchanged" do
      opts = [some: :option]
      assert AdminAuth.init(opts) == opts
    end
  end

  describe "call/2 with session authentication" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      admin = insert(:admin_user, tenant_id: tenant.id)
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: admin.id, tenant_id: tenant.id, role: :owner)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)

      {:ok, tenant: tenant, admin: admin, user: user}
    end

    test "allows admin user from session", %{conn: conn, admin: admin} do
      opts = AdminAuth.init([])

      conn =
        conn
        |> setup_conn_with_session()
        |> Plug.Conn.put_session(:current_user, admin)
        |> AdminAuth.call(opts)

      refute conn.halted
      assert conn.assigns.current_user.id == admin.id
    end

    test "redirects non-admin user from session to home", %{conn: conn, user: user} do
      opts = AdminAuth.init([])

      conn =
        conn
        |> setup_conn_with_session()
        |> Plug.Conn.put_session(:current_user, user)
        |> AdminAuth.call(opts)

      assert conn.halted
      assert redirected_to(conn) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "administrator"
    end
  end

  describe "call/2 with token authentication" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      admin = insert(:admin_user, tenant_id: tenant.id)
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: admin.id, tenant_id: tenant.id, role: :owner)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)

      {:ok, tenant: tenant, admin: admin, user: user}
    end

    test "allows admin user with valid token", %{conn: conn, admin: admin, tenant: tenant} do
      {:ok, tokens} = Token.generate_tokens(admin, tenant.id, :owner)
      opts = AdminAuth.init([])

      conn =
        conn
        |> setup_conn_with_session()
        |> put_req_header("authorization", "Bearer #{tokens.access_token}")
        |> AdminAuth.call(opts)

      refute conn.halted
      assert conn.assigns.current_user.id == admin.id
    end

    test "redirects non-admin user with valid token", %{conn: conn, user: user, tenant: tenant} do
      {:ok, tokens} = Token.generate_tokens(user, tenant.id, :member)
      opts = AdminAuth.init([])

      conn =
        conn
        |> setup_conn_with_session()
        |> put_req_header("authorization", "Bearer #{tokens.access_token}")
        |> AdminAuth.call(opts)

      assert conn.halted
      assert redirected_to(conn) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "administrator"
    end

    test "redirects with invalid token", %{conn: conn} do
      opts = AdminAuth.init([])

      conn =
        conn
        |> setup_conn_with_session()
        |> put_req_header("authorization", "Bearer invalid-token")
        |> AdminAuth.call(opts)

      assert conn.halted
      assert redirected_to(conn) == "/admin/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "logged in"
    end
  end

  describe "call/2 without authentication" do
    test "redirects when no session or token", %{conn: conn} do
      opts = AdminAuth.init([])

      conn =
        conn
        |> setup_conn_with_session()
        |> AdminAuth.call(opts)

      assert conn.halted
      assert redirected_to(conn) == "/admin/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "logged in"
    end

    test "redirects with malformed authorization header", %{conn: conn} do
      opts = AdminAuth.init([])

      conn =
        conn
        |> setup_conn_with_session()
        |> put_req_header("authorization", "Basic some-basic-auth")
        |> AdminAuth.call(opts)

      assert conn.halted
      assert redirected_to(conn) == "/admin/login"
    end
  end
end
