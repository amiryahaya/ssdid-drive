defmodule SecureSharing.Repo.Migrations.AddUserRoleAndFields do
  @moduledoc """
  Adds role, display_name, external_id, vault fields, and last_login_at to users table.

  Matches 02-database-schema.md Section 4.2.

  The vault_* fields support the Credential-Authoritative MK storage model:
  - Used when authenticating with credentials that DON'T provide key material
  - NULL if user only has credentials WITH key material (WebAuthn, cert-based Digital ID)
  """
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :role, :user_role, null: false, default: "member"
      add :display_name, :string, size: 256
      add :external_id, :string, size: 256

      # Vault-based MK storage (for credentials without key material)
      add :vault_encrypted_master_key, :binary
      add :vault_mk_nonce, :binary
      add :vault_salt, :binary

      add :last_login_at, :utc_datetime_usec
    end

    create index(:users, [:tenant_id, :status])
  end
end
