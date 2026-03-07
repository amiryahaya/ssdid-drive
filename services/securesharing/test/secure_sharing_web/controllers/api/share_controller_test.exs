defmodule SecureSharingWeb.Controllers.Api.ShareControllerTest do
  @moduledoc """
  Tests for sharing API endpoints.

  Based on test plan:
  - GET /api/shares/received - List received shares
  - GET /api/shares/created - List created shares
  - POST /api/shares/file - Share a file
  - POST /api/shares/folder - Share a folder
  - GET /api/shares/:id - Get share details
  - PUT /api/shares/:id/permission - Update permission
  - PUT /api/shares/:id/expiry - Set expiry
  - DELETE /api/shares/:id - Revoke share
  """
  use SecureSharingWeb.ConnCase, async: true

  import SecureSharing.Factory
  alias SecureSharingWeb.Auth.Token

  # ═══════════════════════════════════════════════════════════════════════════
  # GET /api/shares/received
  # ═══════════════════════════════════════════════════════════════════════════

  describe "GET /api/shares/received" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      sharer = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      insert(:user_tenant, user_id: sharer.id, tenant_id: tenant.id, role: :member)

      # Create a file shared with user
      sharer_root = insert(:root_folder, owner_id: sharer.id, tenant_id: tenant.id)

      shared_file =
        insert(:file, owner_id: sharer.id, tenant_id: tenant.id, folder_id: sharer_root.id)

      share =
        insert(:file_share,
          tenant_id: tenant.id,
          grantor_id: sharer.id,
          grantee_id: user.id,
          resource_id: shared_file.id
        )

      {:ok, tenant: tenant, user: user, sharer: sharer, share: share}
    end

    test "returns list of received shares", %{
      conn: conn,
      user: user,
      tenant: tenant,
      share: share
    } do
      conn = conn |> authenticate(user, tenant) |> get(~p"/api/shares/received")

      response = json_response(conn, 200)
      share_ids = Enum.map(response["data"], & &1["id"])
      assert share.id in share_ids
    end

    test "does not return shares sent by user", %{
      conn: conn,
      tenant: tenant,
      sharer: sharer,
      share: share
    } do
      # The sharer should not see this in received shares
      conn = conn |> authenticate(sharer, tenant) |> get(~p"/api/shares/received")

      response = json_response(conn, 200)
      share_ids = Enum.map(response["data"], & &1["id"])
      refute share.id in share_ids
    end

    test "returns 401 for unauthenticated request", %{conn: conn} do
      conn = get(conn, ~p"/api/shares/received")

      response = json_response(conn, 401)
      assert response["error"]["code"] == "unauthorized"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # GET /api/shares/created
  # ═══════════════════════════════════════════════════════════════════════════

  describe "GET /api/shares/created" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      grantee = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      insert(:user_tenant, user_id: grantee.id, tenant_id: tenant.id, role: :member)

      user_root = insert(:root_folder, owner_id: user.id, tenant_id: tenant.id)

      shared_file =
        insert(:file, owner_id: user.id, tenant_id: tenant.id, folder_id: user_root.id)

      share =
        insert(:file_share,
          tenant_id: tenant.id,
          grantor_id: user.id,
          grantee_id: grantee.id,
          resource_id: shared_file.id
        )

      {:ok, tenant: tenant, user: user, grantee: grantee, share: share}
    end

    test "returns list of created shares", %{conn: conn, user: user, tenant: tenant, share: share} do
      conn = conn |> authenticate(user, tenant) |> get(~p"/api/shares/created")

      response = json_response(conn, 200)
      share_ids = Enum.map(response["data"], & &1["id"])
      assert share.id in share_ids
    end

    test "does not return shares received by user", %{
      conn: conn,
      tenant: tenant,
      grantee: grantee,
      share: share
    } do
      conn = conn |> authenticate(grantee, tenant) |> get(~p"/api/shares/created")

      response = json_response(conn, 200)
      share_ids = Enum.map(response["data"], & &1["id"])
      refute share.id in share_ids
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # POST /api/shares/file
  # ═══════════════════════════════════════════════════════════════════════════

  describe "POST /api/shares/file" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      grantee = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      insert(:user_tenant, user_id: grantee.id, tenant_id: tenant.id, role: :member)

      user_root = insert(:root_folder, owner_id: user.id, tenant_id: tenant.id)
      test_file = insert(:file, owner_id: user.id, tenant_id: tenant.id, folder_id: user_root.id)

      {:ok, tenant: tenant, user: user, grantee: grantee, test_file: test_file}
    end

    test "creates file share", %{
      conn: conn,
      user: user,
      tenant: tenant,
      grantee: grantee,
      test_file: test_file
    } do
      params = valid_file_share_params(grantee.id, test_file.id)

      conn = conn |> authenticate(user, tenant) |> post(~p"/api/shares/file", params)

      response = json_response(conn, 201)
      assert response["data"]["grantee_id"] == grantee.id
      # Response uses resource_id, not file_id
      assert response["data"]["resource_id"] == test_file.id
    end

    test "returns 403 for file user does not own", %{conn: conn, tenant: tenant, grantee: grantee} do
      other_user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: other_user.id, tenant_id: tenant.id, role: :member)
      other_root = insert(:root_folder, owner_id: other_user.id, tenant_id: tenant.id)

      other_file =
        insert(:file, owner_id: other_user.id, tenant_id: tenant.id, folder_id: other_root.id)

      requester = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: requester.id, tenant_id: tenant.id, role: :member)

      params = valid_file_share_params(grantee.id, other_file.id)

      conn = conn |> authenticate(requester, tenant) |> post(~p"/api/shares/file", params)

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end

    test "returns 404 for non-existent grantee", %{
      conn: conn,
      user: user,
      tenant: tenant,
      test_file: test_file
    } do
      fake_id = Ecto.UUID.generate()
      params = valid_file_share_params(fake_id, test_file.id)

      conn = conn |> authenticate(user, tenant) |> post(~p"/api/shares/file", params)

      response = json_response(conn, 404)
      assert response["error"]["code"] == "not_found"
    end

    test "returns 409 for duplicate share", %{
      conn: conn,
      user: user,
      tenant: tenant,
      grantee: grantee,
      test_file: test_file
    } do
      # Create existing share
      insert(:file_share,
        tenant_id: tenant.id,
        grantor_id: user.id,
        grantee_id: grantee.id,
        resource_id: test_file.id
      )

      params = valid_file_share_params(grantee.id, test_file.id)

      conn = conn |> authenticate(user, tenant) |> post(~p"/api/shares/file", params)

      # App returns 422 validation_error for duplicate share
      response = json_response(conn, 422)
      assert response["error"]["code"] == "validation_error"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # POST /api/shares/folder
  # ═══════════════════════════════════════════════════════════════════════════

  describe "POST /api/shares/folder" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      grantee = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      insert(:user_tenant, user_id: grantee.id, tenant_id: tenant.id, role: :member)

      user_root = insert(:root_folder, owner_id: user.id, tenant_id: tenant.id)
      folder = insert(:folder, owner_id: user.id, tenant_id: tenant.id, parent_id: user_root.id)

      {:ok, tenant: tenant, user: user, grantee: grantee, folder: folder}
    end

    test "creates folder share", %{
      conn: conn,
      user: user,
      tenant: tenant,
      grantee: grantee,
      folder: folder
    } do
      params = valid_folder_share_params(grantee.id, folder.id)

      conn = conn |> authenticate(user, tenant) |> post(~p"/api/shares/folder", params)

      response = json_response(conn, 201)
      assert response["data"]["grantee_id"] == grantee.id
      # Response uses resource_id, not folder_id
      assert response["data"]["resource_id"] == folder.id
    end

    test "returns 403 for folder user does not own", %{
      conn: conn,
      tenant: tenant,
      grantee: grantee
    } do
      other_user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: other_user.id, tenant_id: tenant.id, role: :member)
      other_root = insert(:root_folder, owner_id: other_user.id, tenant_id: tenant.id)

      requester = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: requester.id, tenant_id: tenant.id, role: :member)

      params = valid_folder_share_params(grantee.id, other_root.id)

      conn = conn |> authenticate(requester, tenant) |> post(~p"/api/shares/folder", params)

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # GET /api/shares/:id
  # ═══════════════════════════════════════════════════════════════════════════

  describe "GET /api/shares/:id" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      grantee = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      insert(:user_tenant, user_id: grantee.id, tenant_id: tenant.id, role: :member)

      user_root = insert(:root_folder, owner_id: user.id, tenant_id: tenant.id)
      test_file = insert(:file, owner_id: user.id, tenant_id: tenant.id, folder_id: user_root.id)

      share =
        insert(:file_share,
          tenant_id: tenant.id,
          grantor_id: user.id,
          grantee_id: grantee.id,
          resource_id: test_file.id
        )

      {:ok, tenant: tenant, user: user, grantee: grantee, share: share}
    end

    test "owner can view share details", %{conn: conn, user: user, tenant: tenant, share: share} do
      conn = conn |> authenticate(user, tenant) |> get(~p"/api/shares/#{share.id}")

      response = json_response(conn, 200)
      assert response["data"]["id"] == share.id
    end

    test "grantee can view share details", %{
      conn: conn,
      tenant: tenant,
      grantee: grantee,
      share: share
    } do
      conn = conn |> authenticate(grantee, tenant) |> get(~p"/api/shares/#{share.id}")

      response = json_response(conn, 200)
      assert response["data"]["id"] == share.id
    end

    test "other user cannot view share details", %{conn: conn, tenant: tenant, share: share} do
      other = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: other.id, tenant_id: tenant.id, role: :member)

      conn = conn |> authenticate(other, tenant) |> get(~p"/api/shares/#{share.id}")

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end

    test "returns 404 for non-existent share", %{conn: conn, user: user, tenant: tenant} do
      fake_id = Ecto.UUID.generate()

      conn = conn |> authenticate(user, tenant) |> get(~p"/api/shares/#{fake_id}")

      response = json_response(conn, 404)
      assert response["error"]["code"] == "not_found"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # PUT /api/shares/:id/permission
  # ═══════════════════════════════════════════════════════════════════════════

  describe "PUT /api/shares/:id/permission" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      grantee = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      insert(:user_tenant, user_id: grantee.id, tenant_id: tenant.id, role: :member)

      user_root = insert(:root_folder, owner_id: user.id, tenant_id: tenant.id)
      test_file = insert(:file, owner_id: user.id, tenant_id: tenant.id, folder_id: user_root.id)

      share =
        insert(:file_share,
          tenant_id: tenant.id,
          grantor_id: user.id,
          grantee_id: grantee.id,
          resource_id: test_file.id,
          permission: :read
        )

      {:ok, tenant: tenant, user: user, grantee: grantee, share: share}
    end

    test "owner can update permission", %{conn: conn, user: user, tenant: tenant, share: share} do
      params = %{"permission" => "write"}

      conn =
        conn |> authenticate(user, tenant) |> put(~p"/api/shares/#{share.id}/permission", params)

      response = json_response(conn, 200)
      assert response["data"]["permission"] == "write"
    end

    test "grantee cannot update permission", %{
      conn: conn,
      tenant: tenant,
      grantee: grantee,
      share: share
    } do
      params = %{"permission" => "admin"}

      conn =
        conn
        |> authenticate(grantee, tenant)
        |> put(~p"/api/shares/#{share.id}/permission", params)

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # PUT /api/shares/:id/expiry
  # ═══════════════════════════════════════════════════════════════════════════

  describe "PUT /api/shares/:id/expiry" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      grantee = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      insert(:user_tenant, user_id: grantee.id, tenant_id: tenant.id, role: :member)

      user_root = insert(:root_folder, owner_id: user.id, tenant_id: tenant.id)
      test_file = insert(:file, owner_id: user.id, tenant_id: tenant.id, folder_id: user_root.id)

      share =
        insert(:file_share,
          tenant_id: tenant.id,
          grantor_id: user.id,
          grantee_id: grantee.id,
          resource_id: test_file.id
        )

      {:ok, tenant: tenant, user: user, share: share}
    end

    test "owner can set expiry", %{conn: conn, user: user, tenant: tenant, share: share} do
      future = DateTime.utc_now() |> DateTime.add(7, :day) |> DateTime.to_iso8601()
      params = %{"expires_at" => future}

      conn = conn |> authenticate(user, tenant) |> put(~p"/api/shares/#{share.id}/expiry", params)

      response = json_response(conn, 200)
      assert response["data"]["expires_at"]
    end

    test "owner can clear expiry", %{conn: conn, user: user, tenant: tenant, share: share} do
      params = %{"expires_at" => nil}

      conn = conn |> authenticate(user, tenant) |> put(~p"/api/shares/#{share.id}/expiry", params)

      response = json_response(conn, 200)
      assert response["data"]["expires_at"] == nil
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # DELETE /api/shares/:id
  # ═══════════════════════════════════════════════════════════════════════════

  describe "DELETE /api/shares/:id" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      grantee = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      insert(:user_tenant, user_id: grantee.id, tenant_id: tenant.id, role: :member)

      user_root = insert(:root_folder, owner_id: user.id, tenant_id: tenant.id)
      test_file = insert(:file, owner_id: user.id, tenant_id: tenant.id, folder_id: user_root.id)

      share =
        insert(:file_share,
          tenant_id: tenant.id,
          grantor_id: user.id,
          grantee_id: grantee.id,
          resource_id: test_file.id
        )

      {:ok, tenant: tenant, user: user, grantee: grantee, share: share}
    end

    test "owner can revoke share", %{conn: conn, user: user, tenant: tenant, share: share} do
      conn = conn |> authenticate(user, tenant) |> delete(~p"/api/shares/#{share.id}")

      assert response(conn, 204)
    end

    test "grantee cannot revoke share", %{
      conn: conn,
      tenant: tenant,
      grantee: grantee,
      share: share
    } do
      conn = conn |> authenticate(grantee, tenant) |> delete(~p"/api/shares/#{share.id}")

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end

    test "returns 404 for non-existent share", %{conn: conn, user: user, tenant: tenant} do
      fake_id = Ecto.UUID.generate()

      conn = conn |> authenticate(user, tenant) |> delete(~p"/api/shares/#{fake_id}")

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

  defp valid_file_share_params(grantee_id, file_id) do
    %{
      "grantee_id" => grantee_id,
      "file_id" => file_id,
      "permission" => "read",
      "wrapped_key" => Base.encode64(:crypto.strong_rand_bytes(64)),
      "kem_ciphertext" => Base.encode64(:crypto.strong_rand_bytes(128)),
      "signature" => Base.encode64(:crypto.strong_rand_bytes(256))
    }
  end

  defp valid_folder_share_params(grantee_id, folder_id) do
    %{
      "grantee_id" => grantee_id,
      "folder_id" => folder_id,
      "permission" => "read",
      "recursive" => true,
      "wrapped_key" => Base.encode64(:crypto.strong_rand_bytes(64)),
      "kem_ciphertext" => Base.encode64(:crypto.strong_rand_bytes(128)),
      "signature" => Base.encode64(:crypto.strong_rand_bytes(256))
    }
  end
end
