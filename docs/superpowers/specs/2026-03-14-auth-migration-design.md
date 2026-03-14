# Auth Migration: Email+TOTP, OIDC, Account Linking, Extension Services

## Overview

Replace SSDID Wallet DID-based authentication with standard auth methods across the entire stack: backend API (.NET 10), desktop client (Tauri), Android client (Kotlin), iOS client (Swift), and admin portal. Introduce account linking (multiple login methods per account) and extension service platform (3rd party services via HMAC authentication).

**Target users:** Enterprise/business — not consumer/commercial.

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| OIDC approach | Hybrid (native SDKs on clients, server-side fallback for admin portal + extension services) | Best native UX + admin portal needs server-side anyway |
| Identity anchor | Account entity (UUID PK), independent of Login | SsdidDrive only sees Account, never Login |
| Password | Passwordless — email as identifier, TOTP as proof | No passwords to leak, phishing-resistant |
| TOTP implementation | 3rd party authenticator apps (Google Authenticator, Microsoft Authenticator, etc.) via RFC 6238 | No custom authenticator, standard TOTP |
| TOTP verification window | +/- 1 time step (30 seconds) per RFC 6238 recommendation | Balance between usability and security |
| OIDC providers | Google, Microsoft only | Enterprise-focused — Facebook dropped |
| Account linking | Manual via Settings ("Link Logins"), bidirectional | User controls when and what to link |
| Registration | Invitation-only + "Request Organization" with admin approval. No self-registration. | Enterprise access control |
| Admin auth | Same providers + mandatory TOTP for Owner/Admin roles | Higher security for privileged accounts |
| Extension services | HMAC signed requests (secret never on wire) | Best security for PII-sensitive data |
| Master key | Stays device-bound. Cross-device = future scope (device linking) | Zero-knowledge encryption model preserved |
| Email OTP storage | Redis with TTL (or in-memory SessionStore fallback) | Same infrastructure as existing challenge storage |
| Libraries | OtpNet (TOTP), Microsoft.AspNetCore.Authentication.* (OIDC), QRCoder (QR), built-in HMACSHA256, Resend (email) | Battle-tested .NET libraries, no hand-rolling |

## Data Model

### Account Entity (renamed from User)

The existing `User` entity is renamed to `Account`. All existing columns are preserved as-is with their current names and types.

**New columns added:**

```
TotpSecret        string, encrypted at rest, nullable (set during TOTP setup)
TotpEnabled       bool, default false
BackupCodes       string, encrypted JSON array, nullable (10 one-time codes)
EmailVerified     bool, default false
```

**Existing columns preserved (no changes):**

```
Id                  Guid, PK (already UUID — becomes the identity anchor)
Did                 string (nullable during migration, dropped in final phase)
DisplayName         string?
Email               string? -> changed to required, unique
Status              UserStatus (Active, Suspended)
SystemRole          SystemRole? (SuperAdmin maps to platform super-admin)
PublicKeys          string? (JSON)
EncryptedPrivateKeys  byte[]?
EncryptedMasterKey    byte[]?
KeyDerivationSalt     byte[]?
KemPublicKey          byte[]?
KemAlgorithm          string?
LastLoginAt           DateTimeOffset?
CreatedAt             DateTimeOffset
UpdatedAt             DateTimeOffset
HasRecoverySetup      bool
TenantId              Guid? (primary tenant)
```

**Columns dropped (final migration phase):**

```
Did                 string (after all clients ship new auth)
```

All existing relationships (files, folders, shares, tenants, devices) continue to reference `Account.Id` (same UUID as previous `User.Id`). The rename is cosmetic at the EF Core level — the database table can be renamed via migration or aliased.

### Login Entity (new)

```
Login
  Id                UUID, PK
  AccountId         UUID, FK -> Account, not null
  Provider          enum (Email, Google, Microsoft)
  ProviderSubject   string, not null (email for Email, sub claim for OIDC)
  CreatedAt         DateTimeOffset
  LinkedAt          DateTimeOffset
```

**Unique constraint:** `(Provider, ProviderSubject)` — one provider identity maps to exactly one Account.

