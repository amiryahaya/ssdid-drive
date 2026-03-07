defmodule SecureSharing.Recovery.RecoveryApproval do
  @moduledoc """
  A trustee's approval of a recovery request.

  When approving, the trustee:
  1. Decrypts their share using their private key
  2. Re-encrypts the share for the user's new public key
  3. Signs the approval

  This allows the recovering user to collect shares without
  the server ever seeing the plaintext shares.
  """
  use SecureSharing.Schema

  alias SecureSharing.Accounts.User
  alias SecureSharing.Recovery.{RecoveryRequest, RecoveryShare}

  schema "recovery_approvals" do
    belongs_to :request, RecoveryRequest
    belongs_to :share, RecoveryShare
    belongs_to :trustee, User

    # Re-encrypted share data
    field :reencrypted_share, :binary
    field :kem_ciphertext, :binary
    field :signature, :binary

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a recovery approval.
  """
  def changeset(approval, attrs) do
    approval
    |> cast(attrs, [
      :request_id,
      :share_id,
      :trustee_id,
      :reencrypted_share,
      :kem_ciphertext,
      :signature
    ])
    |> validate_required([
      :request_id,
      :share_id,
      :trustee_id,
      :reencrypted_share,
      :kem_ciphertext,
      :signature
    ])
    |> foreign_key_constraint(:request_id)
    |> foreign_key_constraint(:share_id)
    |> foreign_key_constraint(:trustee_id)
    |> unique_constraint([:request_id, :trustee_id])
  end
end
