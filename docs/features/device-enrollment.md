# Device Enrollment

**Version**: 1.0.0
**Status**: Draft
**Last Updated**: 2026-01

## 1. Overview

Device enrollment provides cryptographic binding between users and their devices. This enables:

- **Device attestation**: Verify requests come from enrolled devices
- **Multi-device support**: Users can have multiple enrolled devices
- **Device revocation**: Instantly revoke access from lost/stolen devices
- **Audit trail**: Track which device performed each action
- **Shared device support**: Multiple users can enroll on the same physical device

### Security Goals

| Goal | Description |
|------|-------------|
| Device Binding | Cryptographically bind device to user account |
| Request Signing | Sign sensitive requests with device key |
| Revocation | Instantly invalidate device access |
| Non-repudiation | Prove which device performed an action |

## 2. Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     SecureSharing Backend                    │
│                                                              │
│  ┌─────────────┐    ┌──────────────────┐    ┌────────────┐ │
│  │   Devices   │───│ DeviceEnrollments │───│   Users    │ │
│  └─────────────┘    └──────────────────┘    └────────────┘ │
│                                                              │
│  Device Signature Verification Plug                          │
│  ├── Verify X-Device-Signature header                       │
│  ├── Check enrollment status                                │
│  └── Update last_used_at                                    │
└─────────────────────────────────────────────────────────────┘
                           │
                           │ HTTPS + Device Signature
                           │
┌─────────────────────────────────────────────────────────────┐
│                      Client Device                           │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                  Device Key Storage                  │   │
│  │  Android: Keystore    iOS: Keychain/Secure Enclave  │   │
│  │  Windows: TPM         macOS: Keychain               │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌─────────────────┐    ┌─────────────────┐                │
│  │  User A Keys    │    │  User B Keys    │   (per-user)   │
│  └─────────────────┘    └─────────────────┘                │
└─────────────────────────────────────────────────────────────┘
```

## 3. Data Model

### 3.1 Device

Represents a physical device. Created once per device, shared across users on that device.

```elixir
%Device{
  id: UUID,

  # Device identification
  device_fingerprint: String,        # Hash of device characteristics

  # Platform info
  platform: :android | :ios | :windows | :macos | :linux | :other,
  device_info: %{
    model: String,                   # "Pixel 8", "iPhone 15 Pro"
    os_version: String,              # "Android 14", "iOS 17.2"
    app_version: String              # "1.0.0"
  },

  # Platform attestation (Phase 2)
  platform_attestation: binary | nil,
  attestation_verified_at: DateTime | nil,

  # Status
  status: :active | :suspended,
  trust_level: :high | :medium | :low,

  # Timestamps
  inserted_at: DateTime,
  updated_at: DateTime
}
```

### 3.2 DeviceEnrollment

Represents a user's enrollment on a specific device. One per (user, device) pair.

```elixir
%DeviceEnrollment{
  id: UUID,

  # Relationships
  device_id: UUID,                   # FK to Device
  user_id: UUID,                     # FK to User
  tenant_id: UUID,                   # FK to Tenant (for multi-tenant)

  # Cryptographic material
  device_public_key: binary,         # User's device signing key (public)
  key_algorithm: :kaz_sign | :ml_dsa,

  # Metadata
  device_name: String,               # User-friendly name ("My Phone")

  # Status
  status: :active | :revoked,
  revoked_at: DateTime | nil,
  revoked_reason: String | nil,

  # Activity tracking
  enrolled_at: DateTime,
  last_used_at: DateTime,

  # Timestamps
  inserted_at: DateTime,
  updated_at: DateTime
}
```

### 3.3 Relationships

```
Device (1) ────────── (N) DeviceEnrollment
                              │
User (1) ─────────────── (N) ─┘
                              │
Tenant (1) ───────────── (N) ─┘
```

- One physical device can have multiple enrollments (one per user)
- One user can have multiple enrollments (one per device)
- Each enrollment belongs to one tenant

## 4. Enrollment Flow

### 4.1 Initial Enrollment (During Login)

```
┌────────┐                     ┌────────┐                     ┌────────┐
│ Client │                     │ Backend│                     │   DB   │
└───┬────┘                     └───┬────┘                     └───┬────┘
    │                              │                              │
    │  1. Login Request            │                              │
    │  (email, password, tenant)   │                              │
    │─────────────────────────────>│                              │
    │                              │                              │
    │  2. Login Success            │                              │
    │  (tokens, user)              │                              │
    │<─────────────────────────────│                              │
    │                              │                              │
    │  3. Generate Device Key Pair │                              │
    │  (in secure hardware)        │                              │
    │                              │                              │
    │  4. Enroll Device            │                              │
    │  POST /api/devices/enroll    │                              │
    │  {                           │                              │
    │    device_fingerprint,       │                              │
    │    platform,                 │                              │
    │    device_info,              │                              │
    │    device_public_key,        │                              │
    │    key_algorithm,            │                              │
    │    device_name               │                              │
    │  }                           │                              │
    │─────────────────────────────>│  5. Find or create Device   │
    │                              │─────────────────────────────>│
    │                              │                              │
    │                              │  6. Create DeviceEnrollment  │
    │                              │─────────────────────────────>│
    │                              │                              │
    │  7. Enrollment Response      │                              │
    │  {                           │                              │
    │    enrollment_id,            │                              │
    │    device_id,                │                              │
    │    enrolled_at               │                              │
    │  }                           │                              │
    │<─────────────────────────────│                              │
    │                              │                              │
    │  8. Store enrollment locally │                              │
    │                              │                              │