**Conflict rule:** If a user tries to link a provider identity already linked to another Account, reject with error. No account merging.

**Deletion:** Hard delete when unlinking (no soft-delete needed — no audit requirement for removed login methods beyond the existing audit log).

### PendingOtp (Redis/SessionStore — not a DB entity)

```
Key:     "ssdid:otp:{email}:{purpose}"    (purpose = "register" | "recovery" | "link")
Value:   JSON { Code: string, ExpiresAt: DateTimeOffset, Attempts: int }
TTL:     10 minutes
```

Stored in Redis (or in-memory SessionStore fallback) — same infrastructure as existing challenge storage. Maximum 5 verification attempts per OTP before invalidation.

### ExtensionService Entity (new)

```
ExtensionService
  Id            UUID, PK
  TenantId      UUID, FK -> Tenant, not null
  Name          string, not null
  ServiceKey    string, encrypted at rest (HMAC secret, 256-bit)
  Permissions   string, JSON
  Enabled       bool, default true
  CreatedAt     DateTimeOffset
  LastUsedAt    DateTimeOffset, nullable
```

**Permissions vocabulary:**

```json
{
  "files.read": false,
  "files.write": false,
  "files.delete": false,
  "folders.read": false,
  "folders.write": false,
  "shares.read": false,
  "shares.write": false,
  "activity.read": false,
  "pii.extract": false
}
```

All permissions default to `false`. Tenant admin explicitly enables each permission per service.

### TenantRequest Entity (new)

```
TenantRequest
  Id                  UUID, PK
  OrganizationName    string, not null
  RequesterEmail      string, not null
  RequesterAccountId  UUID, FK -> Account, nullable (if already registered)
  Reason              string, nullable
  Status              enum (Pending, Approved, Rejected)
  ReviewedBy          UUID, FK -> Account, nullable
  ReviewedAt          DateTimeOffset, nullable
  RejectionReason     string, nullable
  CreatedAt           DateTimeOffset
```

### Existing Entities — Migration Notes

**Invitation:**
- `AcceptedByDid` (string?) — rename to `AcceptedByAccountId` (Guid?, FK -> Account). The `InvitedUserId` field already tracks the target user; `AcceptedByAccountId` records who actually accepted (may differ if invitation was forwarded).
- All other Invitation fields unchanged.

**WebAuthnCredential:**
- **Deprecated and removed.** WebAuthn was part of the DID-based auth flow. TOTP replaces it as the authentication factor. Drop the table in the final migration phase alongside DID columns.

**RecoverySetup:**
- **Kept as-is.** RecoverySetup stores Shamir secret shares for master key recovery — this is about file access recovery, not login recovery. Completely independent of the auth method change.

**Device:**
- `KeyAlgorithm` and `PublicKey` — **kept for future device linking.** Device signing keys will be used when cross-device file access is implemented. Not affected by auth changes.
- `UserId` FK renamed to `AccountId` (same UUID, just follows the rename).

## Authentication Flows

### Registration — Invitation-Gated, Two Independent Paths

**All registration requires a valid invitation.** Both paths accept an `invitation_token` parameter that the backend validates before creating the Account.

**Path A: Email + TOTP**

```
1. User opens invitation link (or enters short code)
2. Client resolves invitation -> shows tenant name, role
3. User selects "Register with Email"
4. User enters email
5. Backend validates invitation_token + sends 6-digit OTP to email, stored in Redis with 10-min TTL
6. User enters OTP -> backend verifies (max 5 attempts)
7. Backend creates Account (EmailVerified=true) + Login(Provider=Email) + accepts invitation (joins tenant)
8. Backend generates TOTP secret, returns otpauth:// URI
9. Client displays QR code -> user scans with authenticator app
10. User enters TOTP code to confirm -> backend verifies, sets TotpEnabled=true
11. Backend generates 10 backup codes -> returns to client (shown once, user saves)
12. Backend creates session -> returns bearer token
```

**Path B: OIDC (Google / Microsoft)**

