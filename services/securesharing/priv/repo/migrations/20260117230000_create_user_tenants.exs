defmodule SecureSharing.Repo.Migrations.CreateUserTenants do
  @moduledoc """
  Create user_tenants junction table for multi-tenant user support.

  This migration enables users to belong to multiple tenants with per-tenant roles.
  The existing users.tenant_id and users.role are migrated to this table.
  """
  use Ecto.Migration

  def up do
    # 1. Create user_tenants junction table
    create table(:user_tenants, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false

      # Role within this tenant (moved from users table)
      add :role, :string, null: false, default: "member"

      # Invitation tracking
      add :invited_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :invitation_accepted_at, :utc_datetime_usec

      # Status within tenant
      add :status, :string, null: false, default: "active"

      # When user joined this tenant
      add :joined_at, :utc_datetime_usec, null: false, default: fragment("NOW()")

      # Use created_at/updated_at to match canonical schema (not inserted_at)
      add :created_at, :utc_datetime_usec, null: false, default: fragment("NOW()")
      add :updated_at, :utc_datetime_usec, null: false, default: fragment("NOW()")
    end

    # Unique constraint: user can only belong to a tenant once
    create unique_index(:user_tenants, [:user_id, :tenant_id])

    # Indexes for common queries
    create index(:user_tenants, [:user_id])
    create index(:user_tenants, [:tenant_id])
    create index(:user_tenants, [:tenant_id, :role])
    create index(:user_tenants, [:tenant_id, :status])

    # 2. Migrate existing user-tenant relationships from users table
    execute """
            INSERT INTO user_tenants (id, user_id, tenant_id, role, status, joined_at, created_at, updated_at)
            SELECT
              gen_random_uuid(),
              id,
              tenant_id,
              COALESCE(role, 'member'),
              CASE WHEN status = 'active' THEN 'active' ELSE 'suspended' END,
              created_at,
              NOW(),
              NOW()
            FROM users
            WHERE tenant_id IS NOT NULL
            """,
            ""

    # 3. Make tenant_id nullable on users table (keep for backward compatibility during transition)
    alter table(:users) do
      modify :tenant_id, :binary_id, null: true
    end

    # Note: We keep users.role for now to avoid breaking existing code
    # It will be deprecated in favor of user_tenants.role
  end

  def down do
    # Restore tenant_id as NOT NULL (only works if all users still have tenant_id set)
    alter table(:users) do
      modify :tenant_id, :binary_id, null: false
    end

    drop table(:user_tenants)
  end
end
