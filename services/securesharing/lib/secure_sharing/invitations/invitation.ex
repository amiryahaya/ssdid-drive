defmodule SecureSharing.Invitations.Invitation do
  @moduledoc """
  Invitation schema for the invitation-only onboarding system.

  Invitations allow admins and authorized users to invite new users to join
  a tenant. The invitation includes a secure token sent via email.

  ## Token Security

  - A 32-byte random token is generated for each invitation
  - Only the SHA-256 hash of the token is stored in the database
  - The actual token is sent to the invitee via email (once)
  - Token lookup is done via hash comparison (constant-time)

  ## Status Lifecycle

      Created -> Pending -> Accepted
                        \\-> Expired (automatic, via scheduled job)
                        \\-> Revoked (manual, by admin)
  """
  use SecureSharing.Schema

  @invitation_statuses ~w(pending accepted expired revoked)a
  @invitation_roles ~w(admin manager member)a

  schema "invitations" do
    # Token hash (actual token is only available at creation time)
    field :token, :string, virtual: true, redact: true
    field :token_hash, :string

    # Invitation details
    field :email, :string
    field :role, Ecto.Enum, values: @invitation_roles, default: :member
    field :message, :string

    # Status
    field :status, Ecto.Enum, values: @invitation_statuses, default: :pending

    # Expiration
    field :expires_at, :utc_datetime_usec

    # Acceptance tracking
    field :accepted_at, :utc_datetime_usec

    # Metadata (pre-shared folders, etc.)
    field :metadata, :map, default: %{}

    # Relationships
    belongs_to :tenant, SecureSharing.Accounts.Tenant
    belongs_to :inviter, SecureSharing.Accounts.User
    belongs_to :accepted_by, SecureSharing.Accounts.User

    timestamps()
  end

  @required_fields [:email, :role, :tenant_id, :inviter_id, :expires_at]
  @optional_fields [:message, :metadata]

  # RFC 5322 compliant email regex
  @email_regex ~r/^[a-zA-Z0-9.!#$%&'*+\/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$/

  @doc """
  Changeset for creating a new invitation.

  Automatically generates a secure token and computes its hash.
  """
  def create_changeset(invitation, attrs) do
    invitation
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_email()
    |> generate_token()
    |> unique_constraint(:token_hash)
    |> unique_constraint([:tenant_id, :email],
      name: :idx_invitations_pending_email_per_tenant,
      message: "already has a pending invitation"
    )
    |> foreign_key_constraint(:tenant_id)
    |> foreign_key_constraint(:inviter_id)
  end

  defp validate_email(changeset) do
    changeset
    |> validate_format(:email, @email_regex, message: "must be a valid email address")
    |> validate_length(:email, max: 255)
    |> update_change(:email, &String.downcase/1)
  end

  defp generate_token(changeset) do
    if changeset.valid? do
      # Generate 32 bytes of random data (256 bits of entropy)
      token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
      # Store only the hash in the database
      token_hash = hash_token(token)

      changeset
      |> put_change(:token, token)
      |> put_change(:token_hash, token_hash)
    else
      changeset
    end
  end

  @doc """
  Hash a token for storage/lookup.
  """
  def hash_token(token) do
    :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
  end

  @doc """
  Changeset for accepting an invitation.
  """
  def accept_changeset(invitation, user_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    invitation
    |> change(%{
      status: :accepted,
      accepted_at: now,
      accepted_by_id: user_id
    })
  end

  @doc """
  Changeset for revoking an invitation.
  """
  def revoke_changeset(invitation) do
    change(invitation, %{status: :revoked})
  end

  @doc """
  Changeset for expiring an invitation.
  """
  def expire_changeset(invitation) do
    change(invitation, %{status: :expired})
  end

  @doc """
  Check if an invitation is still valid (pending and not expired).
  """
  def valid?(%__MODULE__{status: :pending, expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :lt
  end

  def valid?(_), do: false

  @doc """
  Returns the list of valid invitation roles.
  """
  def invitation_roles, do: @invitation_roles

  @doc """
  Returns the list of valid invitation statuses.
  """
  def invitation_statuses, do: @invitation_statuses
end