```
1. User opens invitation link (or enters short code)
2. Client resolves invitation -> shows tenant name, role
3. User taps "Sign in with Google" (or Microsoft)
4. Native SDK handles OAuth flow -> returns ID token
5. Client sends ID token + invitation_token to POST /api/auth/oidc/verify
6. Backend validates invitation_token + verifies ID token (signature, issuer, audience, expiry)
7. Backend extracts email + sub claim
8. If Login(Provider=Google, ProviderSubject=sub) already exists -> existing Account accepts invitation -> create session -> return bearer token
9. If no Login exists -> create Account + Login(Provider=Google) + accept invitation -> create session -> return bearer token
```

Both paths produce a fully functional account with immediate app access.

### Login Flow (Returning Users)

**Email + TOTP:**

```
1. User enters email
2. Backend looks up Account by email -> if not found, error "No account with this email"
3. Backend checks Account has TotpEnabled=true -> prompts for TOTP
4. User enters 6-digit code from authenticator app (or backup code)
5. Backend verifies TOTP (OtpNet, +/- 1 time step) or backup code (one-time use, consumed on verification)
6. Creates session -> returns bearer token
```

**OIDC:**

```
1. User taps "Sign in with Google/Microsoft"
2. Native SDK -> ID token -> POST /api/auth/oidc/verify (no invitation_token for login)
3. Backend verifies + looks up Login(Provider, ProviderSubject)
4. If found -> create session -> return bearer token
5. If not found -> error "No account linked to this Google/Microsoft account"
```

### Admin Portal Login (Server-Side OIDC)

```
1. Admin clicks "Sign in with Google/Microsoft"
2. Redirect to GET /api/auth/oidc/{provider}/authorize
3. Backend redirects to provider OAuth endpoint
4. Provider redirects back to GET /api/auth/oidc/{provider}/callback
5. Backend exchanges auth code for ID token, verifies
6. If account has Owner/Admin role -> creates pending-mfa session (limited: can only call TOTP verify)
7. Admin enters TOTP code -> session upgraded to full access
```

Email+TOTP login on admin portal: same as client flow — TOTP is already part of the login, no extra step needed.

**Session metadata for pending-mfa:** Session store gains an optional `MfaPending` boolean. Middleware checks: if `MfaPending=true`, only allow `POST /api/auth/totp/verify`. All other endpoints return 403 with `"mfa_required"` error.

### TOTP Recovery (Lost Authenticator)

```
1. User clicks "Lost authenticator?" on login page
2. Enter email -> backend sends OTP to email (Redis, 10-min TTL, max 5 attempts)
3. Verify email OTP -> backend disables old TOTP, invalidates old backup codes
4. New TOTP setup (QR + confirm code)
5. New backup codes generated -> shown to user
6. Session created
7. All other active sessions for this Account are revoked (security: in case device was stolen)
```

**Accepted risk:** Email compromise allows TOTP reset. This is the standard trade-off used by Google, GitHub, and most enterprise services. Mitigated by: session revocation on reset, audit log entry, and the fact that login access alone does not grant file access (master key is device-bound).

This recovers **login access only**. File access remains device-bound (master key on device). Cross-device file access requires device linking (future scope).

### Link Logins (Settings)

**Link OIDC to existing account:**

```
1. User (logged in) -> Settings -> Link Logins -> "Google" / "Microsoft"
2. Native OAuth flow -> ID token
3. POST /api/account/logins/oidc with ID token
4. Backend verifies -> checks ProviderSubject not already linked to another Account
5. If available -> creates Login(Provider=Google, AccountId=current) -> success
6. If already linked -> error "This Google account is already linked to another account"
```

**Link Email+TOTP to existing account (e.g., OIDC-first user):**

```
1. Settings -> Link Logins -> "Email + TOTP"
2. Enter email -> OTP verify -> TOTP setup -> backup codes
3. Login(Provider=Email) added to current Account
4. Account.Email updated, EmailVerified=true, TotpEnabled=true
```

**Unlink a login:**

```
1. Settings -> Link Logins -> select login -> "Remove"
2. Backend checks: must keep at least one login method
3. If last login -> error "Cannot remove your only login method"
4. Otherwise -> hard delete Login row, audit log entry
```

