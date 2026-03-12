# Invitation Acceptance Protocol Design

> **Goal:** Define how SSDID Drive invitations are accepted via SSDID Wallet, with double email verification (wallet-side and backend-side) and automatic user registration.

**Status:** Approved
**Date:** 2026-03-13

---

## 1. Overview

When an admin or user invites someone to a tenant by email, the invitee receives an email with an "Accept Invitation" link. Clicking the link opens SSDID Drive, which delegates to SSDID Wallet for email verification and authentication. The wallet verifies the invitation email matches the user's profile email, then authenticates with the Drive backend. The backend independently re-verifies the email match before creating the user account and granting tenant access.

This protocol applies to invitations from the admin portal and from all Drive clients (Android, iOS, Desktop).

## 2. Protocol Flow

```
Invitor (Admin/User)
  │
  ├─ 1. Create invitation: POST /api/invitations { email, role, tenant_id }
  │     Backend stores invitation with token, sends email
  │
Invitee receives email
  │
  ├─ 2. Clicks "Accept Invitation" link: https://drive.ssdid.my/invite/{token}
  │     Opens SSDID Drive (universal/app link)
  │
SSDID Drive Client
  │
  ├─ 3. Extracts token, builds wallet deep link:
  │     ssdid://invite?server_url={api_base}&token={token}&callback_url=ssdiddrive://invite/callback
  │     Launches SSDID Wallet
  │     Shows "Waiting for SSDID Wallet..." with Cancel button
  │
SSDID Wallet
  │
  ├─ 4. Receives ssdid://invite deep link
  ├─ 5. Fetches invitation details: GET {server_url}/api/invitations/token/{token}
  │     Response: { email, tenant_name, inviter_name, role, status }
  ├─ 6. Compares invitation email against wallet profile email (case-insensitive)
  │     If mismatch → show error, stop
  ├─ 7. Shows confirmation screen:
  │     "You've been invited to {tenant_name} by {inviter_name} as {role}"
  │     [Accept Invitation] button
  ├─ 8. User taps Accept → wallet calls:
  │     POST {server_url}/api/invitations/token/{token}/accept-with-wallet
  │     Body: { credential: {...}, email: "user@example.com" }
  ├─ 9. Backend verifies credential, re-verifies email match, creates user if needed,
  │     links user to tenant with role, marks invitation as accepted
  │     Response: { session_token, did, user, tenant }
  ├─ 10. Wallet calls back to Drive:
  │      ssdiddrive://invite/callback?session_token={token}&status=success
  │
SSDID Drive Client
  │
  └─ 11. Saves session token, navigates to main screen
```

## 3. API Endpoint

### `POST /api/invitations/token/{token}/accept-with-wallet`

**Purpose:** Atomic endpoint that verifies the credential, checks email match, creates the user if needed, links to tenant, and returns a session token.

**Authentication:** Public (no Bearer token required — the credential IS the authentication).

**Request:**
```json
{
  "credential": { ... },
  "email": "user@example.com"
}
```

- `credential`: Verifiable Credential (same format as `/api/authenticate`)
- `email`: User's email from wallet profile (backend re-verifies against invitation)

**Backend logic:**
1. Look up invitation by token — fail if expired, already accepted, or not found
2. Verify the credential (same as `SsdidAuthService.VerifyCredential`) → extract DID
3. Compare `request.email` against `invitation.email` (case-insensitive) — fail if mismatch
4. Find or create User by DID (if new user, set display name from credential if available)
5. Create UserTenant link with the invitation's role
6. Mark invitation as accepted (`status = Accepted`, `accepted_at = now`, `accepted_by_did = did`)
7. Create authenticated session (same as `SsdidAuthService.CreateAuthenticatedSession`)
8. Return session token + user + tenant info

**Response (success):**
```json
{
  "session_token": "...",
  "did": "did:ssdid:...",
  "server_did": "did:ssdid:...",
  "server_key_id": "...",
  "server_signature": "...",
  "user": { "id": "...", "did": "...", "display_name": "...", "status": "active" },
  "tenant": { "id": "...", "name": "...", "slug": "...", "role": "member" }
}
```

