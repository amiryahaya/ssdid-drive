defmodule SecureSharing.Devices.Device do
  @moduledoc """
  Device schema for physical device registration.

  A Device represents a physical device (phone, tablet, computer) that can be
  enrolled by one or more users. The device_fingerprint helps identify the same
  physical device across sessions.

  ## Trust Levels

  - `:high` - Platform attestation verified (Play Integrity, App Attest, etc.)
  - `:medium` - Device enrolled with key, but no platform attestation
  - `:low` - Unknown or suspicious device

  ## Status

  - `:active` - Device can be used for enrollments
  - `:suspended` - All enrollments on this device are blocked
  """
  use SecureSharing.Schema

  @platforms ~w(android ios windows macos linux other)a
  @statuses ~w(active suspended)a
  @trust_levels ~w(high medium low)a

  schema "devices" do
    # Device identification
    field :device_fingerprint, :string

    # Platform info
    field :platform, Ecto.Enum, values: @platforms
    field :device_info, :map, default: %{}

    # Platform attestation (Phase 2)
    field :platform_attestation, :binary
    field :attestation_verified_at, :utc_datetime_usec

    # Status
    field :status, Ecto.Enum, values: @statuses, default: :active
    field :trust_level, Ecto.Enum, values: @trust_levels, default: :medium

    # Relationships
    has_many :device_enrollments, SecureSharing.Devices.DeviceEnrollment

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a new device.
  """
  def create_changeset(device, attrs) do
    device
    |> cast(attrs, [:device_fingerprint, :platform, :device_info])
    |> validate_required([:device_fingerprint, :platform])
    |> validate_length(:device_fingerprint, max: 128)
    |> validate_device_info()
  end

  @doc """
  Changeset for updating device status.
  """
  def status_changeset(device, attrs) do
    device
    |> cast(attrs, [:status, :trust_level])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:trust_level, @trust_levels)
  end

  @doc """
  Changeset for updating platform attestation.
  """
  def attestation_changeset(device, attrs) do
    device
    |> cast(attrs, [:platform_attestation, :attestation_verified_at, :trust_level])
  end

  # Validate device_info has expected structure
  defp validate_device_info(changeset) do
    validate_change(changeset, :device_info, fn :device_info, info ->
      cond do
        not is_map(info) ->
          [device_info: "must be a map"]

        true ->
          []
      end
    end)
  end

  @doc """
  Returns the list of valid platforms.
  """
  def platforms, do: @platforms

  @doc """
  Returns the list of valid statuses.
  """
  def statuses, do: @statuses

  @doc """
  Returns the list of valid trust levels.
  """
  def trust_levels, do: @trust_levels
end
