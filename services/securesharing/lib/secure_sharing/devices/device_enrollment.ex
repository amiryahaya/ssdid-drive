defmodule SecureSharing.Devices.DeviceEnrollment do
  @moduledoc """
  DeviceEnrollment schema for user-device cryptographic binding.

  Each enrollment represents a user's cryptographic binding to a specific device.
  The device_public_key is used to verify request signatures from that device,
  ensuring requests originate from an authorized device.

  ## Multi-User Support

  Multiple users can enroll on the same physical device (e.g., shared tablet).
  Each user has their own enrollment with their own device key pair.

  ## Key Algorithm

  - `:kaz_sign` - Malaysian post-quantum signature algorithm
  - `:ml_dsa` - NIST ML-DSA (CRYSTALS-Dilithium)

  ## Status

  - `:active` - Enrollment is valid, requests will be accepted
  - `:revoked` - Enrollment has been revoked, requests will be rejected
  """
  use SecureSharing.Schema

  @key_algorithms ~w(kaz_sign ml_dsa)a
  @statuses ~w(active revoked)a

  schema "device_enrollments" do
    # Relationships
    belongs_to :device, SecureSharing.Devices.Device
    belongs_to :user, SecureSharing.Accounts.User
    belongs_to :tenant, SecureSharing.Accounts.Tenant

    # Cryptographic material
    field :device_public_key, :binary
    field :key_algorithm, Ecto.Enum, values: @key_algorithms

    # Metadata
    field :device_name, :string

    # Status
    field :status, Ecto.Enum, values: @statuses, default: :active
    field :revoked_at, :utc_datetime_usec
    field :revoked_reason, :string

    # Activity tracking
    field :enrolled_at, :utc_datetime_usec
    field :last_used_at, :utc_datetime_usec

    # Push notifications (OneSignal player_id)
    field :push_player_id, :string

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a new device enrollment.
  """
  def create_changeset(enrollment, attrs) do
    enrollment
    |> cast(attrs, [
      :device_id,
      :user_id,
      :tenant_id,
      :device_public_key,
      :key_algorithm,
      :device_name
    ])
    |> validate_required([:device_id, :user_id, :tenant_id, :device_public_key, :key_algorithm])
    |> validate_length(:device_name, max: 128)
    |> validate_public_key()
    |> put_enrolled_at()
    |> foreign_key_constraint(:device_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:tenant_id)
    |> unique_constraint([:device_id, :user_id], message: "already enrolled on this device")
  end

  @doc """
  Changeset for updating device enrollment (name only).
  """
  def update_changeset(enrollment, attrs) do
    enrollment
    |> cast(attrs, [:device_name])
    |> validate_length(:device_name, max: 128)
  end

  @doc """
  Changeset for revoking a device enrollment.
  """
  def revoke_changeset(enrollment, reason \\ nil) do
    enrollment
    |> change(%{
      status: :revoked,
      revoked_at: DateTime.utc_now(),
      revoked_reason: reason
    })
  end

  @doc """
  Changeset for updating last_used_at timestamp.
  """
  def touch_changeset(enrollment) do
    enrollment
    |> change(%{last_used_at: DateTime.utc_now()})
  end

  @doc """
  Changeset for updating the push notification player_id.
  """
  def push_player_id_changeset(enrollment, player_id) do
    enrollment
    |> change(%{push_player_id: player_id})
  end

  # Validate that device_public_key is a valid binary of expected size
  defp validate_public_key(changeset) do
    validate_change(changeset, :device_public_key, fn :device_public_key, key ->
      algorithm = get_field(changeset, :key_algorithm)

      min_size =
        case algorithm do
          :kaz_sign -> 1000
          :ml_dsa -> 1000
          _ -> 32
        end

      cond do
        not is_binary(key) ->
          [device_public_key: "must be a binary"]

        byte_size(key) < min_size ->
          [device_public_key: "is too short for #{algorithm}"]

        true ->
          []
      end
    end)
  end

  defp put_enrolled_at(changeset) do
    if get_field(changeset, :enrolled_at) do
      changeset
    else
      put_change(changeset, :enrolled_at, DateTime.utc_now())
    end
  end

  @doc """
  Returns the list of valid key algorithms.
  """
  def key_algorithms, do: @key_algorithms

  @doc """
  Returns the list of valid statuses.
  """
  def statuses, do: @statuses

  @doc """
  Check if enrollment is active.
  """
  def active?(%__MODULE__{status: :active}), do: true
  def active?(_), do: false
end
