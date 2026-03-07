defmodule SecureSharingWeb.Admin.TenantLiveTest do
  use SecureSharingWeb.LiveCase, async: true

  describe "Index" do
    setup %{conn: conn} do
      tenant = insert(:tenant)
      admin = insert(:admin_user, tenant_id: tenant.id)
      # Create user_tenant association for multi-tenant member listing
      insert(:user_tenant, user_id: admin.id, tenant_id: tenant.id, role: :owner)
      conn = login_admin(conn, admin)
      {:ok, conn: conn, admin: admin, tenant: tenant}
    end

    test "lists all tenants", %{conn: conn, tenant: tenant} do
      {:ok, _view, html} = live(conn, ~p"/admin/tenants")

      assert html =~ "Tenants"
      assert html =~ tenant.name
      assert html =~ tenant.slug
    end

    test "opens new tenant modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/tenants")

      assert view |> element("a", "New Tenant") |> render_click()
      assert_patch(view, ~p"/admin/tenants/new")

      assert render(view) =~ "New Tenant"
    end

    test "saves new tenant", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/tenants/new")

      assert view
             |> form("#tenant-form", tenant: %{name: "New Test Tenant", slug: "new-test-tenant"})
             |> render_submit()

      assert_patch(view, ~p"/admin/tenants")
      assert render(view) =~ "Tenant created successfully"
      assert render(view) =~ "New Test Tenant"
    end

    test "opens edit tenant modal", %{conn: conn, tenant: tenant} do
      {:ok, view, _html} = live(conn, ~p"/admin/tenants")

      assert view |> element("a", "Edit") |> render_click()
      assert_patch(view, ~p"/admin/tenants/#{tenant}/edit")

      assert render(view) =~ "Edit Tenant"
    end

    test "updates tenant in listing", %{conn: conn, tenant: tenant} do
      {:ok, view, _html} = live(conn, ~p"/admin/tenants/#{tenant}/edit")

      assert view
             |> form("#tenant-form", tenant: %{name: "Updated Tenant Name"})
             |> render_submit()

      assert_patch(view, ~p"/admin/tenants")
      assert render(view) =~ "Tenant updated successfully"
      assert render(view) =~ "Updated Tenant Name"
    end

    test "deletes tenant", %{conn: conn} do
      tenant_to_delete = insert(:tenant, name: "Tenant To Delete")

      {:ok, view, _html} = live(conn, ~p"/admin/tenants")

      assert render(view) =~ "Tenant To Delete"

      # Use render_click with the event and value directly
      view |> render_click("delete", %{"id" => tenant_to_delete.id})

      refute render(view) =~ "Tenant To Delete"
    end
  end

  describe "Show" do
    setup %{conn: conn} do
      tenant = insert(:tenant)
      admin = insert(:admin_user, tenant_id: tenant.id)
      # Create user_tenant association for multi-tenant member listing
      insert(:user_tenant, user_id: admin.id, tenant_id: tenant.id, role: :owner)
      conn = login_admin(conn, admin)
      {:ok, conn: conn, admin: admin, tenant: tenant}
    end

    test "displays tenant details", %{conn: conn, tenant: tenant} do
      {:ok, _view, html} = live(conn, ~p"/admin/tenants/#{tenant}")

      assert html =~ tenant.name
      assert html =~ tenant.slug
      assert html =~ "Details"
      assert html =~ "Storage Quota"
      assert html =~ "Max Users"
    end

    test "lists members in tenant", %{conn: conn, tenant: tenant, admin: admin} do
      {:ok, _view, html} = live(conn, ~p"/admin/tenants/#{tenant}")

      # Should show the admin user in the members list
      assert html =~ admin.email
      assert html =~ "Members"
    end

    test "navigates to edit from show page", %{conn: conn, tenant: tenant} do
      {:ok, view, _html} = live(conn, ~p"/admin/tenants/#{tenant}")

      assert view |> element("a", "Edit tenant") |> render_click()
      assert_patch(view, ~p"/admin/tenants/#{tenant}/edit")
    end
  end
end