## Extension Service Authentication (HMAC)

### Registration (Admin Portal)

```
1. Tenant admin -> "Add Extension Service" -> enters name, selects permissions
2. Backend generates ServiceId (UUID) + HMAC secret (256-bit random)
3. Credentials shown once to admin (like API key reveal)
4. Admin provides credentials to 3rd party developer
```

### Per-Request Signing (3rd Party Side)

```
Timestamp format: ISO 8601 UTC with second precision (yyyy-MM-ddTHH:mm:ssZ)
Body hash: lowercase hex SHA-256 of request body (empty string hash for no body)

StringToSign = "{timestamp}\n{HTTP_METHOD}\n{path}\n{body_hash}"
Signature = HMAC-SHA256(secret, UTF8(StringToSign))

Headers:
  X-Service-Id: {service_id}
  X-Timestamp: {timestamp}
  X-Signature: {base64(signature)}
```

### Verification (Backend Middleware)

```
1. Look up ExtensionService by X-Service-Id -> get secret, tenant, permissions, enabled
2. If not found or disabled -> 401
3. Parse X-Timestamp -> if > 5 min old or in the future -> 401 (replay protection)
4. Recompute HMAC with stored secret -> CryptographicOperations.FixedTimeEquals with decoded X-Signature
5. If mismatch -> 401
6. Set request context: TenantId, ServiceId, Permissions
7. Check permissions against endpoint being called -> 403 if not allowed
8. Update LastUsedAt
```

### Secret Rotation

```
POST /api/tenant/services/{id}/rotate
-> Generates new secret, returns it once
-> Old secret invalidated immediately
-> Audit log entry
```

## Admin Portal Changes

### Auth

- Same login options (Email+TOTP, Google, Microsoft) via server-side OIDC
- Mandatory TOTP for Owner/Admin roles (OIDC login creates pending-mfa session until TOTP verified)
- Super-admin: maps to existing `SystemRole.SuperAdmin` on the Account entity. Manages tenants platform-wide.

### New Admin Pages

**Tenant Management:**
- List all tenants (paginated)
- Create tenant + invite Owner
- Review/approve/reject tenant requests (with reason for rejection)
- Disable/enable tenants

**Extension Services (per tenant):**
- List registered services with status, last used
- Add service (name, permissions) -> credential reveal
- Edit permissions
- Rotate HMAC secret
- Revoke/disable service

**User Management:**
- List all accounts across tenants (paginated, searchable)
- View linked logins per account
- Force TOTP reset (triggers email recovery flow)
- Disable/enable accounts

## Client-Side Changes

### All Clients (Desktop, Android, iOS)

**Remove:**
- All SSDID Wallet / DID auth code (challenge-response, VC verification, DID registry calls)
- QR code scanning for wallet auth
- Deep link handling for wallet auth
- WebAuthn credential management

**Add:**
- Login screen: "Email + TOTP" option, "Sign in with Microsoft" option, "Sign in with Google" option
- Invitation acceptance flow: resolve invitation -> choose registration method -> register
- Email input + OTP verification screens
- TOTP code input screen (6-digit)
- TOTP setup flow: QR display + confirm code + backup codes display (save warning)
- Settings -> "Link Logins" page: list current logins, add/remove login methods
- TOTP recovery flow: "Lost authenticator?" -> email verify -> re-setup TOTP
- Backup codes display during TOTP setup (shown once, user must save)

**Unchanged:**
- Master key generation, storage, device-bound encryption
- File upload/download/sharing
- Session token format (bearer token) and handling
- All existing features (files, folders, shares, activity, notifications)
- Device enrollment (kept for future device linking)

### Desktop (Tauri)

- OIDC: open system browser, capture redirect via deep link `ssdid-drive://auth/callback`
- QR code for TOTP setup: JS QR library (e.g., `qrcode.react`)
- OTP/TOTP input: form screens in React

### Android (Kotlin)

- Google Sign-In: Credential Manager API
- Microsoft Sign-In: MSAL Android SDK
- OTP/TOTP input: Compose screens

