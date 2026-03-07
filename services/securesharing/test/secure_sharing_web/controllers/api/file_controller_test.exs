defmodule SecureSharingWeb.Controllers.Api.FileControllerTest do
  @moduledoc """
  Tests for file operations API endpoints.

  Based on test plan:
  - GET /api/folders/:folder_id/files - List files in folder
  - GET /api/files/:id - Get file details
  - PUT /api/files/:id - Update file metadata
  - DELETE /api/files/:id - Delete file
  - POST /api/files/upload-url - Get upload URL
  - GET /api/files/:id/download-url - Get download URL
  - POST /api/files/:id/move - Move file
  """
  use SecureSharingWeb.ConnCase, async: true

  import SecureSharing.Factory
  alias SecureSharingWeb.Auth.Token

  # ═══════════════════════════════════════════════════════════════════════════
  # GET /api/folders/:folder_id/files
  # ═══════════════════════════════════════════════════════════════════════════

  describe "GET /api/folders/:folder_id/files" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      root = insert(:root_folder, owner_id: user.id, tenant_id: tenant.id)
      file1 = insert(:file, owner_id: user.id, tenant_id: tenant.id, folder_id: root.id)
      file2 = insert(:file, owner_id: user.id, tenant_id: tenant.id, folder_id: root.id)
      {:ok, tenant: tenant, user: user, root: root, file1: file1, file2: file2}
    end

    test "returns files in folder", %{
      conn: conn,
      user: user,
      tenant: tenant,
      root: root,
      file1: file1,
      file2: file2
    } do
      conn = conn |> authenticate(user, tenant) |> get(~p"/api/folders/#{root.id}/files")

      response = json_response(conn, 200)
      file_ids = Enum.map(response["data"], & &1["id"])
      assert file1.id in file_ids
      assert file2.id in file_ids
    end

    test "returns empty for folder with no files", %{
      conn: conn,
      user: user,
      tenant: tenant,
      root: root
    } do
      subfolder = insert(:folder, owner_id: user.id, tenant_id: tenant.id, parent_id: root.id)

      conn = conn |> authenticate(user, tenant) |> get(~p"/api/folders/#{subfolder.id}/files")

      response = json_response(conn, 200)
      assert response["data"] == []
    end

    test "returns 403 for other user's folder", %{conn: conn, tenant: tenant} do
      other_user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: other_user.id, tenant_id: tenant.id, role: :member)
      other_root = insert(:root_folder, owner_id: other_user.id, tenant_id: tenant.id)

      requester = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: requester.id, tenant_id: tenant.id, role: :member)

      conn =
        conn |> authenticate(requester, tenant) |> get(~p"/api/folders/#{other_root.id}/files")

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end

    test "returns 401 for unauthenticated request", %{conn: conn, root: root} do
      conn = get(conn, ~p"/api/folders/#{root.id}/files")

      response = json_response(conn, 401)
      assert response["error"]["code"] == "unauthorized"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # GET /api/files/:id
  # ═══════════════════════════════════════════════════════════════════════════

  describe "GET /api/files/:id" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      root = insert(:root_folder, owner_id: user.id, tenant_id: tenant.id)
      test_file = insert(:file, owner_id: user.id, tenant_id: tenant.id, folder_id: root.id)
      {:ok, tenant: tenant, user: user, test_file: test_file}
    end

    test "returns file details", %{conn: conn, user: user, tenant: tenant, test_file: test_file} do
      conn = conn |> authenticate(user, tenant) |> get(~p"/api/files/#{test_file.id}")

      response = json_response(conn, 200)
      assert response["data"]["id"] == test_file.id
    end

    test "returns 404 for non-existent file", %{conn: conn, user: user, tenant: tenant} do
      fake_id = Ecto.UUID.generate()

      conn = conn |> authenticate(user, tenant) |> get(~p"/api/files/#{fake_id}")

      response = json_response(conn, 404)
      assert response["error"]["code"] == "not_found"
    end

    test "returns 403 for other user's file", %{conn: conn, tenant: tenant} do
      other_user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: other_user.id, tenant_id: tenant.id, role: :member)
      other_root = insert(:root_folder, owner_id: other_user.id, tenant_id: tenant.id)

      other_test_file =
        insert(:file, owner_id: other_user.id, tenant_id: tenant.id, folder_id: other_root.id)

      requester = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: requester.id, tenant_id: tenant.id, role: :member)

      conn = conn |> authenticate(requester, tenant) |> get(~p"/api/files/#{other_test_file.id}")

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # PUT /api/files/:id
  # ═══════════════════════════════════════════════════════════════════════════

  describe "PUT /api/files/:id" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      root = insert(:root_folder, owner_id: user.id, tenant_id: tenant.id)
      test_file = insert(:file, owner_id: user.id, tenant_id: tenant.id, folder_id: root.id)
      {:ok, tenant: tenant, user: user, test_file: test_file}
    end

    test "updates file metadata", %{conn: conn, user: user, tenant: tenant, test_file: test_file} do
      params = %{"encrypted_metadata" => Base.encode64("updated metadata")}

      conn = conn |> authenticate(user, tenant) |> put(~p"/api/files/#{test_file.id}", params)

      response = json_response(conn, 200)
      assert response["data"]["id"] == test_file.id
    end

    test "returns 403 for other user's file", %{conn: conn, tenant: tenant} do
      other_user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: other_user.id, tenant_id: tenant.id, role: :member)
      other_root = insert(:root_folder, owner_id: other_user.id, tenant_id: tenant.id)

      other_test_file =
        insert(:file, owner_id: other_user.id, tenant_id: tenant.id, folder_id: other_root.id)

      requester = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: requester.id, tenant_id: tenant.id, role: :member)

      params = %{"encrypted_metadata" => Base.encode64("hacked")}

      conn =
        conn
        |> authenticate(requester, tenant)
        |> put(~p"/api/files/#{other_test_file.id}", params)

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # DELETE /api/files/:id
  # ═══════════════════════════════════════════════════════════════════════════

  describe "DELETE /api/files/:id" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      root = insert(:root_folder, owner_id: user.id, tenant_id: tenant.id)
      test_file = insert(:file, owner_id: user.id, tenant_id: tenant.id, folder_id: root.id)
      {:ok, tenant: tenant, user: user, test_file: test_file}
    end

    test "deletes file", %{conn: conn, user: user, tenant: tenant, test_file: test_file} do
      conn = conn |> authenticate(user, tenant) |> delete(~p"/api/files/#{test_file.id}")

      assert response(conn, 204)
    end

    test "returns 403 for other user's file", %{conn: conn, tenant: tenant} do
      other_user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: other_user.id, tenant_id: tenant.id, role: :member)
      other_root = insert(:root_folder, owner_id: other_user.id, tenant_id: tenant.id)

      other_test_file =
        insert(:file, owner_id: other_user.id, tenant_id: tenant.id, folder_id: other_root.id)

      requester = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: requester.id, tenant_id: tenant.id, role: :member)

      conn =
        conn |> authenticate(requester, tenant) |> delete(~p"/api/files/#{other_test_file.id}")

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # POST /api/files/upload-url
  # ═══════════════════════════════════════════════════════════════════════════

  describe "POST /api/files/upload-url" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      root = insert(:root_folder, owner_id: user.id, tenant_id: tenant.id)
      {:ok, tenant: tenant, user: user, root: root}
    end

    test "returns upload URL for new file", %{conn: conn, user: user, tenant: tenant, root: root} do
      params = valid_upload_params(root.id)

      conn = conn |> authenticate(user, tenant) |> post(~p"/api/files/upload-url", params)

      response = json_response(conn, 201)
      assert response["data"]["upload_url"]
      assert response["data"]["file_id"]
    end

    test "returns 403 for folder without write access", %{conn: conn, tenant: tenant} do
      other_user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: other_user.id, tenant_id: tenant.id, role: :member)
      other_root = insert(:root_folder, owner_id: other_user.id, tenant_id: tenant.id)

      requester = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: requester.id, tenant_id: tenant.id, role: :member)

      params = valid_upload_params(other_root.id)

      conn = conn |> authenticate(requester, tenant) |> post(~p"/api/files/upload-url", params)

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end

    test "returns 401 for unauthenticated request", %{conn: conn, root: root} do
      params = valid_upload_params(root.id)

      conn = post(conn, ~p"/api/files/upload-url", params)

      response = json_response(conn, 401)
      assert response["error"]["code"] == "unauthorized"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # GET /api/files/:id/download-url
  # ═══════════════════════════════════════════════════════════════════════════

  describe "GET /api/files/:id/download-url" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      root = insert(:root_folder, owner_id: user.id, tenant_id: tenant.id)

      test_file =
        insert(:file,
          owner_id: user.id,
          tenant_id: tenant.id,
          folder_id: root.id,
          status: "uploaded"
        )

      {:ok, tenant: tenant, user: user, test_file: test_file}
    end

    test "returns download URL for uploaded file", %{
      conn: conn,
      user: user,
      tenant: tenant,
      test_file: test_file
    } do
      conn =
        conn |> authenticate(user, tenant) |> get(~p"/api/files/#{test_file.id}/download-url")

      response = json_response(conn, 200)
      assert response["data"]["download_url"]
    end

    test "returns 403 for other user's file", %{conn: conn, tenant: tenant} do
      other_user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: other_user.id, tenant_id: tenant.id, role: :member)
      other_root = insert(:root_folder, owner_id: other_user.id, tenant_id: tenant.id)

      other_test_file =
        insert(:file, owner_id: other_user.id, tenant_id: tenant.id, folder_id: other_root.id)

      requester = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: requester.id, tenant_id: tenant.id, role: :member)

      conn =
        conn
        |> authenticate(requester, tenant)
        |> get(~p"/api/files/#{other_test_file.id}/download-url")

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # POST /api/files/:id/move
  # ═══════════════════════════════════════════════════════════════════════════

  describe "POST /api/files/:id/move" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      root = insert(:root_folder, owner_id: user.id, tenant_id: tenant.id)
      folder = insert(:folder, owner_id: user.id, tenant_id: tenant.id, parent_id: root.id)
      test_file = insert(:file, owner_id: user.id, tenant_id: tenant.id, folder_id: root.id)
      {:ok, tenant: tenant, user: user, root: root, folder: folder, test_file: test_file}
    end

    test "moves file to different folder", %{
      conn: conn,
      user: user,
      tenant: tenant,
      folder: folder,
      test_file: test_file
    } do
      params =
        valid_move_params()
        |> Map.put("folder_id", folder.id)

      conn =
        conn |> authenticate(user, tenant) |> post(~p"/api/files/#{test_file.id}/move", params)

      response = json_response(conn, 200)
      assert response["data"]["folder_id"] == folder.id
    end

    test "returns 404 for non-existent target folder", %{
      conn: conn,
      user: user,
      tenant: tenant,
      test_file: test_file
    } do
      fake_id = Ecto.UUID.generate()
      params = valid_move_params() |> Map.put("folder_id", fake_id)

      conn =
        conn |> authenticate(user, tenant) |> post(~p"/api/files/#{test_file.id}/move", params)

      response = json_response(conn, 404)
      assert response["error"]["code"] == "not_found"
    end

    test "returns 403 for target folder without write access", %{
      conn: conn,
      user: user,
      tenant: tenant,
      test_file: test_file
    } do
      other_user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: other_user.id, tenant_id: tenant.id, role: :member)
      other_root = insert(:root_folder, owner_id: other_user.id, tenant_id: tenant.id)

      params = valid_move_params() |> Map.put("folder_id", other_root.id)

      conn =
        conn |> authenticate(user, tenant) |> post(~p"/api/files/#{test_file.id}/move", params)

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Permission-based access (sharing scenarios)
  # ═══════════════════════════════════════════════════════════════════════════

  describe "permission-based file operations" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      owner = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: owner.id, tenant_id: tenant.id, role: :member)
      root = insert(:root_folder, owner_id: owner.id, tenant_id: tenant.id)
      test_file = insert(:file, owner_id: owner.id, tenant_id: tenant.id, folder_id: root.id)

      {:ok, tenant: tenant, owner: owner, root: root, test_file: test_file}
    end

    test "admin share holder can delete file", %{
      conn: conn,
      tenant: tenant,
      owner: owner,
      test_file: test_file
    } do
      admin_user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: admin_user.id, tenant_id: tenant.id, role: :member)

      insert(:file_share,
        tenant_id: tenant.id,
        grantor_id: owner.id,
        grantee_id: admin_user.id,
        resource_id: test_file.id,
        permission: :admin
      )

      conn =
        conn |> authenticate(admin_user, tenant) |> delete(~p"/api/files/#{test_file.id}")

      assert response(conn, 204)
    end

    test "write share holder can update file", %{
      conn: conn,
      tenant: tenant,
      owner: owner,
      test_file: test_file
    } do
      writer = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: writer.id, tenant_id: tenant.id, role: :member)

      insert(:file_share,
        tenant_id: tenant.id,
        grantor_id: owner.id,
        grantee_id: writer.id,
        resource_id: test_file.id,
        permission: :write
      )

      # Use "uploading" status which doesn't require blob verification
      params = %{"status" => "uploading"}

      conn =
        conn |> authenticate(writer, tenant) |> put(~p"/api/files/#{test_file.id}", params)

      response = json_response(conn, 200)
      assert response["data"]["id"] == test_file.id
    end

    test "write share holder CANNOT delete file", %{
      conn: conn,
      tenant: tenant,
      owner: owner,
      test_file: test_file
    } do
      writer = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: writer.id, tenant_id: tenant.id, role: :member)

      insert(:file_share,
        tenant_id: tenant.id,
        grantor_id: owner.id,
        grantee_id: writer.id,
        resource_id: test_file.id,
        permission: :write
      )

      conn =
        conn |> authenticate(writer, tenant) |> delete(~p"/api/files/#{test_file.id}")

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end

    test "read share holder cannot update file", %{
      conn: conn,
      tenant: tenant,
      owner: owner,
      test_file: test_file
    } do
      reader = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: reader.id, tenant_id: tenant.id, role: :member)

      insert(:file_share,
        tenant_id: tenant.id,
        grantor_id: owner.id,
        grantee_id: reader.id,
        resource_id: test_file.id,
        permission: :read
      )

      params = %{"status" => "complete"}

      conn =
        conn |> authenticate(reader, tenant) |> put(~p"/api/files/#{test_file.id}", params)

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end

    test "read share holder cannot delete file", %{
      conn: conn,
      tenant: tenant,
      owner: owner,
      test_file: test_file
    } do
      reader = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: reader.id, tenant_id: tenant.id, role: :member)

      insert(:file_share,
        tenant_id: tenant.id,
        grantor_id: owner.id,
        grantee_id: reader.id,
        resource_id: test_file.id,
        permission: :read
      )

      conn =
        conn |> authenticate(reader, tenant) |> delete(~p"/api/files/#{test_file.id}")

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # POST /api/files/:id/transfer-ownership
  # ═══════════════════════════════════════════════════════════════════════════

  describe "POST /api/files/:id/transfer-ownership" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      owner = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: owner.id, tenant_id: tenant.id, role: :member)
      new_owner = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: new_owner.id, tenant_id: tenant.id, role: :member)
      root = insert(:root_folder, owner_id: owner.id, tenant_id: tenant.id)
      test_file = insert(:file, owner_id: owner.id, tenant_id: tenant.id, folder_id: root.id)
      {:ok, tenant: tenant, owner: owner, new_owner: new_owner, test_file: test_file}
    end

    test "transfers ownership successfully", %{
      conn: conn,
      tenant: tenant,
      owner: owner,
      new_owner: new_owner,
      test_file: test_file
    } do
      params = %{
        "new_owner_id" => new_owner.id,
        "wrapped_dek" => Base.encode64(:crypto.strong_rand_bytes(64)),
        "kem_ciphertext" => Base.encode64(:crypto.strong_rand_bytes(128)),
        "signature" => Base.encode64(:crypto.strong_rand_bytes(256)),
        "old_owner_wrapped_key" => Base.encode64(:crypto.strong_rand_bytes(64)),
        "old_owner_kem_ciphertext" => Base.encode64(:crypto.strong_rand_bytes(128)),
        "old_owner_signature" => Base.encode64(:crypto.strong_rand_bytes(256))
      }

      conn =
        conn
        |> authenticate(owner, tenant)
        |> post(~p"/api/files/#{test_file.id}/transfer-ownership", params)

      response = json_response(conn, 200)
      assert response["data"]["owner_id"] == new_owner.id
    end

    test "returns 403 for non-owner", %{
      conn: conn,
      tenant: tenant,
      new_owner: new_owner,
      test_file: test_file
    } do
      params = %{"new_owner_id" => new_owner.id}

      conn =
        conn
        |> authenticate(new_owner, tenant)
        |> post(~p"/api/files/#{test_file.id}/transfer-ownership", params)

      assert json_response(conn, 403)
    end

    test "returns 400 for self-transfer", %{
      conn: conn,
      tenant: tenant,
      owner: owner,
      test_file: test_file
    } do
      params = %{"new_owner_id" => owner.id}

      conn =
        conn
        |> authenticate(owner, tenant)
        |> post(~p"/api/files/#{test_file.id}/transfer-ownership", params)

      assert json_response(conn, 400)
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # GET /api/files/:id/audit-log
  # ═══════════════════════════════════════════════════════════════════════════

  describe "GET /api/files/:id/audit-log" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      owner = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: owner.id, tenant_id: tenant.id, role: :member)
      root = insert(:root_folder, owner_id: owner.id, tenant_id: tenant.id)
      test_file = insert(:file, owner_id: owner.id, tenant_id: tenant.id, folder_id: root.id)
      {:ok, tenant: tenant, owner: owner, test_file: test_file}
    end

    test "returns audit log for file owner", %{
      conn: conn,
      tenant: tenant,
      owner: owner,
      test_file: test_file
    } do
      conn =
        conn
        |> authenticate(owner, tenant)
        |> get(~p"/api/files/#{test_file.id}/audit-log")

      response = json_response(conn, 200)
      assert Map.has_key?(response, "data")
      assert Map.has_key?(response, "meta")
    end

    test "returns 403 for user with only read access", %{
      conn: conn,
      tenant: tenant,
      owner: owner,
      test_file: test_file
    } do
      reader = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: reader.id, tenant_id: tenant.id, role: :member)

      insert(:file_share,
        tenant_id: tenant.id,
        grantor_id: owner.id,
        grantee_id: reader.id,
        resource_id: test_file.id,
        permission: :read
      )

      conn =
        conn
        |> authenticate(reader, tenant)
        |> get(~p"/api/files/#{test_file.id}/audit-log")

      assert json_response(conn, 403)
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Helper Functions
  # ═══════════════════════════════════════════════════════════════════════════

  defp authenticate(conn, user, tenant, role \\ :member) do
    {:ok, token} = Token.generate_access_token(user, tenant.id, role)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  defp valid_upload_params(folder_id) do
    %{
      "folder_id" => folder_id,
      "encrypted_metadata" => Base.encode64(:crypto.strong_rand_bytes(32)),
      "metadata_nonce" => Base.encode64(:crypto.strong_rand_bytes(12)),
      "encrypted_size" => 1024,
      "content_hash" => Base.encode64(:crypto.strong_rand_bytes(32)),
      "wrapped_dek" => Base.encode64(:crypto.strong_rand_bytes(32)),
      "kem_ciphertext" => Base.encode64(:crypto.strong_rand_bytes(64)),
      "signature" => Base.encode64(:crypto.strong_rand_bytes(64)),
      "chunk_count" => 1
    }
  end

  defp valid_move_params do
    %{
      "wrapped_dek" => Base.encode64(:crypto.strong_rand_bytes(32)),
      "kem_ciphertext" => Base.encode64(:crypto.strong_rand_bytes(64)),
      "signature" => Base.encode64(:crypto.strong_rand_bytes(64))
    }
  end
end
