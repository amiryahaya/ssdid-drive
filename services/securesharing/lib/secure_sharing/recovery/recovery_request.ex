defmodule SecureSharing.Recovery.RecoveryRequest do
  @moduledoc """
  A request from a user who has lost access and needs to recover their Master Key.

  The recovery flow:
  1. User generates a new keypair
  2. User creates a recovery request with the new public key
  3. Trustees are notified
  4. Trustees approve by re-encrypting their shares for the new public key
  5. Once threshold is reached, user can reconstruct the Master Key
  6. User re-encrypts their Master Key with the new passkey
  """
  use SecureSharing.Schema

  alias SecureSharing.Accounts.User
  alias SecureSharing.Recovery.{RecoveryConfig, RecoveryApproval}

  @statuses [:pending, :approved, :rejected, :completed, :expired]

  schema "recovery_requests" do
    belongs_to :config, RecoveryConfig
    belongs_to :user, User
    belongs_to :verified_by, User

    has_many :approvals, RecoveryApproval, foreign_key: :request_id

    # Request data
    field :new_public_key, :binary
    field :reason, :string
    field :status, Ecto.Enum, values: @statuses, default: :pending

    # Verification
    field :verified_at, :utc_datetime_usec

    # Timing
    field :expires_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a recovery request.
  """
  def changeset(request, attrs) do
    request
    |> cast(attrs, [:config_id, :user_id, :new_public_key, :reason, :expires_at])
    |> validate_required([:config_id, :user_id, :new_public_key, :expires_at])
    |> validate_expiry_in_future()
    |> foreign_key_constraint(:config_id)
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Changeset for verifying a recovery request (by admin/security team).
  """
  def verify_changeset(request, %User{id: verifier_id}) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    request
    |> change(verified_by_id: verifier_id, verified_at: now)
  end

  @doc """
  Changeset for updating request status.
  """
  def status_changeset(request, status) when status in @statuses do
    changes = %{status: status}

    changes =
      if status == :completed do
        now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
        Map.put(changes, :completed_at, now)
      else
        changes
      end

    change(request, changes)
  end

  @doc """
  Checks if the request is still active (pending and not expired).
  """
  def active?(%__MODULE__{status: status, expires_at: expires_at}) do
    is_pending = status == :pending
    not_expired = DateTime.compare(expires_at, DateTime.utc_now()) == :gt
    is_pending and not_expired
  end

  defp validate_expiry_in_future(changeset) do
    case get_change(changeset, :expires_at) do
      nil ->
        changeset

      expires_at ->
        if DateTime.compare(expires_at, DateTime.utc_now()) == :gt do
          changeset
        else
          add_error(changeset, :expires_at, "must be in the future")
        end
    end
  end
end
