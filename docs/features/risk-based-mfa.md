# Risk-Based Multi-Factor Authentication

**Version**: 2.0.0
**Status**: Draft
**Last Updated**: 2026-01-18

---

## Overview

This document outlines a **pragmatic, phased approach** to implementing MFA with risk-based authentication for SecureSharing. We start simple and add complexity only when needed.

### Design Principles

1. **Start simple** - Basic TOTP before anomaly detection
2. **Single app** - No distributed services until proven necessary
3. **Iterate based on real usage** - Don't solve imaginary scale problems
4. **BEAM benefits without complexity** - Use OTP patterns in a monolith

---

## Phase 1: Basic TOTP MFA (Implement First)

**Goal**: Users can enable TOTP (Google Authenticator) as a second factor.

### What We're Building

```
┌─────────────┐     ┌─────────────────────────────────────┐
│   Android   │────▶│         SecureSharing Backend       │
│   Client    │     │                                     │
│             │     │  ┌─────────────────────────────────┐│
│ ┌─────────┐ │     │  │        Auth Controller          ││
│ │  TOTP   │ │     │  │   (login, verify_totp)          ││
│ │  Input  │ │     │  └──────────────┬──────────────────┘│
│ └─────────┘ │     │                 │                   │
└─────────────┘     │  ┌──────────────▼──────────────────┐│
                    │  │         MFA Module              ││
                    │  │  ┌───────────┐ ┌─────────────┐  ││
                    │  │  │   TOTP    │ │   Backup    │  ││
                    │  │  │   .ex     │ │   Codes.ex  │  ││
                    │  │  └───────────┘ └─────────────┘  ││
                    │  └─────────────────────────────────┘│
                    │                 │                   │
                    │  ┌──────────────▼──────────────────┐│
                    │  │          PostgreSQL             ││
                    │  │   (mfa_methods, backup_codes)   ││
                    │  └─────────────────────────────────┘│
                    └─────────────────────────────────────┘
```

### Database Schema

```sql
-- User MFA configuration
CREATE TABLE mfa_methods (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    method VARCHAR(20) NOT NULL DEFAULT 'totp',  -- 'totp' only for Phase 1
    secret_encrypted BYTEA NOT NULL,              -- AES-256-GCM encrypted
    enabled BOOLEAN NOT NULL DEFAULT false,
    verified_at TIMESTAMPTZ,
    inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, method)
);

-- Backup codes for account recovery
CREATE TABLE backup_codes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    code_hash VARCHAR(64) NOT NULL,  -- Argon2 hashed
    used_at TIMESTAMPTZ,
    inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_backup_codes_user ON backup_codes(user_id) WHERE used_at IS NULL;
```

### Backend Implementation

```elixir
# lib/secure_sharing/mfa/totp.ex
defmodule SecureSharing.MFA.TOTP do
  @moduledoc """
  TOTP (Time-based One-Time Password) implementation.
  RFC 6238 compliant, compatible with Google Authenticator.
  """

  @issuer "SecureSharing"
  @digits 6
  @period 30

  @doc "Generate a new TOTP secret for user setup"
  def generate_secret do
    NimbleTOTP.secret()
  end

  @doc "Generate QR code URI for authenticator apps"
  def generate_uri(secret, email) do
    NimbleTOTP.otpauth_uri("#{@issuer}:#{email}", secret, issuer: @issuer)
  end

  @doc "Verify a TOTP code"
  def verify(secret, code) do
    NimbleTOTP.valid?(secret, code)
  end
end
```

```elixir
# lib/secure_sharing/mfa/backup_codes.ex
defmodule SecureSharing.MFA.BackupCodes do
  @moduledoc "Generate and verify backup codes for account recovery"

  @code_count 10
  @code_length 8

  def generate do
    for _ <- 1..@code_count do
      :crypto.strong_rand_bytes(4)
      |> Base.encode16(case: :lower)
      |> String.slice(0, @code_length)
    end
  end

  def hash(code) do
    Argon2.hash_pwd_salt(String.downcase(code))
  end

  def verify(code, hash) do
    Argon2.verify_pass(String.downcase(code), hash)
  end
end
```

