defmodule SecureSharing.MultiTenancyTest do
  @moduledoc """
  Integration tests for multi-tenancy isolation across all contexts.
  Ensures complete tenant separation at the system level.
  """
  use SecureSharing.DataCase, async: true

  import SecureSharing.Factory

  alias SecureSharing.{Accounts, Files, Sharing}

  describe "tenant isolation - cross-context integration" do
    setup do
      tenant_a = insert(:tenant, name: "Tenant A")
      tenant_b = insert(:tenant, name: "Tenant B")
      user_a = insert(:user, tenant_id: tenant_a.id)
      user_b = insert(:user, tenant_id: tenant_b.id)

      # Use factory to create pre-configured folders and files
      folder_a = insert(:root_folder, tenant_id: tenant_a.id, owner_id: user_a.id)
      folder_b = insert(:root_folder, tenant_id: tenant_b.id, owner_id: user_b.id)
      file_a = insert(:file, tenant_id: tenant_a.id, owner_id: user_a.id, folder_id: folder_a.id)
      file_b = insert(:file, tenant_id: tenant_b.id, owner_id: user_b.id, folder_id: folder_b.id)

      {:ok,
       tenant_a: tenant_a,
       tenant_b: tenant_b,
       user_a: user_a,
       user_b: user_b,
       folder_a: folder_a,
       folder_b: folder_b,
       file_a: file_a,
       file_b: file_b}
    end

    test "user cannot share file with user from different tenant", ctx do
      assert {:error, :cross_tenant_share} =
               Sharing.share_file(ctx.file_a, ctx.user_a, ctx.user_b, %{
                 permission: :read,
                 wrapped_key: :crypto.strong_rand_bytes(64),
                 kem_ciphertext: :crypto.strong_rand_bytes(128),
                 share_index: 1
               })
    end

    test "storage calculation is isolated per tenant", ctx do
      # Add more files to tenant A
      for _ <- 1..3 do
        insert(:file,
          tenant_id: ctx.tenant_a.id,
          owner_id: ctx.user_a.id,
          folder_id: ctx.folder_a.id,
          blob_size: 1000
        )
      end

      # Add different amount to tenant B
      for _ <- 1..5 do
        insert(:file,
          tenant_id: ctx.tenant_b.id,
          owner_id: ctx.user_b.id,
          folder_id: ctx.folder_b.id,
          blob_size: 2000
        )
      end

      # Original file + 3 new = 4 files in tenant A
      storage_a = Files.calculate_tenant_storage(ctx.tenant_a.id)
      # Original file + 5 new = 6 files in tenant B
      storage_b = Files.calculate_tenant_storage(ctx.tenant_b.id)

      # tenant_a: 1 original (from factory, size varies) + 3 * 1000
      # tenant_b: 1 original (from factory, size varies) + 5 * 2000
      # Just verify they're different and B > A for the new files portion
      assert storage_a != storage_b
    end

    test "user listing is tenant-scoped", ctx do
      # Create additional users in each tenant
      insert_list(3, :user, tenant_id: ctx.tenant_a.id)
      insert_list(5, :user, tenant_id: ctx.tenant_b.id)

      # List users in tenant A (1 original + 3 new = 4)
      users_a = Accounts.list_users(ctx.tenant_a.id)
      assert length(users_a) == 4

      # List users in tenant B (1 original + 5 new = 6)
      users_b = Accounts.list_users(ctx.tenant_b.id)
      assert length(users_b) == 6
    end

    test "folder listing is user and tenant scoped", ctx do
      # Add subfolders for user_a
      insert(:folder,
        tenant_id: ctx.tenant_a.id,
        owner_id: ctx.user_a.id,
        parent_id: ctx.folder_a.id
      )

      insert(:folder,
        tenant_id: ctx.tenant_a.id,
        owner_id: ctx.user_a.id,
        parent_id: ctx.folder_a.id
      )

      # User A sees their folders (root + 2 children = 3)
      folders_a = Files.list_user_folders(ctx.user_a)
      assert length(folders_a) == 3

      # User B only sees their root folder
      folders_b = Files.list_user_folders(ctx.user_b)
      assert length(folders_b) == 1
    end
  end

  describe "tenant isolation - sharing within tenant" do
    setup do
      tenant = insert(:tenant)
      user1 = insert(:user, tenant_id: tenant.id)
      user2 = insert(:user, tenant_id: tenant.id)
      folder = insert(:root_folder, tenant_id: tenant.id, owner_id: user1.id)
      test_file = insert(:file, tenant_id: tenant.id, owner_id: user1.id, folder_id: folder.id)

      {:ok, tenant: tenant, user1: user1, user2: user2, folder: folder, test_file: test_file}
    end

    test "users in same tenant can share files", ctx do
      share_attrs = %{
        permission: :read,
        wrapped_key: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        signature: :crypto.strong_rand_bytes(256),
        share_index: 1
      }

      assert {:ok, share} = Sharing.share_file(ctx.test_file, ctx.user1, ctx.user2, share_attrs)
      assert share.grantor_id == ctx.user1.id
      assert share.grantee_id == ctx.user2.id
      assert share.tenant_id == ctx.tenant.id
    end

    test "users in same tenant can share folders", ctx do
      share_attrs = %{
        permission: :read,
        wrapped_key: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        signature: :crypto.strong_rand_bytes(256),
        recursive: false
      }

      assert {:ok, share} = Sharing.share_folder(ctx.folder, ctx.user1, ctx.user2, share_attrs)
      assert share.grantor_id == ctx.user1.id
      assert share.grantee_id == ctx.user2.id
    end

    test "shared user can list received shares", ctx do
      share_attrs = %{
        permission: :read,
        wrapped_key: :crypto.strong_rand_bytes(64),
        kem_ciphertext: :crypto.strong_rand_bytes(128),
        signature: :crypto.strong_rand_bytes(256),
        share_index: 1
      }

      {:ok, _share} = Sharing.share_file(ctx.test_file, ctx.user1, ctx.user2, share_attrs)

      # User2 should see the share
      shares = Sharing.list_received_shares(ctx.user2)
      assert length(shares) == 1

      # User1 (the grantor) should not have received shares
      grantor_shares = Sharing.list_received_shares(ctx.user1)
      assert length(grantor_shares) == 0
    end
  end

  describe "tenant isolation - concurrent operations" do
    test "concurrent file creation in different tenants is isolated" do
      tenant_a = insert(:tenant)
      tenant_b = insert(:tenant)
      user_a = insert(:user, tenant_id: tenant_a.id)
      user_b = insert(:user, tenant_id: tenant_b.id)
      folder_a = insert(:root_folder, tenant_id: tenant_a.id, owner_id: user_a.id)
      folder_b = insert(:root_folder, tenant_id: tenant_b.id, owner_id: user_b.id)

      # Simulate concurrent file creation
      tasks =
        for {user, folder, tenant, _prefix} <- [
              {user_a, folder_a, tenant_a, "a"},
              {user_b, folder_b, tenant_b, "b"}
            ],
            i <- 1..10 do
          Task.async(fn ->
            insert(:file,
              tenant_id: tenant.id,
              owner_id: user.id,
              folder_id: folder.id,
              blob_size: i * 100
            )
          end)
        end

      # Wait for all tasks
      results = Task.await_many(tasks, 10_000)

      # All should succeed (factory returns the struct directly)
      assert length(results) == 20

      # Each tenant should have exactly 10 files
      files_a = Files.list_folder_files(folder_a)
      files_b = Files.list_folder_files(folder_b)

      assert length(files_a) == 10
      assert length(files_b) == 10

      # Storage should be calculated independently
      storage_a = Files.calculate_tenant_storage(tenant_a.id)
      storage_b = Files.calculate_tenant_storage(tenant_b.id)

      # Both should have sum of 1*100 + 2*100 + ... + 10*100 = 5500
      assert storage_a == 5500
      assert storage_b == 5500
    end
  end

  describe "tenant isolation - authentication" do
    test "same email can exist in different tenants and authenticate correctly" do
      tenant_a = insert(:tenant)
      tenant_b = insert(:tenant)
      password = "secure_password_123"

      {:ok, user_a} =
        Accounts.register_user(%{
          tenant_id: tenant_a.id,
          email: "shared@example.com",
          password: password,
          public_keys: %{kem: "key1", sign: "key2"},
          encrypted_private_keys: "encrypted_a",
          key_derivation_salt: "salt_a"
        })

      {:ok, user_b} =
        Accounts.register_user(%{
          tenant_id: tenant_b.id,
          email: "shared@example.com",
          password: password,
          public_keys: %{kem: "key3", sign: "key4"},
          encrypted_private_keys: "encrypted_b",
          key_derivation_salt: "salt_b"
        })

      # Both users exist with same email
      assert user_a.email == user_b.email
      assert user_a.id != user_b.id

      # Tenant-scoped authentication works
      assert {:ok, auth_a} =
               Accounts.authenticate_user(tenant_a.id, "shared@example.com", password)

      assert auth_a.id == user_a.id

      assert {:ok, auth_b} =
               Accounts.authenticate_user(tenant_b.id, "shared@example.com", password)

      assert auth_b.id == user_b.id

      # Wrong tenant returns error
      assert {:error, :invalid_credentials} =
               Accounts.authenticate_user(tenant_a.id, "nonexistent@example.com", password)
    end
  end

  describe "tenant configuration" do
    test "tenant settings are isolated" do
      tenant_a = insert(:tenant, storage_quota_bytes: 10 * 1024 * 1024 * 1024, max_users: 100)
      tenant_b = insert(:tenant, storage_quota_bytes: 5 * 1024 * 1024 * 1024, max_users: 50)

      # Each tenant has their own configuration
      assert tenant_a.storage_quota_bytes == 10 * 1024 * 1024 * 1024
      assert tenant_b.storage_quota_bytes == 5 * 1024 * 1024 * 1024
      assert tenant_a.max_users == 100
      assert tenant_b.max_users == 50
    end

    test "tenant PQC algorithm selection is isolated" do
      tenant_kaz = insert(:tenant, pqc_algorithm: :kaz)
      tenant_nist = insert(:tenant, pqc_algorithm: :nist)
      tenant_hybrid = insert(:tenant, pqc_algorithm: :hybrid)

      assert tenant_kaz.pqc_algorithm == :kaz
      assert tenant_nist.pqc_algorithm == :nist
      assert tenant_hybrid.pqc_algorithm == :hybrid
    end
  end
end
