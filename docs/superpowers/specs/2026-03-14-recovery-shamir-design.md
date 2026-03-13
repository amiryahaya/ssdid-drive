# Recovery via Shamir's Secret Sharing — Design Spec

## Problem

SSDID Drive encrypts all files and folders with keys derived from a 32-byte master key stored exclusively on the client device. If the device is lost, stolen, or broken, the master key — and all encrypted data — is permanently unrecoverable. No server-side backup exists by design (zero-knowledge architecture). The existing `User.EncryptedMasterKey` column stores the master key encrypted with a device-local key — it is equally unrecoverable without the device.

## Solution

Split the master key into 3 shares using Shamir's Secret Sharing (2-of-3 threshold over GF(256)). The user stores shares in 3 locations:

1. **Self-custody** — downloaded as a `.recovery` file, stored by the user (USB drive, personal cloud, printed)
2. **Trusted person** — downloaded as a `.recovery` file, given to someone the user trusts (out-of-band, outside SSDID Drive)
3. **Server-held** — stored as a base64 string in the SSDID Drive database

Any 2 of the 3 shares reconstruct the master key. A single share reveals zero information about the secret (information-theoretic security).

## Recovery Setup

### Trigger

- After first login, a persistent warning banner appears: **"Your files are at risk. If you lose this device, your encrypted files will be permanently unrecoverable. Set up recovery now."**
- User can dismiss with "Remind me later" — banner reappears every session.
- After 3 dismissals, the banner becomes non-dismissable and blocks file operations until setup is complete.

### Wizard (3 Steps)

**Step 1 — Explanation:**
- Headline: "Protect Your Files Forever"
- Body explains that encryption keys exist only on this device, and loss means permanent data loss. Recovery splits the key into 3 parts; any 2 parts recover access. Takes ~2 minutes.
- Simple diagram showing 3 shares and the 2-of-3 threshold.
- Button: "Begin Setup"

**Step 2 — Generate & Download Shares:**
- App generates 3 Shamir shares client-side using CSPRNG.
- During share generation, the app also computes a `key_proof`: SHA-256 hash of the user's KEM public key (derived from the master key). This proof is uploaded with the server share to enable verification during recovery.
- **Share 1 (Self-custody):** Download button saves `recovery-self.recovery`. Checkbox: "I confirm I've saved this file in a safe location" (required).
- **Share 2 (Trusted person):** Download button saves `recovery-trusted.recovery`. Checkbox: "I confirm I've sent or given this file to someone I trust" (required).
- Warning text: "Do NOT store these files on this device."
- Both checkboxes required to proceed.

**Step 3 — Server Share + Confirmation:**
- Auto-uploads Share 3 + `key_proof` to server via `POST /api/recovery/setup`.
- Success screen: "Recovery is active. You can now recover your files from any new device using any 2 of your 3 recovery shares."
- Summary card showing status of all 3 shares.
- Button: "Done"

### Settings Page

- Recovery section showing: Active / Not configured, last configured date.
- "Regenerate Recovery Shares" button — invalidates old shares, runs wizard again.

## Recovery Flow (Login Page)

### Entry Point

"Recover Account" link on the login page, below normal QR/wallet authentication.

### Identity Proof

The 2-of-3 shares themselves are the identity proof. The client proves successful reconstruction by deriving the KEM public key from the reconstructed master key and submitting its SHA-256 hash (`key_proof`) to the server. The server compares this against the `key_proof` stored during recovery setup. This proves the client possesses the real master key without revealing it.

### Two Recovery Paths

**Path A — "I have 2 recovery files":**
1. Upload first `.recovery` file — app reads `share_index` and `user_did`.
2. Upload second `.recovery` file — app validates different `share_index`, same `user_did`.
3. App reconstructs master key client-side via Lagrange interpolation.
4. App verifies reconstruction by re-deriving KEM public key and comparing hash.
5. Proceed to re-enrollment.

**Path B — "I have 1 recovery file + server share":**
1. Upload `.recovery` file — app reads `user_did`.
2. App calls `GET /api/recovery/share?did={user_did}` — server returns its share.
3. App reconstructs master key client-side from uploaded share + server share.
4. App verifies reconstruction by re-deriving KEM public key and comparing hash.
5. Proceed to re-enrollment.

