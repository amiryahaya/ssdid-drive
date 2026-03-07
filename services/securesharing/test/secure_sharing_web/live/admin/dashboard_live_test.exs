defmodule SecureSharingWeb.Admin.DashboardLiveTest do
  use SecureSharingWeb.LiveCase, async: true

  describe "dashboard" do
    test "displays system statistics", %{conn: conn} do
      tenant = insert(:tenant)
      admin = insert(:admin_user, tenant_id: tenant.id)

      conn = login_admin(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/admin")

      # Should show statistics
      assert html =~ "Total Tenants"
      assert html =~ "Total Users"
      assert html =~ "Total Files"
      assert html =~ "Active Shares"
    end

    test "displays recent tenants and users", %{conn: conn} do
      tenant = insert(:tenant, name: "Test Tenant Dashboard")
      admin = insert(:admin_user, tenant_id: tenant.id, email: "admin@dashboard.test")

      conn = login_admin(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/admin")

      # Should show recent tenant
      assert html =~ "Test Tenant Dashboard"
      # Should show admin user
      assert html =~ "admin@dashboard.test"
    end

    test "redirects non-admin to login", %{conn: conn} do
      tenant = insert(:tenant)
      user = insert(:user, tenant_id: tenant.id)

      conn = login_admin(conn, user)

      assert {:error, {:redirect, %{to: "/admin/login"}}} = live(conn, ~p"/admin")
    end

    test "redirects unauthenticated users to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/admin/login"}}} = live(conn, ~p"/admin")
    end
  end
end
