defmodule SecureSharingWeb.Admin.UserLiveTest do
  use SecureSharingWeb.LiveCase, async: true

  describe "Index" do
    setup %{conn: conn} do
      tenant = insert(:tenant)
      admin = insert(:admin_user, tenant_id: tenant.id)
      conn = login_admin(conn, admin)
      {:ok, conn: conn, admin: admin, tenant: tenant}
    end

    test "lists all users", %{conn: conn, admin: admin} do
      {:ok, _view, html} = live(conn, ~p"/admin/users")

      assert html =~ "Users"
      assert html =~ admin.email
    end

    test "shows user status badges", %{conn: conn, tenant: tenant} do
      active_user = insert(:user, tenant_id: tenant.id, status: :active)

      {:ok, _view, html} = live(conn, ~p"/admin/users")

      assert html =~ active_user.email
      assert html =~ "active"
    end

    test "can suspend a user", %{conn: conn, tenant: tenant} do
      user = insert(:user, tenant_id: tenant.id, status: :active)

      {:ok, view, _html} = live(conn, ~p"/admin/users")

      # Use render_click with the event and value directly
      view |> render_click("suspend", %{"id" => user.id})

      # User should now be suspended
      updated_user = SecureSharing.Accounts.get_user!(user.id)
      assert updated_user.status == :suspended
    end

    test "can activate a suspended user", %{conn: conn, tenant: tenant} do
      user = insert(:user, tenant_id: tenant.id, status: :suspended)

      {:ok, view, _html} = live(conn, ~p"/admin/users")

      # Use render_click with the event and value directly
      view |> render_click("activate", %{"id" => user.id})

      # User should now be active
      updated_user = SecureSharing.Accounts.get_user!(user.id)
      assert updated_user.status == :active
    end

    test "can toggle admin status", %{conn: conn, tenant: tenant} do
      user = insert(:user, tenant_id: tenant.id, is_admin: false)

      {:ok, view, _html} = live(conn, ~p"/admin/users")

      # Use render_click with the event and value directly
      view |> render_click("toggle_admin", %{"id" => user.id})

      # User should now be admin
      updated_user = SecureSharing.Accounts.get_user!(user.id)
      assert updated_user.is_admin == true
    end
  end

  describe "Show" do
    setup %{conn: conn} do
      tenant = insert(:tenant)
      admin = insert(:admin_user, tenant_id: tenant.id)
      conn = login_admin(conn, admin)
      {:ok, conn: conn, admin: admin, tenant: tenant}
    end

    test "displays user details", %{conn: conn, admin: admin} do
      {:ok, _view, html} = live(conn, ~p"/admin/users/#{admin}")

      assert html =~ admin.email
      assert html =~ "Details"
      assert html =~ "Email"
      assert html =~ "Status"
      assert html =~ "Admin"
    end

    test "displays storage and share statistics", %{conn: conn, tenant: tenant} do
      user = insert(:user, tenant_id: tenant.id)

      {:ok, _view, html} = live(conn, ~p"/admin/users/#{user}")

      assert html =~ "Storage & Shares"
      assert html =~ "Storage Used"
      assert html =~ "Shares Received"
      assert html =~ "Shares Created"
    end

    test "can suspend user from show page", %{conn: conn, tenant: tenant} do
      user = insert(:user, tenant_id: tenant.id, status: :active)

      {:ok, view, _html} = live(conn, ~p"/admin/users/#{user}")

      assert view |> element("button", "Suspend User") |> render_click()

      updated_user = SecureSharing.Accounts.get_user!(user.id)
      assert updated_user.status == :suspended
    end

    test "can toggle admin from show page", %{conn: conn, tenant: tenant} do
      user = insert(:user, tenant_id: tenant.id, is_admin: false)

      {:ok, view, _html} = live(conn, ~p"/admin/users/#{user}")

      assert view |> element("button", "Make Admin") |> render_click()

      updated_user = SecureSharing.Accounts.get_user!(user.id)
      assert updated_user.is_admin == true
    end
  end
end
