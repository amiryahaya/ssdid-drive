defmodule SecureSharing.FactoryTest do
  @moduledoc """
  Tests for the ExMachina factory to ensure all factory variants work correctly.

  This includes testing:
  - build_pair/insert_pair variants
  - Factory sequences produce unique values
  - All factory types can be built and inserted
  - Factory associations work correctly
  """
  use SecureSharing.DataCase, async: true

  describe "build_pair/2" do
    test "builds two tenants with unique slugs" do
      [tenant1, tenant2] = build_pair(:tenant)

      assert tenant1.slug != tenant2.slug
      assert tenant1.name != tenant2.name
      refute tenant1.id
      refute tenant2.id
    end

    test "builds two tenants with custom attributes" do
      [tenant1, tenant2] = build_pair(:tenant, storage_quota_bytes: 5_000_000)

      assert tenant1.storage_quota_bytes == 5_000_000
      assert tenant2.storage_quota_bytes == 5_000_000
      assert tenant1.slug != tenant2.slug
    end

    test "builds two users with unique emails" do
      [user1, user2] = build_pair(:user)

      assert user1.email != user2.email
      refute user1.id
      refute user2.id
    end

    test "builds two files with unique storage paths" do
      [file1, file2] = build_pair(:file)

      assert file1.storage_path != file2.storage_path
      refute file1.id
      refute file2.id
    end

    test "builds two recovery shares with unique share indexes" do
      [share1, share2] = build_pair(:recovery_share)

      assert share1.share_index != share2.share_index
    end
  end

  describe "insert_pair/2" do
    test "inserts two tenants with unique slugs" do
      [tenant1, tenant2] = insert_pair(:tenant)

      assert tenant1.id
      assert tenant2.id
      assert tenant1.id != tenant2.id
      assert tenant1.slug != tenant2.slug
    end

    test "inserts two users in the same tenant" do
      tenant = insert(:tenant)
      [user1, user2] = insert_pair(:user, tenant_id: tenant.id)

      assert user1.id
      assert user2.id
      assert user1.id != user2.id
      assert user1.tenant_id == tenant.id
      assert user2.tenant_id == tenant.id
      assert user1.email != user2.email
    end

    test "inserts two folders for the same owner" do
      tenant = insert(:tenant)
      user = insert(:user, tenant_id: tenant.id)
      [folder1, folder2] = insert_pair(:folder, tenant_id: tenant.id, owner_id: user.id)

      assert folder1.id
      assert folder2.id
      assert folder1.id != folder2.id
      assert folder1.owner_id == user.id
      assert folder2.owner_id == user.id
    end

    test "inserts two files in the same folder" do
      tenant = insert(:tenant)
      user = insert(:user, tenant_id: tenant.id)
      folder = insert(:folder, tenant_id: tenant.id, owner_id: user.id)

      [file1, file2] =
        insert_pair(:file, tenant_id: tenant.id, owner_id: user.id, folder_id: folder.id)

      assert file1.id
      assert file2.id
      assert file1.storage_path != file2.storage_path
      assert file1.folder_id == folder.id
      assert file2.folder_id == folder.id
    end

    test "inserts two share grants for different resources" do
      tenant = insert(:tenant)
      [grantor, grantee] = insert_pair(:user, tenant_id: tenant.id)
      # Create two folders to share (avoids unique constraint on active shares)
      [folder1, folder2] = insert_pair(:folder, tenant_id: tenant.id, owner_id: grantor.id)

      share1 =
        insert(:folder_share,
          tenant_id: tenant.id,
          grantor_id: grantor.id,
          grantee_id: grantee.id,
          resource_id: folder1.id
        )

      share2 =
        insert(:folder_share,
          tenant_id: tenant.id,
          grantor_id: grantor.id,
          grantee_id: grantee.id,
          resource_id: folder2.id
        )

      assert share1.id
      assert share2.id
      assert share1.id != share2.id
      assert share1.resource_id != share2.resource_id
    end
  end

  describe "factory sequences" do
    test "tenant sequences produce unique values across multiple builds" do
      tenants = for _ <- 1..10, do: build(:tenant)
      slugs = Enum.map(tenants, & &1.slug)

      assert length(Enum.uniq(slugs)) == 10
    end

    test "user sequences produce unique emails" do
      users = for _ <- 1..10, do: build(:user)
      emails = Enum.map(users, & &1.email)

      assert length(Enum.uniq(emails)) == 10
    end

    test "file sequences produce unique storage paths" do
      files = for _ <- 1..10, do: build(:file)
      paths = Enum.map(files, & &1.storage_path)

      assert length(Enum.uniq(paths)) == 10
    end

    test "recovery share sequences produce unique indexes" do
      shares = for _ <- 1..10, do: build(:recovery_share)
      indexes = Enum.map(shares, & &1.share_index)

      assert length(Enum.uniq(indexes)) == 10
    end
  end

  describe "factory variants" do
    test "admin_user_factory creates admin user" do
      admin = build(:admin_user)

      assert admin.is_admin == true
      assert admin.email
    end

    test "user_with_password_factory creates user with known password" do
      user = build(:user_with_password)

      assert user.hashed_password
      assert Bcrypt.verify_pass("test_password_123", user.hashed_password)
    end

    test "root_folder_factory creates root folder" do
      folder = build(:root_folder)

      assert folder.is_root == true
      assert folder.parent_id == nil
    end

    test "file_share_factory creates non-recursive file share" do
      share = build(:file_share)

      assert share.resource_type == :file
      assert share.recursive == false
    end

    test "folder_share_factory creates recursive folder share" do
      share = build(:folder_share)

      assert share.resource_type == :folder
      assert share.recursive == true
    end
  end

  describe "factory associations" do
    test "user can be inserted with tenant association" do
      tenant = insert(:tenant)
      user = insert(:user, tenant: tenant)

      assert user.tenant_id == tenant.id
    end

    test "folder can be inserted with owner and tenant associations" do
      tenant = insert(:tenant)
      user = insert(:user, tenant_id: tenant.id)
      folder = insert(:folder, tenant_id: tenant.id, owner_id: user.id)

      assert folder.tenant_id == tenant.id
      assert folder.owner_id == user.id
    end

    test "nested folder hierarchy can be created" do
      tenant = insert(:tenant)
      user = insert(:user, tenant_id: tenant.id)
      root = insert(:root_folder, tenant_id: tenant.id, owner_id: user.id)
      child1 = insert(:folder, tenant_id: tenant.id, owner_id: user.id, parent_id: root.id)
      child2 = insert(:folder, tenant_id: tenant.id, owner_id: user.id, parent_id: child1.id)

      assert child1.parent_id == root.id
      assert child2.parent_id == child1.id
    end

    test "share grant can be created with all required associations" do
      tenant = insert(:tenant)
      grantor = insert(:user, tenant_id: tenant.id)
      grantee = insert(:user, tenant_id: tenant.id)
      folder = insert(:folder, tenant_id: tenant.id, owner_id: grantor.id)

      share =
        insert(:folder_share,
          tenant_id: tenant.id,
          grantor_id: grantor.id,
          grantee_id: grantee.id,
          resource_id: folder.id
        )

      assert share.tenant_id == tenant.id
      assert share.grantor_id == grantor.id
      assert share.grantee_id == grantee.id
      assert share.resource_id == folder.id
    end

    test "recovery flow entities can be created" do
      tenant = insert(:tenant)
      owner = insert(:user, tenant_id: tenant.id)
      trustee = insert(:user, tenant_id: tenant.id)

      config = insert(:recovery_config, user_id: owner.id)

      share =
        insert(:recovery_share, config_id: config.id, owner_id: owner.id, trustee_id: trustee.id)

      request = insert(:recovery_request, config_id: config.id, user_id: owner.id)

      approval =
        insert(:recovery_approval,
          request_id: request.id,
          share_id: share.id,
          trustee_id: trustee.id
        )

      assert config.user_id == owner.id
      assert share.trustee_id == trustee.id
      assert request.config_id == config.id
      assert approval.request_id == request.id
    end
  end

  describe "factory defaults" do
    test "tenant has sensible defaults" do
      tenant = build(:tenant)

      assert tenant.storage_quota_bytes == 10_737_418_240
      assert tenant.max_users == 100
      assert tenant.settings == %{}
    end

    test "user has sensible defaults" do
      user = build(:user)

      assert user.status == :active
      assert user.recovery_setup_complete == false
      assert user.is_admin == false
      assert user.public_keys
      assert user.encrypted_private_keys
      assert user.encrypted_master_key
      assert user.key_derivation_salt
    end

    test "folder has sensible defaults" do
      folder = build(:folder)

      assert folder.is_root == false
      assert folder.encrypted_metadata
      assert folder.wrapped_kek
      assert folder.kem_ciphertext
    end

    test "file has sensible defaults" do
      file = build(:file)

      assert file.status == "complete"
      assert file.chunk_count == 1
      assert file.blob_size > 0
      assert file.blob_hash
      assert file.storage_path
    end

    test "share_grant has sensible defaults" do
      share = build(:share_grant)

      assert share.permission == :read
      assert share.recursive == true
      assert share.algorithm == "kaz"
    end

    test "recovery_config has sensible defaults" do
      config = build(:recovery_config)

      assert config.threshold == 3
      assert config.total_shares == 5
      assert config.setup_complete == false
    end

    test "recovery_share has sensible defaults" do
      share = build(:recovery_share)

      assert share.accepted == false
      assert share.encrypted_share
      assert share.kem_ciphertext
      assert share.signature
    end

    test "recovery_request has sensible defaults" do
      request = build(:recovery_request)

      assert request.status == :pending
      assert request.reason == "Lost device"
      assert request.new_public_key
      assert request.expires_at
    end
  end

  describe "build_list/3" do
    test "builds multiple tenants" do
      tenants = build_list(5, :tenant)

      assert length(tenants) == 5
      slugs = Enum.map(tenants, & &1.slug)
      assert length(Enum.uniq(slugs)) == 5
    end

    test "builds multiple users with custom attributes" do
      users = build_list(3, :user, status: :suspended)

      assert length(users) == 3
      assert Enum.all?(users, &(&1.status == :suspended))
    end
  end

  describe "insert_list/3" do
    test "inserts multiple tenants" do
      tenants = insert_list(3, :tenant)

      assert length(tenants) == 3
      assert Enum.all?(tenants, & &1.id)
      ids = Enum.map(tenants, & &1.id)
      assert length(Enum.uniq(ids)) == 3
    end

    test "inserts multiple users in same tenant" do
      tenant = insert(:tenant)
      users = insert_list(5, :user, tenant_id: tenant.id)

      assert length(users) == 5
      assert Enum.all?(users, &(&1.tenant_id == tenant.id))
      emails = Enum.map(users, & &1.email)
      assert length(Enum.uniq(emails)) == 5
    end
  end
end
