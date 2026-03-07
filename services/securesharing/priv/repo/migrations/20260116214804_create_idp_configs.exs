defmodule SecureSharing.Repo.Migrations.CreateIdpConfigs do
  @moduledoc """
  Creates the idp_configs table for identity provider configurations.

  Matches 02-database-schema.md Section 4.3.

  IdP configurations define how users can authenticate to a tenant:
  - WebAuthn (passkeys)
  - Digital ID (MyDigitalID integration)
  - OIDC (OpenID Connect providers)
  - SAML (SAML 2.0 providers)

  The `provides_key_material` field determines where the Master Key is stored:
  - true: Credential.encrypted_master_key (WebAuthn, cert-based Digital ID)
  - false: User.vault_encrypted_master_key (OIDC, SAML, OIDC-based Digital ID)
  """
  use Ecto.Migration

  def change do
    create table(:idp_configs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # Relationships
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false

      # Configuration
      add :type, :idp_type, null: false
      add :name, :string, size: 128, null: false
      add :enabled, :boolean, null: false, default: true
      add :priority, :integer, null: false, default: 0

      # Key material capability
      add :provides_key_material, :boolean, null: false, default: false

      # Provider-specific configuration (JSONB)
      add :config, :map, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:idp_configs, [:tenant_id, :enabled, :priority])
  end
end
