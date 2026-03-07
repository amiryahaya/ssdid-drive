defmodule SecureSharing.Recovery.RecoveryShare do
  @moduledoc """
  A Shamir secret share distributed to a trustee.

  Each share is:
  - Encrypted with the trustee's PQC public key
  - Signed by the owner
  - Has a unique index for Shamir reconstruction

  When the owner needs to recover, trustees re-encrypt their shares
  for the owner's new public key.
  """
  use SecureSharing.Schema

  alias SecureSharing.Accounts.User
  alias SecureSharing.Recovery.RecoveryConfig

  schema "recovery_shares" do
    belongs_to :config, RecoveryConfig
    belongs_to :owner, User
    belongs_to :trustee, User

    # Share data
    field :share_index, :integer
    field :encrypted_share, :binary
    field :kem_ciphertext, :binary
    field :signature, :binary

    # Status
    field :accepted, :boolean, default: false
    field :accepted_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a recovery share.
  """
  def changeset(share, attrs) do
    share
    |> cast(attrs, [
      :config_id,
      :owner_id,
      :trustee_id,
      :share_index,
      :encrypted_share,
      :kem_ciphertext,
      :signature
    ])
    |> validate_required([
      :config_id,
      :owner_id,
      :trustee_id,
      :share_index,
      :encrypted_share,
      :kem_ciphertext,
      :signature
    ])
    |> validate_number(:share_index, greater_than: 0)
    |> validate_not_self_trustee()
    |> foreign_key_constraint(:config_id)
    |> foreign_key_constraint(:owner_id)
    |> foreign_key_constraint(:trustee_id)
    |> unique_constraint([:owner_id, :trustee_id])
    |> unique_constraint([:config_id, :share_index])
  end

  @doc """
  Changeset for trustee accepting a share.
  """
  def accept_changeset(share) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    share
    |> change(accepted: true, accepted_at: now)
  end

  defp validate_not_self_trustee(changeset) do
    owner_id = get_field(changeset, :owner_id)
    trustee_id = get_field(changeset, :trustee_id)

    if owner_id && trustee_id && owner_id == trustee_id do
      add_error(changeset, :trustee_id, "cannot be your own trustee")
    else
      changeset
    end
  end
end