```elixir
# lib/secure_sharing/mfa/mfa.ex
defmodule SecureSharing.MFA do
  @moduledoc "Main MFA context - coordinates TOTP and backup codes"

  alias SecureSharing.{Repo, MFA}
  alias MFA.{TOTP, BackupCodes, MfaMethod, BackupCode}

  def setup_totp(user) do
    secret = TOTP.generate_secret()
    uri = TOTP.generate_uri(secret, user.email)

    # Store encrypted, not yet enabled
    encrypted = encrypt_secret(secret)

    %MfaMethod{}
    |> MfaMethod.changeset(%{
      user_id: user.id,
      method: "totp",
      secret_encrypted: encrypted,
      enabled: false
    })
    |> Repo.insert(on_conflict: :replace_all, conflict_target: [:user_id, :method])

    {:ok, %{secret: secret, uri: uri}}
  end

  def verify_and_enable_totp(user, code) do
    with {:ok, method} <- get_mfa_method(user.id, "totp"),
         secret <- decrypt_secret(method.secret_encrypted),
         true <- TOTP.verify(secret, code) do

      # Generate backup codes
      codes = BackupCodes.generate()
      store_backup_codes(user.id, codes)

      # Enable MFA
      method
      |> MfaMethod.changeset(%{enabled: true, verified_at: DateTime.utc_now()})
      |> Repo.update()

      {:ok, codes}
    else
      false -> {:error, :invalid_code}
      error -> error
    end
  end

  def verify_totp(user, code) do
    with {:ok, method} <- get_mfa_method(user.id, "totp"),
         true <- method.enabled,
         secret <- decrypt_secret(method.secret_encrypted) do
      TOTP.verify(secret, code)
    else
      _ -> false
    end
  end

  def verify_backup_code(user, code) do
    # Find unused backup code
    query = from bc in BackupCode,
      where: bc.user_id == ^user.id and is_nil(bc.used_at)

    Repo.all(query)
    |> Enum.find(fn bc -> BackupCodes.verify(code, bc.code_hash) end)
    |> case do
      nil -> false
      bc ->
        # Mark as used
        bc |> BackupCode.changeset(%{used_at: DateTime.utc_now()}) |> Repo.update()
        true
    end
  end

  def mfa_enabled?(user_id) do
    case get_mfa_method(user_id, "totp") do
      {:ok, method} -> method.enabled
      _ -> false
    end
  end
end
```

### API Endpoints

```elixir
# POST /api/mfa/totp/setup
# Response: { "secret": "base32...", "uri": "otpauth://...", "qr_code": "base64..." }

# POST /api/mfa/totp/verify
# Body: { "code": "123456" }
# Response: { "enabled": true, "backup_codes": ["abc123", ...] }

# POST /api/auth/login
# Body: { "email": "...", "password": "..." }
# Response (if MFA enabled): { "mfa_required": true, "challenge_token": "..." }
# Response (if MFA disabled): { "access_token": "...", "refresh_token": "..." }

# POST /api/auth/mfa/verify
# Body: { "challenge_token": "...", "code": "123456" }
# Response: { "access_token": "...", "refresh_token": "..." }
```

### Android Implementation

```kotlin
// presentation/settings/mfa/TotpSetupScreen.kt
@Composable
fun TotpSetupScreen(
    onSetupComplete: (List<String>) -> Unit,  // backup codes
    viewModel: TotpSetupViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsState()

    Column {
        // Step 1: Show QR code
        if (uiState.qrCodeBitmap != null) {
            Image(bitmap = uiState.qrCodeBitmap.asImageBitmap())
            Text("Scan with Google Authenticator")
        }

        // Step 2: Verify code
        OutlinedTextField(
            value = uiState.verificationCode,
            onValueChange = { viewModel.updateCode(it) },
            label = { Text("Enter 6-digit code") },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number)
        )

        Button(onClick = { viewModel.verifyAndEnable() }) {
            Text("Verify & Enable")
        }

        // Step 3: Show backup codes
        if (uiState.backupCodes.isNotEmpty()) {
            BackupCodesDisplay(codes = uiState.backupCodes)
        }
    }
}
```

### Phase 1 Deliverables