### Re-Enrollment (Both Paths)

The entire re-enrollment is handled by a single atomic endpoint (`POST /api/recovery/complete`) to prevent race conditions with the old device.

1. Master key reconstructed in memory.
2. App re-derives all private keys from master key (ML-KEM, KAZ-KEM, ML-DSA, KAZ-SIGN keypairs).
3. App generates a new DID for the new device (new wallet identity).
4. App calls `POST /api/recovery/complete` with:
   - `old_did` (from the `.recovery` file's `user_did`)
   - `new_did` (newly generated)
   - `key_proof` (SHA-256 of KEM public key derived from reconstructed master key)
   - `kem_public_key` (new KEM public key, base64)
5. Server atomically (single DB transaction):
   a. Validates `key_proof` matches the stored proof in `RecoverySetup`.
   b. Updates `User.Did` from `old_did` to `new_did`.
   c. Updates `User.KemPublicKey` with the new public key.
   d. Invalidates all old sessions (Redis).
   e. Deletes recovery setup (sets `IsActive = false`, clears `ServerShare`).
   f. Sets `User.HasRecoverySetup = false`.
   g. Creates a new session for the `new_did`, returns a bearer token.
6. App stores master key + private keys in new device's secure storage (keyring/keychain).
7. App re-encapsulates all folder keys with the new KEM keys:
   a. For each folder the user owns, decrypt the folder key using the old KEM keys (derived from master key).
   b. Re-encapsulate with the new KEM public key.
   c. Upload updated `WrappedKek` + `OwnerKemCiphertext` to server via existing folder key update endpoints.
8. Memory is zeroized (old KEM keys no longer needed).
9. App immediately launches recovery setup wizard again (forced, non-dismissable).

**Note:** Step 7 (folder key re-encapsulation) happens after the user regains access. The old KEM private keys are derived from the same master key, so the client can decrypt all existing folder keys and re-encrypt them with freshly generated KEM keypairs. This ensures forward secrecy — even if old KEM keys are later compromised, re-encapsulated folders remain safe.

## `.recovery` File Format

```json
{
  "version": 1,
  "scheme": "shamir-gf256",
  "threshold": 2,
  "share_index": 1,
  "share_data": "<base64-encoded 32 bytes: share values only>",
  "checksum": "<SHA-256 hex of the raw share_data bytes>",
  "user_did": "did:ssdid:abc123",
  "created_at": "2026-03-14T12:00:00Z"
}
```

**Field details:**
- Not encrypted — a single Shamir share is information-theoretically secure.
- `user_did` identifies the account during recovery.
- `share_index` (1, 2, or 3) serves as the GF(256) x-coordinate and prevents uploading the same share twice. The x-coordinate is NOT duplicated inside `share_data`.
- `checksum` — SHA-256 of the raw `share_data` bytes (before base64). Clients validate this on load to detect file corruption before attempting reconstruction. A corrupted file produces a clear "Recovery file is damaged" error rather than a silent wrong-key reconstruction.
- `version` — clients must reject `version > 1` with error: "This recovery file requires a newer version of SSDID Drive."

## Data Model

### New Entity: RecoverySetup

| Column | Type | Notes |
|--------|------|-------|
| Id | Guid | PK |
| UserId | Guid | FK -> User, unique |
| ServerShare | string | Base64-encoded share (plaintext — useless alone) |
| KeyProof | string | SHA-256 hex of user's KEM public key at setup time |
| ShareCreatedAt | DateTimeOffset | When shares were generated |
| IsActive | bool | False after recovery or manual deactivation |

### Existing Entity: User (add column)

| Column | Type | Notes |
|--------|------|-------|
| HasRecoverySetup | bool | Default false. True when setup complete. |

## API Endpoints

All under `/api/recovery`, mapped via `RecoveryFeature.cs`.

### `POST /api/recovery/setup` (requires auth)

- Body: `{ "server_share": "<base64>", "key_proof": "<sha256-hex>" }`
- Creates/updates `RecoverySetup` for the authenticated user.
- Stores `ServerShare` and `KeyProof`.
- Sets `User.HasRecoverySetup = true`.
- Returns 201.

### `GET /api/recovery/status` (requires auth)

- Returns `{ "is_active": true, "created_at": "..." }` or `{ "is_active": false }`.
- Used by clients to show/hide the setup banner.

### `GET /api/recovery/share?did={did}` (no auth, rate-limited)

- Returns `{ "server_share": "<base64>", "share_index": 3 }` if active setup exists for that DID.
- Returns 404 if no setup, inactive, or unknown DID.
- No auth required — the share is useless alone, and the user has no credentials at recovery time.
- **Constant-time response:** All requests (hit or miss) are padded to a minimum 200ms response time using `Task.Delay` to prevent timing-based DID enumeration.
- **Rate limiting:** 5 requests per DID per hour, 20 requests per IP per hour. Redis sliding window counter keyed by `recovery:did:{did}` and `recovery:ip:{ip}`, TTL 1 hour. **Fallback when Redis is unavailable:** in-memory `ConcurrentDictionary` with periodic cleanup (same limits, best-effort — acceptable because the share is useless alone).

### `POST /api/recovery/complete` (no auth, rate-limited)

- Body: `{ "old_did": "did:ssdid:old", "new_did": "did:ssdid:new", "key_proof": "<sha256-hex>", "kem_public_key": "<base64>" }`
- **No auth required** — the `key_proof` serves as cryptographic proof of master key possession. This avoids the chicken-and-egg problem where the user cannot authenticate (no wallet/device) but needs to complete recovery.
- Validates `key_proof` matches `RecoverySetup.KeyProof` for the user identified by `old_did`.
- Executes atomically in a single DB transaction:
  - Updates `User.Did` to `new_did`.
  - Updates `User.KemPublicKey`.
  - Invalidates all old sessions.
  - Sets `RecoverySetup.IsActive = false`, clears `ServerShare`.
  - Sets `User.HasRecoverySetup = false`.
  - Creates a new session, returns bearer token.
- **Rate limiting:** 3 requests per `old_did` per hour, 10 requests per IP per hour.
- Returns 200 with `{ "token": "<bearer>", "user_id": "<guid>" }`.

### `DELETE /api/recovery/setup` (requires auth)

- Deactivates recovery, clears server share and key proof.
- Sets `User.HasRecoverySetup = false`.
- Returns 204.

## Shamir's Secret Sharing Implementation

### Algorithm

Shamir's Secret Sharing over GF(256), per-byte splitting.

- Each of the 32 bytes of the master key is an independent secret in GF(256).
- For each byte, generate a random polynomial of degree 1 (threshold - 1): `f(x) = secret + a1*x` over GF(256).
- Evaluate at x=1, x=2, x=3 to produce 3 shares.
- Each share: 32 bytes (share values). The x-coordinate is stored in the `.recovery` file's `share_index` field.
- GF(256) uses irreducible polynomial `x^8 + x^4 + x^3 + x + 1` (0x11B, same as AES).
- Random coefficient `a1` from CSPRNG per byte (`OsRng` in Rust, `SecureRandom` in Kotlin, `SecRandomCopyBytes` in Swift).

### Reconstruction

- Given 2 shares (two points on each polynomial), Lagrange interpolation over GF(256) recovers each byte.
- Verify result: re-derive KEM public keys from reconstructed master key and compare SHA-256 hash against the `key_proof` stored on server (or locally if Path A).

### Platform Implementations

- **Desktop (Rust):** `sharks` crate (audited SSS over GF(256)). Must verify it uses the same irreducible polynomial (0x11B). If it does not, implement custom GF(256) (~100 lines) instead. Compatibility is validated by cross-platform test vectors.
- **Android (Kotlin):** ~100 lines of GF(256) arithmetic + Lagrange interpolation in `domain/crypto/ShamirSecretSharing.kt`. No suitable audited Kotlin library; math is straightforward and testable.
- **iOS (Swift):** ~100 lines of GF(256) + Lagrange in `Domain/Crypto/ShamirSecretSharing.swift`. Same approach as Android.

### Cross-Platform Test Vectors

- File: `tests/fixtures/shamir-test-vectors.json`
- 3-5 known master keys with their expected shares at x=1,2,3 using fixed random coefficients.
- All platforms must produce identical shares and reconstruct identically.
- Tested in CI for each platform.
- Test vectors also verify reconstruction from every possible 2-of-3 combination: (1,2), (1,3), (2,3).

## Client Platform Changes

### Desktop (Tauri/Rust)

- Add `sharks` crate dependency (or custom GF(256) if polynomial mismatch).
- New `RecoveryService`: `split_master_key()` -> 3 shares, `reconstruct_master_key(share1, share2)` -> master key.
- New Tauri commands: `setup_recovery`, `get_recovery_status`, `download_recovery_share`, `recover_with_files`, `recover_with_file_and_server`.
- File save/open via Tauri's `dialog::save_file` / `dialog::open_file`.
- New routes: `/recover` (login page recovery flow), recovery wizard component (setup flow).
- Persistent banner in main layout.

### Android (Kotlin)

- New `ShamirSecretSharing` in `domain/crypto/`.
- New `RecoveryRepository` interface + `RecoveryRepositoryImpl`.
- New `RecoverySetupViewModel` + `RecoverySetupScreen` (wizard).
- New `RecoveryViewModel` + `RecoveryScreen` (login flow).
- Recovery banner composable in main scaffold.
- File save/open via SAF (`Intent.ACTION_CREATE_DOCUMENT` / `Intent.ACTION_OPEN_DOCUMENT`).
- "Recover Account" button on login screen.

### iOS (Swift)

- New `ShamirSecretSharing` in `Domain/Crypto/`.
- New `RecoveryRepository` protocol + `RecoveryRepositoryImpl`.
- New `RecoverySetupViewModel` + `RecoverySetupViewController` (wizard).
- New `RecoveryViewModel` + `RecoveryViewController` (login flow).
- Recovery banner `UIView` in main tab controller.
- File save/open via `UIDocumentPickerViewController`.
- "Recover Account" button on login screen.
- New `RecoveryCoordinator`.

## Security Considerations

| Threat | Mitigation |
|--------|-----------|
| Server compromise (DB breach) | Server holds 1 share — useless alone (information-theoretic) |
| Attacker gets self-custody file | 1 share — useless alone |
| Attacker gets 2 shares (stolen device + file on device) | Force regeneration after recovery invalidates old shares |
| Enumeration via unauthenticated endpoint | Rate limiting + constant-time 200ms response floor. 404 for unknown DIDs |
| Replay of old shares after regeneration | Server deletes share on completion. Old shares reconstruct old master key, but folder keys are re-encapsulated with new KEM keys during DID migration |
| MITM during server share retrieval | TLS. Share is useless alone |
| User stores both files on the lost device | UX warning: "Do NOT store these files on this device" |
| Attacker knows DID + bypasses rate limit | Still needs 2 shares. Server share alone is useless. `key_proof` prevents unauthorized DID migration |
| Corrupted `.recovery` file | SHA-256 checksum in file catches corruption before reconstruction attempt |
| Race condition during DID migration | `POST /api/recovery/complete` is a single atomic DB transaction |
| Redis unavailable for rate limiting | Fallback to in-memory rate limiting (best-effort, acceptable because share is useless alone) |

### Not Protected Against

- User loses 2+ shares simultaneously — by design (2-of-3 threshold).
- User never sets up recovery — escalating banner mitigates but cannot prevent.

### Master Key Memory Safety

- Memory zeroized after storage: Rust `zeroize` crate, Kotlin `Arrays.fill(0)`, Swift `memset_s`.
- Master key exists in memory only during reconstruction, then immediately stored in secure storage.

## Audit Logging

All recovery operations emit activity log events via `FileActivityService`:

| Event | Logged When |
|-------|-------------|
| `recovery.setup` | User completes recovery setup wizard |
| `recovery.share_retrieved` | Server share requested (log DID + IP, even on 404) |
| `recovery.completed` | Successful DID migration via recovery |
| `recovery.deactivated` | User or system deactivates recovery |
| `recovery.regenerated` | User regenerates recovery shares |

These events are visible in the admin activity feed for security monitoring.
