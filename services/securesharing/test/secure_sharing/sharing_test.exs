defmodule SecureSharing.SharingTest do
  use SecureSharing.DataCase, async: true

  alias SecureSharing.Sharing
  alias SecureSharing.Sharing.ShareGrant

  describe "file sharing" do
    setup do
      tenant = insert(:tenant)
      owner = insert(:user, tenant_id: tenant.id)
      recipient = insert(:user, tenant_id: tenant.id)
      folder = insert(:root_folder, tenant_id: tenant.id, owner_id: owner.id)
      file = insert(:file, tenant_id: tenant.id, owner_id: owner.id, folder_id: folder.id)

      {:ok, tenant: tenant, owner: owner, recipient: recipient, folder: folder, test_file: file}
    end

    test "share_file/4 creates a file share", %{
      test_file: file,
      owner: owner,
      recipient: recipient
    } do
      attrs = %{
        wrapped_key: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        signature: :crypto.strong_rand_bytes(256),
        permission: :read
      }

      assert {:ok, %ShareGrant{} = share} = Sharing.share_file(file, owner, recipient, attrs)
      assert share.resource_type == :file
      assert share.resource_id == file.id
      assert share.grantor_id == owner.id
      assert share.grantee_id == recipient.id
      assert share.permission == :read
      assert share.recursive == false
    end

    test "share_file/4 with write permission", %{
      test_file: file,
      owner: owner,
      recipient: recipient
    } do
      attrs = %{
        wrapped_key: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        signature: :crypto.strong_rand_bytes(256),
        permission: :write
      }

      assert {:ok, share} = Sharing.share_file(file, owner, recipient, attrs)
      assert share.permission == :write
    end

    test "share_file/4 with expiry", %{test_file: file, owner: owner, recipient: recipient} do
      expires_at = DateTime.utc_now() |> DateTime.add(7, :day) |> DateTime.truncate(:microsecond)

      attrs = %{
        wrapped_key: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        signature: :crypto.strong_rand_bytes(256),
        expires_at: expires_at
      }

      assert {:ok, share} = Sharing.share_file(file, owner, recipient, attrs)
      assert share.expires_at == expires_at
    end

    test "share_file/4 prevents duplicate shares", %{
      test_file: file,
      owner: owner,
      recipient: recipient
    } do
      attrs = %{
        wrapped_key: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        signature: :crypto.strong_rand_bytes(256)
      }

      assert {:ok, _} = Sharing.share_file(file, owner, recipient, attrs)
      assert {:error, changeset} = Sharing.share_file(file, owner, recipient, attrs)
      assert "share already exists for this resource" in errors_on(changeset).grantor_id
    end

    test "share_file/4 prevents self-share", %{test_file: file, owner: owner} do
      attrs = %{
        wrapped_key: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        signature: :crypto.strong_rand_bytes(256)
      }

      assert {:error, changeset} = Sharing.share_file(file, owner, owner, attrs)
      assert "cannot share with yourself" in errors_on(changeset).grantee_id
    end

    test "share_file/4 prevents cross-tenant share", %{test_file: file, owner: owner} do
      other_tenant = insert(:tenant)
      other_user = insert(:user, tenant_id: other_tenant.id)

      attrs = %{
        wrapped_key: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        signature: :crypto.strong_rand_bytes(256)
      }

      assert {:error, :cross_tenant_share} = Sharing.share_file(file, owner, other_user, attrs)
    end
  end

  describe "folder sharing" do
    setup do
      tenant = insert(:tenant)
      owner = insert(:user, tenant_id: tenant.id)
      recipient = insert(:user, tenant_id: tenant.id)
      folder = insert(:root_folder, tenant_id: tenant.id, owner_id: owner.id)

      {:ok, tenant: tenant, owner: owner, recipient: recipient, folder: folder}
    end

    test "share_folder/4 creates a folder share", %{
      folder: folder,
      owner: owner,
      recipient: recipient
    } do
      attrs = %{
        wrapped_key: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        signature: :crypto.strong_rand_bytes(256),
        permission: :read
      }

      assert {:ok, %ShareGrant{} = share} = Sharing.share_folder(folder, owner, recipient, attrs)
      assert share.resource_type == :folder
      assert share.resource_id == folder.id
      assert share.recursive == true
    end

    test "share_folder/4 with recursive=false", %{
      folder: folder,
      owner: owner,
      recipient: recipient
    } do
      attrs = %{
        wrapped_key: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        signature: :crypto.strong_rand_bytes(256),
        recursive: false
      }

      assert {:ok, share} = Sharing.share_folder(folder, owner, recipient, attrs)
      assert share.recursive == false
    end

    test "share_folder/4 with admin permission", %{
      folder: folder,
      owner: owner,
      recipient: recipient
    } do
      attrs = %{
        wrapped_key: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        signature: :crypto.strong_rand_bytes(256),
        permission: :admin
      }

      assert {:ok, share} = Sharing.share_folder(folder, owner, recipient, attrs)
      assert share.permission == :admin
    end
  end

  describe "querying shares" do
    setup do
      tenant = insert(:tenant)
      owner = insert(:user, tenant_id: tenant.id)
      recipient = insert(:user, tenant_id: tenant.id)
      folder = insert(:root_folder, tenant_id: tenant.id, owner_id: owner.id)
      file = insert(:file, tenant_id: tenant.id, owner_id: owner.id, folder_id: folder.id)

      {:ok, tenant: tenant, owner: owner, recipient: recipient, folder: folder, test_file: file}
    end

    test "list_received_shares/1 returns active shares", %{
      test_file: file,
      folder: folder,
      owner: owner,
      recipient: recipient,
      tenant: tenant
    } do
      # Create file share
      insert(:file_share,
        tenant_id: tenant.id,
        grantor_id: owner.id,
        grantee_id: recipient.id,
        resource_id: file.id
      )

      # Create folder share
      insert(:folder_share,
        tenant_id: tenant.id,
        grantor_id: owner.id,
        grantee_id: recipient.id,
        resource_id: folder.id
      )

      shares = Sharing.list_received_shares(recipient)
      assert length(shares) == 2
    end

    test "list_received_shares/1 excludes revoked shares", %{
      test_file: file,
      owner: owner,
      recipient: recipient,
      tenant: tenant
    } do
      # Create active share
      insert(:file_share,
        tenant_id: tenant.id,
        grantor_id: owner.id,
        grantee_id: recipient.id,
        resource_id: file.id
      )

      # Create revoked share
      insert(:file_share,
        tenant_id: tenant.id,
        grantor_id: owner.id,
        grantee_id: recipient.id,
        resource_id: UUIDv7.generate(),
        revoked_at: DateTime.utc_now()
      )

      shares = Sharing.list_received_shares(recipient)
      assert length(shares) == 1
    end

    test "list_received_shares/1 excludes expired shares", %{
      test_file: file,
      owner: owner,
      recipient: recipient,
      tenant: tenant
    } do
      # Create active share
      insert(:file_share,
        tenant_id: tenant.id,
        grantor_id: owner.id,
        grantee_id: recipient.id,
        resource_id: file.id
      )

      # Create expired share
      insert(:file_share,
        tenant_id: tenant.id,
        grantor_id: owner.id,
        grantee_id: recipient.id,
        resource_id: UUIDv7.generate(),
        expires_at: DateTime.utc_now() |> DateTime.add(-1, :day)
      )

      shares = Sharing.list_received_shares(recipient)
      assert length(shares) == 1
    end

    test "list_created_shares/1 returns all shares created by user", %{
      test_file: file,
      owner: owner,
      recipient: recipient,
      tenant: tenant
    } do
      insert(:file_share,
        tenant_id: tenant.id,
        grantor_id: owner.id,
        grantee_id: recipient.id,
        resource_id: file.id
      )

      shares = Sharing.list_created_shares(owner)
      assert length(shares) == 1
      assert hd(shares).grantor_id == owner.id
    end

    test "list_file_shares/1 returns shares for a file", %{
      test_file: file,
      owner: owner,
      recipient: recipient,
      tenant: tenant
    } do
      insert(:file_share,
        tenant_id: tenant.id,
        grantor_id: owner.id,
        grantee_id: recipient.id,
        resource_id: file.id
      )

      shares = Sharing.list_file_shares(file)
      assert length(shares) == 1
    end

    test "get_share_for_user/3 returns active share", %{
      test_file: file,
      owner: owner,
      recipient: recipient,
      tenant: tenant
    } do
      insert(:file_share,
        tenant_id: tenant.id,
        grantor_id: owner.id,
        grantee_id: recipient.id,
        resource_id: file.id
      )

      share = Sharing.get_share_for_user(recipient, :file, file.id)
      assert share != nil
      assert share.grantee_id == recipient.id
    end
  end

  describe "share revocation" do
    setup do
      tenant = insert(:tenant)
      owner = insert(:user, tenant_id: tenant.id)
      recipient = insert(:user, tenant_id: tenant.id)
      folder = insert(:root_folder, tenant_id: tenant.id, owner_id: owner.id)
      file = insert(:file, tenant_id: tenant.id, owner_id: owner.id, folder_id: folder.id)

      share =
        insert(:file_share,
          tenant_id: tenant.id,
          grantor_id: owner.id,
          grantee_id: recipient.id,
          resource_id: file.id
        )

      {:ok, tenant: tenant, owner: owner, recipient: recipient, test_file: file, share: share}
    end

    test "revoke_share/2 revokes a share", %{share: share, owner: owner} do
      assert {:ok, revoked} = Sharing.revoke_share(share, owner)
      assert revoked.revoked_at != nil
      assert revoked.revoked_by_id == owner.id
    end

    test "revoke_share/2 prevents double revocation", %{share: share, owner: owner} do
      {:ok, revoked} = Sharing.revoke_share(share, owner)
      assert {:error, :already_revoked} = Sharing.revoke_share(revoked, owner)
    end

    test "revoke_all_shares/3 revokes all shares for resource", %{
      test_file: file,
      owner: owner,
      tenant: tenant
    } do
      # Add another recipient
      recipient2 = insert(:user, tenant_id: tenant.id)

      insert(:file_share,
        tenant_id: tenant.id,
        grantor_id: owner.id,
        grantee_id: recipient2.id,
        resource_id: file.id
      )

      assert {:ok, 2} = Sharing.revoke_all_shares(:file, file.id, owner)
      assert Sharing.list_file_shares(file) == []
    end

    test "revoke_share/2 allows grantor to revoke", %{share: share, owner: owner} do
      assert {:ok, revoked} = Sharing.revoke_share(share, owner)
      assert revoked.revoked_at != nil
    end

    test "revoke_share/2 allows admin permission holder to revoke", %{tenant: tenant} do
      # Create a new owner with a separate file for this test
      file_owner = insert(:user, tenant_id: tenant.id)
      folder = insert(:root_folder, tenant_id: tenant.id, owner_id: file_owner.id)

      new_file =
        insert(:file, tenant_id: tenant.id, owner_id: file_owner.id, folder_id: folder.id)

      # Create a user with admin permission on the file
      admin_user = insert(:user, tenant_id: tenant.id)

      insert(:file_share,
        tenant_id: tenant.id,
        grantor_id: file_owner.id,
        grantee_id: admin_user.id,
        resource_id: new_file.id,
        permission: :admin
      )

      # Create another share from owner to a third user
      third_user = insert(:user, tenant_id: tenant.id)

      other_share =
        insert(:file_share,
          tenant_id: tenant.id,
          grantor_id: file_owner.id,
          grantee_id: third_user.id,
          resource_id: new_file.id
        )

      # Admin user should be able to revoke the other share
      assert {:ok, revoked} = Sharing.revoke_share(other_share, admin_user)
      assert revoked.revoked_at != nil
    end

    test "revoke_share/2 denies non-grantor without admin permission", %{
      share: share,
      tenant: tenant
    } do
      stranger = insert(:user, tenant_id: tenant.id)
      assert {:error, :forbidden} = Sharing.revoke_share(share, stranger)
    end

    test "revoke_share/2 denies grantee from revoking their own share", %{
      share: share,
      recipient: recipient
    } do
      # Grantee cannot revoke shares given to them (only grantor or admin can)
      assert {:error, :forbidden} = Sharing.revoke_share(share, recipient)
    end
  end

  describe "access checking" do
    setup do
      tenant = insert(:tenant)
      owner = insert(:user, tenant_id: tenant.id)
      recipient = insert(:user, tenant_id: tenant.id)
      stranger = insert(:user, tenant_id: tenant.id)
      folder = insert(:root_folder, tenant_id: tenant.id, owner_id: owner.id)
      file = insert(:file, tenant_id: tenant.id, owner_id: owner.id, folder_id: folder.id)

      {:ok,
       tenant: tenant,
       owner: owner,
       recipient: recipient,
       stranger: stranger,
       folder: folder,
       test_file: file}
    end

    test "has_file_access?/2 returns true for owner", %{test_file: file, owner: owner} do
      assert Sharing.has_file_access?(owner, file) == true
    end

    test "has_file_access?/2 returns true for user with share", %{
      test_file: file,
      owner: owner,
      recipient: recipient,
      tenant: tenant
    } do
      insert(:file_share,
        tenant_id: tenant.id,
        grantor_id: owner.id,
        grantee_id: recipient.id,
        resource_id: file.id
      )

      assert Sharing.has_file_access?(recipient, file) == true
    end

    test "has_file_access?/2 returns false for stranger", %{test_file: file, stranger: stranger} do
      assert Sharing.has_file_access?(stranger, file) == false
    end

    test "has_file_access?/2 returns true via recursive folder share", %{
      test_file: file,
      folder: folder,
      owner: owner,
      recipient: recipient,
      tenant: tenant
    } do
      # Share the folder with recursive=true
      insert(:folder_share,
        tenant_id: tenant.id,
        grantor_id: owner.id,
        grantee_id: recipient.id,
        resource_id: folder.id,
        recursive: true
      )

      # Recipient should have access to file via folder share
      assert Sharing.has_file_access?(recipient, file) == true
    end

    test "has_file_access?/2 returns false via non-recursive folder share", %{
      folder: folder,
      owner: owner,
      recipient: recipient,
      tenant: tenant
    } do
      # Create a child folder and file
      child_folder =
        insert(:folder,
          tenant_id: tenant.id,
          owner_id: owner.id,
          parent_id: folder.id
        )

      child_file =
        insert(:file,
          tenant_id: tenant.id,
          owner_id: owner.id,
          folder_id: child_folder.id
        )

      # Share the parent folder with recursive=false
      insert(:folder_share,
        tenant_id: tenant.id,
        grantor_id: owner.id,
        grantee_id: recipient.id,
        resource_id: folder.id,
        recursive: false
      )

      # Recipient should NOT have access to child file via non-recursive share
      assert Sharing.has_file_access?(recipient, child_file) == false
    end

    test "has_folder_access?/2 returns false for child folder via non-recursive parent share", %{
      folder: folder,
      owner: owner,
      recipient: recipient,
      tenant: tenant
    } do
      # Create a child folder
      child_folder =
        insert(:folder,
          tenant_id: tenant.id,
          owner_id: owner.id,
          parent_id: folder.id
        )

      # Share the parent folder with recursive=false
      insert(:folder_share,
        tenant_id: tenant.id,
        grantor_id: owner.id,
        grantee_id: recipient.id,
        resource_id: folder.id,
        recursive: false
      )

      # Recipient should NOT have access to child folder
      assert Sharing.has_folder_access?(recipient, child_folder) == false
    end

    test "has_folder_access?/2 returns true for child folder via recursive parent share", %{
      folder: folder,
      owner: owner,
      recipient: recipient,
      tenant: tenant
    } do
      # Create a child folder
      child_folder =
        insert(:folder,
          tenant_id: tenant.id,
          owner_id: owner.id,
          parent_id: folder.id
        )

      # Share the parent folder with recursive=true
      insert(:folder_share,
        tenant_id: tenant.id,
        grantor_id: owner.id,
        grantee_id: recipient.id,
        resource_id: folder.id,
        recursive: true
      )

      # Recipient should have access to child folder
      assert Sharing.has_folder_access?(recipient, child_folder) == true
    end

    test "get_folder_permission/2 returns nil for child folder via non-recursive share", %{
      folder: folder,
      owner: owner,
      recipient: recipient,
      tenant: tenant
    } do
      child_folder =
        insert(:folder,
          tenant_id: tenant.id,
          owner_id: owner.id,
          parent_id: folder.id
        )

      insert(:folder_share,
        tenant_id: tenant.id,
        grantor_id: owner.id,
        grantee_id: recipient.id,
        resource_id: folder.id,
        recursive: false,
        permission: :write
      )

      # Should get nil for child folder (non-recursive doesn't propagate)
      assert Sharing.get_folder_permission(recipient, child_folder) == nil
    end

    test "get_folder_permission/2 returns permission for child folder via recursive share", %{
      folder: folder,
      owner: owner,
      recipient: recipient,
      tenant: tenant
    } do
      child_folder =
        insert(:folder,
          tenant_id: tenant.id,
          owner_id: owner.id,
          parent_id: folder.id
        )

      insert(:folder_share,
        tenant_id: tenant.id,
        grantor_id: owner.id,
        grantee_id: recipient.id,
        resource_id: folder.id,
        recursive: true,
        permission: :write
      )

      # Should inherit permission from recursive parent share
      assert Sharing.get_folder_permission(recipient, child_folder) == :write
    end

    test "has_folder_access?/2 returns true for owner", %{folder: folder, owner: owner} do
      assert Sharing.has_folder_access?(owner, folder) == true
    end

    test "get_file_permission/2 returns :owner for owner", %{test_file: file, owner: owner} do
      assert Sharing.get_file_permission(owner, file) == :owner
    end

    test "get_file_permission/2 returns permission for share", %{
      test_file: file,
      owner: owner,
      recipient: recipient,
      tenant: tenant
    } do
      insert(:file_share,
        tenant_id: tenant.id,
        grantor_id: owner.id,
        grantee_id: recipient.id,
        resource_id: file.id,
        permission: :write
      )

      assert Sharing.get_file_permission(recipient, file) == :write
    end

    test "get_file_permission/2 returns nil for stranger", %{test_file: file, stranger: stranger} do
      assert Sharing.get_file_permission(stranger, file) == nil
    end

    test "can_write_file?/2 returns true for owner", %{test_file: file, owner: owner} do
      assert Sharing.can_write_file?(owner, file) == true
    end

    test "can_write_file?/2 returns true for write permission", %{
      test_file: file,
      owner: owner,
      recipient: recipient,
      tenant: tenant
    } do
      insert(:file_share,
        tenant_id: tenant.id,
        grantor_id: owner.id,
        grantee_id: recipient.id,
        resource_id: file.id,
        permission: :write
      )

      assert Sharing.can_write_file?(recipient, file) == true
    end

    test "can_write_file?/2 returns false for read permission", %{
      test_file: file,
      owner: owner,
      recipient: recipient,
      tenant: tenant
    } do
      insert(:file_share,
        tenant_id: tenant.id,
        grantor_id: owner.id,
        grantee_id: recipient.id,
        resource_id: file.id,
        permission: :read
      )

      assert Sharing.can_write_file?(recipient, file) == false
    end

    test "can_share_file?/2 returns true for owner", %{test_file: file, owner: owner} do
      assert Sharing.can_share_file?(owner, file) == true
    end

    test "can_share_file?/2 returns true for admin", %{
      test_file: file,
      owner: owner,
      recipient: recipient,
      tenant: tenant
    } do
      insert(:file_share,
        tenant_id: tenant.id,
        grantor_id: owner.id,
        grantee_id: recipient.id,
        resource_id: file.id,
        permission: :admin
      )

      assert Sharing.can_share_file?(recipient, file) == true
    end

    test "can_share_file?/2 returns false for write", %{
      test_file: file,
      owner: owner,
      recipient: recipient,
      tenant: tenant
    } do
      insert(:file_share,
        tenant_id: tenant.id,
        grantor_id: owner.id,
        grantee_id: recipient.id,
        resource_id: file.id,
        permission: :write
      )

      assert Sharing.can_share_file?(recipient, file) == false
    end
  end

  describe "ShareGrant helpers" do
    test "active?/1 returns true for active share" do
      share = %ShareGrant{revoked_at: nil, expires_at: nil}
      assert ShareGrant.active?(share) == true
    end

    test "active?/1 returns false for revoked share" do
      share = %ShareGrant{revoked_at: DateTime.utc_now(), expires_at: nil}
      assert ShareGrant.active?(share) == false
    end

    test "active?/1 returns false for expired share" do
      share = %ShareGrant{
        revoked_at: nil,
        expires_at: DateTime.utc_now() |> DateTime.add(-1, :day)
      }

      assert ShareGrant.active?(share) == false
    end

    test "active?/1 returns true for future expiry" do
      share = %ShareGrant{
        revoked_at: nil,
        expires_at: DateTime.utc_now() |> DateTime.add(1, :day)
      }

      assert ShareGrant.active?(share) == true
    end

    test "has_permission?/2 checks permission level" do
      read_share = %ShareGrant{permission: :read}
      write_share = %ShareGrant{permission: :write}
      admin_share = %ShareGrant{permission: :admin}

      assert ShareGrant.has_permission?(read_share, :read) == true
      assert ShareGrant.has_permission?(read_share, :write) == false

      assert ShareGrant.has_permission?(write_share, :read) == true
      assert ShareGrant.has_permission?(write_share, :write) == true
      assert ShareGrant.has_permission?(write_share, :admin) == false

      assert ShareGrant.has_permission?(admin_share, :read) == true
      assert ShareGrant.has_permission?(admin_share, :write) == true
      assert ShareGrant.has_permission?(admin_share, :admin) == true
    end
  end

  describe "can_delete_file?/2" do
    setup do
      tenant = insert(:tenant)
      owner = insert(:user, tenant_id: tenant.id)
      folder = insert(:root_folder, tenant_id: tenant.id, owner_id: owner.id)
      file = insert(:file, tenant_id: tenant.id, owner_id: owner.id, folder_id: folder.id)

      {:ok, tenant: tenant, owner: owner, folder: folder, test_file: file}
    end

    test "returns true for owner", %{test_file: file, owner: owner} do
      assert Sharing.can_delete_file?(owner, file) == true
    end

    test "returns true for admin share", %{
      test_file: file,
      owner: owner,
      tenant: tenant
    } do
      admin_user = insert(:user, tenant_id: tenant.id)

      insert(:file_share,
        tenant_id: tenant.id,
        grantor_id: owner.id,
        grantee_id: admin_user.id,
        resource_id: file.id,
        permission: :admin
      )

      assert Sharing.can_delete_file?(admin_user, file) == true
    end

    test "returns false for write share", %{
      test_file: file,
      owner: owner,
      tenant: tenant
    } do
      writer = insert(:user, tenant_id: tenant.id)

      insert(:file_share,
        tenant_id: tenant.id,
        grantor_id: owner.id,
        grantee_id: writer.id,
        resource_id: file.id,
        permission: :write
      )

      assert Sharing.can_delete_file?(writer, file) == false
    end

    test "returns false for read share", %{
      test_file: file,
      owner: owner,
      tenant: tenant
    } do
      reader = insert(:user, tenant_id: tenant.id)

      insert(:file_share,
        tenant_id: tenant.id,
        grantor_id: owner.id,
        grantee_id: reader.id,
        resource_id: file.id,
        permission: :read
      )

      assert Sharing.can_delete_file?(reader, file) == false
    end

    test "returns false for stranger", %{test_file: file, tenant: tenant} do
      stranger = insert(:user, tenant_id: tenant.id)
      assert Sharing.can_delete_file?(stranger, file) == false
    end
  end

  describe "can_delete_folder?/2" do
    setup do
      tenant = insert(:tenant)
      owner = insert(:user, tenant_id: tenant.id)
      root = insert(:root_folder, tenant_id: tenant.id, owner_id: owner.id)
      folder = insert(:folder, tenant_id: tenant.id, owner_id: owner.id, parent_id: root.id)

      {:ok, tenant: tenant, owner: owner, folder: folder}
    end

    test "returns true for owner", %{folder: folder, owner: owner} do
      assert Sharing.can_delete_folder?(owner, folder) == true
    end

    test "returns true for admin share", %{
      folder: folder,
      owner: owner,
      tenant: tenant
    } do
      admin_user = insert(:user, tenant_id: tenant.id)

      insert(:folder_share,
        tenant_id: tenant.id,
        grantor_id: owner.id,
        grantee_id: admin_user.id,
        resource_id: folder.id,
        permission: :admin
      )

      assert Sharing.can_delete_folder?(admin_user, folder) == true
    end

    test "returns false for write share", %{
      folder: folder,
      owner: owner,
      tenant: tenant
    } do
      writer = insert(:user, tenant_id: tenant.id)

      insert(:folder_share,
        tenant_id: tenant.id,
        grantor_id: owner.id,
        grantee_id: writer.id,
        resource_id: folder.id,
        permission: :write
      )

      assert Sharing.can_delete_folder?(writer, folder) == false
    end

    test "returns false for read share", %{
      folder: folder,
      owner: owner,
      tenant: tenant
    } do
      reader = insert(:user, tenant_id: tenant.id)

      insert(:folder_share,
        tenant_id: tenant.id,
        grantor_id: owner.id,
        grantee_id: reader.id,
        resource_id: folder.id,
        permission: :read
      )

      assert Sharing.can_delete_folder?(reader, folder) == false
    end

    test "returns false for stranger", %{folder: folder, tenant: tenant} do
      stranger = insert(:user, tenant_id: tenant.id)
      assert Sharing.can_delete_folder?(stranger, folder) == false
    end
  end

  describe "statistics" do
    setup do
      tenant = insert(:tenant)
      owner = insert(:user, tenant_id: tenant.id)
      recipient = insert(:user, tenant_id: tenant.id)
      folder = insert(:root_folder, tenant_id: tenant.id, owner_id: owner.id)
      file = insert(:file, tenant_id: tenant.id, owner_id: owner.id, folder_id: folder.id)

      {:ok, tenant: tenant, owner: owner, recipient: recipient, folder: folder, test_file: file}
    end

    test "count_user_shares/1 returns share counts", %{
      test_file: file,
      owner: owner,
      recipient: recipient,
      tenant: tenant
    } do
      insert(:file_share,
        tenant_id: tenant.id,
        grantor_id: owner.id,
        grantee_id: recipient.id,
        resource_id: file.id
      )

      owner_counts = Sharing.count_user_shares(owner)
      assert owner_counts.created == 1
      assert owner_counts.received == 0

      recipient_counts = Sharing.count_user_shares(recipient)
      assert recipient_counts.created == 0
      assert recipient_counts.received == 1
    end
  end
end
