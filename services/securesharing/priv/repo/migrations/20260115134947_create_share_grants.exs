defmodule SecureSharing.Repo.Migrations.CreateShareGrants do
  use Ecto.Migration

  def change do
    # Create enum for resource type
    execute(
      "CREATE TYPE share_resource_type AS ENUM ('file', 'folder')",
      "DROP TYPE share_resource_type"
    )

    # Create enum for permission level
    execute(
      "CREATE TYPE share_permission AS ENUM ('read', 'write', 'admin')",
      "DROP TYPE share_permission"
    )

    create table(:share_grants, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false

      # Resource being shared (polymorphic)
      add :resource_type, :share_resource_type, null: false
      add :resource_id, :binary_id, null: false

      # Who shared and who received
      add :grantor_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :grantee_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      # Cryptographic access - key wrapped for recipient's public key
      # For files: wrapped DEK
      # For folders: wrapped KEK
      add :wrapped_key, :binary, null: false

      # KEM ciphertext for decapsulating the shared secret
      add :kem_ciphertext, :binary, null: false

      # Algorithm used for this share (matches tenant's pqc_algorithm)
      add :algorithm, :string, null: false, default: "kaz"

      # Permission level
      add :permission, :share_permission, null: false, default: "read"

      # For folder shares: whether children are included
      add :recursive, :boolean, default: true, null: false

      # Optional expiry for time-limited shares
      add :expires_at, :utc_datetime_usec

      # Grantor's signature over the share grant
      # Signs: resource_id + grantee_id + permission + wrapped_key + kem_ciphertext
      add :signature, :binary, null: false

      # Share status
      add :revoked_at, :utc_datetime_usec
      add :revoked_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    # Index for listing shares received by a user
    create index(:share_grants, [:grantee_id])

    # Index for listing shares created by a user
    create index(:share_grants, [:grantor_id])

    # Index for finding shares for a specific resource
    create index(:share_grants, [:resource_type, :resource_id])

    # Index for tenant isolation
    create index(:share_grants, [:tenant_id])

    # Unique constraint: one active share per grantor-grantee-resource combination
    create unique_index(:share_grants, [:grantor_id, :grantee_id, :resource_type, :resource_id],
             where: "revoked_at IS NULL",
             name: :share_grants_active_unique
           )

    # Index for finding expired shares
    create index(:share_grants, [:expires_at], where: "expires_at IS NOT NULL")
  end
end
