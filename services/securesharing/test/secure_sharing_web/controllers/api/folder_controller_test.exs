defmodule SecureSharingWeb.Controllers.Api.FolderControllerTest do
  @moduledoc """
  Tests for folder operations API endpoints.

  Based on test plan:
  - GET /api/folders/root - Get root folder
  - GET /api/folders - List folders
  - POST /api/folders - Create folder
  - GET /api/folders/:id - Get folder
  - PUT /api/folders/:id - Update folder
  - DELETE /api/folders/:id - Delete folder
  - POST /api/folders/:id/move - Move folder
  - GET /api/folders/:folder_id/children - List child folders
  """
  use SecureSharingWeb.ConnCase, async: true

  import SecureSharing.Factory
  alias SecureSharingWeb.Auth.Token

  # ═══════════════════════════════════════════════════════════════════════════
  # GET /api/folders/root
  # ═══════════════════════════════════════════════════════════════════════════

  describe "GET /api/folders/root" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      {:ok, tenant: tenant, user: user}
    end

    test "returns root folder if exists", %{conn: conn, user: user, tenant: tenant} do
      root_folder = insert(:root_folder, owner_id: user.id, tenant_id: tenant.id)

      conn = conn |> authenticate(user, tenant) |> get(~p"/api/folders/root")

      response = json_response(conn, 200)
      assert response["data"]["id"] == root_folder.id
      assert response["data"]["is_root"] == true
    end

    test "returns null if no root folder", %{conn: conn, user: user, tenant: tenant} do
      conn = conn |> authenticate(user, tenant) |> get(~p"/api/folders/root")

      response = json_response(conn, 200)
      assert response["data"] == nil
    end

    test "returns 401 for unauthenticated request", %{conn: conn} do
      conn = get(conn, ~p"/api/folders/root")

      response = json_response(conn, 401)
      assert response["error"]["code"] == "unauthorized"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # GET /api/folders
  # ═══════════════════════════════════════════════════════════════════════════

  describe "GET /api/folders" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      root = insert(:root_folder, owner_id: user.id, tenant_id: tenant.id)
      {:ok, tenant: tenant, user: user, root: root}
    end

    test "returns paginated list of folders", %{
      conn: conn,
      user: user,
      tenant: tenant,
      root: root
    } do
      folder1 = insert(:folder, owner_id: user.id, tenant_id: tenant.id, parent_id: root.id)
      folder2 = insert(:folder, owner_id: user.id, tenant_id: tenant.id, parent_id: root.id)

      conn = conn |> authenticate(user, tenant) |> get(~p"/api/folders")

      response = json_response(conn, 200)
      assert is_list(response["data"])
      folder_ids = Enum.map(response["data"], & &1["id"])
      assert root.id in folder_ids
      assert folder1.id in folder_ids
      assert folder2.id in folder_ids
      # Note: pagination may or may not be present depending on implementation
    end

    test "does not return other user's folders", %{conn: conn, user: user, tenant: tenant} do
      other_user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: other_user.id, tenant_id: tenant.id, role: :member)
      other_folder = insert(:root_folder, owner_id: other_user.id, tenant_id: tenant.id)

      conn = conn |> authenticate(user, tenant) |> get(~p"/api/folders")

      response = json_response(conn, 200)
      folder_ids = Enum.map(response["data"], & &1["id"])
      refute other_folder.id in folder_ids
    end

    test "supports pagination parameters", %{conn: conn, user: user, tenant: tenant} do
      params = %{"page" => "1", "page_size" => "10"}

      conn =
        conn |> authenticate(user, tenant) |> get(~p"/api/folders?#{URI.encode_query(params)}")

      response = json_response(conn, 200)
      # Just verify that query params are accepted and response is valid
      assert is_list(response["data"])
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # POST /api/folders (Create Root Folder)
  # ═══════════════════════════════════════════════════════════════════════════

  describe "POST /api/folders (root folder)" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      {:ok, tenant: tenant, user: user}
    end

    test "creates root folder", %{conn: conn, user: user, tenant: tenant} do
      params = valid_folder_params() |> Map.put("is_root", true)

      conn = conn |> authenticate(user, tenant) |> post(~p"/api/folders", params)

      response = json_response(conn, 201)
      assert response["data"]["is_root"] == true
      assert response["data"]["owner"]["id"] == user.id
    end

    test "returns error if root folder already exists", %{conn: conn, user: user, tenant: tenant} do
      insert(:root_folder, owner_id: user.id, tenant_id: tenant.id)
      params = valid_folder_params() |> Map.put("is_root", true)

      conn = conn |> authenticate(user, tenant) |> post(~p"/api/folders", params)

      # App returns 422 validation_error for duplicate root folder
      response = json_response(conn, 422)
      assert response["error"]["code"] == "validation_error"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # POST /api/folders (Create Subfolder)
  # ═══════════════════════════════════════════════════════════════════════════

  describe "POST /api/folders (subfolder)" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      root = insert(:root_folder, owner_id: user.id, tenant_id: tenant.id)
      {:ok, tenant: tenant, user: user, root: root}
    end

    test "creates subfolder in parent", %{conn: conn, user: user, tenant: tenant, root: root} do
      params = valid_folder_params() |> Map.put("parent_id", root.id)

      conn = conn |> authenticate(user, tenant) |> post(~p"/api/folders", params)

      response = json_response(conn, 201)
      assert response["data"]["parent_id"] == root.id
      assert response["data"]["is_root"] == false
    end

    test "returns 404 for non-existent parent", %{conn: conn, user: user, tenant: tenant} do
      fake_id = Ecto.UUID.generate()
      params = valid_folder_params() |> Map.put("parent_id", fake_id)

      conn = conn |> authenticate(user, tenant) |> post(~p"/api/folders", params)

      response = json_response(conn, 404)
      assert response["error"]["code"] == "not_found"
    end

    test "returns 403 for other user's parent folder", %{conn: conn, user: user, tenant: tenant} do
      other_user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: other_user.id, tenant_id: tenant.id, role: :member)
      other_root = insert(:root_folder, owner_id: other_user.id, tenant_id: tenant.id)
      params = valid_folder_params() |> Map.put("parent_id", other_root.id)

      conn = conn |> authenticate(user, tenant) |> post(~p"/api/folders", params)

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # GET /api/folders/:id
  # ═══════════════════════════════════════════════════════════════════════════

  describe "GET /api/folders/:id" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      root = insert(:root_folder, owner_id: user.id, tenant_id: tenant.id)
      folder = insert(:folder, owner_id: user.id, tenant_id: tenant.id, parent_id: root.id)
      {:ok, tenant: tenant, user: user, folder: folder}
    end

    test "returns folder details", %{conn: conn, user: user, tenant: tenant, folder: folder} do
      conn = conn |> authenticate(user, tenant) |> get(~p"/api/folders/#{folder.id}")

      response = json_response(conn, 200)
      assert response["data"]["id"] == folder.id
    end

    test "returns 404 for non-existent folder", %{conn: conn, user: user, tenant: tenant} do
      fake_id = Ecto.UUID.generate()

      conn = conn |> authenticate(user, tenant) |> get(~p"/api/folders/#{fake_id}")

      response = json_response(conn, 404)
      assert response["error"]["code"] == "not_found"
    end

    test "returns 403 for other user's folder (no share)", %{conn: conn, tenant: tenant} do
      other_user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: other_user.id, tenant_id: tenant.id, role: :member)
      other_root = insert(:root_folder, owner_id: other_user.id, tenant_id: tenant.id)

      requester = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: requester.id, tenant_id: tenant.id, role: :member)

      conn = conn |> authenticate(requester, tenant) |> get(~p"/api/folders/#{other_root.id}")

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # PUT /api/folders/:id
  # ═══════════════════════════════════════════════════════════════════════════

  describe "PUT /api/folders/:id" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      root = insert(:root_folder, owner_id: user.id, tenant_id: tenant.id)
      folder = insert(:folder, owner_id: user.id, tenant_id: tenant.id, parent_id: root.id)
      {:ok, tenant: tenant, user: user, folder: folder}
    end

    test "updates folder metadata", %{conn: conn, user: user, tenant: tenant, folder: folder} do
      params = %{"encrypted_metadata" => Base.encode64("updated metadata")}

      conn = conn |> authenticate(user, tenant) |> put(~p"/api/folders/#{folder.id}", params)

      response = json_response(conn, 200)
      assert response["data"]["id"] == folder.id
    end

    test "returns 403 for other user's folder", %{conn: conn, tenant: tenant, folder: _folder} do
      other_user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: other_user.id, tenant_id: tenant.id, role: :member)
      other_root = insert(:root_folder, owner_id: other_user.id, tenant_id: tenant.id)

      other_folder =
        insert(:folder, owner_id: other_user.id, tenant_id: tenant.id, parent_id: other_root.id)

      requester = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: requester.id, tenant_id: tenant.id, role: :member)

      params = %{"encrypted_metadata" => Base.encode64("hacked")}

      conn =
        conn
        |> authenticate(requester, tenant)
        |> put(~p"/api/folders/#{other_folder.id}", params)

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # DELETE /api/folders/:id
  # ═══════════════════════════════════════════════════════════════════════════

  describe "DELETE /api/folders/:id" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      root = insert(:root_folder, owner_id: user.id, tenant_id: tenant.id)
      folder = insert(:folder, owner_id: user.id, tenant_id: tenant.id, parent_id: root.id)
      {:ok, tenant: tenant, user: user, root: root, folder: folder}
    end

    test "deletes folder", %{conn: conn, user: user, tenant: tenant, folder: folder} do
      conn = conn |> authenticate(user, tenant) |> delete(~p"/api/folders/#{folder.id}")

      assert response(conn, 204)
    end

    test "cannot delete root folder", %{conn: conn, user: user, tenant: tenant, root: root} do
      conn = conn |> authenticate(user, tenant) |> delete(~p"/api/folders/#{root.id}")

      # App returns 422 unprocessable_entity for root folder deletion
      response = json_response(conn, 422)
      assert response["error"]["code"] == "unprocessable_entity"
    end

    test "returns 403 for other user's folder", %{conn: conn, tenant: tenant} do
      other_user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: other_user.id, tenant_id: tenant.id, role: :member)
      other_root = insert(:root_folder, owner_id: other_user.id, tenant_id: tenant.id)

      other_folder =
        insert(:folder, owner_id: other_user.id, tenant_id: tenant.id, parent_id: other_root.id)

      requester = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: requester.id, tenant_id: tenant.id, role: :member)

      conn =
        conn |> authenticate(requester, tenant) |> delete(~p"/api/folders/#{other_folder.id}")

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # POST /api/folders/:id/move
  # ═══════════════════════════════════════════════════════════════════════════

  describe "POST /api/folders/:id/move" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      root = insert(:root_folder, owner_id: user.id, tenant_id: tenant.id)
      folder1 = insert(:folder, owner_id: user.id, tenant_id: tenant.id, parent_id: root.id)
      folder2 = insert(:folder, owner_id: user.id, tenant_id: tenant.id, parent_id: root.id)
      {:ok, tenant: tenant, user: user, root: root, folder1: folder1, folder2: folder2}
    end

    test "moves folder to new parent", %{
      conn: conn,
      user: user,
      tenant: tenant,
      folder1: folder1,
      folder2: folder2
    } do
      params =
        valid_folder_params()
        |> Map.put("parent_id", folder2.id)

      conn =
        conn |> authenticate(user, tenant) |> post(~p"/api/folders/#{folder1.id}/move", params)

      response = json_response(conn, 200)
      assert response["data"]["parent_id"] == folder2.id
    end

    test "returns 404 for non-existent target parent", %{
      conn: conn,
      user: user,
      tenant: tenant,
      folder1: folder1
    } do
      fake_id = Ecto.UUID.generate()
      params = valid_folder_params() |> Map.put("parent_id", fake_id)

      conn =
        conn |> authenticate(user, tenant) |> post(~p"/api/folders/#{folder1.id}/move", params)

      response = json_response(conn, 404)
      assert response["error"]["code"] == "not_found"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # GET /api/folders/:folder_id/children
  # ═══════════════════════════════════════════════════════════════════════════

  describe "GET /api/folders/:folder_id/children" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: user.id, tenant_id: tenant.id, role: :member)
      root = insert(:root_folder, owner_id: user.id, tenant_id: tenant.id)
      child1 = insert(:folder, owner_id: user.id, tenant_id: tenant.id, parent_id: root.id)
      child2 = insert(:folder, owner_id: user.id, tenant_id: tenant.id, parent_id: root.id)
      {:ok, tenant: tenant, user: user, root: root, child1: child1, child2: child2}
    end

    test "returns child folders", %{
      conn: conn,
      user: user,
      tenant: tenant,
      root: root,
      child1: child1,
      child2: child2
    } do
      conn = conn |> authenticate(user, tenant) |> get(~p"/api/folders/#{root.id}/children")

      response = json_response(conn, 200)
      child_ids = Enum.map(response["data"], & &1["id"])
      assert child1.id in child_ids
      assert child2.id in child_ids
    end

    test "returns empty for folder with no children", %{
      conn: conn,
      user: user,
      tenant: tenant,
      child1: child1
    } do
      conn = conn |> authenticate(user, tenant) |> get(~p"/api/folders/#{child1.id}/children")

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
        conn |> authenticate(requester, tenant) |> get(~p"/api/folders/#{other_root.id}/children")

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Permission-based access (sharing scenarios)
  # ═══════════════════════════════════════════════════════════════════════════

  describe "permission-based folder operations" do
    setup do
      tenant = insert(:tenant, name: "Test Company")
      owner = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: owner.id, tenant_id: tenant.id, role: :member)
      root = insert(:root_folder, owner_id: owner.id, tenant_id: tenant.id)
      folder = insert(:folder, owner_id: owner.id, tenant_id: tenant.id, parent_id: root.id)

      {:ok, tenant: tenant, owner: owner, root: root, folder: folder}
    end

    test "admin share holder can delete folder", %{
      conn: conn,
      tenant: tenant,
      owner: owner,
      folder: folder
    } do
      admin_user = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: admin_user.id, tenant_id: tenant.id, role: :member)

      insert(:folder_share,
        tenant_id: tenant.id,
        grantor_id: owner.id,
        grantee_id: admin_user.id,
        resource_id: folder.id,
        permission: :admin
      )

      conn =
        conn |> authenticate(admin_user, tenant) |> delete(~p"/api/folders/#{folder.id}")

      assert response(conn, 204)
    end

    test "write share holder can update folder", %{
      conn: conn,
      tenant: tenant,
      owner: owner,
      folder: folder
    } do
      writer = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: writer.id, tenant_id: tenant.id, role: :member)

      insert(:folder_share,
        tenant_id: tenant.id,
        grantor_id: owner.id,
        grantee_id: writer.id,
        resource_id: folder.id,
        permission: :write
      )

      params = %{"encrypted_metadata" => Base.encode64("updated by writer")}

      conn =
        conn |> authenticate(writer, tenant) |> put(~p"/api/folders/#{folder.id}", params)

      response = json_response(conn, 200)
      assert response["data"]["id"] == folder.id
    end

    test "write share holder CANNOT delete folder", %{
      conn: conn,
      tenant: tenant,
      owner: owner,
      folder: folder
    } do
      writer = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: writer.id, tenant_id: tenant.id, role: :member)

      insert(:folder_share,
        tenant_id: tenant.id,
        grantor_id: owner.id,
        grantee_id: writer.id,
        resource_id: folder.id,
        permission: :write
      )

      conn =
        conn |> authenticate(writer, tenant) |> delete(~p"/api/folders/#{folder.id}")

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end

    test "read share holder cannot update folder", %{
      conn: conn,
      tenant: tenant,
      owner: owner,
      folder: folder
    } do
      reader = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: reader.id, tenant_id: tenant.id, role: :member)

      insert(:folder_share,
        tenant_id: tenant.id,
        grantor_id: owner.id,
        grantee_id: reader.id,
        resource_id: folder.id,
        permission: :read
      )

      params = %{"encrypted_metadata" => Base.encode64("hacked")}

      conn =
        conn |> authenticate(reader, tenant) |> put(~p"/api/folders/#{folder.id}", params)

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end

    test "read share holder cannot delete folder", %{
      conn: conn,
      tenant: tenant,
      owner: owner,
      folder: folder
    } do
      reader = insert(:user, tenant_id: tenant.id)
      insert(:user_tenant, user_id: reader.id, tenant_id: tenant.id, role: :member)

      insert(:folder_share,
        tenant_id: tenant.id,
        grantor_id: owner.id,
        grantee_id: reader.id,
        resource_id: folder.id,
        permission: :read
      )

      conn =
        conn |> authenticate(reader, tenant) |> delete(~p"/api/folders/#{folder.id}")

      response = json_response(conn, 403)
      assert response["error"]["code"] == "forbidden"
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Helper Functions
  # ═══════════════════════════════════════════════════════════════════════════

  defp authenticate(conn, user, tenant, role \\ :member) do
    {:ok, token} = Token.generate_access_token(user, tenant.id, role)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  defp valid_folder_params do
    %{
      "encrypted_metadata" => Base.encode64(:crypto.strong_rand_bytes(32)),
      "metadata_nonce" => Base.encode64(:crypto.strong_rand_bytes(12)),
      "wrapped_kek" => Base.encode64(:crypto.strong_rand_bytes(32)),
      "kem_ciphertext" => Base.encode64(:crypto.strong_rand_bytes(64)),
      "owner_wrapped_kek" => Base.encode64(:crypto.strong_rand_bytes(32)),
      "owner_kem_ciphertext" => Base.encode64(:crypto.strong_rand_bytes(64)),
      "signature" => Base.encode64(:crypto.strong_rand_bytes(64))
    }
  end
end