- [ ] Database migrations for mfa_methods, backup_codes
- [ ] TOTP module with NimbleTOTP
- [ ] Backup codes generation and verification
- [ ] API endpoints for setup/verify
- [ ] Login flow modification (check MFA, require if enabled)
- [ ] Android: TOTP setup screen with QR code
- [ ] Android: MFA verification screen at login
- [ ] Android: Backup codes display and copy

**Estimated effort**: 1-2 weeks

---

## Phase 2: Device Trust & Basic Risk Signals

**Goal**: Remember trusted devices, collect basic signals for future risk scoring.

**When to implement**: After Phase 1 is in production and working.

### What We're Adding

```
┌─────────────────────────────────────────────────────────────┐
│                  SecureSharing Backend                      │
│                                                             │
│  ┌────────────────────┐    ┌────────────────────────────┐  │
│  │   Auth Controller  │───▶│       MFA Module           │  │
│  └────────────────────┘    │  + DeviceTrust             │  │
│            │               │  + SignalCollector         │  │
│            ▼               └────────────────────────────┘  │
│  ┌────────────────────┐                                    │
│  │   Login Attempts   │  ← Store for future analysis       │
│  │   (logging only)   │                                    │
│  └────────────────────┘                                    │
└─────────────────────────────────────────────────────────────┘
```

### Database Additions

```sql
-- Trusted devices (skip MFA for 30 days)
CREATE TABLE trusted_devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_fingerprint VARCHAR(64) NOT NULL,
    device_name VARCHAR(100),
    last_used_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, device_fingerprint)
);

-- Login attempts (for future analysis, logging only)
CREATE TABLE login_attempts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    email VARCHAR(255) NOT NULL,
    success BOOLEAN NOT NULL,
    ip_address INET,
    device_fingerprint VARCHAR(64),
    user_agent TEXT,
    country_code VARCHAR(2),
    inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_login_attempts_user ON login_attempts(user_id, inserted_at DESC);
CREATE INDEX idx_login_attempts_ip ON login_attempts(ip_address, inserted_at DESC);
```

### Device Trust Logic

```elixir
defmodule SecureSharing.MFA.DeviceTrust do
  @trust_duration_days 30

  def trust_device(user_id, device_fingerprint, device_name) do
    %TrustedDevice{}
    |> TrustedDevice.changeset(%{
      user_id: user_id,
      device_fingerprint: device_fingerprint,
      device_name: device_name,
      expires_at: DateTime.add(DateTime.utc_now(), @trust_duration_days, :day)
    })
    |> Repo.insert(on_conflict: :replace_all, conflict_target: [:user_id, :device_fingerprint])
  end

  def device_trusted?(user_id, device_fingerprint) do
    query = from td in TrustedDevice,
      where: td.user_id == ^user_id
        and td.device_fingerprint == ^device_fingerprint
        and td.expires_at > ^DateTime.utc_now()

    Repo.exists?(query)
  end

  def list_trusted_devices(user_id) do
    query = from td in TrustedDevice,
      where: td.user_id == ^user_id and td.expires_at > ^DateTime.utc_now(),
      order_by: [desc: td.last_used_at]

    Repo.all(query)
  end

  def revoke_device(user_id, device_id) do
    Repo.delete_all(from td in TrustedDevice,
      where: td.id == ^device_id and td.user_id == ^user_id)
  end
end
```

### Updated Login Flow

```elixir
def login(email, password, device_info) do
  with {:ok, user} <- verify_credentials(email, password) do
    log_attempt(user.id, email, true, device_info)

    cond do
      not MFA.mfa_enabled?(user.id) ->
        # No MFA, issue tokens directly
        issue_tokens(user)

      DeviceTrust.device_trusted?(user.id, device_info.fingerprint) ->
        # Trusted device, skip MFA
        DeviceTrust.update_last_used(user.id, device_info.fingerprint)
        issue_tokens(user)

      true ->
        # Require MFA
        {:mfa_required, create_challenge(user.id)}
    end
  else
    {:error, :invalid_credentials} ->
      log_attempt(nil, email, false, device_info)
      {:error, :invalid_credentials}
  end
end
```

### Phase 2 Deliverables

- [ ] Trusted devices table and CRUD
- [ ] Login attempts logging
- [ ] "Trust this device" checkbox on MFA screen
- [ ] Android: Device fingerprint collection
- [ ] Android: Manage trusted devices in Settings
- [ ] Skip MFA for trusted devices

