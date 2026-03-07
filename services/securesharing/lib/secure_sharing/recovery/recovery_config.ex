defmodule SecureSharing.Recovery.RecoveryConfig do
  @moduledoc """
  Recovery configuration for a user's Shamir Secret Sharing setup.

  Each user can configure their recovery with:
  - threshold: minimum shares needed (k)
  - total_shares: total shares distributed (n)

  The Master Key is split into n shares, any k of which can reconstruct it.
  """
  use SecureSharing.Schema

  alias SecureSharing.Accounts.User

  schema "recovery_configs" do
    belongs_to :user, User
    has_many :shares, SecureSharing.Recovery.RecoveryShare, foreign_key: :config_id
    has_many :requests, SecureSharing.Recovery.RecoveryRequest, foreign_key: :config_id

    # Shamir parameters
    field :threshold, :integer, default: 3
    field :total_shares, :integer, default: 5

    # Status
    field :setup_complete, :boolean, default: false
    field :last_verified_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a recovery configuration.
  """
  def changeset(config, attrs) do
    config
    |> cast(attrs, [:user_id, :threshold, :total_shares])
    |> validate_required([:user_id, :threshold, :total_shares])
    |> validate_number(:threshold, greater_than: 0)
    |> validate_number(:total_shares, greater_than: 0)
    |> validate_threshold_less_than_total()
    |> unique_constraint(:user_id)
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Changeset for marking setup as complete.
  """
  def complete_setup_changeset(config) do
    config
    |> change(setup_complete: true)
  end

  @doc """
  Changeset for recording verification.
  """
  def verify_changeset(config) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    change(config, last_verified_at: now)
  end

  defp validate_threshold_less_than_total(changeset) do
    threshold = get_field(changeset, :threshold)
    total = get_field(changeset, :total_shares)

    if threshold && total && threshold > total do
      add_error(changeset, :threshold, "must be less than or equal to total_shares")
    else
      changeset
    end
  end
end
