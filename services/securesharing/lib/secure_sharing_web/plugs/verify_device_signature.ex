defmodule SecureSharingWeb.Plugs.VerifyDeviceSignature do
  @moduledoc """
  Plug to verify device signatures on sensitive requests.

  This plug checks for device signature headers and verifies that the request
  was signed by an enrolled device's private key.

  ## Headers

  - `X-Device-ID` - The device ID (from enrollment)
  - `X-Device-Signature` - Base64-encoded signature
  - `X-Signature-Timestamp` - Unix timestamp (milliseconds) when signature was created

  ## Signature Payload

  The signature is computed over:
  ```
  {method}|{path}|{timestamp}|{body_hash}
  ```

  Where `body_hash` is the SHA-256 hex digest of the request body (empty string for GET).

  ## Usage

  ```elixir
  # Require device signature for specific actions
  plug VerifyDeviceSignature when action in [:delete, :update]

  # Optional verification (assigns enrollment if present)
  plug VerifyDeviceSignature, optional: true
  ```

  ## Assigns

  On successful verification:
  - `device_enrollment` - The DeviceEnrollment struct
  - `device` - The Device struct

  ## Options

  - `:optional` - If true, missing/invalid signature is allowed (default: false)
  - `:max_age` - Maximum age of signature in seconds (default: 300 = 5 minutes)
  """

  import Plug.Conn

  alias SecureSharing.Devices

  @behaviour Plug

  # Default signature max age: 5 minutes
  @default_max_age 300

  @impl true
  def init(opts) do
    %{
      optional: Keyword.get(opts, :optional, false),
      max_age: Keyword.get(opts, :max_age, @default_max_age)
    }
  end

  @impl true
  def call(conn, opts) do
    with {:ok, device_id} <- extract_device_id(conn, opts),
         {:ok, signature} <- extract_signature(conn, opts),
         {:ok, timestamp} <- extract_timestamp(conn, opts),
         :ok <- verify_timestamp(timestamp, opts.max_age),
         {:ok, user} <- get_current_user(conn),
         {:ok, payload} <- build_payload(conn, timestamp),
         {:ok, enrollment} <-
           Devices.verify_device_signature(device_id, user.id, signature, payload) do
      conn
      |> assign(:device_enrollment, enrollment)
      |> assign(:device, enrollment.device)
    else
      {:error, :missing_header} when opts.optional ->
        conn

      {:error, reason} when opts.optional ->
        # Log but don't fail for optional verification
        log_verification_failure(conn, reason)
        conn

      {:error, reason} ->
        log_verification_failure(conn, reason)
        send_error(conn, reason)
    end
  end

  # Extract device ID from header
  defp extract_device_id(conn, opts) do
    case get_req_header(conn, "x-device-id") do
      [device_id | _] -> {:ok, device_id}
      _ when opts.optional -> {:error, :missing_header}
      _ -> {:error, :missing_device_id}
    end
  end

  # Extract signature from header
  defp extract_signature(conn, opts) do
    case get_req_header(conn, "x-device-signature") do
      [signature | _] -> {:ok, signature}
      _ when opts.optional -> {:error, :missing_header}
      _ -> {:error, :missing_signature}
    end
  end

  # Extract timestamp from header
  defp extract_timestamp(conn, opts) do
    case get_req_header(conn, "x-signature-timestamp") do
      [timestamp_str | _] ->
        case Integer.parse(timestamp_str) do
          {timestamp, ""} -> {:ok, timestamp}
          _ -> {:error, :invalid_timestamp}
        end

      _ when opts.optional ->
        {:error, :missing_header}

      _ ->
        {:error, :missing_timestamp}
    end
  end

  # Verify timestamp is within acceptable range
  defp verify_timestamp(timestamp, max_age) do
    now = System.system_time(:millisecond)
    age_ms = abs(now - timestamp)
    max_age_ms = max_age * 1000

    if age_ms <= max_age_ms do
      :ok
    else
      {:error, :signature_expired}
    end
  end

  # Get current user from conn assigns
  defp get_current_user(conn) do
    case conn.assigns[:current_user] do
      nil -> {:error, :not_authenticated}
      user -> {:ok, user}
    end
  end

  # Build the signature payload
  defp build_payload(conn, timestamp) do
    method = String.upcase(to_string(conn.method))
    path = conn.request_path

    # Get body for non-GET requests
    body =
      case conn.body_params do
        %Plug.Conn.Unfetched{} -> ""
        params when map_size(params) == 0 -> ""
        params -> Jason.encode!(params)
      end

    payload = Devices.build_signature_payload(method, path, timestamp, body)
    {:ok, payload}
  end

  # Log verification failure for monitoring
  defp log_verification_failure(conn, reason) do
    require Logger

    Logger.warning(
      "Device signature verification failed",
      reason: reason,
      path: conn.request_path,
      method: conn.method,
      device_id: get_device_id_for_log(conn)
    )
  end

  defp get_device_id_for_log(conn) do
    case get_req_header(conn, "x-device-id") do
      [device_id | _] -> device_id
      _ -> "unknown"
    end
  end

  # Send error response
  defp send_error(conn, reason) do
    {status, message} = error_response(reason)

    conn
    |> put_status(status)
    |> Phoenix.Controller.put_view(json: SecureSharingWeb.ErrorJSON)
    |> Phoenix.Controller.json(%{error: %{message: message, code: to_string(reason)}})
    |> halt()
  end

  defp error_response(:missing_device_id), do: {400, "Missing X-Device-ID header"}
  defp error_response(:missing_signature), do: {400, "Missing X-Device-Signature header"}
  defp error_response(:missing_timestamp), do: {400, "Missing X-Signature-Timestamp header"}
  defp error_response(:invalid_timestamp), do: {400, "Invalid X-Signature-Timestamp format"}
  defp error_response(:signature_expired), do: {401, "Signature has expired"}
  defp error_response(:enrollment_not_found), do: {401, "Device not enrolled"}
  defp error_response(:device_suspended), do: {403, "Device has been suspended"}
  defp error_response(:invalid_signature), do: {401, "Invalid device signature"}
  defp error_response(:not_authenticated), do: {401, "Authentication required"}
  defp error_response(_), do: {401, "Device signature verification failed"}
end
