defmodule SecureSharing.Integration.FullUploadFlowTest do
  @moduledoc """
  End-to-end integration test for the complete file upload flow.

  Tests the full journey:
  1. User registration with crypto keys
  2. User login and session management
  3. Root folder creation
  4. File metadata creation
  5. Storage presigned URL generation
  6. File status update to complete
  7. File download URL generation
  8. File listing and retrieval
  """
  # Not async to avoid rate limiting issues
  use SecureSharingWeb.ConnCase, async: false

  import SecureSharing.Factory

  alias SecureSharing.{Accounts, Files}

  @password "test_password_12345"
  # Default factory password from factory.ex
  @factory_password "valid_password123"

  describe "complete file upload flow" do
    setup do
      tenant = insert(:tenant, slug: "upload-test-#{System.unique_integer([:positive])}")
      {:ok, tenant: tenant}
    end

    test "user registers, creates folder, uploads file, and retrieves it", %{
      conn: conn,
      tenant: tenant
    } do
      # Step 1: Register user with crypto keys (uses tenant_slug)
      registration_attrs = %{
        "tenant_slug" => tenant.slug,
        "email" => "upload_test_#{System.unique_integer([:positive])}@example.com",
        "password" => @password,
        "public_keys" => %{
          "kem" => Base.encode64(:crypto.strong_rand_bytes(64)),
          "sign" => Base.encode64(:crypto.strong_rand_bytes(64))
        },
        "encrypted_private_keys" => Base.encode64(:crypto.strong_rand_bytes(256)),
        "key_derivation_salt" => Base.encode64(:crypto.strong_rand_bytes(32))
      }

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/auth/register", registration_attrs)

      assert %{"data" => %{"user" => %{"id" => user_id}, "access_token" => token}} =
               json_response(conn, 201)

      assert is_binary(user_id)
      assert is_binary(token)

      # Step 2: Verify user was created correctly
      user = Accounts.get_user!(user_id)
      assert user.email == registration_attrs["email"]
      assert user.tenant_id == tenant.id

      # Step 3: Login to get fresh token and key bundle
      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/auth/login", %{
          "tenant_slug" => tenant.slug,
          "email" => registration_attrs["email"],
          "password" => @password
        })

      assert %{"data" => %{"access_token" => login_token, "user" => user_data}} =
               json_response(conn, 200)

      assert is_map(user_data)

      # Step 4: Get or create root folder
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{login_token}")
        |> get(~p"/api/folders/root")

      root_folder_id =
        case json_response(conn, 200) do
          %{"data" => nil} ->
            # Create root folder
            folder_attrs = %{
              "wrapped_kek" => Base.encode64(:crypto.strong_rand_bytes(64)),
              "kem_ciphertext" => Base.encode64(:crypto.strong_rand_bytes(128)),
              "owner_wrapped_kek" => Base.encode64(:crypto.strong_rand_bytes(64)),
              "owner_kem_ciphertext" => Base.encode64(:crypto.strong_rand_bytes(128)),
              "encrypted_metadata" => Base.encode64(:crypto.strong_rand_bytes(64)),
              "is_root" => true
            }

            conn =
              build_conn()
              |> put_req_header("authorization", "Bearer #{login_token}")
              |> put_req_header("content-type", "application/json")
              |> post(~p"/api/folders", folder_attrs)

            %{"data" => %{"id" => folder_id}} = json_response(conn, 201)
            folder_id

          %{"data" => %{"id" => folder_id}} ->
            folder_id
        end

      # Step 5: Request upload URL for new file
      upload_request = %{
        "folder_id" => root_folder_id,
        "encrypted_metadata" => Base.encode64(:crypto.strong_rand_bytes(128)),
        "wrapped_dek" => Base.encode64(:crypto.strong_rand_bytes(64)),
        "kem_ciphertext" => Base.encode64(:crypto.strong_rand_bytes(128)),
        "signature" => Base.encode64(:crypto.strong_rand_bytes(256)),
        "blob_size" => 1024,
        "blob_hash" => Base.encode16(:crypto.strong_rand_bytes(32), case: :lower),
        "content_type" => "application/octet-stream"
      }

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{login_token}")
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/files/upload-url", upload_request)

      assert %{"data" => %{"file_id" => file_id, "upload_url" => upload_url}} =
               json_response(conn, 201)

      assert is_binary(file_id)
      assert is_binary(upload_url)

      # Step 6: Verify file was created in pending state (uploading)
      file = Files.get_file(file_id)
      # File status starts as "uploading" until client confirms upload complete
      assert file.status in ["uploading", "complete"]
      assert file.folder_id == root_folder_id
      assert file.owner_id == user_id

      # Step 7: Ensure file is complete (either already complete or update status)
      {:ok, complete_file} =
        if file.status == "complete" do
          {:ok, file}
        else
          Files.update_file_status(file, %{status: "complete"})
        end

      assert complete_file.status == "complete"

      # Step 8: Request download URL
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{login_token}")
        |> get(~p"/api/files/#{file_id}/download-url")

      assert %{"data" => %{"download_url" => download_url}} = json_response(conn, 200)
      assert is_binary(download_url)

      # Step 9: List folder contents
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{login_token}")
        |> get(~p"/api/folders/#{root_folder_id}/files")

      assert %{"data" => files} = json_response(conn, 200)
      assert length(files) == 1
      assert hd(files)["id"] == file_id

      # Step 10: Get file details
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{login_token}")
        |> get(~p"/api/files/#{file_id}")

      assert %{"data" => file_data} = json_response(conn, 200)
      assert file_data["id"] == file_id
      assert file_data["status"] == "complete"
    end
  end

  describe "nested folder operations" do
    setup do
      tenant = insert(:tenant, slug: "nested-test-#{System.unique_integer([:positive])}")
      user = insert(:user, tenant_id: tenant.id)
      root_folder = insert(:root_folder, tenant_id: tenant.id, owner_id: user.id)

      # Login using default factory password
      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/auth/login", %{
          "tenant_slug" => tenant.slug,
          "email" => user.email,
          "password" => @factory_password
        })

      %{"data" => %{"access_token" => token}} = json_response(conn, 200)

      {:ok, tenant: tenant, user: user, root_folder: root_folder, token: token}
    end

    test "user can create nested folders and files", %{
      root_folder: root_folder,
      token: token
    } do
      # Create subfolder
      subfolder_attrs = %{
        "parent_id" => root_folder.id,
        "wrapped_kek" => Base.encode64(:crypto.strong_rand_bytes(64)),
        "kem_ciphertext" => Base.encode64(:crypto.strong_rand_bytes(128)),
        "owner_wrapped_kek" => Base.encode64(:crypto.strong_rand_bytes(64)),
        "owner_kem_ciphertext" => Base.encode64(:crypto.strong_rand_bytes(128)),
        "encrypted_metadata" => Base.encode64(:crypto.strong_rand_bytes(64))
      }

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/folders", subfolder_attrs)

      assert %{"data" => %{"id" => subfolder_id}} = json_response(conn, 201)

      # Create file in subfolder
      file_request = %{
        "folder_id" => subfolder_id,
        "encrypted_metadata" => Base.encode64(:crypto.strong_rand_bytes(128)),
        "wrapped_dek" => Base.encode64(:crypto.strong_rand_bytes(64)),
        "kem_ciphertext" => Base.encode64(:crypto.strong_rand_bytes(128)),
        "signature" => Base.encode64(:crypto.strong_rand_bytes(256)),
        "blob_size" => 2048,
        "blob_hash" => Base.encode16(:crypto.strong_rand_bytes(32), case: :lower),
        "content_type" => "text/plain"
      }

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/files/upload-url", file_request)

      assert %{"data" => %{"file_id" => file_id}} = json_response(conn, 201)

      # Verify file is in subfolder
      file = Files.get_file(file_id)
      assert file.folder_id == subfolder_id

      # List children of root should show subfolder
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> get(~p"/api/folders/#{root_folder.id}/children")

      assert %{"data" => children} = json_response(conn, 200)
      assert length(children) == 1
      assert hd(children)["id"] == subfolder_id
    end
  end

  describe "cross-tenant isolation" do
    test "user cannot access other tenant's files", %{conn: conn} do
      # Create user in first tenant
      tenant_a = insert(:tenant, slug: "tenant-a-#{System.unique_integer([:positive])}")
      user_a = insert(:user, tenant_id: tenant_a.id)
      folder_a = insert(:root_folder, tenant_id: tenant_a.id, owner_id: user_a.id)
      file_a = insert(:file, tenant_id: tenant_a.id, owner_id: user_a.id, folder_id: folder_a.id)

      # Create user in different tenant
      tenant_b = insert(:tenant, slug: "tenant-b-#{System.unique_integer([:positive])}")
      user_b = insert(:user, tenant_id: tenant_b.id)

      # Login as user_b
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/auth/login", %{
          "tenant_slug" => tenant_b.slug,
          "email" => user_b.email,
          "password" => @factory_password
        })

      assert %{"data" => %{"access_token" => token_b}} = json_response(conn, 200)

      # Try to access file_a (should fail)
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token_b}")
        |> get(~p"/api/files/#{file_a.id}")

      # Should return 403 (forbidden - user doesn't have access to this resource)
      assert json_response(conn, 403)
    end
  end

  describe "file operations" do
    setup do
      tenant = insert(:tenant, slug: "file-ops-#{System.unique_integer([:positive])}")
      user = insert(:user, tenant_id: tenant.id)
      folder = insert(:root_folder, tenant_id: tenant.id, owner_id: user.id)

      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/auth/login", %{
          "tenant_slug" => tenant.slug,
          "email" => user.email,
          "password" => @factory_password
        })

      %{"data" => %{"access_token" => token}} = json_response(conn, 200)

      {:ok, tenant: tenant, user: user, folder: folder, token: token}
    end

    test "can move file between folders", %{
      user: user,
      folder: root_folder,
      token: token,
      tenant: tenant
    } do
      # Create a file in root folder
      file = insert(:file, tenant_id: tenant.id, owner_id: user.id, folder_id: root_folder.id)

      # Create destination folder
      dest_folder =
        insert(:folder, tenant_id: tenant.id, owner_id: user.id, parent_id: root_folder.id)

      # Move file
      move_attrs = %{
        "folder_id" => dest_folder.id,
        "wrapped_dek" => Base.encode64(:crypto.strong_rand_bytes(64)),
        "kem_ciphertext" => Base.encode64(:crypto.strong_rand_bytes(128)),
        "signature" => Base.encode64(:crypto.strong_rand_bytes(256))
      }

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/files/#{file.id}/move", move_attrs)

      assert %{"data" => %{"folder_id" => new_folder_id}} = json_response(conn, 200)
      assert new_folder_id == dest_folder.id
    end

    test "can delete file", %{user: user, folder: folder, token: token, tenant: tenant} do
      file = insert(:file, tenant_id: tenant.id, owner_id: user.id, folder_id: folder.id)

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> delete(~p"/api/files/#{file.id}")

      assert response(conn, 204)

      # Verify file is deleted
      assert Files.get_file(file.id) == nil
    end

    test "can delete non-root folder", %{
      user: user,
      folder: root_folder,
      token: token,
      tenant: tenant
    } do
      child_folder =
        insert(:folder, tenant_id: tenant.id, owner_id: user.id, parent_id: root_folder.id)

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> delete(~p"/api/folders/#{child_folder.id}")

      assert response(conn, 204)
    end

    test "cannot delete root folder", %{folder: root_folder, token: token} do
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> delete(~p"/api/folders/#{root_folder.id}")

      assert json_response(conn, 422)
    end
  end
end
