defmodule SecureSharing.Repo.Migrations.MigrateToSsdidAuth do
  use Ecto.Migration

  @moduledoc """
  Migrate users table from email/password auth to SSDID (DID-based) auth.

  Changes:
  - Add `did` column as the primary identity field
  - Make `email` optional (used for notifications only, not auth)
  - Remove `hashed_password` (no password-based auth)
  - Remove `confirmed_at` (no email confirmation needed)
  - Drop `users_tokens` table (no JWT/session tokens in DB)
  - Drop unique index on [tenant_id, email]
  - Add unique index on `did`
  """

  def change do
    # Add DID column
    alter table(:users) do
      add :did, :string, size: 256
      add :display_name, :string, size: 256
      add :external_id, :string, size: 256
      add :role, :string, default: "member"
      add :is_admin, :boolean, default: false
      add :last_login_at, :utc_datetime_usec

      # Vault-based MK storage
      add :vault_encrypted_master_key, :binary
      add :vault_mk_nonce, :binary
      add :vault_salt, :binary
    end

    # Make email nullable (no longer required for auth)
    execute "ALTER TABLE users ALTER COLUMN email DROP NOT NULL",
            "ALTER TABLE users ALTER COLUMN email SET NOT NULL"

    # Make tenant_id nullable (DID users get auto-provisioned tenant)
    execute "ALTER TABLE users ALTER COLUMN tenant_id DROP NOT NULL",
            "ALTER TABLE users ALTER COLUMN tenant_id SET NOT NULL"

    # Create unique index on DID
    create unique_index(:users, [:did])
    create index(:users, [:display_name])

    # Drop the email+tenant unique index (email is optional now)
    drop_if_exists unique_index(:users, [:tenant_id, :email])

    # Drop users_tokens table (SSDID uses in-memory session store, no DB tokens)
    drop_if_exists table(:users_tokens)

    # Remove password column
    alter table(:users) do
      remove :hashed_password, :string
      remove :confirmed_at, :utc_datetime_usec
    end
  end
end
