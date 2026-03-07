defmodule SecureSharingWeb.API.DeviceJSON do
  @moduledoc """
  JSON rendering for device enrollment responses.
  """

  alias SecureSharing.Devices.DeviceEnrollment
  alias SecureSharing.Devices.Device

  @doc """
  Renders a list of device enrollments.
  """
  def index(%{enrollments: enrollments, current_device_id: current_device_id}) do
    %{data: Enum.map(enrollments, &enrollment_data(&1, current_device_id))}
  end

  def index(%{enrollments: enrollments}) do
    %{data: Enum.map(enrollments, &enrollment_data(&1, nil))}
  end

  @doc """
  Renders a single device enrollment.
  """
  def show(%{enrollment: enrollment, current_device_id: current_device_id}) do
    %{data: enrollment_data(enrollment, current_device_id)}
  end

  def show(%{enrollment: enrollment}) do
    %{data: enrollment_data(enrollment, nil)}
  end

  # Build enrollment response data
  defp enrollment_data(%DeviceEnrollment{} = enrollment, current_device_id) do
    device = enrollment.device

    %{
      id: enrollment.id,
      device_id: enrollment.device_id,
      device_name: enrollment.device_name,
      status: enrollment.status,
      key_algorithm: enrollment.key_algorithm,
      enrolled_at: enrollment.enrolled_at,
      last_used_at: enrollment.last_used_at,
      revoked_at: enrollment.revoked_at,
      revoked_reason: enrollment.revoked_reason,
      is_current: current_device_id && enrollment.device_id == current_device_id,
      device: device_data(device)
    }
  end

  # Build device info
  defp device_data(nil), do: nil

  defp device_data(%Ecto.Association.NotLoaded{}), do: nil

  defp device_data(%Device{} = device) do
    %{
      id: device.id,
      platform: device.platform,
      device_info: device.device_info,
      status: device.status,
      trust_level: device.trust_level,
      attestation_verified_at: device.attestation_verified_at
    }
  end
end