### iOS (Swift)

- Google Sign-In: Google Sign-In SDK
- Microsoft Sign-In: MSAL iOS SDK
- OTP/TOTP input: UIKit screens
- Sign in with Apple: not in scope, but Login entity supports adding it later

## API Endpoints

### Remove

```
POST   /api/auth/ssdid/register              (DID registration)
POST   /api/auth/ssdid/register/verify        (DID challenge verification)
POST   /api/auth/ssdid/authenticate           (VC authentication)
GET    /api/auth/ssdid/server-info            (server DID info)
POST   /api/auth/ssdid/login/initiate         (QR login initiation)
GET    /api/auth/ssdid/events/{challengeId}   (SSE for login completion)
```

### New — Email + TOTP Auth

```
POST   /api/auth/email/register
  Body: { email, invitation_token }
  Action: Validate invitation, send OTP to email
  Public: yes (no auth required)
  Rate limit: 5 per email per hour

POST   /api/auth/email/register/verify
  Body: { email, code, invitation_token }
  Action: Verify OTP, create Account + Login, accept invitation
  Public: yes
  Rate limit: 5 attempts per OTP

POST   /api/auth/email/login
  Body: { email }
  Action: Verify account exists, return { requires_totp: true }
  Public: yes
  Rate limit: 10 per email per hour

POST   /api/auth/totp/setup
  Action: Generate TOTP secret + otpauth:// URI (for new accounts during registration or linking)
  Auth: required (temporary registration session or full session)

POST   /api/auth/totp/setup/confirm
  Body: { code }
  Action: Verify first TOTP code, enable TOTP, return 10 backup codes
  Auth: required

POST   /api/auth/totp/verify
  Body: { email, code }
  Action: Verify TOTP code or backup code, create session
  Public: yes
  Rate limit: 5 per email per 15 minutes (lockout after 5 failures)

POST   /api/auth/totp/recovery
  Body: { email }
  Action: Send email OTP to reset TOTP
  Public: yes
  Rate limit: 3 per email per hour

POST   /api/auth/totp/recovery/verify
  Body: { email, code }
  Action: Verify email OTP, disable old TOTP, revoke all sessions, start re-setup
  Public: yes
  Rate limit: 5 attempts per OTP
```

### New — OIDC

```
POST   /api/auth/oidc/verify
  Body: { provider, id_token, invitation_token? }
  Action: Verify ID token. If invitation_token present: register + accept invitation. Otherwise: login.
  Public: yes
  Rate limit: 20 per IP per hour

GET    /api/auth/oidc/{provider}/authorize
  Action: Server-side OIDC redirect (admin portal). Sets state cookie.
  Public: yes

GET    /api/auth/oidc/{provider}/callback
  Query: code, state
  Action: Exchange code for ID token, verify, create session. Admin roles get pending-mfa session.
  Public: yes
```

### New — Link Logins

```
GET    /api/account/logins
  Action: List linked logins for current account (provider, subject, linked_at)
  Auth: required

POST   /api/account/logins/email
  Body: { email }
  Action: Send OTP to link email login
  Auth: required

POST   /api/account/logins/email/verify
  Body: { email, code }
  Action: Verify OTP, proceed to TOTP setup for email login
  Auth: required

POST   /api/account/logins/oidc
  Body: { provider, id_token }
  Action: Verify ID token, link OIDC login to current account
  Auth: required

DELETE /api/account/logins/{id}
  Action: Unlink a login (must keep >= 1)
  Auth: required
```

### New — Extension Services

```
POST   /api/tenant/services                 Register extension service (Owner/Admin)
GET    /api/tenant/services                  List extension services (Owner/Admin)
GET    /api/tenant/services/{id}             Get service details (Owner/Admin)
PUT    /api/tenant/services/{id}             Update permissions (Owner/Admin)
DELETE /api/tenant/services/{id}             Revoke/disable service (Owner/Admin)
POST   /api/tenant/services/{id}/rotate      Rotate HMAC secret (Owner/Admin)
```

### New — Tenant Requests

