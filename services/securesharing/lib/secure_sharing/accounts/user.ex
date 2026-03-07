defmodule SecureSharing.Accounts.User do
  @moduledoc """
  User schema with DID-based identity and zero-knowledge key storage.

  Users authenticate via SSDID (Self-Sovereign Distributed Identity):
  - Identity is a DID (Decentralized Identifier)
  - Authentication uses challenge-response with DID keypairs
  - No email/password required
  - The server never sees private keys or the Master Key

  ## Identity Model

  Each user has a unique DID (e.g., `did:ssdid:abc123`) that serves as their
  primary identifier. The DID maps to a DID Document in the SSDID Registry
  containing the user's public keys.
  """
  use SecureSharing.Schema

  @user_statuses ~w(active suspended pending_recovery)a
  @user_roles ~w(member admin owner)a

  schema "users" do
    # SSDID identity (primary identifier)
    field :did, :string
    field :status, Ecto.Enum, values: @user_statuses, default: :active
    field :role, Ecto.Enum, values: @user_roles, default: :member
    field :display_name, :string
    field :external_id, :string

    # Optional email (for notifications only, not authentication)
    field :email, :string

    # Zero-knowledge key storage (client-side encrypted)
    field :public_keys, :map, default: %{}
    field :encrypted_private_keys, :binary
    field :encrypted_master_key, :binary
    field :key_derivation_salt, :binary

    # Vault-based MK storage
    field :vault_encrypted_master_key, :binary
    field :vault_mk_nonce, :binary
    field :vault_salt, :binary

    # Recovery
    field :recovery_setup_complete, :boolean, default: false

    # Admin
    field :is_admin, :boolean, default: false

    # Activity tracking
    field :last_login_at, :utc_datetime_usec

    # Tenant relationships
    belongs_to :tenant, SecureSharing.Accounts.Tenant

    has_many :user_tenants, SecureSharing.Accounts.UserTenant
    has_many :tenants, through: [:user_tenants, :tenant]

    has_many :credentials, SecureSharing.Accounts.Credential

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a user from a DID (auto-provisioned on first SSDID registration).
  """
  def did_registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:did, :display_name, :tenant_id])
    |> validate_required([:did])
    |> sanitize_display_name()
    |> validate_length(:did, max: 256)
    |> validate_length(:display_name, max: 256)
    |> unique_constraint(:did)
  end

  @doc """
  Changeset for admin user setup (bootstrap).
  """
  def admin_registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:did, :display_name])
    |> validate_required([:did])
    |> unique_constraint(:did)
  end

  @doc """
  Changeset for updating user's key material.
  """
  def key_changeset(user, attrs) do
    user
    |> cast(attrs, [
      :public_keys,
      :encrypted_private_keys,
      :encrypted_master_key,
      :key_derivation_salt
    ])
  end

  @doc """
  Changeset for updating user status.
  """
  def status_changeset(user, attrs) do
    user
    |> cast(attrs, [:status])
    |> validate_inclusion(:status, @user_statuses)
  end

  @doc """
  Changeset for updating user role.
  """
  def role_changeset(user, attrs) do
    user
    |> cast(attrs, [:role])
    |> validate_inclusion(:role, @user_roles)
  end

  @doc """
  Changeset for updating vault-based master key storage.
  """
  def vault_changeset(user, attrs) do
    user
    |> cast(attrs, [
      :vault_encrypted_master_key,
      :vault_mk_nonce,
      :vault_salt
    ])
  end

  @doc """
  Changeset for updating user profile fields.
  """
  def profile_changeset(user, attrs) do
    user
    |> cast(attrs, [:display_name, :external_id, :email])
    |> sanitize_display_name()
    |> validate_length(:display_name, max: 256)
    |> validate_length(:external_id, max: 256)
    |> validate_length(:email, max: 160)
  end

  defp sanitize_display_name(changeset) do
    case get_change(changeset, :display_name) do
      nil ->
        changeset

      value ->
        sanitized = SecureSharing.InputSanitizer.sanitize_display_name(value)
        put_change(changeset, :display_name, sanitized)
    end
  end

  @doc """
  Changeset for recording login activity.
  """
  def login_changeset(user) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    change(user, last_login_at: now)
  end

  @doc """
  Returns the list of valid user roles.
  """
  def user_roles, do: @user_roles

  @doc """
  Changeset for updating admin status.
  """
  def admin_changeset(user, attrs) do
    user
    |> cast(attrs, [:is_admin])
  end
end
