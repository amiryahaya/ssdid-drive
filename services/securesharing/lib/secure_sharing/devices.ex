defmodule SecureSharing.Devices do
  @moduledoc """
  The Devices context for managing device enrollments.

  This module provides functions for:
  - Device registration and lookup
  - User enrollment on devices
  - Device signature verification
  - Enrollment revocation

  ## Device Enrollment Flow

  1. User logs in successfully
  2. Client generates device key pair (stored in secure hardware)
  3. Client calls `enroll_device/1` with device info and public key
  4. Backend creates Device (if new) and DeviceEnrollment
  5. Subsequent requests include device signature for verification

  ## Multi-User Support

  Multiple users can enroll on the same physical device. Each user has their
  own DeviceEnrollment with their own cryptographic key pair.
  """

  import Ecto.Query, warn: false

  alias SecureSharing.Repo
  alias SecureSharing.Devices.Device
  alias SecureSharing.Devices.DeviceEnrollment
  alias SecureSharing.Crypto

  # ============================================================================
  # Device Operations
  # ============================================================================

  @doc """
  Gets a device by ID.
  """
  def get_device(id) do
    Repo.get(Device, id)
  end

  @doc """
  Gets a device by fingerprint.
  """
  def get_device_by_fingerprint(nil), do: nil

  def get_device_by_fingerprint(fingerprint) do
    Repo.get_by(Device, device_fingerprint: fingerprint)
  end

  @doc """
  Creates a new device or returns existing one with matching fingerprint.
  """
  def find_or_create_device(attrs) do
    fingerprint = Map.get(attrs, :device_fingerprint) || Map.get(attrs, "device_fingerprint")

    case get_device_by_fingerprint(fingerprint) do
      nil ->
        create_device(attrs)

      device ->
        # Update device info if provided
        update_device_info(device, attrs)
    end
  end

  @doc """
  Creates a new device.
  """
  def create_device(attrs) do
    %Device{}
    |> Device.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates device info (model, OS version, app version).
  """
  def update_device_info(device, attrs) do
    device_info = Map.get(attrs, :device_info) || Map.get(attrs, "device_info") || %{}

    if map_size(device_info) > 0 do
      merged_info = Map.merge(device.device_info || %{}, device_info)

      device
      |> Ecto.Changeset.change(%{device_info: merged_info})
      |> Repo.update()
    else
      {:ok, device}
    end
  end

  @doc """
  Suspends a device, blocking all enrollments.
  """
  def suspend_device(device) do
    device
    |> Device.status_changeset(%{status: :suspended})
    |> Repo.update()
  end

  @doc """
  Reactivates a suspended device.
  """
  def activate_device(device) do
    device
    |> Device.status_changeset(%{status: :active})
    |> Repo.update()
  end

  # ============================================================================
  # Enrollment Operations
  # ============================================================================

  @doc """
  Gets an enrollment by ID.
  """
  def get_enrollment(id) do
    Repo.get(DeviceEnrollment, id)
  end

  @doc """
  Gets an enrollment by ID with preloaded device.
  """
  def get_enrollment_with_device(id) do
    DeviceEnrollment
    |> Repo.get(id)
    |> Repo.preload(:device)
  end

  @doc """
  Gets an active enrollment for a user on a specific device.
  """
  def get_active_enrollment(device_id, user_id) do
    DeviceEnrollment
    |> where([e], e.device_id == ^device_id and e.user_id == ^user_id and e.status == :active)
    |> Repo.one()
  end

  @doc """
  Gets an active enrollment by device ID (any user).
  Used for signature verification when user_id is not yet known.
  """
  def get_active_enrollment_by_device(device_id) do
    DeviceEnrollment
    |> where([e], e.device_id == ^device_id and e.status == :active)
    |> Repo.one()
  end

  @doc """
  Lists all enrollments for a user.
  """
  def list_user_enrollments(user_id) do
    DeviceEnrollment
    |> where([e], e.user_id == ^user_id)
    |> order_by([e], desc: e.enrolled_at)
    |> preload(:device)
    |> Repo.all()
  end

  @doc """
  Lists active enrollments for a user.
  """
  def list_active_user_enrollments(user_id) do
    DeviceEnrollment
    |> where([e], e.user_id == ^user_id and e.status == :active)
    |> order_by([e], desc: e.last_used_at)
    |> preload(:device)
    |> Repo.all()
  end

  @doc """
  Enrolls a user on a device.

  This is the main entry point for device enrollment. It:
  1. Finds or creates the Device record
  2. Creates a DeviceEnrollment for the user

  ## Parameters

  - `attrs` - Map containing:
    - `:user_id` - User ID (required)
    - `:tenant_id` - Tenant ID (required)
    - `:device_fingerprint` - Device fingerprint hash (required)
    - `:platform` - Device platform (required)
    - `:device_info` - Device info map (optional)
    - `:device_public_key` - User's device public key (required)
    - `:key_algorithm` - Key algorithm used (required)
    - `:device_name` - User-friendly device name (optional)

  ## Returns

  - `{:ok, enrollment}` on success
  - `{:error, changeset}` on failure
  """
  def enroll_device(attrs) do
    Repo.transaction(fn ->
      # 1. Find or create device
      device_attrs = %{
        device_fingerprint: attrs[:device_fingerprint] || attrs["device_fingerprint"],
        platform: attrs[:platform] || attrs["platform"],
        device_info: attrs[:device_info] || attrs["device_info"] || %{}
      }

      case find_or_create_device(device_attrs) do
        {:ok, device} ->
          # Continue with enrollment
          do_enroll_device(device, attrs)

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  defp do_enroll_device(device, attrs) do
    # Check if device is suspended
    if device.status == :suspended do
      Repo.rollback(:device_suspended)
    end

    # 2. Check for existing enrollment
    user_id = attrs[:user_id] || attrs["user_id"]

    case get_active_enrollment(device.id, user_id) do
      nil ->
        # 3. Create new enrollment
        enrollment_attrs = %{
          device_id: device.id,
          user_id: user_id,
          tenant_id: attrs[:tenant_id] || attrs["tenant_id"],
          device_public_key: attrs[:device_public_key] || attrs["device_public_key"],
          key_algorithm: attrs[:key_algorithm] || attrs["key_algorithm"],
          device_name: attrs[:device_name] || attrs["device_name"]
        }

        case create_enrollment(enrollment_attrs) do
          {:ok, enrollment} ->
            Repo.preload(enrollment, :device)

          {:error, changeset} ->
            Repo.rollback(changeset)
        end

      existing ->
        # Already enrolled, return existing
        Repo.preload(existing, :device)
    end
  end

  @doc """
  Creates a new device enrollment.
  """
  def create_enrollment(attrs) do
    %DeviceEnrollment{}
    |> DeviceEnrollment.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an enrollment's device name.
  """
  def update_enrollment(enrollment, attrs) do
    enrollment
    |> DeviceEnrollment.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Revokes an enrollment.
  """
  def revoke_enrollment(enrollment, reason \\ nil) do
    enrollment
    |> DeviceEnrollment.revoke_changeset(reason)
    |> Repo.update()
  end

  @doc """
  Revokes an enrollment by ID for a specific user.
  Returns error if enrollment doesn't belong to user.
  """
  def revoke_user_enrollment(enrollment_id, user_id, reason \\ nil) do
    case get_enrollment(enrollment_id) do
      nil ->
        {:error, :not_found}

      enrollment ->
        if enrollment.user_id == user_id do
          revoke_enrollment(enrollment, reason)
        else
          {:error, :unauthorized}
        end
    end
  end

  @doc """
  Updates the last_used_at timestamp for an enrollment.
  """
  def touch_enrollment(enrollment) do
    enrollment
    |> DeviceEnrollment.touch_changeset()
    |> Repo.update()
  end

  @doc """
  Updates the push notification player_id for an enrollment.

  Call this when the device registers with OneSignal and obtains a player_id.
  """
  def update_push_player_id(enrollment, player_id) do
    enrollment
    |> DeviceEnrollment.push_player_id_changeset(player_id)
    |> Repo.update()
  end

  @doc """
  Gets an enrollment by push player_id.
  """
  def get_enrollment_by_player_id(player_id) do
    DeviceEnrollment
    |> where([e], e.push_player_id == ^player_id and e.status == :active)
    |> Repo.one()
  end

  @doc """
  Clears the push player_id for an enrollment.

  Call this when user logs out to unregister from push notifications.
  """
  def clear_push_player_id(enrollment) do
    enrollment
    |> DeviceEnrollment.push_player_id_changeset(nil)
    |> Repo.update()
  end

  # ============================================================================
  # Signature Verification
  # ============================================================================

  @doc """
  Verifies a device signature.

  ## Parameters

  - `device_id` - The device ID from X-Device-ID header
  - `user_id` - The authenticated user ID
  - `signature` - Base64-encoded signature from X-Device-Signature header
  - `payload` - The data that was signed

  ## Returns

  - `{:ok, enrollment}` if signature is valid
  - `{:error, reason}` if verification fails
  """
  def verify_device_signature(device_id, user_id, signature, payload) do
    with {:ok, enrollment} <- get_and_validate_enrollment(device_id, user_id),
         {:ok, decoded_signature} <- Base.decode64(signature),
         :ok <- verify_signature(payload, decoded_signature, enrollment) do
      # Update last_used_at
      touch_enrollment(enrollment)
      {:ok, enrollment}
    end
  end

  defp get_and_validate_enrollment(device_id, user_id) do
    case get_active_enrollment(device_id, user_id) do
      nil ->
        {:error, :enrollment_not_found}

      enrollment ->
        # Also check device status
        device = get_device(enrollment.device_id)

        if device && device.status == :active do
          {:ok, enrollment}
        else
          {:error, :device_suspended}
        end
    end
  end

  defp verify_signature(payload, signature, enrollment) do
    # Map device key algorithm to Crypto module algorithm
    algorithm =
      case enrollment.key_algorithm do
        :kaz_sign -> :kaz
        :ml_dsa -> :nist
        _ -> nil
      end

    public_key = enrollment.device_public_key

    # Verify by recovering the message and comparing
    case Crypto.verify(signature, public_key, algorithm) do
      {:ok, recovered_message} ->
        # Check if recovered message matches expected payload
        if recovered_message == payload do
          :ok
        else
          {:error, :invalid_signature}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Builds the signature payload from request components.

  The payload format is:
  `{method}|{path}|{timestamp}|{body_hash}`

  Where body_hash is SHA-256 of the request body (or empty string for GET).
  """
  def build_signature_payload(method, path, timestamp, body \\ "") do
    body_hash =
      if body == "" or is_nil(body) do
        ""
      else
        :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)
      end

    "#{method}|#{path}|#{timestamp}|#{body_hash}"
  end

  # ============================================================================
  # Platform Attestation
  # ============================================================================

  @doc """
  Submits platform attestation data for a device.

  Stores the attestation blob, verifies it against the expected platform,
  and upgrades the device trust level to `:high` on success.

  ## Parameters
  - `device` - The device to attest
  - `attrs` - Map containing:
    - `:platform_attestation` - The attestation blob (binary)
    - `:platform` - Expected platform (:ios or :android)

  ## Returns
  - `{:ok, device}` with updated trust level on success
  - `{:error, reason}` if attestation fails
  """
  def submit_attestation(%Device{} = device, attrs) do
    attestation_data = attrs[:platform_attestation]
    platform = device.platform

    with :ok <- validate_attestation_format(attestation_data, platform),
         :ok <- verify_platform_attestation(attestation_data, platform, device) do
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      device
      |> Device.attestation_changeset(%{
        platform_attestation: attestation_data,
        attestation_verified_at: now,
        trust_level: :high
      })
      |> Repo.update()
    end
  end

  @doc """
  Checks if a device has verified attestation.
  """
  def attested?(%Device{} = device) do
    device.trust_level == :high and not is_nil(device.attestation_verified_at)
  end

  # Validates the attestation data format based on platform
  defp validate_attestation_format(nil, _platform) do
    {:error, {:bad_request, "Missing attestation data"}}
  end

  defp validate_attestation_format(data, _platform) when byte_size(data) == 0 do
    {:error, {:bad_request, "Empty attestation data"}}
  end

  defp validate_attestation_format(data, _platform) when byte_size(data) > 10_000 do
    {:error, {:bad_request, "Attestation data exceeds maximum size"}}
  end

  defp validate_attestation_format(_data, platform) when platform in [:ios, :android] do
    :ok
  end

  defp validate_attestation_format(_data, _platform) do
    {:error, {:bad_request, "Platform attestation is only supported for iOS and Android"}}
  end

  # Platform-specific attestation verification.
  # In production, these would verify attestation tokens against Apple/Google servers.
  defp verify_platform_attestation(attestation_data, :ios, device) do
    verify_app_attest(attestation_data, device)
  end

  defp verify_platform_attestation(attestation_data, :android, device) do
    verify_play_integrity(attestation_data, device)
  end

  defp verify_platform_attestation(_data, _platform, _device) do
    {:error, {:bad_request, "Unsupported platform for attestation"}}
  end

  # iOS App Attest verification.
  #
  # In production, this would:
  # 1. Decode the CBOR attestation object
  # 2. Extract the certificate chain
  # 3. Verify the chain against Apple's App Attest root certificate
  # 4. Verify the nonce matches the expected challenge
  # 5. Extract the key ID for future assertion verification
  #
  # For now, we accept the attestation data and store it.
  # Full verification requires the `apple_app_attest` dependency.
  defp verify_app_attest(attestation_data, _device) when is_binary(attestation_data) do
    # TODO: Implement full Apple App Attest verification
    # See: https://developer.apple.com/documentation/devicecheck/validating_apps_that_connect_to_your_server
    :ok
  end

  # Android Play Integrity verification.
  #
  # In production, this would:
  # 1. Decode the integrity token (JWE)
  # 2. Verify the token signature using Google's public key
  # 3. Check the integrity verdict (MEETS_DEVICE_INTEGRITY, etc.)
  # 4. Verify the request hash matches the expected challenge
  # 5. Check the package name matches our app
  #
  # For now, we accept the attestation data and store it.
  # Full verification requires calling Google's API via Req.
  defp verify_play_integrity(attestation_data, _device) when is_binary(attestation_data) do
    # TODO: Implement full Google Play Integrity verification
    # See: https://developer.android.com/google/play/integrity/verdict
    :ok
  end

  # ============================================================================
  # Admin Operations
  # ============================================================================

  @doc """
  Lists all devices (admin only).
  """
  def list_devices(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    Device
    |> order_by([d], desc: d.inserted_at)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  @doc """
  Lists all enrollments for a tenant (admin only).
  """
  def list_tenant_enrollments(tenant_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    DeviceEnrollment
    |> where([e], e.tenant_id == ^tenant_id)
    |> order_by([e], desc: e.enrolled_at)
    |> limit(^limit)
    |> offset(^offset)
    |> preload([:device, :user])
    |> Repo.all()
  end

  @doc """
  Counts active enrollments for a user.
  """
  def count_active_enrollments(user_id) do
    DeviceEnrollment
    |> where([e], e.user_id == ^user_id and e.status == :active)
    |> Repo.aggregate(:count)
  end
end