```

### 4.2 Subsequent Logins (Existing Enrollment)

```
┌────────┐                     ┌────────┐
│ Client │                     │ Backend│
└───┬────┘                     └───┬────┘
    │                              │
    │  1. Login Request            │
    │─────────────────────────────>│
    │                              │
    │  2. Login Success            │
    │<─────────────────────────────│
    │                              │
    │  3. Check local enrollment   │
    │  (exists for this user?)     │
    │                              │
    │  [If exists and key valid]   │
    │  4. Use existing enrollment  │
    │                              │
    │  [If not exists]             │
    │  4. Generate new key pair    │
    │  5. Enroll device            │
    │─────────────────────────────>│
    │                              │
```

## 5. Request Signing

### 5.1 Which Requests to Sign

| Request Type | Signed | Reason |
|--------------|--------|--------|
| File upload | Yes | Prevent unauthorized uploads |
| File download | Yes | Audit trail for access |
| Share creation | Yes | Non-repudiation |
| Share revocation | Yes | Authorization |
| Folder operations | Yes | Data integrity |
| Settings changes | Yes | Account security |
| Device management | Yes | Security critical |
| Read-only queries | Optional | Performance vs security |

### 5.2 Signature Format

```
Headers:
  X-Device-ID: <device_id>
  X-Device-Signature: <base64_signature>
  X-Signature-Timestamp: <unix_timestamp_ms>

Signature payload:
  sign(
    concat(
      method,           # "POST"
      path,             # "/api/files/upload"
      timestamp,        # "1705590000000"
      body_hash         # SHA-256 of request body (or empty for GET)
    ),
    device_private_key
  )
```

### 5.3 Verification Process

```elixir
def verify_device_signature(conn) do
  device_id = get_req_header(conn, "x-device-id")
  signature = get_req_header(conn, "x-device-signature")
  timestamp = get_req_header(conn, "x-signature-timestamp")

  # 1. Check timestamp freshness (prevent replay)
  if abs(now() - timestamp) > 5_minutes do
    {:error, :signature_expired}
  end

  # 2. Get enrollment
  enrollment = Devices.get_active_enrollment(device_id, conn.assigns.user_id)

  if enrollment == nil do
    {:error, :device_not_enrolled}
  end

  # 3. Reconstruct payload
  payload = build_signature_payload(conn, timestamp)

  # 4. Verify signature
  case Crypto.verify_signature(payload, signature, enrollment.device_public_key) do
    :ok ->
      # 5. Update last_used_at
      Devices.touch_enrollment(enrollment)
      {:ok, enrollment}
    :error ->
      {:error, :invalid_signature}
  end
end
```

## 6. Device Management

### 6.1 List Devices

Users can view all their enrolled devices.

```
GET /api/devices

Response:
{
  "data": [
    {
      "id": "enrollment-uuid",
      "device_id": "device-uuid",
      "device_name": "My Pixel 8",
      "platform": "android",
      "device_info": {
        "model": "Pixel 8",
        "os_version": "Android 14",
        "app_version": "1.0.0"
      },
      "status": "active",
      "enrolled_at": "2026-01-18T10:00:00Z",
      "last_used_at": "2026-01-18T15:30:00Z",
      "is_current": true
    }
  ]
}
```

### 6.2 Revoke Device

Immediately invalidate a device's access.

```
DELETE /api/devices/:enrollment_id

Response:
{
  "data": {
    "id": "enrollment-uuid",
    "status": "revoked",
    "revoked_at": "2026-01-18T16:00:00Z"
  }
}
```

### 6.3 Rename Device

Update the user-friendly device name.

```
PUT /api/devices/:enrollment_id

Request:
{
  "device_name": "Work Phone"
}

Response:
{
  "data": {
    "id": "enrollment-uuid",
    "device_name": "Work Phone"
  }
}
```

## 7. Multi-User Device Support

When multiple users share a device (e.g., family tablet, shared workstation):

```
Physical Device (device-123)
├── User A enrollment (enrollment-aaa)
│   └── Device key pair for User A
├── User B enrollment (enrollment-bbb)
│   └── Device key pair for User B
└── User C enrollment (enrollment-ccc)
    └── Device key pair for User C