```
POST   /api/tenant-requests                  Submit create organization request (authenticated)
GET    /api/admin/tenant-requests             List pending requests (SuperAdmin)
POST   /api/admin/tenant-requests/{id}/approve   Approve request, create tenant + invite requester as Owner (SuperAdmin)
POST   /api/admin/tenant-requests/{id}/reject    Reject request with reason, send notification email (SuperAdmin)
```

### Unchanged

```
POST   /api/auth/logout
GET    /api/me
PUT    /api/me
```

All file, folder, share, tenant, device, activity, notification, recovery, invitation endpoints remain unchanged — they reference Account.Id (same UUID as previous User.Id).

## Audit Logging

New auth events logged to existing `AuditLogEntry`:

| Event | Logged When |
|-------|-------------|
| `auth.register.email` | Account created via email+TOTP |
| `auth.register.oidc` | Account created via OIDC |
| `auth.login.email` | Successful email+TOTP login |
| `auth.login.oidc` | Successful OIDC login |
| `auth.login.failed` | Failed login attempt (TOTP wrong, account not found) |
| `auth.totp.setup` | TOTP enabled on account |
| `auth.totp.reset` | TOTP reset via recovery flow |
| `auth.login.linked` | Login method linked to account |
| `auth.login.unlinked` | Login method removed from account |
| `auth.sessions.revoked` | All sessions revoked (TOTP recovery) |
| `service.registered` | Extension service created |
| `service.secret.rotated` | Extension service HMAC secret rotated |
| `service.revoked` | Extension service disabled/deleted |
| `tenant.requested` | Tenant creation requested |
| `tenant.request.approved` | Tenant request approved |
| `tenant.request.rejected` | Tenant request rejected |

## Migration Strategy

### Database Migration

```
Phase 1: Add new tables (Login, ExtensionService, TenantRequest)
Phase 2: Add new columns to User (TotpSecret, TotpEnabled, BackupCodes, EmailVerified)
Phase 3: Make User.Email required + unique (populate from existing data where possible)
Phase 4: Make User.Did nullable
Phase 5: Add Invitation.AcceptedByAccountId (Guid?, FK -> User) alongside AcceptedByDid
Phase 6: Rename User -> Account at EF Core level (table rename via migration)
Phase 7: Rename Device.UserId -> Device.AccountId (FK rename)
Phase 8: After all clients ship new auth:
         - Drop User/Account.Did column
         - Drop Invitation.AcceptedByDid column
         - Drop WebAuthnCredential table
         - Drop WebAuthnChallengeStore service
```

### Code Migration Order

```
Phase 1:  Backend — Email+TOTP auth endpoints + OTP storage in Redis/SessionStore
Phase 2:  Backend — OIDC verification endpoint (ID token validation)
Phase 3:  Backend — Account/Login linking endpoints
Phase 4:  Backend — Extension service + HMAC middleware + tenant request endpoints
Phase 5:  Backend — Session metadata (MfaPending for admin TOTP gate)
Phase 6:  Admin portal — server-side OIDC auth + new admin pages
Phase 7:  Desktop client — auth screens + native OIDC
Phase 8:  Android client — auth screens + native OIDC
Phase 9:  iOS client — auth screens + native OIDC
Phase 10: Remove all SSDID/DID code across entire stack
Phase 11: Drop DID columns + WebAuthnCredential table from database
```

**Key principle:** Phase 10 is last. Old SSDID auth stays functional until all clients ship with new auth. No big-bang cutover. Each phase is independently deployable and testable. Client phases (7-9) can run in parallel after backend phases (1-5) are complete.

**Session migration:** When Phase 10 deploys, all existing SSDID sessions are invalidated (the verification code is removed). Users must re-login with new auth. This is expected and communicated as part of the release.

## Out of Scope

- Device linking / cross-device file access (future feature)
- Sign in with Apple (future, Login entity supports it)
- Custom OIDC providers per tenant (e.g., Okta, OneLogin — future enhancement)
- Password-based authentication (design decision: passwordless only)
- Facebook OIDC (dropped — enterprise focus)
- Self-registration without invitation (enterprise: invitation-only + request flow)
