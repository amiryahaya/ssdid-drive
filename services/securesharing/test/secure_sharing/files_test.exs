defmodule SecureSharing.FilesTest do
  use SecureSharing.DataCase, async: true

  alias SecureSharing.Files
  alias SecureSharing.Files.{Folder, File}

  describe "folders" do
    setup do
      tenant = insert(:tenant)
      user = insert(:user, tenant_id: tenant.id)
      {:ok, tenant: tenant, user: user}
    end

    test "create_root_folder/2 creates a root folder for user", %{user: user} do
      attrs = %{
        wrapped_kek: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        owner_wrapped_kek: :crypto.strong_rand_bytes(64),
        owner_kem_ciphertext: :crypto.strong_rand_bytes(128),
        encrypted_metadata: :crypto.strong_rand_bytes(64)
      }

      assert {:ok, %Folder{} = folder} = Files.create_root_folder(user, attrs)
      assert folder.is_root == true
      assert folder.parent_id == nil
      assert folder.owner_id == user.id
      assert folder.tenant_id == user.tenant_id
    end

    test "create_root_folder/2 stores metadata nonce and signature", %{user: user} do
      metadata_nonce = :crypto.strong_rand_bytes(12)
      signature = :crypto.strong_rand_bytes(256)

      attrs = %{
        wrapped_kek: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        owner_wrapped_kek: :crypto.strong_rand_bytes(64),
        owner_kem_ciphertext: :crypto.strong_rand_bytes(128),
        encrypted_metadata: :crypto.strong_rand_bytes(64),
        metadata_nonce: metadata_nonce,
        signature: signature
      }

      assert {:ok, %Folder{} = folder} = Files.create_root_folder(user, attrs)
      assert folder.metadata_nonce == metadata_nonce
      assert folder.signature == signature
    end

    test "create_root_folder/2 enforces one root per user", %{user: user} do
      attrs = %{
        wrapped_kek: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        owner_wrapped_kek: :crypto.strong_rand_bytes(64),
        owner_kem_ciphertext: :crypto.strong_rand_bytes(128)
      }

      assert {:ok, _} = Files.create_root_folder(user, attrs)
      assert {:error, changeset} = Files.create_root_folder(user, attrs)
      assert "user already has a root folder" in errors_on(changeset).owner_id
    end

    test "create_folder/3 creates a child folder", %{user: user} do
      root = insert(:root_folder, tenant_id: user.tenant_id, owner_id: user.id)

      attrs = %{
        wrapped_kek: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        owner_wrapped_kek: :crypto.strong_rand_bytes(64),
        owner_kem_ciphertext: :crypto.strong_rand_bytes(128),
        encrypted_metadata: :crypto.strong_rand_bytes(64)
      }

      assert {:ok, %Folder{} = folder} = Files.create_folder(root, user, attrs)
      assert folder.is_root == false
      assert folder.parent_id == root.id
      assert folder.owner_id == user.id
    end

    test "get_root_folder/1 returns user's root folder", %{user: user} do
      root = insert(:root_folder, tenant_id: user.tenant_id, owner_id: user.id)

      assert found = Files.get_root_folder(user)
      assert found.id == root.id
    end

    test "get_or_create_root_folder/2 returns existing root", %{user: user} do
      root = insert(:root_folder, tenant_id: user.tenant_id, owner_id: user.id)

      attrs = %{
        wrapped_kek: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        owner_wrapped_kek: :crypto.strong_rand_bytes(64),
        owner_kem_ciphertext: :crypto.strong_rand_bytes(128)
      }

      assert {:ok, found} = Files.get_or_create_root_folder(user, attrs)
      assert found.id == root.id
    end

    test "list_user_folders/1 returns all user's folders", %{user: user} do
      root = insert(:root_folder, tenant_id: user.tenant_id, owner_id: user.id)
      child = insert(:folder, tenant_id: user.tenant_id, owner_id: user.id, parent_id: root.id)

      folders = Files.list_user_folders(user)
      assert length(folders) == 2
      folder_ids = Enum.map(folders, & &1.id)
      assert root.id in folder_ids
      assert child.id in folder_ids
    end

    test "list_child_folders/1 returns folder's children", %{user: user} do
      root = insert(:root_folder, tenant_id: user.tenant_id, owner_id: user.id)
      child1 = insert(:folder, tenant_id: user.tenant_id, owner_id: user.id, parent_id: root.id)
      child2 = insert(:folder, tenant_id: user.tenant_id, owner_id: user.id, parent_id: root.id)

      _grandchild =
        insert(:folder, tenant_id: user.tenant_id, owner_id: user.id, parent_id: child1.id)

      children = Files.list_child_folders(root)
      assert length(children) == 2
      child_ids = Enum.map(children, & &1.id)
      assert child1.id in child_ids
      assert child2.id in child_ids
    end

    test "delete_folder/1 cannot delete root folder", %{user: user} do
      root = insert(:root_folder, tenant_id: user.tenant_id, owner_id: user.id)

      assert {:error, :cannot_delete_root} = Files.delete_folder(root)
    end

    test "delete_folder/1 deletes non-root folder", %{user: user} do
      root = insert(:root_folder, tenant_id: user.tenant_id, owner_id: user.id)
      child = insert(:folder, tenant_id: user.tenant_id, owner_id: user.id, parent_id: root.id)

      assert {:ok, _} = Files.delete_folder(child)
      assert Files.get_folder(child.id) == nil
    end

    test "move_folder/4 updates parent and wrapped KEK", %{user: user} do
      root = insert(:root_folder, tenant_id: user.tenant_id, owner_id: user.id)
      folder = insert(:folder, tenant_id: user.tenant_id, owner_id: user.id, parent_id: root.id)

      new_parent =
        insert(:folder, tenant_id: user.tenant_id, owner_id: user.id, parent_id: root.id)

      new_wrapped_kek = :crypto.strong_rand_bytes(64)
      new_kem_ciphertext = :crypto.strong_rand_bytes(128)
      new_signature = :crypto.strong_rand_bytes(256)

      attrs = %{
        wrapped_kek: new_wrapped_kek,
        kem_ciphertext: new_kem_ciphertext,
        signature: new_signature
      }

      assert {:ok, moved} = Files.move_folder(folder, new_parent, user, attrs)
      assert moved.parent_id == new_parent.id
      assert moved.wrapped_kek == new_wrapped_kek
      assert moved.kem_ciphertext == new_kem_ciphertext
      assert moved.signature == new_signature
    end

    test "move_folder/4 prevents cycles", %{user: user} do
      root = insert(:root_folder, tenant_id: user.tenant_id, owner_id: user.id)
      child = insert(:folder, tenant_id: user.tenant_id, owner_id: user.id, parent_id: root.id)

      attrs = %{
        wrapped_kek: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        signature: :crypto.strong_rand_bytes(256)
      }

      assert {:error, :conflict} = Files.move_folder(root, child, user, attrs)
    end

    test "move_folder/4 requires write access to destination", %{user: user} do
      root = insert(:root_folder, tenant_id: user.tenant_id, owner_id: user.id)
      folder = insert(:folder, tenant_id: user.tenant_id, owner_id: user.id, parent_id: root.id)
      other_user = insert(:user, tenant_id: user.tenant_id)
      other_parent = insert(:folder, tenant_id: user.tenant_id, owner_id: other_user.id)

      attrs = %{
        wrapped_kek: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        signature: :crypto.strong_rand_bytes(256)
      }

      assert {:error, :forbidden} = Files.move_folder(folder, other_parent, user, attrs)
    end

    test "get_folder_path/1 returns path from root", %{user: user} do
      root = insert(:root_folder, tenant_id: user.tenant_id, owner_id: user.id)
      child = insert(:folder, tenant_id: user.tenant_id, owner_id: user.id, parent_id: root.id)

      grandchild =
        insert(:folder, tenant_id: user.tenant_id, owner_id: user.id, parent_id: child.id)

      path = Files.get_folder_path(grandchild)
      assert length(path) == 3
      assert Enum.at(path, 0).id == root.id
      assert Enum.at(path, 1).id == child.id
      assert Enum.at(path, 2).id == grandchild.id
    end
  end

  describe "files" do
    setup do
      tenant = insert(:tenant)
      user = insert(:user, tenant_id: tenant.id)
      folder = insert(:root_folder, tenant_id: tenant.id, owner_id: user.id)
      {:ok, tenant: tenant, user: user, folder: folder}
    end

    test "create_file/3 creates a file in folder", %{user: user, folder: folder} do
      attrs = %{
        encrypted_metadata: :crypto.strong_rand_bytes(128),
        wrapped_dek: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        signature: :crypto.strong_rand_bytes(256),
        storage_path: "uploads/test/#{UUIDv7.generate()}",
        blob_size: 1024,
        blob_hash: Base.encode16(:crypto.strong_rand_bytes(32), case: :lower)
      }

      assert {:ok, %File{} = file} = Files.create_file(folder, user, attrs)
      assert file.folder_id == folder.id
      assert file.owner_id == user.id
      assert file.tenant_id == folder.tenant_id
      assert file.blob_size == 1024
      assert file.status == "complete"
    end

    test "create_file/3 requires unique storage_path", %{user: user, folder: folder} do
      storage_path = "uploads/test/#{UUIDv7.generate()}"

      attrs = %{
        encrypted_metadata: :crypto.strong_rand_bytes(128),
        wrapped_dek: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        signature: :crypto.strong_rand_bytes(256),
        storage_path: storage_path,
        blob_size: 1024
      }

      assert {:ok, _} = Files.create_file(folder, user, attrs)
      assert {:error, changeset} = Files.create_file(folder, user, attrs)
      assert "has already been taken" in errors_on(changeset).storage_path
    end

    test "list_folder_files/1 returns files in folder", %{user: user, folder: folder} do
      file1 = insert(:file, tenant_id: folder.tenant_id, owner_id: user.id, folder_id: folder.id)
      file2 = insert(:file, tenant_id: folder.tenant_id, owner_id: user.id, folder_id: folder.id)

      files = Files.list_folder_files(folder)
      assert length(files) == 2
      file_ids = Enum.map(files, & &1.id)
      assert file1.id in file_ids
      assert file2.id in file_ids
    end

    test "list_user_files/1 returns all user's files", %{
      tenant: tenant,
      user: user,
      folder: folder
    } do
      file1 = insert(:file, tenant_id: tenant.id, owner_id: user.id, folder_id: folder.id)

      # Create another folder and file
      folder2 = insert(:folder, tenant_id: tenant.id, owner_id: user.id, parent_id: folder.id)
      file2 = insert(:file, tenant_id: tenant.id, owner_id: user.id, folder_id: folder2.id)

      files = Files.list_user_files(user)
      assert length(files) == 2
      file_ids = Enum.map(files, & &1.id)
      assert file1.id in file_ids
      assert file2.id in file_ids
    end

    test "update_file_status/2 updates status", %{user: user, folder: folder} do
      file =
        insert(:file,
          tenant_id: folder.tenant_id,
          owner_id: user.id,
          folder_id: folder.id,
          status: "uploading"
        )

      assert {:ok, updated} =
               Files.update_file_status(file, %{status: "complete", blob_size: 2048})

      assert updated.status == "complete"
      assert updated.blob_size == 2048
    end

    test "delete_file/1 removes file", %{user: user, folder: folder} do
      file = insert(:file, tenant_id: folder.tenant_id, owner_id: user.id, folder_id: folder.id)

      assert {:ok, _} = Files.delete_file(file)
      assert Files.get_file(file.id) == nil
    end

    test "calculate_user_storage/1 sums blob sizes", %{tenant: tenant, user: user, folder: folder} do
      insert(:file,
        tenant_id: tenant.id,
        owner_id: user.id,
        folder_id: folder.id,
        blob_size: 1000
      )

      insert(:file,
        tenant_id: tenant.id,
        owner_id: user.id,
        folder_id: folder.id,
        blob_size: 2000
      )

      insert(:file,
        tenant_id: tenant.id,
        owner_id: user.id,
        folder_id: folder.id,
        blob_size: 3000
      )

      assert Files.calculate_user_storage(user) == 6000
    end

    test "has_storage_quota?/2 checks against tenant quota", %{
      tenant: tenant,
      user: user,
      folder: folder
    } do
      # Tenant has 10GB quota by default
      insert(:file,
        tenant_id: tenant.id,
        owner_id: user.id,
        folder_id: folder.id,
        blob_size: 5_000_000_000
      )

      # Should have room for 1GB more
      assert Files.has_storage_quota?(user, 1_000_000_000) == true

      # Should not have room for 6GB more
      assert Files.has_storage_quota?(user, 6_000_000_000) == false
    end

    test "move_file/4 updates folder and re-wrapped keys", %{
      tenant: tenant,
      user: user,
      folder: folder
    } do
      file = insert(:file, tenant_id: tenant.id, owner_id: user.id, folder_id: folder.id)
      new_folder = insert(:folder, tenant_id: tenant.id, owner_id: user.id, parent_id: folder.id)

      new_wrapped_dek = :crypto.strong_rand_bytes(64)
      new_kem_ciphertext = :crypto.strong_rand_bytes(128)
      new_signature = :crypto.strong_rand_bytes(256)

      attrs = %{
        wrapped_dek: new_wrapped_dek,
        kem_ciphertext: new_kem_ciphertext,
        signature: new_signature
      }

      assert {:ok, moved} = Files.move_file(file, new_folder, user, attrs)
      assert moved.folder_id == new_folder.id
      assert moved.wrapped_dek == new_wrapped_dek
      assert moved.kem_ciphertext == new_kem_ciphertext
      assert moved.signature == new_signature
    end

    test "move_file/4 prevents cross-tenant moves", %{tenant: tenant, user: user, folder: folder} do
      file = insert(:file, tenant_id: tenant.id, owner_id: user.id, folder_id: folder.id)

      # Create folder in different tenant
      other_tenant = insert(:tenant)
      other_user = insert(:user, tenant_id: other_tenant.id)
      other_folder = insert(:root_folder, tenant_id: other_tenant.id, owner_id: other_user.id)

      attrs = %{
        wrapped_dek: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        signature: :crypto.strong_rand_bytes(256)
      }

      assert {:error, :cross_tenant_operation} = Files.move_file(file, other_folder, user, attrs)
    end

    test "move_file/4 requires write permission on file", %{
      tenant: tenant,
      user: user,
      folder: folder
    } do
      # Create a file owned by someone else
      other_user = insert(:user, tenant_id: tenant.id)
      other_folder = insert(:root_folder, tenant_id: tenant.id, owner_id: other_user.id)

      other_file =
        insert(:file, tenant_id: tenant.id, owner_id: other_user.id, folder_id: other_folder.id)

      # user tries to move other_user's file
      attrs = %{
        wrapped_dek: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        signature: :crypto.strong_rand_bytes(256)
      }

      assert {:error, :forbidden} = Files.move_file(other_file, folder, user, attrs)
    end

    test "move_file/4 requires write permission on destination folder", %{
      tenant: tenant,
      user: user,
      folder: folder
    } do
      file = insert(:file, tenant_id: tenant.id, owner_id: user.id, folder_id: folder.id)

      # Create folder owned by someone else (no share granted to user)
      other_user = insert(:user, tenant_id: tenant.id)
      other_folder = insert(:root_folder, tenant_id: tenant.id, owner_id: other_user.id)

      attrs = %{
        wrapped_dek: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        signature: :crypto.strong_rand_bytes(256)
      }

      # user owns the file but doesn't have write access to destination
      assert {:error, :forbidden} = Files.move_file(file, other_folder, user, attrs)
    end
  end

  describe "tenant isolation" do
    test "folders are isolated by tenant" do
      tenant1 = insert(:tenant)
      tenant2 = insert(:tenant)
      user1 = insert(:user, tenant_id: tenant1.id)
      user2 = insert(:user, tenant_id: tenant2.id)

      folder1 = insert(:root_folder, tenant_id: tenant1.id, owner_id: user1.id)
      folder2 = insert(:root_folder, tenant_id: tenant2.id, owner_id: user2.id)

      # User1's folders
      folders1 = Files.list_user_folders(user1)
      assert length(folders1) == 1
      assert hd(folders1).id == folder1.id

      # User2's folders
      folders2 = Files.list_user_folders(user2)
      assert length(folders2) == 1
      assert hd(folders2).id == folder2.id
    end

    test "create_folder/3 prevents cross-tenant folder creation" do
      tenant1 = insert(:tenant)
      tenant2 = insert(:tenant)
      user_from_tenant2 = insert(:user, tenant_id: tenant2.id)

      folder_in_tenant1 =
        insert(:root_folder,
          tenant_id: tenant1.id,
          owner_id: insert(:user, tenant_id: tenant1.id).id
        )

      attrs = %{
        wrapped_kek: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        owner_wrapped_kek: :crypto.strong_rand_bytes(64),
        owner_kem_ciphertext: :crypto.strong_rand_bytes(128),
        encrypted_metadata: :crypto.strong_rand_bytes(64)
      }

      # User from tenant2 should not be able to create folder in tenant1's folder
      assert {:error, :cross_tenant_operation} =
               Files.create_folder(folder_in_tenant1, user_from_tenant2, attrs)
    end

    test "create_file/3 prevents cross-tenant file creation" do
      tenant1 = insert(:tenant)
      tenant2 = insert(:tenant)
      user_from_tenant2 = insert(:user, tenant_id: tenant2.id)

      folder_in_tenant1 =
        insert(:root_folder,
          tenant_id: tenant1.id,
          owner_id: insert(:user, tenant_id: tenant1.id).id
        )

      attrs = %{
        encrypted_metadata: :crypto.strong_rand_bytes(128),
        wrapped_dek: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        signature: :crypto.strong_rand_bytes(256),
        storage_path: "uploads/test/#{UUIDv7.generate()}",
        blob_size: 1024
      }

      # User from tenant2 should not be able to create file in tenant1's folder
      assert {:error, :cross_tenant_operation} =
               Files.create_file(folder_in_tenant1, user_from_tenant2, attrs)
    end
  end

  describe "authorization" do
    test "create_folder/3 requires write permission on parent folder" do
      tenant = insert(:tenant)
      owner = insert(:user, tenant_id: tenant.id)
      other_user = insert(:user, tenant_id: tenant.id)
      owner_folder = insert(:root_folder, tenant_id: tenant.id, owner_id: owner.id)

      attrs = %{
        wrapped_kek: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        owner_wrapped_kek: :crypto.strong_rand_bytes(64),
        owner_kem_ciphertext: :crypto.strong_rand_bytes(128),
        encrypted_metadata: :crypto.strong_rand_bytes(64)
      }

      # Same-tenant user without write permission should be forbidden
      assert {:error, :forbidden} = Files.create_folder(owner_folder, other_user, attrs)
    end

    test "create_folder/3 allows owner to create child folder" do
      tenant = insert(:tenant)
      owner = insert(:user, tenant_id: tenant.id)
      owner_folder = insert(:root_folder, tenant_id: tenant.id, owner_id: owner.id)

      attrs = %{
        wrapped_kek: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        owner_wrapped_kek: :crypto.strong_rand_bytes(64),
        owner_kem_ciphertext: :crypto.strong_rand_bytes(128),
        encrypted_metadata: :crypto.strong_rand_bytes(64)
      }

      # Owner should be able to create child folder
      assert {:ok, %Folder{}} = Files.create_folder(owner_folder, owner, attrs)
    end

    test "create_folder/3 allows user with write share to create child folder" do
      alias SecureSharing.Sharing

      tenant = insert(:tenant)
      owner = insert(:user, tenant_id: tenant.id)
      shared_user = insert(:user, tenant_id: tenant.id)
      owner_folder = insert(:root_folder, tenant_id: tenant.id, owner_id: owner.id)

      # Grant write share to shared_user
      share_attrs = %{
        wrapped_key: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        signature: :crypto.strong_rand_bytes(256),
        permission: :write,
        recursive: false
      }

      {:ok, _share} = Sharing.share_folder(owner_folder, owner, shared_user, share_attrs)

      attrs = %{
        wrapped_kek: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        owner_wrapped_kek: :crypto.strong_rand_bytes(64),
        owner_kem_ciphertext: :crypto.strong_rand_bytes(128),
        encrypted_metadata: :crypto.strong_rand_bytes(64)
      }

      # User with write share should be able to create child folder
      assert {:ok, %Folder{}} = Files.create_folder(owner_folder, shared_user, attrs)
    end

    test "create_folder/3 denies user with read-only share" do
      alias SecureSharing.Sharing

      tenant = insert(:tenant)
      owner = insert(:user, tenant_id: tenant.id)
      shared_user = insert(:user, tenant_id: tenant.id)
      owner_folder = insert(:root_folder, tenant_id: tenant.id, owner_id: owner.id)

      # Grant read-only share to shared_user
      share_attrs = %{
        wrapped_key: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        signature: :crypto.strong_rand_bytes(256),
        permission: :read,
        recursive: false
      }

      {:ok, _share} = Sharing.share_folder(owner_folder, owner, shared_user, share_attrs)

      attrs = %{
        wrapped_kek: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        owner_wrapped_kek: :crypto.strong_rand_bytes(64),
        owner_kem_ciphertext: :crypto.strong_rand_bytes(128),
        encrypted_metadata: :crypto.strong_rand_bytes(64)
      }

      # User with read-only share should be forbidden from creating
      assert {:error, :forbidden} = Files.create_folder(owner_folder, shared_user, attrs)
    end

    test "create_file/3 requires write permission on folder" do
      tenant = insert(:tenant)
      owner = insert(:user, tenant_id: tenant.id)
      other_user = insert(:user, tenant_id: tenant.id)
      owner_folder = insert(:root_folder, tenant_id: tenant.id, owner_id: owner.id)

      attrs = %{
        encrypted_metadata: :crypto.strong_rand_bytes(128),
        wrapped_dek: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        signature: :crypto.strong_rand_bytes(256),
        storage_path: "uploads/test/#{UUIDv7.generate()}",
        blob_size: 1024
      }

      # Same-tenant user without write permission should be forbidden
      assert {:error, :forbidden} = Files.create_file(owner_folder, other_user, attrs)
    end

    test "create_file/3 allows owner to create file" do
      tenant = insert(:tenant)
      owner = insert(:user, tenant_id: tenant.id)
      owner_folder = insert(:root_folder, tenant_id: tenant.id, owner_id: owner.id)

      attrs = %{
        encrypted_metadata: :crypto.strong_rand_bytes(128),
        wrapped_dek: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        signature: :crypto.strong_rand_bytes(256),
        storage_path: "uploads/test/#{UUIDv7.generate()}",
        blob_size: 1024
      }

      # Owner should be able to create file
      assert {:ok, %File{}} = Files.create_file(owner_folder, owner, attrs)
    end

    test "create_file/3 allows user with write share to create file" do
      alias SecureSharing.Sharing

      tenant = insert(:tenant)
      owner = insert(:user, tenant_id: tenant.id)
      shared_user = insert(:user, tenant_id: tenant.id)
      owner_folder = insert(:root_folder, tenant_id: tenant.id, owner_id: owner.id)

      # Grant write share to shared_user
      share_attrs = %{
        wrapped_key: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        signature: :crypto.strong_rand_bytes(256),
        permission: :write,
        recursive: false
      }

      {:ok, _share} = Sharing.share_folder(owner_folder, owner, shared_user, share_attrs)

      attrs = %{
        encrypted_metadata: :crypto.strong_rand_bytes(128),
        wrapped_dek: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        signature: :crypto.strong_rand_bytes(256),
        storage_path: "uploads/test/#{UUIDv7.generate()}",
        blob_size: 1024
      }

      # User with write share should be able to create file
      assert {:ok, %File{}} = Files.create_file(owner_folder, shared_user, attrs)
    end

    test "create_file/3 denies user with read-only share" do
      alias SecureSharing.Sharing

      tenant = insert(:tenant)
      owner = insert(:user, tenant_id: tenant.id)
      shared_user = insert(:user, tenant_id: tenant.id)
      owner_folder = insert(:root_folder, tenant_id: tenant.id, owner_id: owner.id)

      # Grant read-only share to shared_user
      share_attrs = %{
        wrapped_key: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        signature: :crypto.strong_rand_bytes(256),
        permission: :read,
        recursive: false
      }

      {:ok, _share} = Sharing.share_folder(owner_folder, owner, shared_user, share_attrs)

      attrs = %{
        encrypted_metadata: :crypto.strong_rand_bytes(128),
        wrapped_dek: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        signature: :crypto.strong_rand_bytes(256),
        storage_path: "uploads/test/#{UUIDv7.generate()}",
        blob_size: 1024
      }

      # User with read-only share should be forbidden from creating
      assert {:error, :forbidden} = Files.create_file(owner_folder, shared_user, attrs)
    end
  end

  describe "pagination" do
    setup do
      tenant = insert(:tenant)
      user = insert(:user, tenant_id: tenant.id)
      root = insert(:root_folder, tenant_id: tenant.id, owner_id: user.id)
      {:ok, tenant: tenant, user: user, folder: root}
    end

    test "list_folder_files/2 supports pagination", %{tenant: tenant, user: user, folder: folder} do
      # Create 5 files
      for i <- 1..5 do
        insert(:file,
          tenant_id: tenant.id,
          owner_id: user.id,
          folder_id: folder.id,
          blob_size: i * 100
        )
      end

      # Get first page (2 items)
      page1 = Files.list_folder_files(folder, %{offset: 0, limit: 2})
      assert length(page1) == 2

      # Get second page
      page2 = Files.list_folder_files(folder, %{offset: 2, limit: 2})
      assert length(page2) == 2

      # Get third page
      page3 = Files.list_folder_files(folder, %{offset: 4, limit: 2})
      assert length(page3) == 1

      # All pages should have different files
      all_ids = Enum.map(page1 ++ page2 ++ page3, & &1.id)
      assert length(Enum.uniq(all_ids)) == 5
    end

    test "count_folder_files/1 returns correct count", %{
      tenant: tenant,
      user: user,
      folder: folder
    } do
      # Create 3 files
      for _ <- 1..3 do
        insert(:file, tenant_id: tenant.id, owner_id: user.id, folder_id: folder.id)
      end

      assert Files.count_folder_files(folder) == 3
    end

    test "list_user_folders/2 supports pagination", %{tenant: tenant, user: user, folder: root} do
      # Create 4 more folders (root is already 1)
      for _ <- 1..4 do
        insert(:folder, tenant_id: tenant.id, owner_id: user.id, parent_id: root.id)
      end

      # Get first page
      page1 = Files.list_user_folders(user, %{offset: 0, limit: 2})
      assert length(page1) == 2

      # Get second page
      page2 = Files.list_user_folders(user, %{offset: 2, limit: 2})
      assert length(page2) == 2

      # Get third page
      page3 = Files.list_user_folders(user, %{offset: 4, limit: 2})
      assert length(page3) == 1
    end

    test "count_user_folders/1 returns correct count", %{tenant: tenant, user: user, folder: root} do
      # Root + 2 child folders = 3 total
      insert(:folder, tenant_id: tenant.id, owner_id: user.id, parent_id: root.id)
      insert(:folder, tenant_id: tenant.id, owner_id: user.id, parent_id: root.id)

      assert Files.count_user_folders(user) == 3
    end

    test "list_child_folders/2 supports pagination", %{tenant: tenant, user: user, folder: root} do
      # Create 5 child folders
      for _ <- 1..5 do
        insert(:folder, tenant_id: tenant.id, owner_id: user.id, parent_id: root.id)
      end

      # Get first page
      page1 = Files.list_child_folders(root, %{offset: 0, limit: 2})
      assert length(page1) == 2

      # Get remaining
      page2 = Files.list_child_folders(root, %{offset: 2, limit: 10})
      assert length(page2) == 3
    end

    test "count_child_folders/1 returns correct count", %{
      tenant: tenant,
      user: user,
      folder: root
    } do
      # Create 3 child folders
      for _ <- 1..3 do
        insert(:folder, tenant_id: tenant.id, owner_id: user.id, parent_id: root.id)
      end

      assert Files.count_child_folders(root) == 3
    end

    test "pagination with empty opts returns all results", %{
      tenant: tenant,
      user: user,
      folder: folder
    } do
      # Create 3 files
      for _ <- 1..3 do
        insert(:file, tenant_id: tenant.id, owner_id: user.id, folder_id: folder.id)
      end

      # Empty opts should return all
      files = Files.list_folder_files(folder, %{})
      assert length(files) == 3
    end
  end
end