- `server_did`, `server_key_id`, `server_signature`: For mutual authentication — the wallet verifies the server's signature using the server's DID document from the SSDID Registry, same as the `/api/authenticate` response. This ensures the session token was issued by the legitimate server. The Drive client only uses `session_token`; the wallet consumes the server auth fields before calling back.

**Error responses (RFC 7807):**
- `404` — Token not found or expired
- `409` — Invitation already accepted
- `403` — Email mismatch
- `401` — Credential verification failed

### `GET /api/invitations/token/{token}` (existing — requires modification)

**Purpose:** Returns invitation details for the wallet to display and verify email.

**Authentication:** Public (already exists with `SsdidPublicAttribute`).

**Current response** includes `Id`, `TenantId`, `TenantName`, `InvitedById`, `Email`, `InvitedUserId`, `Role`, `Status`, `ShortCode`, `Message`, `ExpiresAt`, `CreatedAt`.

**Required change:** Add `inviter_name` field. The current query does not `.Include(i => i.InvitedBy)`, so `InvitedBy.DisplayName` is not available. Add the include and return `inviter_name` in the response.

**Response (after modification):**
```json
{
  "id": "...",
  "tenant_id": "...",
  "tenant_name": "Acme Corp",
  "invited_by_id": "...",
  "inviter_name": "Alice",
  "email": "user@example.com",
  "role": "member",
  "status": "pending",
  "short_code": "ACME-7K9X",
  "message": "Welcome!",
  "expires_at": "...",
  "created_at": "..."
}
```

## 4. Wallet — `ssdid://invite` Deep Link Handler

### New action type: `invite`

Added to the wallet's `DeepLinkHandler` alongside existing actions (`register`, `authenticate`, `sign`, `credential-offer`).

**Required wallet changes:**
1. Add `"invite"` to `VALID_ACTIONS` set in `DeepLinkHandler.kt` (currently rejects unknown actions)
2. Update `callback_url` extraction to also apply for `invite` action (currently only extracted for `authenticate`)
3. Add `token` parameter extraction from deep link query params
4. Add `toNavRoute()` dispatch case for `invite` → new `InviteAcceptScreen`

**Deep link format:**
```
ssdid://invite?server_url={api_base}&token={token}&callback_url=ssdiddrive://invite/callback
```

**Parameters:**
- `server_url` — Drive backend base URL
- `token` — Invitation token
- `callback_url` — Where to send the result back to Drive

### Wallet UI: Invite Acceptance Screen

Single screen showing:
- Tenant name, inviter name, role (fetched from backend)
- Invitation email (for user to confirm)
- "Accept Invitation" button
- "Decline" button (calls back with `status=cancelled`)

### Flow:
1. Parse deep link parameters
2. `GET {server_url}/api/invitations/token/{token}` to fetch details
3. Compare `invitation.email` with wallet profile email (case-insensitive)
4. If mismatch: show "This invitation was sent to a different email address", callback with error
5. If match: show confirmation screen
6. On accept: `POST {server_url}/api/invitations/token/{token}/accept-with-wallet` with credential + email
7. On success: callback `{callback_url}?session_token=...&status=success`
8. On error: callback `{callback_url}?status=error&message=...`

## 5. Drive Client Changes (Android, iOS, Desktop)

All three clients follow the same pattern:

### Deep link registration
- Register `ssdiddrive://invite/callback` as a new callback route (alongside existing `ssdiddrive://auth/callback`)

### Invitation accept flow
1. Handle invitation URL: `https://drive.ssdid.my/invite/{token}`
2. Extract token from URL
3. Build wallet deep link: `ssdid://invite?server_url={api_base}&token={token}&callback_url=ssdiddrive://invite/callback`
4. Launch SSDID Wallet
5. Show "Waiting for SSDID Wallet..." with Cancel button (same pattern as login)

### Callback handling
- `ssdiddrive://invite/callback?session_token=...&status=success` → save session, navigate to main screen
- `ssdiddrive://invite/callback?status=error&message=...` → show error message

### Universal/app link
- `https://drive.ssdid.my/invite/{token}` opens the app if installed, otherwise opens website with download instructions

## 6. Invitation Email Template