**Estimated effort**: 1 week

---

## Phase 3: Risk Scoring (Only If Needed)

**Goal**: Analyze login patterns and challenge suspicious logins.

**When to implement**: When you have enough login data to make it meaningful (1000+ users, months of data).

### Risk Signals to Collect

| Signal | Weight | Detection |
|--------|--------|-----------|
| New device | +20 | Device fingerprint not seen before |
| New country | +25 | GeoIP lookup differs from history |
| Failed attempts (3+) | +15 | Recent failures for this user |
| Unusual time | +10 | Outside user's typical login hours |
| Known VPN/Proxy | +15 | IP in known VPN range |

### Simple Scoring Engine

```elixir
defmodule SecureSharing.Risk.Scorer do
  @moduledoc """
  Simple rule-based risk scoring.
  NOT machine learning - that's overkill for most apps.
  """

  def calculate_score(user_id, signals) do
    base_score = 0

    score = base_score
      |> add_if(signals.new_device, 20)
      |> add_if(signals.new_country, 25)
      |> add_if(signals.recent_failures >= 3, 15)
      |> add_if(signals.unusual_time, 10)
      |> add_if(signals.vpn_detected, 15)
      |> subtract_if(signals.trusted_device, 30)

    min(max(score, 0), 100)
  end

  def decide(score) do
    cond do
      score < 30 -> :allow
      score < 60 -> :challenge  # Require MFA
      true -> :block            # Too risky, deny login
    end
  end
end
```

### Phase 3 Deliverables

- [ ] GeoIP integration (MaxMind GeoLite2 - free)
- [ ] Risk scoring module
- [ ] Unusual time detection (based on user's history)
- [ ] Challenge high-risk logins even for trusted devices
- [ ] Admin dashboard for risk events (optional)

**Estimated effort**: 2-3 weeks

---

## Phase 4: Advanced Features (Future)

Only consider these if you have significant scale or specific requirements:

| Feature | When to Consider |
|---------|------------------|
| Email OTP | Users request alternative to TOTP |
| Push notifications | You have FCM set up already |
| Hardware keys (WebAuthn) | Enterprise customers require it |
| Impossible travel | You have users in multiple countries |
| ML-based scoring | You have millions of login events |
| Distributed service | You're doing 10,000+ auth/sec |

---

## Dependencies

### Phase 1

```elixir
# mix.exs
{:nimble_totp, "~> 1.0"},  # TOTP generation/verification
{:qr_code, "~> 3.0"},       # QR code generation (optional, can use URI)
```

```kotlin
// Android - build.gradle
implementation("com.journeyapps:zxing-android-embedded:4.3.0")  // QR code scanning
```

### Phase 3 (if needed)

```elixir
{:geolix, "~> 2.0"},           # GeoIP lookup
{:geolix_adapter_mmdb2, "~> 0.6"}  # MaxMind database adapter
```

---

## Security Considerations

### Secret Storage

- TOTP secrets encrypted with AES-256-GCM before storage
- Encryption key from environment variable, not in code
- Backup codes hashed with Argon2 (not reversible)

### Rate Limiting

| Endpoint | Limit | Window |
|----------|-------|--------|
| POST /mfa/totp/verify | 5 attempts | 15 minutes |
| POST /auth/mfa/verify | 5 attempts | 15 minutes |
| POST /mfa/totp/setup | 3 attempts | 1 hour |

### Recovery Flow

```
User loses phone
       │
       ▼
┌─────────────────┐
│ Try backup code │
└────────┬────────┘
         │
    ┌────┴────┐
    │         │
 Success    Failed
    │         │
    ▼         ▼
 Login    Contact support
          (manual verification)
```

---

## What This Document Is NOT

- ❌ A distributed systems design
- ❌ Machine learning architecture
- ❌ Enterprise SSO integration
- ❌ Something to build all at once

Build Phase 1. Ship it. Learn from real usage. Then decide if Phase 2 is needed.

---

## Revision History

| Version | Date | Changes |
|---------|------|---------|
| 2.0.0 | 2026-01-18 | Simplified to phased approach, removed distributed architecture |
| 1.0.0 | 2026-01-18 | Initial comprehensive design (over-engineered) |
