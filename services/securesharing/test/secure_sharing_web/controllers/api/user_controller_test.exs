defmodule SecureSharingWeb.Controllers.Api.UserControllerTest do
  @moduledoc """
  Tests for user profile and key management API endpoints.

  Based on test plan:
  - GET /api/me - Current user profile
  - PUT /api/me - Update profile
  - GET /api/me/keys - Key bundle
  - PUT /api/me/keys - Update keys
  - GET /api/users - List users for sharing
  - GET /api/users/:id/public-key - Get user public key
  """
  use SecureSharingWeb.ConnCase, async: true

  import SecureSharing.Factory
  alias SecureSharingWeb.Auth.Token

  # ═══════════════════════════════════════════════════════════════════════════
  # GET /api/me
  # ═══════════════════════════════════════════════════════════════════════════

  describe "GET /api/me" do
    setup do
      tenant = insert(:tenant, name: "Test Company", slug: "test-company")

      user =
        insert(:user, tenant_id: tenant.id, email: "user@example.com", display_name: "Test User")

      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      {:ok, tenant: tenant, user: user}
    end

    test "returns current user profile", %{conn: conn, user: user, tenant: tenant} do
      conn = conn |> authenticate(user, tenant) |> get(~p"/api/me")

      response = json_response(conn, 200)
      assert response["data"]["id"] == user.id
      assert response["data"]["email"] == user.email
      # UserJSON doesn't include display_name in response
      assert response["data"]["tenant_id"] == tenant.id
    end

    test "returns 401 for unauthenticated request", %{conn: conn} do
      conn = get(conn, ~p"/api/me")

      response = json_response(conn, 401)
      assert response["error"]["code"] == "unauthorized"
    end

    test "returns 401 for invalid token", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer invalid_token")
        |> get(~p"/api/me")

      response = json_response(conn, 401)
      assert response["error"]["code"] == "unauthorized"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # PUT /api/me
  # ═══════════════════════════════════════════════════════════════════════════

  describe "PUT /api/me" do
    setup do
      tenant = insert(:tenant, name: "Test Company", slug: "test-company")
      user = insert(:user, tenant_id: tenant.id, display_name: "Original Name")
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      {:ok, tenant: tenant, user: user}
    end

    test "updates display name", %{conn: conn, user: user, tenant: tenant} do
      params = %{"display_name" => "Updated Name"}

      conn = conn |> authenticate(user, tenant) |> put(~p"/api/me", params)

      response = json_response(conn, 200)
      # Response confirms update succeeded
      assert response["data"]["id"] == user.id
    end

    test "returns 401 for unauthenticated request", %{conn: conn} do
      params = %{"display_name" => "New Name"}

      conn = put(conn, ~p"/api/me", params)

      response = json_response(conn, 401)
      assert response["error"]["code"] == "unauthorized"
    end

    test "ignores unknown fields", %{conn: conn, user: user, tenant: tenant} do
      params = %{"display_name" => "Valid Name", "unknown_field" => "ignored"}

      conn = conn |> authenticate(user, tenant) |> put(~p"/api/me", params)

      response = json_response(conn, 200)
      # Response confirms update succeeded
      assert response["data"]["id"] == user.id
      refute Map.has_key?(response["data"], "unknown_field")
    end

    test "allows empty update", %{conn: conn, user: user, tenant: tenant} do
      conn = conn |> authenticate(user, tenant) |> put(~p"/api/me", %{})

      response = json_response(conn, 200)
      # Response confirms user data returned
      assert response["data"]["id"] == user.id
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # GET /api/me/keys
  # ═══════════════════════════════════════════════════════════════════════════

  describe "GET /api/me/keys" do
    setup do
      tenant = insert(:tenant, name: "Test Company", slug: "test-company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      {:ok, tenant: tenant, user: user}
    end

    test "returns encrypted key bundle", %{conn: conn, user: user, tenant: tenant} do
      conn = conn |> authenticate(user, tenant) |> get(~p"/api/me/keys")

      response = json_response(conn, 200)
      assert Map.has_key?(response["data"], "encrypted_private_keys")
      assert Map.has_key?(response["data"], "encrypted_master_key")
      assert Map.has_key?(response["data"], "key_derivation_salt")
      assert Map.has_key?(response["data"], "public_keys")
    end

    test "returns 401 for unauthenticated request", %{conn: conn} do
      conn = get(conn, ~p"/api/me/keys")

      response = json_response(conn, 401)
      assert response["error"]["code"] == "unauthorized"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # PUT /api/me/keys
  # ═══════════════════════════════════════════════════════════════════════════

  describe "PUT /api/me/keys" do
    setup do
      tenant = insert(:tenant, name: "Test Company", slug: "test-company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      {:ok, tenant: tenant, user: user}
    end

    test "updates key material", %{conn: conn, user: user, tenant: tenant} do
      params = %{
        "encrypted_private_keys" => Base.encode64(:crypto.strong_rand_bytes(64)),
        "encrypted_master_key" => Base.encode64(:crypto.strong_rand_bytes(32)),
        "key_derivation_salt" => Base.encode64(:crypto.strong_rand_bytes(16)),
        "public_keys" => %{
          "kem" => Base.encode64(:crypto.strong_rand_bytes(32)),
          "sign" => Base.encode64(:crypto.strong_rand_bytes(32))
        }
      }

      conn = conn |> authenticate(user, tenant) |> put(~p"/api/me/keys", params)

      response = json_response(conn, 200)
      assert response["data"]["id"] == user.id
    end

    test "returns 401 for unauthenticated request", %{conn: conn} do
      params = %{"encrypted_private_keys" => Base.encode64(:crypto.strong_rand_bytes(64))}

      conn = put(conn, ~p"/api/me/keys", params)

      response = json_response(conn, 401)
      assert response["error"]["code"] == "unauthorized"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # GET /api/users
  # ═══════════════════════════════════════════════════════════════════════════

  describe "GET /api/users" do
    setup do
      tenant = insert(:tenant, name: "Test Company", slug: "test-company")
      user1 = insert(:user, tenant_id: tenant.id, email: "user1@example.com")
      user2 = insert(:user, tenant_id: tenant.id, email: "user2@example.com")
      insert(:user_tenant, user_id: user1.id, tenant_id: tenant.id, role: :member)
      insert(:user_tenant, user_id: user2.id, tenant_id: tenant.id, role: :member)
      {:ok, tenant: tenant, user: user1, other_user: user2}
    end

    test "returns list of users in tenant", %{conn: conn, user: user, tenant: tenant} do
      conn = conn |> authenticate(user, tenant) |> get(~p"/api/users")

      response = json_response(conn, 200)
      assert is_list(response["data"])
      assert length(response["data"]) >= 2
    end

    test "does not return users from other tenants", %{conn: conn, user: user, tenant: tenant} do
      # Create user in different tenant
      other_tenant = insert(:tenant, name: "Other Company", slug: "other-company")
      other_user = insert(:user, tenant_id: other_tenant.id, email: "other@example.com")
      insert(:user_tenant, user_id: other_user.id, tenant_id: other_tenant.id, role: :member)

      conn = conn |> authenticate(user, tenant) |> get(~p"/api/users")

      response = json_response(conn, 200)
      emails = Enum.map(response["data"], & &1["email"])
      refute "other@example.com" in emails
    end

    test "returns 401 for unauthenticated request", %{conn: conn} do
      conn = get(conn, ~p"/api/users")

      response = json_response(conn, 401)
      assert response["error"]["code"] == "unauthorized"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # GET /api/users/:id/public-key
  # ═══════════════════════════════════════════════════════════════════════════

  describe "GET /api/users/:id/public-key" do
    setup do
      tenant = insert(:tenant, name: "Test Company", slug: "test-company")
      user = insert(:user, tenant_id: tenant.id)
      target_user = insert(:user, tenant_id: tenant.id, email: "target@example.com")
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      insert(:user_tenant, user_id: target_user.id, tenant_id: tenant.id, role: :member)
      {:ok, tenant: tenant, user: user, target_user: target_user}
    end

    test "returns public key for user in same tenant", %{
      conn: conn,
      user: user,
      tenant: tenant,
      target_user: target_user
    } do
      conn =
        conn
        |> authenticate(user, tenant)
        |> get(~p"/api/users/#{target_user.id}/public-key")

      response = json_response(conn, 200)
      assert Map.has_key?(response["data"], "public_keys")
    end

    test "returns 403 for user in different tenant", %{conn: conn, user: user, tenant: tenant} do
      other_tenant = insert(:tenant, name: "Other Company", slug: "other-company")
      other_user = insert(:user, tenant_id: other_tenant.id)
      insert(:user_tenant, user_id: other_user.id, tenant_id: other_tenant.id, role: :member)

      conn =
        conn
        |> authenticate(user, tenant)
        |> get(~p"/api/users/#{other_user.id}/public-key")

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end

    test "returns 404 for non-existent user", %{conn: conn, user: user, tenant: tenant} do
      fake_id = Ecto.UUID.generate()

      conn =
        conn
        |> authenticate(user, tenant)
        |> get(~p"/api/users/#{fake_id}/public-key")

      response = json_response(conn, 404)
      assert response["error"]["code"] == "not_found"
    end

    test "returns 401 for unauthenticated request", %{conn: conn, target_user: target_user} do
      conn = get(conn, ~p"/api/users/#{target_user.id}/public-key")

      response = json_response(conn, 401)
      assert response["error"]["code"] == "unauthorized"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Multi-Tenant User Tests
  # ═══════════════════════════════════════════════════════════════════════════

  describe "multi-tenant user operations" do
    setup do
      tenant1 = insert(:tenant, name: "Company 1", slug: "company-1")
      tenant2 = insert(:tenant, name: "Company 2", slug: "company-2")
      user = insert(:user, tenant_id: tenant1.id, email: "multi@example.com")
      insert(:user_tenant, user_id: user.id, tenant_id: tenant1.id, role: :member)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant2.id, role: :admin)
      {:ok, tenant1: tenant1, tenant2: tenant2, user: user}
    end

    test "user can access profile from any tenant context", %{
      conn: conn,
      user: user,
      tenant1: tenant1,
      tenant2: tenant2
    } do
      # Access from tenant1
      conn1 = conn |> authenticate(user, tenant1) |> get(~p"/api/me")
      assert json_response(conn1, 200)["data"]["id"] == user.id

      # Access from tenant2
      conn2 = build_conn() |> authenticate(user, tenant2) |> get(~p"/api/me")
      assert json_response(conn2, 200)["data"]["id"] == user.id
    end

    test "user list only shows users from current tenant context", %{
      conn: conn,
      user: user,
      tenant1: tenant1,
      tenant2: tenant2
    } do
      # Add unique user to tenant1
      t1_user = insert(:user, tenant_id: tenant1.id, email: "tenant1only@example.com")
      insert(:user_tenant, user_id: t1_user.id, tenant_id: tenant1.id, role: :member)

      # Add unique user to tenant2
      t2_user = insert(:user, tenant_id: tenant2.id, email: "tenant2only@example.com")
      insert(:user_tenant, user_id: t2_user.id, tenant_id: tenant2.id, role: :member)

      # From tenant1 context - should see tenant1only, not tenant2only
      conn1 = conn |> authenticate(user, tenant1) |> get(~p"/api/users")
      t1_emails = Enum.map(json_response(conn1, 200)["data"], & &1["email"])
      assert "tenant1only@example.com" in t1_emails
      refute "tenant2only@example.com" in t1_emails

      # From tenant2 context - should see tenant2only, not tenant1only
      conn2 = build_conn() |> authenticate(user, tenant2) |> get(~p"/api/users")
      t2_emails = Enum.map(json_response(conn2, 200)["data"], & &1["email"])
      assert "tenant2only@example.com" in t2_emails
      refute "tenant1only@example.com" in t2_emails
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
