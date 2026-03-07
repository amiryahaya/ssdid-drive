defmodule SecureSharing.Accounts.IdpConfig do
  @moduledoc """
  Identity Provider Configuration schema.

  Defines how users can authenticate to a tenant using various identity providers:
  - WebAuthn (passkeys)
  - Digital ID (MyDigitalID integration)
  - OIDC (OpenID Connect)
  - SAML (SAML 2.0)

  ## Key Material Capability

  The `provides_key_material` field determines where the user's Master Key is stored:

  - `true`: The credential itself stores the encrypted MK (in `Credential.encrypted_master_key`)
    - Used for: WebAuthn, certificate-based Digital ID
    - Key derivation happens from the credential's key material

  - `false`: The user's vault stores the encrypted MK (in `User.vault_encrypted_master_key`)
    - Used for: OIDC, SAML, OIDC-based Digital ID
    - Key derivation happens from password or vault mechanism
  """
  use SecureSharing.Schema

  @idp_types ~w(webauthn digital_id oidc saml)a

  schema "idp_configs" do
    field :type, Ecto.Enum, values: @idp_types
    field :name, :string
    field :enabled, :boolean, default: true
    field :priority, :integer, default: 0
    field :provides_key_material, :boolean, default: false
    field :config, :map

    belongs_to :tenant, SecureSharing.Accounts.Tenant
    has_many :credentials, SecureSharing.Accounts.Credential, foreign_key: :provider_id

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Returns the list of valid IdP types.
  """
  def idp_types, do: @idp_types

  @doc """
  Changeset for creating an IdP configuration.
  """
  def changeset(idp_config, attrs) do
    idp_config
    |> cast(attrs, [
      :type,
      :name,
      :enabled,
      :priority,
      :provides_key_material,
      :config,
      :tenant_id
    ])
    |> validate_required([:type, :name, :config, :tenant_id])
    |> validate_length(:name, min: 1, max: 128)
    |> validate_inclusion(:type, @idp_types)
    |> validate_config()
    |> foreign_key_constraint(:tenant_id)
  end

  @doc """
  Changeset for updating an IdP configuration.
  """
  def update_changeset(idp_config, attrs) do
    idp_config
    |> cast(attrs, [:name, :enabled, :priority, :config])
    |> validate_length(:name, min: 1, max: 128)
    |> validate_config()
  end

  defp validate_config(changeset) do
    type = get_field(changeset, :type)
    config = get_field(changeset, :config)

    case validate_config_for_type(type, config) do
      :ok -> changeset
      {:error, message} -> add_error(changeset, :config, message)
    end
  end

  defp validate_config_for_type(:webauthn, config) when is_map(config) do
    required = ~w(rp_id rp_name)
    missing = required -- Map.keys(config)

    if Enum.empty?(missing) do
      :ok
    else
      {:error, "missing required fields: #{Enum.join(missing, ", ")}"}
    end
  end

  defp validate_config_for_type(:oidc, config) when is_map(config) do
    required = ~w(client_id issuer)
    missing = required -- Map.keys(config)

    if Enum.empty?(missing) do
      :ok
    else
      {:error, "missing required fields: #{Enum.join(missing, ", ")}"}
    end
  end

  defp validate_config_for_type(:saml, config) when is_map(config) do
    required = ~w(idp_entity_id idp_sso_url)
    missing = required -- Map.keys(config)

    if Enum.empty?(missing) do
      :ok
    else
      {:error, "missing required fields: #{Enum.join(missing, ", ")}"}
    end
  end

  defp validate_config_for_type(:digital_id, config) when is_map(config) do
    required = ~w(provider)
    missing = required -- Map.keys(config)

    if Enum.empty?(missing) do
      :ok
    else
      {:error, "missing required fields: #{Enum.join(missing, ", ")}"}
    end
  end

  defp validate_config_for_type(nil, _config), do: :ok
  defp validate_config_for_type(_type, nil), do: :ok
  defp validate_config_for_type(_type, _config), do: :ok
end
