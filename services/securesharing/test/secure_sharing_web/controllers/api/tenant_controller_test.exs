defmodule SecureSharingWeb.Controllers.Api.TenantControllerTest do
  @moduledoc """
  Tests for multi-tenant operations API endpoints.

  Based on test plan:
  - GET /api/tenants - List user's tenants
  - POST /api/tenant/switch - Switch active tenant
  - DELETE /api/tenants/:id/leave - Leave a tenant
  - GET /api/tenant/config - Get tenant configuration
  - Member management (list, invite, update role, remove)
  - Invitation management (list, accept, decline)
  """
  use SecureSharingWeb.ConnCase, async: true

  import SecureSharing.Factory
  alias SecureSharingWeb.Auth.Token

  # ═══════════════════════════════════════════════════════════════════════════
  # GET /api/tenants
  # ═══════════════════════════════════════════════════════════════════════════

  describe "GET /api/tenants" do
    setup do
      tenant1 = insert(:tenant, name: "Company 1", slug: "company-1")
      tenant2 = insert(:tenant, name: "Company 2", slug: "company-2")
      user = insert(:user, tenant_id: tenant1.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant1.id, role: :admin)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant2.id, role: :member)
      {:ok, tenant1: tenant1, tenant2: tenant2, user: user}
    end

    test "returns all tenants for user", %{conn: conn, user: user, tenant1: tenant1} do
      conn = conn |> authenticate(user, tenant1) |> get(~p"/api/tenants")

      response = json_response(conn, 200)
      assert is_list(response["data"])
      assert length(response["data"]) >= 2

      slugs = Enum.map(response["data"], & &1["slug"])
      assert "company-1" in slugs
      assert "company-2" in slugs
    end

    test "includes role information for each tenant", %{conn: conn, user: user, tenant1: tenant1} do
      conn = conn |> authenticate(user, tenant1) |> get(~p"/api/tenants")

      response = json_response(conn, 200)
      tenant1_data = Enum.find(response["data"], &(&1["slug"] == "company-1"))
      tenant2_data = Enum.find(response["data"], &(&1["slug"] == "company-2"))

      assert tenant1_data["role"] == "admin"
      assert tenant2_data["role"] == "member"
    end

    test "returns 401 for unauthenticated request", %{conn: conn} do
      conn = get(conn, ~p"/api/tenants")

      response = json_response(conn, 401)
      assert response["error"]["code"] == "unauthorized"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # POST /api/tenant/switch
  # ═══════════════════════════════════════════════════════════════════════════

  describe "POST /api/tenant/switch" do
    setup do
      tenant1 = insert(:tenant, name: "Company 1", slug: "company-1")
      tenant2 = insert(:tenant, name: "Company 2", slug: "company-2")
      user = insert(:user, tenant_id: tenant1.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant1.id, role: :admin)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant2.id, role: :member)
      {:ok, tenant1: tenant1, tenant2: tenant2, user: user}
    end

    test "switches to different tenant and returns new tokens", %{
      conn: conn,
      user: user,
      tenant1: tenant1,
      tenant2: tenant2
    } do
      params = %{"tenant_id" => tenant2.id}

      conn = conn |> authenticate(user, tenant1) |> post(~p"/api/tenant/switch", params)

      response = json_response(conn, 200)
      assert response["data"]["current_tenant_id"] == tenant2.id
      assert response["data"]["role"] == "member"
      assert response["data"]["access_token"]
      assert response["data"]["refresh_token"]
    end

    test "returns 403 for tenant user is not member of", %{
      conn: conn,
      user: user,
      tenant1: tenant1
    } do
      other_tenant = insert(:tenant, name: "Other", slug: "other")
      params = %{"tenant_id" => other_tenant.id}

      conn = conn |> authenticate(user, tenant1) |> post(~p"/api/tenant/switch", params)

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end

    test "returns 403 for pending invitation status", %{
      conn: conn,
      user: user,
      tenant1: tenant1
    } do
      pending_tenant = insert(:tenant, name: "Pending", slug: "pending")

      insert(:user_tenant,
        user_id: user.id,
        tenant_id: pending_tenant.id,
        role: :member,
        status: "pending"
      )

      params = %{"tenant_id" => pending_tenant.id}

      conn = conn |> authenticate(user, tenant1) |> post(~p"/api/tenant/switch", params)

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end

    test "returns 401 for unauthenticated request", %{conn: conn, tenant2: tenant2} do
      params = %{"tenant_id" => tenant2.id}

      conn = post(conn, ~p"/api/tenant/switch", params)

      response = json_response(conn, 401)
      assert response["error"]["code"] == "unauthorized"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # DELETE /api/tenants/:id/leave
  # ═══════════════════════════════════════════════════════════════════════════

  describe "DELETE /api/tenants/:id/leave" do
    test "allows member to leave tenant" do
      tenant = insert(:tenant, name: "Test Company")
      owner = insert(:user, tenant_id: tenant.id)
      member = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: owner.id, tenant_id: tenant.id, role: :owner)
      insert(:user_tenant, user_id: member.id, tenant_id: tenant.id, role: :member)

      conn =
        build_conn()
        |> authenticate(member, tenant)
        |> delete(~p"/api/tenants/#{tenant.id}/leave")

      assert response(conn, 204)
    end

    test "prevents only owner from leaving" do
      tenant = insert(:tenant, name: "Test Company")
      owner = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: owner.id, tenant_id: tenant.id, role: :owner)

      conn =
        build_conn()
        |> authenticate(owner, tenant, :owner)
        |> delete(~p"/api/tenants/#{tenant.id}/leave")

      response = json_response(conn, 409)
      assert response["error"]["code"] == "conflict"
    end

    test "allows one of multiple owners to leave" do
      tenant = insert(:tenant, name: "Test Company")
      owner1 = insert(:user, tenant_id: tenant.id)
      owner2 = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: owner1.id, tenant_id: tenant.id, role: :owner)
      insert(:user_tenant, user_id: owner2.id, tenant_id: tenant.id, role: :owner)

      conn =
        build_conn()
        |> authenticate(owner1, tenant, :owner)
        |> delete(~p"/api/tenants/#{tenant.id}/leave")

      assert response(conn, 204)
    end

    test "returns 404 for non-member tenant" do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      other_tenant = insert(:tenant, name: "Other")
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)

      conn =
        build_conn()
        |> authenticate(user, tenant)
        |> delete(~p"/api/tenants/#{other_tenant.id}/leave")

      response = json_response(conn, 404)
      assert response["error"]["code"] == "not_found"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # GET /api/tenant/config
  # ═══════════════════════════════════════════════════════════════════════════

  describe "GET /api/tenant/config" do
    setup do
      tenant = insert(:tenant, name: "Test Company", slug: "test-company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      {:ok, tenant: tenant, user: user}
    end

    test "returns tenant configuration", %{conn: conn, user: user, tenant: tenant} do
      conn = conn |> authenticate(user, tenant) |> get(~p"/api/tenant/config")

      response = json_response(conn, 200)
      assert response["data"]["id"] == tenant.id
      assert response["data"]["name"] == tenant.name
      assert response["data"]["slug"] == tenant.slug
    end

    test "returns 401 for unauthenticated request", %{conn: conn} do
      conn = get(conn, ~p"/api/tenant/config")

      response = json_response(conn, 401)
      assert response["error"]["code"] == "unauthorized"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # GET /api/tenants/:tenant_id/members
  # ═══════════════════════════════════════════════════════════════════════════

  describe "GET /api/tenants/:tenant_id/members" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      admin = insert(:admin_user, tenant_id: tenant.id)
      member = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: admin.id, tenant_id: tenant.id, role: :admin)
      insert(:user_tenant, user_id: member.id, tenant_id: tenant.id, role: :member)
      {:ok, tenant: tenant, admin: admin, member: member}
    end

    test "admin can list members", %{conn: conn, admin: admin, tenant: tenant} do
      conn =
        conn |> authenticate(admin, tenant, :admin) |> get(~p"/api/tenants/#{tenant.id}/members")

      response = json_response(conn, 200)
      assert is_list(response["data"])
      assert length(response["data"]) >= 2
    end

    test "member cannot list members", %{conn: conn, member: member, tenant: tenant} do
      conn = conn |> authenticate(member, tenant) |> get(~p"/api/tenants/#{tenant.id}/members")

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end

    test "returns 403 for other tenant", %{conn: conn, admin: admin, tenant: tenant} do
      other_tenant = insert(:tenant, name: "Other")

      conn =
        conn
        |> authenticate(admin, tenant, :admin)
        |> get(~p"/api/tenants/#{other_tenant.id}/members")

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # POST /api/tenants/:tenant_id/members
  # ═══════════════════════════════════════════════════════════════════════════

  describe "POST /api/tenants/:tenant_id/members" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      admin = insert(:admin_user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: admin.id, tenant_id: tenant.id, role: :admin)
      {:ok, tenant: tenant, admin: admin}
    end

    test "admin can invite existing user", %{conn: conn, admin: admin, tenant: tenant} do
      invitee = insert(:user, tenant_id: nil, email: "invitee@example.com")
      params = %{"email" => invitee.email, "role" => "member"}

      conn =
        conn
        |> authenticate(admin, tenant, :admin)
        |> post(~p"/api/tenants/#{tenant.id}/members", params)

      response = json_response(conn, 200)
      # Response uses TenantJSON.invitation/1 format
      assert response["data"]["email"] == invitee.email
    end

    test "returns 409 for already member", %{conn: conn, admin: admin, tenant: tenant} do
      existing_member = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: existing_member.id, tenant_id: tenant.id, role: :member)
      params = %{"email" => existing_member.email}

      conn =
        conn
        |> authenticate(admin, tenant, :admin)
        |> post(~p"/api/tenants/#{tenant.id}/members", params)

      response = json_response(conn, 409)
      assert response["error"]["code"] == "conflict"
    end

    test "returns 404 for non-existent email", %{conn: conn, admin: admin, tenant: tenant} do
      params = %{"email" => "nonexistent@example.com"}

      conn =
        conn
        |> authenticate(admin, tenant, :admin)
        |> post(~p"/api/tenants/#{tenant.id}/members", params)

      response = json_response(conn, 404)
      assert response["error"]["code"] == "not_found"
    end

    test "member cannot invite users", %{conn: conn, tenant: tenant} do
      member = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: member.id, tenant_id: tenant.id, role: :member)
      invitee = insert(:user, tenant_id: nil, email: "invitee2@example.com")
      params = %{"email" => invitee.email}

      conn =
        conn
        |> authenticate(member, tenant)
        |> post(~p"/api/tenants/#{tenant.id}/members", params)

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # PUT /api/tenants/:tenant_id/members/:user_id/role
  # ═══════════════════════════════════════════════════════════════════════════

  describe "PUT /api/tenants/:tenant_id/members/:user_id/role" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      owner = insert(:user, tenant_id: tenant.id)
      admin = insert(:admin_user, tenant_id: tenant.id)
      member = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: owner.id, tenant_id: tenant.id, role: :owner)
      insert(:user_tenant, user_id: admin.id, tenant_id: tenant.id, role: :admin)
      insert(:user_tenant, user_id: member.id, tenant_id: tenant.id, role: :member)
      {:ok, tenant: tenant, owner: owner, admin: admin, member: member}
    end

    test "owner can update member role", %{
      conn: conn,
      owner: owner,
      tenant: tenant,
      member: member
    } do
      params = %{"role" => "admin"}

      conn =
        conn
        |> authenticate(owner, tenant, :owner)
        |> put(~p"/api/tenants/#{tenant.id}/members/#{member.id}/role", params)

      response = json_response(conn, 200)
      assert response["data"]["role"] == "admin"
    end

    test "admin cannot update roles", %{conn: conn, admin: admin, tenant: tenant, member: member} do
      params = %{"role" => "admin"}

      conn =
        conn
        |> authenticate(admin, tenant, :admin)
        |> put(~p"/api/tenants/#{tenant.id}/members/#{member.id}/role", params)

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end

    test "owner cannot change own role", %{conn: conn, owner: owner, tenant: tenant} do
      params = %{"role" => "member"}

      conn =
        conn
        |> authenticate(owner, tenant, :owner)
        |> put(~p"/api/tenants/#{tenant.id}/members/#{owner.id}/role", params)

      response = json_response(conn, 400)
      assert response["error"]["code"] == "bad_request"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # DELETE /api/tenants/:tenant_id/members/:user_id
  # ═══════════════════════════════════════════════════════════════════════════

  describe "DELETE /api/tenants/:tenant_id/members/:user_id" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      owner = insert(:user, tenant_id: tenant.id)
      admin = insert(:admin_user, tenant_id: tenant.id)
      member = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: owner.id, tenant_id: tenant.id, role: :owner)
      insert(:user_tenant, user_id: admin.id, tenant_id: tenant.id, role: :admin)
      insert(:user_tenant, user_id: member.id, tenant_id: tenant.id, role: :member)
      {:ok, tenant: tenant, owner: owner, admin: admin, member: member}
    end

    test "admin can remove member", %{conn: conn, admin: admin, tenant: tenant, member: member} do
      conn =
        conn
        |> authenticate(admin, tenant, :admin)
        |> delete(~p"/api/tenants/#{tenant.id}/members/#{member.id}")

      assert response(conn, 204)
    end

    test "admin cannot remove owner", %{conn: conn, admin: admin, tenant: tenant, owner: owner} do
      conn =
        conn
        |> authenticate(admin, tenant, :admin)
        |> delete(~p"/api/tenants/#{tenant.id}/members/#{owner.id}")

      response = json_response(conn, 409)
      assert response["error"]["code"] == "conflict"
    end

    test "admin cannot remove self", %{conn: conn, admin: admin, tenant: tenant} do
      conn =
        conn
        |> authenticate(admin, tenant, :admin)
        |> delete(~p"/api/tenants/#{tenant.id}/members/#{admin.id}")

      response = json_response(conn, 400)
      assert response["error"]["code"] == "bad_request"
    end

    test "member cannot remove others", %{
      conn: conn,
      member: member,
      tenant: tenant,
      admin: admin
    } do
      conn =
        conn
        |> authenticate(member, tenant)
        |> delete(~p"/api/tenants/#{tenant.id}/members/#{admin.id}")

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # GET /api/invitations
  # ═══════════════════════════════════════════════════════════════════════════

  describe "GET /api/invitations" do
    setup do
      tenant = insert(:tenant, name: "Current Tenant")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)

      # Create pending invitation to another tenant
      inviting_tenant = insert(:tenant, name: "Inviting Tenant")

      insert(:user_tenant,
        user_id: user.id,
        tenant_id: inviting_tenant.id,
        role: :member,
        status: "pending"
      )

      {:ok, tenant: tenant, user: user, inviting_tenant: inviting_tenant}
    end

    test "returns pending invitations", %{
      conn: conn,
      user: user,
      tenant: tenant,
      inviting_tenant: inviting_tenant
    } do
      conn = conn |> authenticate(user, tenant) |> get(~p"/api/invitations")

      response = json_response(conn, 200)
      assert is_list(response["data"])
      tenant_ids = Enum.map(response["data"], & &1["tenant_id"])
      assert inviting_tenant.id in tenant_ids
    end

    test "returns 401 for unauthenticated request", %{conn: conn} do
      conn = get(conn, ~p"/api/invitations")

      response = json_response(conn, 401)
      assert response["error"]["code"] == "unauthorized"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # POST /api/invitations/:id/accept
  # ═══════════════════════════════════════════════════════════════════════════

  describe "POST /api/invitations/:id/accept" do
    setup do
      current_tenant = insert(:tenant, name: "Current Tenant")
      user = insert(:user, tenant_id: current_tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: current_tenant.id, role: :member)

      inviting_tenant = insert(:tenant, name: "Inviting Tenant")

      invitation =
        insert(:user_tenant,
          user_id: user.id,
          tenant_id: inviting_tenant.id,
          role: :member,
          status: "pending"
        )

      {:ok, current_tenant: current_tenant, user: user, invitation: invitation}
    end

    test "accepts pending invitation", %{
      conn: conn,
      user: user,
      current_tenant: current_tenant,
      invitation: invitation
    } do
      conn =
        conn
        |> authenticate(user, current_tenant)
        |> post(~p"/api/invitations/#{invitation.id}/accept")

      response = json_response(conn, 200)
      assert response["data"]["status"] == "active"
    end

    test "returns 404 for non-existent invitation", %{
      conn: conn,
      user: user,
      current_tenant: current_tenant
    } do
      fake_id = Ecto.UUID.generate()

      conn =
        conn |> authenticate(user, current_tenant) |> post(~p"/api/invitations/#{fake_id}/accept")

      response = json_response(conn, 404)
      assert response["error"]["code"] == "not_found"
    end

    test "returns 403 for other user's invitation", %{conn: conn, current_tenant: current_tenant} do
      other_user = insert(:user, tenant_id: current_tenant.id)
      other_tenant = insert(:tenant, name: "Other")

      other_invitation =
        insert(:user_tenant,
          user_id: other_user.id,
          tenant_id: other_tenant.id,
          status: "pending"
        )

      requester = insert(:user, tenant_id: current_tenant.id)
      insert(:user_tenant, user_id: requester.id, tenant_id: current_tenant.id, role: :member)

      conn =
        conn
        |> authenticate(requester, current_tenant)
        |> post(~p"/api/invitations/#{other_invitation.id}/accept")

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # POST /api/invitations/:id/decline
  # ═══════════════════════════════════════════════════════════════════════════

  describe "POST /api/invitations/:id/decline" do
    setup do
      current_tenant = insert(:tenant, name: "Current Tenant")
      user = insert(:user, tenant_id: current_tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: current_tenant.id, role: :member)

      inviting_tenant = insert(:tenant, name: "Inviting Tenant")

      invitation =
        insert(:user_tenant,
          user_id: user.id,
          tenant_id: inviting_tenant.id,
          role: :member,
          status: "pending"
        )

      {:ok, current_tenant: current_tenant, user: user, invitation: invitation}
    end

    test "declines pending invitation", %{
      conn: conn,
      user: user,
      current_tenant: current_tenant,
      invitation: invitation
    } do
      conn =
        conn
        |> authenticate(user, current_tenant)
        |> post(~p"/api/invitations/#{invitation.id}/decline")

      assert response(conn, 204)
    end

    test "returns 404 for non-existent invitation", %{
      conn: conn,
      user: user,
      current_tenant: current_tenant
    } do
      fake_id = Ecto.UUID.generate()

      conn =
        conn
        |> authenticate(user, current_tenant)
        |> post(~p"/api/invitations/#{fake_id}/decline")

      response = json_response(conn, 404)
      assert response["error"]["code"] == "not_found"
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
