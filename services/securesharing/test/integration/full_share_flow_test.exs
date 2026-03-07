defmodule SecureSharing.Integration.FullShareFlowTest do
  @moduledoc """
  End-to-end integration test for the complete file sharing flow.

  Tests the full sharing journey:
  1. User A creates folder and file
  2. User A shares file with User B
  3. User B accepts share and can access file
  4. User A revokes share
  5. User B can no longer access file
  """
  use SecureSharingWeb.ConnCase, async: false

  import SecureSharing.Factory

  alias SecureSharing.{Files, Sharing}

  @factory_password "valid_password123"

  describe "complete file sharing flow" do
    setup do
      tenant = insert(:tenant, slug: "share-test-#{System.unique_integer([:positive])}")

      # Create two users in the same tenant
      user_a = insert(:user, tenant_id: tenant.id, email: "user_a@example.com")
      user_b = insert(:user, tenant_id: tenant.id, email: "user_b@example.com")

      # Login as both users
      conn_a =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/auth/login", %{
          "tenant_slug" => tenant.slug,
          "email" => user_a.email,
          "password" => @factory_password
        })

      %{"data" => %{"access_token" => token_a}} = json_response(conn_a, 200)

      conn_b =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/auth/login", %{
          "tenant_slug" => tenant.slug,
          "email" => user_b.email,
          "password" => @factory_password
        })

      %{"data" => %{"access_token" => token_b}} = json_response(conn_b, 200)

      {:ok, tenant: tenant, user_a: user_a, user_b: user_b, token_a: token_a, token_b: token_b}
    end

    test "user A shares file with user B, then revokes access", %{
      tenant: tenant,
      user_a: user_a,
      user_b: user_b,
      token_a: token_a,
      token_b: token_b
    } do
      # Step 1: User A creates root folder
      folder_attrs = %{
        "is_root" => true,
        "wrapped_kek" => Base.encode64(:crypto.strong_rand_bytes(64)),
        "kem_ciphertext" => Base.encode64(:crypto.strong_rand_bytes(128)),
        "owner_wrapped_kek" => Base.encode64(:crypto.strong_rand_bytes(64)),
        "owner_kem_ciphertext" => Base.encode64(:crypto.strong_rand_bytes(128)),
        "encrypted_metadata" => Base.encode64(:crypto.strong_rand_bytes(64))
      }

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token_a}")
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/folders", folder_attrs)

      assert %{"data" => %{"id" => folder_id}} = json_response(conn, 201)

      # Step 2: User A creates file
      file = insert(:file, tenant_id: tenant.id, owner_id: user_a.id, folder_id: folder_id)

      # Step 3: User A shares file with User B
      share_attrs = %{
        "grantee_id" => user_b.id,
        "file_id" => file.id,
        "permission" => "read",
        "wrapped_key" => Base.encode64(:crypto.strong_rand_bytes(64)),
        "kem_ciphertext" => Base.encode64(:crypto.strong_rand_bytes(128)),
        "signature" => Base.encode64(:crypto.strong_rand_bytes(256))
      }

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token_a}")
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/shares/file", share_attrs)

      assert %{"data" => %{"id" => share_id}} = json_response(conn, 201)
      assert is_binary(share_id)

      # Step 4: Verify share was created
      share = Sharing.get_share_grant(share_id)
      assert share.grantor_id == user_a.id
      assert share.grantee_id == user_b.id
      assert share.resource_id == file.id

      # Step 5: User B can now access the file
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token_b}")
        |> get(~p"/api/files/#{file.id}")

      assert %{"data" => file_data} = json_response(conn, 200)
      assert file_data["id"] == file.id

      # Step 6: User B can list shared files
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token_b}")
        |> get(~p"/api/shares/received")

      assert %{"data" => received_shares} = json_response(conn, 200)
      assert length(received_shares) >= 1
      assert Enum.any?(received_shares, fn s -> s["resource_id"] == file.id end)

      # Step 7: User A revokes the share
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token_a}")
        |> delete(~p"/api/shares/#{share_id}")

      assert response(conn, 204)

      # Step 8: User B can no longer access the file
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token_b}")
        |> get(~p"/api/files/#{file.id}")

      # Should return 403 (forbidden) since share was revoked
      assert json_response(conn, 403)
    end
  end

  describe "folder sharing with recursive access" do
    setup do
      tenant = insert(:tenant, slug: "folder-share-#{System.unique_integer([:positive])}")
      user_a = insert(:user, tenant_id: tenant.id)
      user_b = insert(:user, tenant_id: tenant.id)
      root_folder = insert(:root_folder, tenant_id: tenant.id, owner_id: user_a.id)

      conn_a =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/auth/login", %{
          "tenant_slug" => tenant.slug,
          "email" => user_a.email,
          "password" => @factory_password
        })

      %{"data" => %{"access_token" => token_a}} = json_response(conn_a, 200)

      conn_b =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/auth/login", %{
          "tenant_slug" => tenant.slug,
          "email" => user_b.email,
          "password" => @factory_password
        })

      %{"data" => %{"access_token" => token_b}} = json_response(conn_b, 200)

      {:ok,
       tenant: tenant,
       user_a: user_a,
       user_b: user_b,
       root_folder: root_folder,
       token_a: token_a,
       token_b: token_b}
    end

    test "sharing folder grants access to files within", %{
      tenant: tenant,
      user_a: user_a,
      user_b: user_b,
      root_folder: root_folder,
      token_a: token_a,
      token_b: token_b
    } do
      # User A creates subfolder and file
      subfolder =
        insert(:folder, tenant_id: tenant.id, owner_id: user_a.id, parent_id: root_folder.id)

      file = insert(:file, tenant_id: tenant.id, owner_id: user_a.id, folder_id: subfolder.id)

      # Share the subfolder with User B (recursive)
      share_attrs = %{
        "grantee_id" => user_b.id,
        "folder_id" => subfolder.id,
        "permission" => "read",
        "recursive" => true,
        "wrapped_key" => Base.encode64(:crypto.strong_rand_bytes(64)),
        "kem_ciphertext" => Base.encode64(:crypto.strong_rand_bytes(128)),
        "signature" => Base.encode64(:crypto.strong_rand_bytes(256))
      }

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token_a}")
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/shares/folder", share_attrs)

      assert %{"data" => %{"id" => _share_id}} = json_response(conn, 201)

      # User B can access the subfolder
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token_b}")
        |> get(~p"/api/folders/#{subfolder.id}")

      assert %{"data" => folder_data} = json_response(conn, 200)
      assert folder_data["id"] == subfolder.id

      # User B can access the file in the shared folder (recursive access)
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token_b}")
        |> get(~p"/api/files/#{file.id}")

      assert %{"data" => file_data} = json_response(conn, 200)
      assert file_data["id"] == file.id
    end

    test "user cannot share cross-tenant", %{
      tenant: _tenant,
      user_a: user_a,
      root_folder: root_folder,
      token_a: token_a
    } do
      # Create user in different tenant
      other_tenant = insert(:tenant, slug: "other-#{System.unique_integer([:positive])}")
      other_user = insert(:user, tenant_id: other_tenant.id)

      # Create file in user A's folder
      file =
        insert(:file, tenant_id: user_a.tenant_id, owner_id: user_a.id, folder_id: root_folder.id)

      # Try to share with user from different tenant
      share_attrs = %{
        "grantee_id" => other_user.id,
        "file_id" => file.id,
        "permission" => "read",
        "wrapped_key" => Base.encode64(:crypto.strong_rand_bytes(64)),
        "kem_ciphertext" => Base.encode64(:crypto.strong_rand_bytes(128)),
        "signature" => Base.encode64(:crypto.strong_rand_bytes(256))
      }

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token_a}")
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/shares/file", share_attrs)

      # Should fail - cannot share across tenants
      assert json_response(conn, 403)
    end
  end

  describe "share permissions" do
    setup do
      tenant = insert(:tenant, slug: "perm-test-#{System.unique_integer([:positive])}")
      owner = insert(:user, tenant_id: tenant.id)
      reader = insert(:user, tenant_id: tenant.id)
      writer = insert(:user, tenant_id: tenant.id)
      root_folder = insert(:root_folder, tenant_id: tenant.id, owner_id: owner.id)

      test_file =
        insert(:file, tenant_id: tenant.id, owner_id: owner.id, folder_id: root_folder.id)

      # Login all users
      conn_owner =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/auth/login", %{
          "tenant_slug" => tenant.slug,
          "email" => owner.email,
          "password" => @factory_password
        })

      %{"data" => %{"access_token" => token_owner}} = json_response(conn_owner, 200)

      conn_reader =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/auth/login", %{
          "tenant_slug" => tenant.slug,
          "email" => reader.email,
          "password" => @factory_password
        })

      %{"data" => %{"access_token" => token_reader}} = json_response(conn_reader, 200)

      conn_writer =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/auth/login", %{
          "tenant_slug" => tenant.slug,
          "email" => writer.email,
          "password" => @factory_password
        })

      %{"data" => %{"access_token" => token_writer}} = json_response(conn_writer, 200)

      {:ok,
       tenant: tenant,
       owner: owner,
       reader: reader,
       writer: writer,
       root_folder: root_folder,
       test_file: test_file,
       token_owner: token_owner,
       token_reader: token_reader,
       token_writer: token_writer}
    end

    test "read-only share allows read but not write", %{
      reader: reader,
      test_file: test_file,
      token_owner: token_owner,
      token_reader: token_reader
    } do
      # Owner shares file with reader (read permission)
      share_attrs = %{
        "grantee_id" => reader.id,
        "file_id" => test_file.id,
        "permission" => "read",
        "wrapped_key" => Base.encode64(:crypto.strong_rand_bytes(64)),
        "kem_ciphertext" => Base.encode64(:crypto.strong_rand_bytes(128)),
        "signature" => Base.encode64(:crypto.strong_rand_bytes(256))
      }

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token_owner}")
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/shares/file", share_attrs)

      assert %{"data" => %{"id" => _}} = json_response(conn, 201)

      # Reader can read file
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token_reader}")
        |> get(~p"/api/files/#{test_file.id}")

      assert %{"data" => _} = json_response(conn, 200)

      # Reader cannot delete file (would need write access)
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token_reader}")
        |> delete(~p"/api/files/#{test_file.id}")

      # Should be forbidden (read-only)
      assert json_response(conn, 403)
    end

    test "write share allows write operations", %{
      writer: writer,
      root_folder: root_folder,
      token_owner: token_owner,
      token_writer: token_writer
    } do
      # Owner shares folder with writer (write permission)
      share_attrs = %{
        "grantee_id" => writer.id,
        "folder_id" => root_folder.id,
        "permission" => "write",
        "recursive" => true,
        "wrapped_key" => Base.encode64(:crypto.strong_rand_bytes(64)),
        "kem_ciphertext" => Base.encode64(:crypto.strong_rand_bytes(128)),
        "signature" => Base.encode64(:crypto.strong_rand_bytes(256))
      }

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token_owner}")
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/shares/folder", share_attrs)

      assert %{"data" => %{"id" => _}} = json_response(conn, 201)

      # Writer can create file in shared folder
      file_request = %{
        "folder_id" => root_folder.id,
        "encrypted_metadata" => Base.encode64(:crypto.strong_rand_bytes(128)),
        "wrapped_dek" => Base.encode64(:crypto.strong_rand_bytes(64)),
        "kem_ciphertext" => Base.encode64(:crypto.strong_rand_bytes(128)),
        "signature" => Base.encode64(:crypto.strong_rand_bytes(256)),
        "blob_size" => 1024,
        "blob_hash" => Base.encode16(:crypto.strong_rand_bytes(32), case: :lower),
        "content_type" => "text/plain"
      }

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token_writer}")
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/files/upload-url", file_request)

      assert %{"data" => %{"file_id" => new_file_id}} = json_response(conn, 201)

      # New file was created with writer as owner
      new_file = Files.get_file(new_file_id)
      assert new_file.owner_id == writer.id
      assert new_file.folder_id == root_folder.id
    end
  end
end
