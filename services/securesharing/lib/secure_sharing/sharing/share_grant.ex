defmodule SecureSharing.Sharing.ShareGrant do
  @moduledoc """
  ShareGrant schema for zero-knowledge file and folder sharing.

  A ShareGrant represents a cryptographic access grant from one user to another.
  The key (DEK for files, KEK for folders) is wrapped using the recipient's
  PQC public key, ensuring only the recipient can decrypt.

  The grantor signs the share to provide authenticity and integrity.
  Shares can be time-limited (expires_at) and revoked (revoked_at).

  For folder shares with recursive=true, the grantee gains access to all
  files and subfolders within the shared folder.
  """
  use SecureSharing.Schema

  alias SecureSharing.Accounts.{Tenant, User}

  @resource_types [:file, :folder]
  @permissions [:read, :write, :admin]
  @algorithms ~w(kaz nist hybrid)

  schema "share_grants" do
    belongs_to :tenant, Tenant
    belongs_to :grantor, User
    belongs_to :grantee, User
    belongs_to :revoked_by, User

    # Resource being shared (polymorphic reference)
    field :resource_type, Ecto.Enum, values: @resource_types
    field :resource_id, UUIDv7

    # Cryptographic access
    field :wrapped_key, :binary
    field :kem_ciphertext, :binary
    field :algorithm, :string, default: "kaz"

    # Permission and scope
    field :permission, Ecto.Enum, values: @permissions, default: :read
    field :recursive, :boolean, default: true

    # Time-limited access
    field :expires_at, :utc_datetime_usec

    # Integrity
    field :signature, :binary

    # Revocation
    field :revoked_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a new share grant.

  Required fields:
  - tenant_id: The tenant this share belongs to
  - grantor_id: User creating the share
  - grantee_id: User receiving the share
  - resource_type: :file or :folder
  - resource_id: ID of the file or folder
  - wrapped_key: DEK/KEK wrapped for grantee's public key
  - kem_ciphertext: KEM ciphertext for unwrapping
  - signature: Grantor's signature over the grant

  Optional fields:
  - algorithm: PQC algorithm used (default: kaz)
  - permission: :read, :write, or :admin (default: read)
  - recursive: For folders, include children (default: true)
  - expires_at: Optional expiry time
  """
  def changeset(share_grant, attrs) do
    share_grant
    |> cast(attrs, [
      :tenant_id,
      :grantor_id,
      :grantee_id,
      :resource_type,
      :resource_id,
      :wrapped_key,
      :kem_ciphertext,
      :algorithm,
      :permission,
      :recursive,
      :expires_at,
      :signature
    ])
    |> validate_required([
      :tenant_id,
      :grantor_id,
      :grantee_id,
      :resource_type,
      :resource_id,
      :wrapped_key,
      :kem_ciphertext,
      :signature
    ])
    |> validate_inclusion(:resource_type, @resource_types)
    |> validate_inclusion(:permission, @permissions)
    |> validate_inclusion(:algorithm, @algorithms)
    |> validate_not_self_share()
    |> foreign_key_constraint(:tenant_id)
    |> foreign_key_constraint(:grantor_id)
    |> foreign_key_constraint(:grantee_id)
    |> unique_constraint([:grantor_id, :grantee_id, :resource_type, :resource_id],
      name: :share_grants_active_unique,
      message: "share already exists for this resource"
    )
  end

  @doc """
  Changeset for revoking a share.
  """
  def revoke_changeset(share_grant, %User{id: revoked_by_id}) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    share_grant
    |> change(revoked_at: now, revoked_by_id: revoked_by_id)
  end

  @doc """
  Changeset for updating share permissions.
  Requires re-signing since permission is part of the signed data.
  """
  def permission_changeset(share_grant, attrs) do
    share_grant
    |> cast(attrs, [:permission, :signature])
    |> validate_required([:permission, :signature])
    |> validate_inclusion(:permission, @permissions)
  end

  @doc """
  Changeset for extending or setting expiry.
  """
  def expiry_changeset(share_grant, attrs) do
    share_grant
    |> cast(attrs, [:expires_at])
    |> validate_expiry_in_future()
  end

  # Validates that grantor and grantee are different users
  defp validate_not_self_share(changeset) do
    grantor_id = get_field(changeset, :grantor_id)
    grantee_id = get_field(changeset, :grantee_id)

    if grantor_id && grantee_id && grantor_id == grantee_id do
      add_error(changeset, :grantee_id, "cannot share with yourself")
    else
      changeset
    end
  end

  # Validates that expiry is in the future
  defp validate_expiry_in_future(changeset) do
    case get_change(changeset, :expires_at) do
      nil ->
        changeset

      expires_at ->
        now = DateTime.utc_now()

        if DateTime.compare(expires_at, now) == :gt do
          changeset
        else
          add_error(changeset, :expires_at, "must be in the future")
        end
    end
  end

  @doc """
  Checks if the share grant is currently active (not revoked, not expired).
  """
  def active?(%__MODULE__{revoked_at: revoked_at, expires_at: expires_at}) do
    not_revoked = is_nil(revoked_at)

    not_expired =
      case expires_at do
        nil -> true
        dt -> DateTime.compare(dt, DateTime.utc_now()) == :gt
      end

    not_revoked and not_expired
  end

  @doc """
  Checks if the share grant has a specific permission level or higher.
  Permission hierarchy: read < write < admin
  """
  def has_permission?(%__MODULE__{permission: grant_permission}, required_permission) do
    permission_level(grant_permission) >= permission_level(required_permission)
  end

  defp permission_level(:read), do: 1
  defp permission_level(:write), do: 2
  defp permission_level(:admin), do: 3
end
