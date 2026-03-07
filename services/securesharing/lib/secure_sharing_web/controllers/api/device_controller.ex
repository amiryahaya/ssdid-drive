defmodule SecureSharingWeb.API.DeviceController do
  @moduledoc """
  Controller for device enrollment and management.

  Provides endpoints for:
  - Enrolling a device for the current user
  - Listing enrolled devices
  - Revoking device enrollments
  - Updating device names
  """

  use SecureSharingWeb, :controller

  alias SecureSharing.Devices

  action_fallback SecureSharingWeb.FallbackController

  @doc """
  Enroll a device for the current user.

  POST /api/devices/enroll

  Request body:
  ```json
  {
    "device_fingerprint": "sha256:abc123...",
    "platform": "android",
    "device_info": {
      "model": "Pixel 8",
      "os_version": "Android 14",
      "app_version": "1.0.0"
    },
    "device_public_key": "base64...",
    "key_algorithm": "kaz_sign",
    "device_name": "My Phone"
  }
  ```
  """
  def enroll(conn, params) do
    user = conn.assigns.current_user
    tenant = conn.assigns.current_tenant

    attrs = %{
      user_id: user.id,
      tenant_id: tenant.id,
      device_fingerprint: params["device_fingerprint"],
      platform: params["platform"],
      device_info: params["device_info"] || %{},
      device_public_key: decode_binary(params["device_public_key"]),
      key_algorithm: parse_algorithm(params["key_algorithm"]),
      device_name: params["device_name"]
    }

    case Devices.enroll_device(attrs) do
      {:ok, enrollment} ->
        # Send new device login notification email
        send_new_device_email(user, enrollment, conn)

        conn
        |> put_status(:created)
        |> render(:show, enrollment: enrollment)

      {:error, :device_suspended} ->
        {:error, :forbidden, "Device has been suspended"}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp send_new_device_email(user, enrollment, conn) do
    alias SecureSharing.Workers.EmailWorker

    # Platform is on the device, not the enrollment
    platform =
      case enrollment.device do
        %{platform: p} when not is_nil(p) -> to_string(p)
        _ -> "Unknown"
      end

    device_info = %{
      "name" => enrollment.device_name || "Unknown device",
      "platform" => platform
    }

    login_metadata = %{
      login_at: enrollment.enrolled_at || DateTime.utc_now(),
      ip_address: get_client_ip(conn),
      location: "Unknown location"
    }

    # Send asynchronously via Oban with retry logic
    EmailWorker.enqueue_new_device_login(user, device_info, login_metadata)
  end

  defp get_client_ip(conn) do
    case get_req_header(conn, "x-forwarded-for") do
      [ip | _] ->
        ip

      _ ->
        conn.remote_ip
        |> :inet.ntoa()
        |> to_string()
    end
  end

  @doc """
  List all enrolled devices for the current user.

  GET /api/devices
  """
  def index(conn, _params) do
    user = conn.assigns.current_user
    enrollments = Devices.list_user_enrollments(user.id)

    # Mark the current device if we can identify it
    current_device_id = get_current_device_id(conn)

    render(conn, :index, enrollments: enrollments, current_device_id: current_device_id)
  end

  @doc """
  Get details of a specific enrollment.

  GET /api/devices/:id
  """
  def show(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    with {:ok, enrollment} <- get_user_enrollment(id, user.id) do
      current_device_id = get_current_device_id(conn)
      render(conn, :show, enrollment: enrollment, current_device_id: current_device_id)
    end
  end

  @doc """
  Update a device enrollment (name only).

  PUT /api/devices/:id

  Request body:
  ```json
  {
    "device_name": "Work Phone"
  }
  ```
  """
  def update(conn, %{"id" => id} = params) do
    user = conn.assigns.current_user

    with {:ok, enrollment} <- get_user_enrollment(id, user.id),
         {:ok, updated} <- Devices.update_enrollment(enrollment, params) do
      render(conn, :show, enrollment: Devices.get_enrollment_with_device(updated.id))
    end
  end

  @doc """
  Revoke a device enrollment.

  DELETE /api/devices/:id

  Optional query param:
  - reason: Reason for revocation
  """
  def delete(conn, %{"id" => id} = params) do
    user = conn.assigns.current_user
    reason = params["reason"]

    case Devices.revoke_user_enrollment(id, user.id, reason) do
      {:ok, enrollment} ->
        render(conn, :show, enrollment: enrollment)

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, :unauthorized} ->
        {:error, :forbidden}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Register push notification player_id for a device enrollment.

  POST /api/devices/:id/push

  Request body:
  ```json
  {
    "player_id": "onesignal-player-id"
  }
  ```

  This endpoint:
  1. Updates the enrollment with the player_id
  2. Sets the external_user_id in OneSignal to enable user-targeted notifications
  """
  def register_push(conn, %{"id" => id, "player_id" => player_id}) do
    user = conn.assigns.current_user

    alias SecureSharing.Workers.NotificationWorker

    with {:ok, enrollment} <- get_user_enrollment(id, user.id),
         {:ok, updated} <- Devices.update_push_player_id(enrollment, player_id) do
      # Also set external_user_id in OneSignal for user-targeted notifications
      # Do this in background via Oban with retry logic
      NotificationWorker.enqueue_set_external_user_id(player_id, user.id)

      render(conn, :show, enrollment: Devices.get_enrollment_with_device(updated.id))
    end
  end

  @doc """
  Unregister push notifications for a device enrollment.

  DELETE /api/devices/:id/push

  Call this when user logs out to stop receiving notifications on this device.
  """
  def unregister_push(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    alias SecureSharing.Workers.NotificationWorker

    with {:ok, enrollment} <- get_user_enrollment(id, user.id) do
      # Clear external_user_id in OneSignal via Oban with retry logic
      if enrollment.push_player_id do
        NotificationWorker.enqueue_clear_external_user_id(enrollment.push_player_id)
      end

      {:ok, updated} = Devices.clear_push_player_id(enrollment)
      render(conn, :show, enrollment: Devices.get_enrollment_with_device(updated.id))
    end
  end

  @doc """
  Submit platform attestation for a device.

  POST /api/devices/:id/attest

  Request body:
  ```json
  {
    "attestation": "base64-encoded attestation blob"
  }
  ```

  On success, the device's trust_level is upgraded to `:high`.
  """
  def attest(conn, %{"id" => id, "attestation" => attestation}) do
    user = conn.assigns.current_user

    with {:ok, enrollment} <- get_user_enrollment(id, user.id),
         {:ok, attestation_data} <- decode_attestation(attestation),
         {:ok, device} <- {:ok, Devices.get_device(enrollment.device_id)},
         {:ok, _attested_device} <-
           Devices.submit_attestation(device, %{platform_attestation: attestation_data}) do
      # Re-fetch the enrollment with updated device
      updated_enrollment = Devices.get_enrollment_with_device(enrollment.id)
      render(conn, :show, enrollment: updated_enrollment, attested: true)
    end
  end

  def attest(_conn, _params) do
    {:error, {:bad_request, "Missing required field: attestation"}}
  end

  defp decode_attestation(data) when is_binary(data) do
    case Base.decode64(data) do
      {:ok, decoded} -> {:ok, decoded}
      :error -> {:error, :invalid_base64}
    end
  end

  # Private functions

  defp get_user_enrollment(id, user_id) do
    case Devices.get_enrollment_with_device(id) do
      nil ->
        {:error, :not_found}

      enrollment ->
        if enrollment.user_id == user_id do
          {:ok, enrollment}
        else
          {:error, :forbidden}
        end
    end
  end

  defp get_current_device_id(conn) do
    case get_req_header(conn, "x-device-id") do
      [device_id | _] -> device_id
      _ -> nil
    end
  end

  defp decode_binary(nil), do: nil

  defp decode_binary(data) when is_binary(data) do
    alias SecureSharingWeb.Helpers.BinaryHelpers
    BinaryHelpers.decode_base64_optional(data)
  end

  defp parse_algorithm("kaz_sign"), do: :kaz_sign
  defp parse_algorithm("ml_dsa"), do: :ml_dsa
  defp parse_algorithm(other), do: other
end
