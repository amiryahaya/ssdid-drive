defmodule SecureSharing.Security.AccessControlTest do
  @moduledoc """
  Security tests for access control mechanisms.

  Tests:
  - Cross-tenant data isolation
  - User role enforcement
  - Share permission enforcement
  - Device ownership verification
  - File/folder ownership checks
  """
  use SecureSharingWeb.ConnCase, async: true

  import SecureSharing.Factory
  alias SecureSharingWeb.Auth.Token

  # ═══════════════════════════════════════════════════════════════════════════
  # SEC-001: Cross-Tenant Data Isolation
  # ═══════════════════════════════════════════════════════════════════════════

  describe "SEC-001: Cross-Tenant Data Isolation" do
    setup do
      tenant_a = insert(:tenant, name: "Tenant A", slug: "tenant-a")
      tenant_b = insert(:tenant, name: "Tenant B", slug: "tenant-b")

      user_a = insert(:user, tenant_id: tenant_a.id, email: "user_a@tenant-a.com")
      user_b = insert(:user, tenant_id: tenant_b.id, email: "user_b@tenant-b.com")

      insert(:user_tenant, user_id: user_a.id, tenant_id: tenant_a.id, role: :member)
      insert(:user_tenant, user_id: user_b.id, tenant_id: tenant_b.id, role: :member)

      # Create data in tenant A
      root_a = insert(:root_folder, owner_id: user_a.id, tenant_id: tenant_a.id)
      file_a = insert(:file, owner_id: user_a.id, tenant_id: tenant_a.id, folder_id: root_a.id)

      {:ok,
       tenant_a: tenant_a,
       tenant_b: tenant_b,
       user_a: user_a,
       user_b: user_b,
       root_a: root_a,
       file_a: file_a}
    end

    test "user cannot access files from other tenant", %{
      conn: conn,
      tenant_b: tenant_b,
      user_b: user_b,
      file_a: file_a
    } do
      conn = conn |> authenticate(user_b, tenant_b) |> get(~p"/api/files/#{file_a.id}")

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end

    test "user cannot access folders from other tenant", %{
      conn: conn,
      tenant_b: tenant_b,
      user_b: user_b,
      root_a: root_a
    } do
      conn = conn |> authenticate(user_b, tenant_b) |> get(~p"/api/folders/#{root_a.id}")

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end

    test "user cannot list files in other tenant's folder", %{
      conn: conn,
      tenant_b: tenant_b,
      user_b: user_b,
      root_a: root_a
    } do
      conn = conn |> authenticate(user_b, tenant_b) |> get(~p"/api/folders/#{root_a.id}/files")

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end

    test "user list only shows users from current tenant", %{
      conn: conn,
      tenant_a: tenant_a,
      user_a: user_a,
      user_b: user_b
    } do
      conn = conn |> authenticate(user_a, tenant_a) |> get(~p"/api/users")

      response = json_response(conn, 200)
      emails = Enum.map(response["data"], & &1["email"])
      refute user_b.email in emails
    end

    test "cannot share file with user from different tenant", %{
      conn: conn,
      tenant_a: tenant_a,
      user_a: user_a,
      user_b: user_b,
      file_a: file_a
    } do
      params = %{
        "grantee_id" => user_b.id,
        "file_id" => file_a.id,
        "permission" => "view",
        "wrapped_dek" => Base.encode64(:crypto.strong_rand_bytes(32)),
        "kem_ciphertext" => Base.encode64(:crypto.strong_rand_bytes(64)),
        "signature" => Base.encode64(:crypto.strong_rand_bytes(64))
      }

      conn = conn |> authenticate(user_a, tenant_a) |> post(~p"/api/shares/file", params)

      # Cross-tenant sharing is forbidden, not a "not found" error
      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # SEC-002: User Role Enforcement
  # ═══════════════════════════════════════════════════════════════════════════

  describe "SEC-002: User Role Enforcement" do
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

    test "member cannot list tenant members", %{conn: conn, tenant: tenant, member: member} do
      conn = conn |> authenticate(member, tenant) |> get(~p"/api/tenants/#{tenant.id}/members")

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end

    test "member cannot invite users to tenant", %{conn: conn, tenant: tenant, member: member} do
      invitee = insert(:user, tenant_id: nil, email: "invitee@example.com")
      params = %{"email" => invitee.email, "role" => "member"}

      conn =
        conn
        |> authenticate(member, tenant)
        |> post(~p"/api/tenants/#{tenant.id}/members", params)

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end

    test "admin can list tenant members", %{conn: conn, tenant: tenant, admin: admin} do
      conn =
        conn |> authenticate(admin, tenant, :admin) |> get(~p"/api/tenants/#{tenant.id}/members")

      assert json_response(conn, 200)["data"]
    end

    test "admin cannot change roles (only owner can)", %{
      conn: conn,
      tenant: tenant,
      admin: admin,
      member: member
    } do
      params = %{"role" => "admin"}

      conn =
        conn
        |> authenticate(admin, tenant, :admin)
        |> put(~p"/api/tenants/#{tenant.id}/members/#{member.id}/role", params)

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end

    test "owner can change roles", %{conn: conn, tenant: tenant, owner: owner, member: member} do
      params = %{"role" => "admin"}

      conn =
        conn
        |> authenticate(owner, tenant, :owner)
        |> put(~p"/api/tenants/#{tenant.id}/members/#{member.id}/role", params)

      response = json_response(conn, 200)
      assert response["data"]["role"] == "admin"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # SEC-003: Share Permission Enforcement
  # ═══════════════════════════════════════════════════════════════════════════

  describe "SEC-003: Share Permission Enforcement" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      owner = insert(:user, tenant_id: tenant.id)
      viewer = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: owner.id, tenant_id: tenant.id, role: :member)
      insert(:user_tenant, user_id: viewer.id, tenant_id: tenant.id, role: :member)

      root = insert(:root_folder, owner_id: owner.id, tenant_id: tenant.id)
      shared_file = insert(:file, owner_id: owner.id, tenant_id: tenant.id, folder_id: root.id)

      # Share with read permission only
      share =
        insert(:file_share,
          tenant_id: tenant.id,
          grantor_id: owner.id,
          grantee_id: viewer.id,
          resource_id: shared_file.id,
          permission: :read
        )

      {:ok, tenant: tenant, owner: owner, viewer: viewer, shared_file: shared_file, share: share}
    end

    test "viewer can read shared file", %{
      conn: conn,
      tenant: tenant,
      viewer: viewer,
      shared_file: shared_file
    } do
      conn = conn |> authenticate(viewer, tenant) |> get(~p"/api/files/#{shared_file.id}")

      assert json_response(conn, 200)["data"]
    end

    test "viewer cannot update shared file", %{
      conn: conn,
      tenant: tenant,
      viewer: viewer,
      shared_file: shared_file
    } do
      params = %{"encrypted_metadata" => Base.encode64("hacked")}

      conn = conn |> authenticate(viewer, tenant) |> put(~p"/api/files/#{shared_file.id}", params)

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end

    test "viewer cannot delete shared file", %{
      conn: conn,
      tenant: tenant,
      viewer: viewer,
      shared_file: shared_file
    } do
      conn = conn |> authenticate(viewer, tenant) |> delete(~p"/api/files/#{shared_file.id}")

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end

    test "viewer cannot revoke share", %{conn: conn, tenant: tenant, viewer: viewer, share: share} do
      conn = conn |> authenticate(viewer, tenant) |> delete(~p"/api/shares/#{share.id}")

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end

    test "non-participant cannot access shared file", %{
      conn: conn,
      tenant: tenant,
      shared_file: shared_file
    } do
      bystander = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: bystander.id, tenant_id: tenant.id, role: :member)

      conn = conn |> authenticate(bystander, tenant) |> get(~p"/api/files/#{shared_file.id}")

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # SEC-004: Device Ownership Verification
  # ═══════════════════════════════════════════════════════════════════════════

  describe "SEC-004: Device Ownership Verification" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      other = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      insert(:user_tenant, user_id: other.id, tenant_id: tenant.id, role: :member)

      {:ok, enrollment} =
        SecureSharing.Devices.enroll_device(%{
          user_id: user.id,
          tenant_id: tenant.id,
          device_fingerprint: "sha256:#{Base.encode16(:crypto.strong_rand_bytes(32))}",
          platform: "android",
          device_info: %{},
          device_public_key: :crypto.strong_rand_bytes(1024),
          key_algorithm: :kaz_sign,
          device_name: "User's Phone"
        })

      {:ok, tenant: tenant, user: user, other: other, enrollment: enrollment}
    end

    test "user can access own device", %{
      conn: conn,
      tenant: tenant,
      user: user,
      enrollment: enrollment
    } do
      conn = conn |> authenticate(user, tenant) |> get(~p"/api/devices/#{enrollment.id}")

      assert json_response(conn, 200)["data"]
    end

    test "user cannot access other's device", %{
      conn: conn,
      tenant: tenant,
      other: other,
      enrollment: enrollment
    } do
      conn = conn |> authenticate(other, tenant) |> get(~p"/api/devices/#{enrollment.id}")

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end

    test "user cannot update other's device", %{
      conn: conn,
      tenant: tenant,
      other: other,
      enrollment: enrollment
    } do
      params = %{"device_name" => "Hacked Name"}

      conn = conn |> authenticate(other, tenant) |> put(~p"/api/devices/#{enrollment.id}", params)

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end

    test "user cannot revoke other's device", %{
      conn: conn,
      tenant: tenant,
      other: other,
      enrollment: enrollment
    } do
      conn = conn |> authenticate(other, tenant) |> delete(~p"/api/devices/#{enrollment.id}")

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # SEC-005: Recovery Access Control
  # ═══════════════════════════════════════════════════════════════════════════

  describe "SEC-005: Recovery Access Control" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      trustee = insert(:user, tenant_id: tenant.id)
      attacker = insert(:user, tenant_id: tenant.id)

      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      insert(:user_tenant, user_id: trustee.id, tenant_id: tenant.id, role: :member)
      insert(:user_tenant, user_id: attacker.id, tenant_id: tenant.id, role: :member)

      config = insert(:recovery_config, user_id: user.id)

      share =
        insert(:recovery_share,
          config_id: config.id,
          owner_id: user.id,
          trustee_id: trustee.id,
          accepted: false
        )

      {:ok, tenant: tenant, trustee: trustee, attacker: attacker, share: share}
    end

    test "only trustee can accept recovery share", %{
      conn: conn,
      tenant: tenant,
      attacker: attacker,
      share: share
    } do
      conn =
        conn
        |> authenticate(attacker, tenant)
        |> post(~p"/api/recovery/shares/#{share.id}/accept")

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end

    test "trustee can accept their share", %{
      conn: conn,
      tenant: tenant,
      trustee: trustee,
      share: share
    } do
      conn =
        conn |> authenticate(trustee, tenant) |> post(~p"/api/recovery/shares/#{share.id}/accept")

      assert json_response(conn, 200)["data"]
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
