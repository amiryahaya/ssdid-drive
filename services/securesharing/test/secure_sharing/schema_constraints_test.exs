defmodule SecureSharing.SchemaConstraintsTest do
  @moduledoc """
  Tests for database-level schema constraints.

  These tests verify that database constraints (unique indexes, foreign keys,
  not null constraints) work correctly at the database level, independent of
  Ecto validations.
  """
  use SecureSharing.DataCase, async: true

  alias Ecto.Adapters.SQL

  # Helper to convert UUID string to binary for Postgrex
  defp uuid_to_binary(uuid_string) when is_binary(uuid_string) do
    {:ok, binary} = Ecto.UUID.dump(uuid_string)
    binary
  end

  describe "tenants table constraints" do
    test "unique index on slug prevents duplicate slugs at database level" do
      # Insert first tenant
      tenant = insert(:tenant, slug: "unique-slug")
      assert tenant.id

      # Attempt to insert duplicate slug directly via SQL (bypassing Ecto)
      result =
        SQL.query(
          Repo,
          """
          INSERT INTO tenants (id, name, slug, created_at, updated_at)
          VALUES (gen_random_uuid(), 'Duplicate', 'unique-slug', NOW(), NOW())
          """
        )

      assert {:error, %Postgrex.Error{postgres: %{code: :unique_violation}}} = result
    end

    test "name cannot be null" do
      result =
        SQL.query(
          Repo,
          """
          INSERT INTO tenants (id, slug, created_at, updated_at)
          VALUES (gen_random_uuid(), 'test-slug', NOW(), NOW())
          """
        )

      assert {:error, %Postgrex.Error{postgres: %{code: :not_null_violation}}} = result
    end

    test "slug cannot be null" do
      result =
        SQL.query(
          Repo,
          """
          INSERT INTO tenants (id, name, created_at, updated_at)
          VALUES (gen_random_uuid(), 'Test Name', NOW(), NOW())
          """
        )

      assert {:error, %Postgrex.Error{postgres: %{code: :not_null_violation}}} = result
    end
  end

  describe "users table constraints" do
    test "unique composite index on tenant_id and email prevents duplicates" do
      tenant = insert(:tenant)
      insert(:user, tenant_id: tenant.id, email: "user@example.com")

      # Attempt to insert duplicate email in same tenant via SQL
      result =
        SQL.query(
          Repo,
          """
          INSERT INTO users (id, tenant_id, email, status, public_keys, created_at, updated_at)
          VALUES (gen_random_uuid(), $1, 'user@example.com', 'active', '{}', NOW(), NOW())
          """,
          [uuid_to_binary(tenant.id)]
        )

      assert {:error, %Postgrex.Error{postgres: %{code: :unique_violation}}} = result
    end

    test "same email allowed in different tenants" do
      tenant1 = insert(:tenant)
      tenant2 = insert(:tenant)

      insert(:user, tenant_id: tenant1.id, email: "shared@example.com")
      user2 = insert(:user, tenant_id: tenant2.id, email: "shared@example.com")

      assert user2.id
    end

    test "tenant_id can be null (for multi-tenant users via user_tenants)" do
      # With the multi-tenant migration, tenant_id is now nullable on users table.
      # Users can belong to multiple tenants through the user_tenants junction table.
      result =
        SQL.query(
          Repo,
          """
          INSERT INTO users (id, email, status, public_keys, created_at, updated_at)
          VALUES (gen_random_uuid(), 'test@example.com', 'active', '{}', NOW(), NOW())
          """
        )

      assert {:ok, _} = result
    end

    test "email cannot be null" do
      tenant = insert(:tenant)

      result =
        SQL.query(
          Repo,
          """
          INSERT INTO users (id, tenant_id, status, public_keys, created_at, updated_at)
          VALUES (gen_random_uuid(), $1, 'active', '{}', NOW(), NOW())
          """,
          [uuid_to_binary(tenant.id)]
        )

      assert {:error, %Postgrex.Error{postgres: %{code: :not_null_violation}}} = result
    end

    test "foreign key constraint cascades delete from tenant to users" do
      tenant = insert(:tenant)
      user = insert(:user, tenant_id: tenant.id)

      # Delete tenant
      Repo.delete!(tenant)

      # User should be deleted via cascade
      assert Repo.get(SecureSharing.Accounts.User, user.id) == nil
    end

    test "status must be valid enum value" do
      tenant = insert(:tenant)

      result =
        SQL.query(
          Repo,
          """
          INSERT INTO users (id, tenant_id, email, status, public_keys, created_at, updated_at)
          VALUES (gen_random_uuid(), $1, 'test@example.com', 'invalid_status', '{}', NOW(), NOW())
          """,
          [uuid_to_binary(tenant.id)]
        )

      assert {:error, %Postgrex.Error{postgres: %{code: :invalid_text_representation}}} = result
    end
  end

  describe "folders table constraints" do
    test "foreign key constraint cascades delete from owner to folders" do
      tenant = insert(:tenant)
      user = insert(:user, tenant_id: tenant.id)
      folder = insert(:folder, tenant_id: tenant.id, owner_id: user.id)

      # Delete user
      Repo.delete!(user)

      # Folder should be deleted via cascade
      assert Repo.get(SecureSharing.Files.Folder, folder.id) == nil
    end

    test "parent_id foreign key references folders table" do
      tenant = insert(:tenant)
      user = insert(:user, tenant_id: tenant.id)
      parent = insert(:folder, tenant_id: tenant.id, owner_id: user.id)
      child = insert(:folder, tenant_id: tenant.id, owner_id: user.id, parent_id: parent.id)

      assert child.parent_id == parent.id

      # Deleting parent should cascade to child
      Repo.delete!(parent)
      assert Repo.get(SecureSharing.Files.Folder, child.id) == nil
    end

    test "tenant_id cannot be null for folders" do
      result =
        SQL.query(
          Repo,
          """
          INSERT INTO folders (id, owner_id, is_root, wrapped_kek, kem_ciphertext, owner_wrapped_kek, owner_kem_ciphertext, created_at, updated_at)
          VALUES (gen_random_uuid(), gen_random_uuid(), true, 'kek', 'cipher', 'okek', 'ocipher', NOW(), NOW())
          """
        )

      assert {:error, %Postgrex.Error{postgres: %{code: :not_null_violation}}} = result
    end
  end

  describe "files table constraints" do
    test "unique constraint on storage_path" do
      tenant = insert(:tenant)
      user = insert(:user, tenant_id: tenant.id)
      folder = insert(:folder, tenant_id: tenant.id, owner_id: user.id)

      storage_path = "uploads/test/#{UUIDv7.generate()}"

      insert(:file,
        tenant_id: tenant.id,
        owner_id: user.id,
        folder_id: folder.id,
        storage_path: storage_path
      )

      # Attempt to insert duplicate storage_path via SQL (include all NOT NULL columns)
      result =
        SQL.query(
          Repo,
          """
          INSERT INTO files (id, tenant_id, owner_id, folder_id, encrypted_metadata, wrapped_dek, kem_ciphertext, signature, storage_path, blob_hash, blob_size, created_at, updated_at)
          VALUES (gen_random_uuid(), $1, $2, $3, 'metadata', 'dek', 'cipher', 'sig', $4, 'abc123', 100, NOW(), NOW())
          """,
          [
            uuid_to_binary(tenant.id),
            uuid_to_binary(user.id),
            uuid_to_binary(folder.id),
            storage_path
          ]
        )

      assert {:error, %Postgrex.Error{postgres: %{code: :unique_violation}}} = result
    end

    test "foreign key constraint cascades delete from folder to files" do
      tenant = insert(:tenant)
      user = insert(:user, tenant_id: tenant.id)
      folder = insert(:folder, tenant_id: tenant.id, owner_id: user.id)
      file = insert(:file, tenant_id: tenant.id, owner_id: user.id, folder_id: folder.id)

      # Delete folder
      Repo.delete!(folder)

      # File should be deleted via cascade
      assert Repo.get(SecureSharing.Files.File, file.id) == nil
    end
  end

  describe "share_grants table constraints" do
    test "permission must be valid enum value" do
      tenant = insert(:tenant)
      user1 = insert(:user, tenant_id: tenant.id)
      user2 = insert(:user, tenant_id: tenant.id)
      folder = insert(:folder, tenant_id: tenant.id, owner_id: user1.id)

      result =
        SQL.query(
          Repo,
          """
          INSERT INTO share_grants (id, tenant_id, grantor_id, grantee_id, resource_type, resource_id, permission, wrapped_key, kem_ciphertext, signature, created_at, updated_at)
          VALUES (gen_random_uuid(), $1, $2, $3, 'folder', $4, 'invalid_permission', 'key', 'cipher', 'sig', NOW(), NOW())
          """,
          [
            uuid_to_binary(tenant.id),
            uuid_to_binary(user1.id),
            uuid_to_binary(user2.id),
            uuid_to_binary(folder.id)
          ]
        )

      assert {:error, %Postgrex.Error{postgres: %{code: :invalid_text_representation}}} = result
    end

    test "resource_type must be valid enum value" do
      tenant = insert(:tenant)
      user1 = insert(:user, tenant_id: tenant.id)
      user2 = insert(:user, tenant_id: tenant.id)
      folder = insert(:folder, tenant_id: tenant.id, owner_id: user1.id)

      result =
        SQL.query(
          Repo,
          """
          INSERT INTO share_grants (id, tenant_id, grantor_id, grantee_id, resource_type, resource_id, permission, wrapped_key, kem_ciphertext, signature, created_at, updated_at)
          VALUES (gen_random_uuid(), $1, $2, $3, 'invalid_type', $4, 'read', 'key', 'cipher', 'sig', NOW(), NOW())
          """,
          [
            uuid_to_binary(tenant.id),
            uuid_to_binary(user1.id),
            uuid_to_binary(user2.id),
            uuid_to_binary(folder.id)
          ]
        )

      assert {:error, %Postgrex.Error{postgres: %{code: :invalid_text_representation}}} = result
    end
  end

  describe "recovery tables constraints" do
    test "recovery_config has unique constraint on user_id" do
      tenant = insert(:tenant)
      user = insert(:user, tenant_id: tenant.id)

      insert(:recovery_config, user_id: user.id)

      # Attempt to insert second config for same user via SQL
      result =
        SQL.query(
          Repo,
          """
          INSERT INTO recovery_configs (id, user_id, threshold, total_shares, created_at, updated_at)
          VALUES (gen_random_uuid(), $1, 3, 5, NOW(), NOW())
          """,
          [uuid_to_binary(user.id)]
        )

      assert {:error, %Postgrex.Error{postgres: %{code: :unique_violation}}} = result
    end

    test "recovery_status enum constraint" do
      tenant = insert(:tenant)
      user = insert(:user, tenant_id: tenant.id)
      config = insert(:recovery_config, user_id: user.id)

      result =
        SQL.query(
          Repo,
          """
          INSERT INTO recovery_requests (id, config_id, user_id, status, created_at, updated_at)
          VALUES (gen_random_uuid(), $1, $2, 'invalid_status', NOW(), NOW())
          """,
          [uuid_to_binary(config.id), uuid_to_binary(user.id)]
        )

      assert {:error, %Postgrex.Error{postgres: %{code: :invalid_text_representation}}} = result
    end
  end

  describe "index existence" do
    test "all expected indexes exist" do
      result =
        SQL.query!(
          Repo,
          """
          SELECT indexname, tablename
          FROM pg_indexes
          WHERE schemaname = 'public'
          ORDER BY tablename, indexname
          """
        )

      indexes =
        Enum.map(result.rows, fn [indexname, tablename] ->
          {tablename, indexname}
        end)
        |> MapSet.new()

      # Verify key indexes exist
      assert {"tenants", "tenants_slug_index"} in indexes
      assert {"users", "users_tenant_id_email_index"} in indexes
      assert {"users", "users_tenant_id_index"} in indexes
      assert {"files", "files_storage_path_index"} in indexes
    end
  end
end