```

### Key Isolation

- Each user has their own device key pair
- Keys are stored with user-specific aliases
- Revoking one user's enrollment doesn't affect others
- Device-level suspension affects all users on that device

### Storage Strategy

**Android:**
```kotlin
// Key alias includes user ID for isolation
val keyAlias = "securesharing_device_key_${userId}"
```

**iOS:**
```swift
// Keychain tag includes user ID
let tag = "com.securesharing.device.\(userId)"
```

## 8. Revocation Scenarios

| Scenario | Action | Effect |
|----------|--------|--------|
| Lost phone | User revokes enrollment | That enrollment rejected |
| Stolen device | Admin suspends device | All enrollments on device rejected |
| User leaves org | Admin revokes user | All user's enrollments invalidated |
| Security incident | Admin revokes all | Force re-enrollment for all users |

## 9. Trust Levels

Devices are assigned trust levels based on attestation:

| Level | Criteria | Capabilities |
|-------|----------|--------------|
| **High** | Platform attestation verified | Full access |
| **Medium** | Device key only, no attestation | Standard access |
| **Low** | Unknown/suspicious device | Restricted access |

### Trust Level Enforcement (Phase 2)

```elixir
# Example: Restrict sensitive operations to high-trust devices
plug :require_high_trust when action in [:export_keys, :change_password]

defp require_high_trust(conn, _opts) do
  case conn.assigns.device_enrollment.trust_level do
    :high -> conn
    _ ->
      conn
      |> put_status(:forbidden)
      |> json(%{error: "This operation requires a high-trust device"})
      |> halt()
  end
end
```

## 10. Platform Attestation (Phase 2)

Future enhancement to integrate platform-specific attestation:

| Platform | Attestation API | What It Proves |
|----------|-----------------|----------------|
| Android | Play Integrity API | Genuine device, unmodified app |
| iOS | App Attest | Key in Secure Enclave, genuine app |
| Windows | TPM Attestation | Hardware-backed keys |
| macOS | DeviceCheck | Apple device verification |

### Integration Flow (Phase 2)

```
1. Client requests attestation from platform
2. Platform returns signed attestation
3. Client sends attestation to backend
4. Backend verifies with platform's servers
5. Backend updates device trust_level to :high
```

## 11. Audit Events

All device operations are logged for compliance:

| Event | Details Logged |
|-------|----------------|
| `device.enrolled` | device_id, platform, device_info |
| `device.revoked` | enrollment_id, reason, revoked_by |
| `device.signature_verified` | enrollment_id, endpoint, timestamp |
| `device.signature_failed` | device_id, reason, endpoint |
| `device.suspended` | device_id, reason, suspended_by |

## 12. API Reference

### Endpoints

| Method | Path | Description | Auth |
|--------|------|-------------|------|
| POST | /api/devices/enroll | Enroll device for current user | Token |
| GET | /api/devices | List user's enrolled devices | Token |
| GET | /api/devices/:id | Get enrollment details | Token |
| PUT | /api/devices/:id | Update device (name) | Token + Signature |
| DELETE | /api/devices/:id | Revoke enrollment | Token + Signature |

### Enroll Device

```
POST /api/devices/enroll

Request:
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

Response (201 Created):
{
  "data": {
    "id": "enrollment-uuid",
    "device_id": "device-uuid",
    "device_name": "My Phone",
    "platform": "android",
    "status": "active",
    "enrolled_at": "2026-01-18T10:00:00Z"
  }
}
```

## 13. Security Considerations

### Threat Mitigations

| Threat | Mitigation |
|--------|------------|
| Key extraction | Hardware-backed storage (Keystore, Secure Enclave) |
| Replay attacks | Timestamp in signature, 5-minute window |
| Device cloning | Platform attestation (Phase 2) |
| Stolen tokens | Device signature required for sensitive ops |
| Man-in-the-middle | TLS + request signing |

### Key Storage Requirements

- **Android**: Must use Android Keystore with `setUserAuthenticationRequired(false)` for background operations
- **iOS**: Must use Keychain with `kSecAttrAccessibleAfterFirstUnlock`
- **Windows**: Should use TPM-backed keys where available
- **macOS**: Should use Keychain with Secure Enclave on Apple Silicon

## 14. Implementation Checklist

### Backend
- [ ] Database migrations (devices, device_enrollments)
- [ ] Device and DeviceEnrollment schemas
- [ ] Devices context (CRUD)
- [ ] DeviceController (API endpoints)
- [ ] DeviceSignaturePlug (verification)
- [ ] Audit event integration

### Android
- [ ] Device key generation (KeyManager integration)
- [ ] Enrollment flow (post-login)
- [ ] Request signing interceptor
- [ ] Device management UI
- [ ] Multi-user key isolation

### iOS (Future)
- [ ] Device key generation (Secure Enclave)
- [ ] Enrollment flow
- [ ] Request signing
- [ ] Device management UI
