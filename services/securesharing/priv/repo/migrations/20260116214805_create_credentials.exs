defmodule SecureSharing.Repo.Migrations.CreateCredentials do
  @moduledoc """
  Creates the credentials table for user authentication credentials.

  Matches 02-database-schema.md Section 4.4.

  Credentials represent authentication methods linked to a user:
  - WebAuthn passkeys (credential_id, public_key, counter)
  - Digital ID certificates (external_id)
  - OIDC/SAML tokens (external_id)

  Master Key Storage Model:
  - If IdpConfig.provides_key_material = true → encrypted_master_key is populated here
  - If IdpConfig.provides_key_material = false → User.vault_encrypted_master_key is used

  LOGIN PRECEDENCE RULE:
  MK source is determined by the credential being used to authenticate.
  """
  use Ecto.Migration

  def change do
    create table(:credentials, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # Relationships
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :provider_id, references(:idp_configs, type: :binary_id, on_delete: :nilify_all)

      # Type
      add :type, :credential_type, null: false

      # WebAuthn-specific
      add :credential_id, :binary
      add :public_key, :binary
      add :counter, :integer, null: false, default: 0
      add :transports, :map

      # OIDC/Digital ID specific
      add :external_id, :string, size: 256

      # Credential-level MK storage (for IdPs with key material)
      add :encrypted_master_key, :binary
      add :mk_nonce, :binary

      # Metadata
      add :device_name, :string, size: 128
      add :last_used_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # Indexes
    create index(:credentials, [:user_id, :type])
    create index(:credentials, [:external_id], where: "external_id IS NOT NULL")

    # Unique constraint: one credential_id per system (WebAuthn spec requirement)
    # This also serves as the index for credential_id lookups
    create unique_index(:credentials, [:credential_id], where: "credential_id IS NOT NULL")

    # Constraints
    execute(
      """
      ALTER TABLE credentials
      ADD CONSTRAINT credentials_webauthn_check CHECK (
        type != 'webauthn' OR (credential_id IS NOT NULL AND public_key IS NOT NULL)
      )
      """,
      "ALTER TABLE credentials DROP CONSTRAINT credentials_webauthn_check"
    )

    execute(
      """
      ALTER TABLE credentials
      ADD CONSTRAINT credentials_oidc_check CHECK (
        type NOT IN ('oidc', 'digital_id') OR external_id IS NOT NULL
      )
      """,
      "ALTER TABLE credentials DROP CONSTRAINT credentials_oidc_check"
    )
  end
end