**Subject:** "You've been invited to {tenant_name} on SSDID Drive"

**Body contents:**
- Who invited them (inviter name)
- What tenant/organization they're joining
- Their role (Admin/Member)
- Instruction: **"You need both SSDID Wallet and SSDID Drive installed before accepting"**
- Download links for both apps (Play Store, App Store, Desktop)
- **"Accept Invitation" button** → `https://drive.ssdid.my/invite/{token}`
- Expiry notice: "This invitation expires in 7 days"

## 7. Error Handling

| Scenario | Who detects | User sees |
|---|---|---|
| Wallet not installed | Drive client (intent/URL fails) | "Please install SSDID Wallet first" with download link |
| Email mismatch | Wallet (local check) | "This invitation was sent to a different email address" |
| Token expired/invalid | Backend (GET token details) | "This invitation has expired or is invalid" |
| Token already accepted | Backend | "This invitation has already been accepted" |
| Email mismatch (backend double-check) | Backend (accept endpoint) | "Email verification failed" |
| Credential verification failed | Backend | "Authentication failed" |
| Wallet cancelled by user | Wallet → callback | Drive shows "Invitation cancelled" |
| Network error | Wallet or Drive | Standard retry prompt |

All errors from the wallet flow back to Drive via the callback URL: `ssdiddrive://invite/callback?status=error&message=...`

## 8. Security Considerations

- **Token is single-use:** Once accepted, the invitation token is consumed and cannot be reused
- **Token expiry:** Invitations expire after a configurable period (default 7 days)
- **Double email verification:** Wallet checks locally first (fast fail, good UX), backend re-checks independently (wallet cannot be trusted blindly)
- **No email in deep link:** The invitation email is NOT embedded in the `ssdid://invite` deep link. Wallet fetches it from the backend via the token, preventing tampering
- **Credential verification:** Backend verifies the Verifiable Credential using the same path as normal authentication — DID resolution, signature verification, all 19 algorithms supported
- **Rate limiting:** The accept endpoint shares the auth rate limiter to prevent brute-force token guessing
- **Token in callback URL:** Session tokens are passed via deep link query parameters (`ssdiddrive://invite/callback?session_token=...`). This is consistent with the existing login callback flow. Deep links are app-to-app on the same device and not exposed to network or referrer headers.
- **Email exposure on token endpoint:** The `GET /api/invitations/token/{token}` endpoint returns the full email. This is an accepted trade-off — the token itself is a 256-bit secret, and the endpoint is rate-limited. The email is needed for the wallet to perform the local comparison.

## 9. Database Changes

### Existing Invitation fields (no changes needed)

The `Invitation` entity already has: `Id`, `TenantId`, `InvitedById`, `Email`, `InvitedUserId`, `Role` (TenantRole), `Status` (InvitationStatus with Pending/Accepted/Declined/Expired/Revoked), `Token`, `ShortCode`, `Message`, `ExpiresAt`, `CreatedAt`, `UpdatedAt`.

### New fields requiring migration

- `accepted_by_did` (string, nullable) — DID of the user who accepted. Distinct from `InvitedUserId` (which is a Guid FK set during invitation creation if the user already exists). `accepted_by_did` records which DID actually completed the wallet-based acceptance.
- `accepted_at` (DateTimeOffset, nullable) — Explicit acceptance timestamp, separate from `UpdatedAt` which changes on any modification (decline, revoke, etc.).

## 10. Scope

**In scope:**
- Backend: Accept-with-wallet endpoint, GET token details endpoint, email sending
- Wallet: `ssdid://invite` handler, invite acceptance screen, email comparison
- Drive clients: Invitation link handling, wallet launch, callback handling
- Email template

**Already-authenticated users:** If the user is already logged into Drive and clicks an invitation link, Drive should use the existing `POST /api/invitations/{id}/accept` endpoint directly (already implemented), bypassing the wallet flow. The wallet flow is only for unauthenticated users who need to establish identity.

**Out of scope:**
- Invitation management UI (create/list/revoke) — covered by existing admin invite spec
- Invitation link landing page (web) — future work
- Push notifications for invitation status
- Short code-based acceptance via wallet (only token-based links from email)
