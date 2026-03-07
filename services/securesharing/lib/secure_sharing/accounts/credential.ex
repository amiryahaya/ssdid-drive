defmodule SecureSharing.Accounts.Credential do
  @moduledoc """
  User Credential schema for authentication methods.

  Represents authentication credentials linked to a user:
  - WebAuthn passkeys
  - Digital ID certificates
  - OIDC tokens
  - SAML assertions

  ## Master Key Storage Model

  The location of the encrypted Master Key depends on the IdP configuration:

  - If `IdpConfig.provides_key_material = true`:
    - `encrypted_master_key` is stored HERE (in this credential)
    - Used for WebAuthn, certificate-based Digital ID

  - If `IdpConfig.provides_key_material = false`:
    - `encrypted_master_key` is stored in `User.vault_encrypted_master_key`
    - Used for OIDC, SAML, OIDC-based Digital ID

  ## Login Precedence Rule

  When authenticating, the MK source is determined by the credential being used:
  1. Look up the credential's `provider_id` → `IdpConfig`
  2. Check `IdpConfig.provides_key_material`
  3. Retrieve MK from credential or user vault accordingly
  """
  use SecureSharing.Schema

  @credential_types ~w(password webauthn digital_id oidc saml)a

  schema "credentials" do
    field :type, Ecto.Enum, values: @credential_types

    # WebAuthn-specific
    field :credential_id, :binary
    field :public_key, :binary
    field :counter, :integer, default: 0
    field :transports, :map

    # OIDC/Digital ID specific
    field :external_id, :string

    # Credential-level MK storage
    field :encrypted_master_key, :binary
    field :mk_nonce, :binary

    # Metadata
    field :device_name, :string
    field :last_used_at, :utc_datetime_usec

    belongs_to :user, SecureSharing.Accounts.User
    belongs_to :provider, SecureSharing.Accounts.IdpConfig

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc """
  Returns the list of valid credential types.
  """
  def credential_types, do: @credential_types

  @doc """
  Changeset for creating a WebAuthn credential.
  """
  def webauthn_changeset(credential, attrs) do
    credential
    |> cast(attrs, [
      :user_id,
      :provider_id,
      :credential_id,
      :public_key,
      :counter,
      :transports,
      :encrypted_master_key,
      :mk_nonce,
      :device_name
    ])
    |> put_change(:type, :webauthn)
    |> validate_required([:user_id, :credential_id, :public_key])
    |> validate_length(:device_name, max: 128)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:provider_id)
    |> unique_constraint(:credential_id)
  end

  @doc """
  Changeset for creating an OIDC/SAML/Digital ID credential.
  """
  def external_changeset(credential, attrs, type) when type in [:oidc, :saml, :digital_id] do
    credential
    |> cast(attrs, [
      :user_id,
      :provider_id,
      :external_id,
      :device_name
    ])
    |> put_change(:type, type)
    |> validate_required([:user_id, :external_id])
    |> validate_length(:external_id, max: 256)
    |> validate_length(:device_name, max: 128)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:provider_id)
  end

  @doc """
  Changeset for updating credential counter (WebAuthn).
  """
  def counter_changeset(credential, attrs) do
    credential
    |> cast(attrs, [:counter])
    |> validate_required([:counter])
    |> validate_number(:counter, greater_than_or_equal_to: 0)
  end

  @doc """
  Changeset for updating last_used_at timestamp.
  """
  def touch_changeset(credential) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    change(credential, last_used_at: now)
  end

  @doc """
  Changeset for updating device name.
  """
  def device_name_changeset(credential, attrs) do
    credential
    |> cast(attrs, [:device_name])
    |> validate_length(:device_name, max: 128)
  end
end
