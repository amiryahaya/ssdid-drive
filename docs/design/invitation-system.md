# Invitation-Only Onboarding System

## Design Document

**Version:** 1.0
**Status:** Draft
**Date:** 2026-01-19

---

## Table of Contents

1. [Overview](#1-overview)
2. [Goals & Non-Goals](#2-goals--non-goals)
3. [Invitation Types](#3-invitation-types)
4. [User Flows](#4-user-flows)
5. [Data Model](#5-data-model)
6. [API Design](#6-api-design)
7. [Security Considerations](#7-security-considerations)
8. [Mobile Deep Linking](#8-mobile-deep-linking)
9. [Email Templates](#9-email-templates)
10. [Admin Dashboard](#10-admin-dashboard)
11. [Migration Strategy](#11-migration-strategy)
12. [Future Enhancements](#12-future-enhancements)

---

## 1. Overview

### Current State
- Users can self-register with email/password
- Multi-tenant architecture exists
- Users must specify a tenant slug during registration

### Proposed State
- **No public registration** - registration form removed
- Users can only join via invitation from:
  - Tenant administrators
  - Existing users (if permitted by tenant policy)
- First tenant admin created via admin setup flow (already exists)

### Why Invitation-Only?

```
┌─────────────────────────────────────────────────────────────────┐
│                    TRUST CHAIN MODEL                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   Platform Admin                                                │
│        │                                                        │
│        ▼                                                        │
│   Creates Tenant ──▶ Assigns Tenant Admin                       │
│                            │                                    │
│                            ▼                                    │
│                      Tenant Admin                               │
│                       │       │                                 │
│                       ▼       ▼                                 │
│                   Invites   Invites                             │
│                   Users     Managers                            │
│                     │           │                               │
│                     ▼           ▼                               │
│                  Users      Managers ──▶ Invite Users           │
│                                                                 │
│   Every user has a traceable invitation chain                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. Goals & Non-Goals

### Goals

| Goal | Description |
|------|-------------|
| **Controlled Access** | Only authorized users can join a tenant |
| **Audit Trail** | Track who invited whom, when, and with what role |
| **Role Assignment** | Inviter can pre-assign role during invitation |
| **Flexibility** | Support admin invites and peer invites (configurable) |
| **Security** | Cryptographically secure, expiring, single-use tokens |
| **Cross-Platform** | Work seamlessly on web, iOS, and Android |

### Non-Goals (Out of Scope for v1)

- SSO/SAML integration (future enhancement)
- Bulk CSV import of users
- Self-service tenant creation
- Public invitation links (open to anyone)

---

## 3. Invitation Types

### 3.1 Admin Invitation

**Who can send:** Tenant Admin, Platform Admin
**Who can receive:** Anyone (by email)
**Permissions:** Can assign any role up to their own level

```
Tenant Admin ──▶ Can invite: Admin, Manager, Member
Manager      ──▶ Can invite: Member (if peer_invite enabled)
Member       ──▶ Cannot invite (unless peer_invite enabled)
```

### 3.2 Peer Invitation (Optional)

**Who can send:** Any user (if tenant allows)
**Who can receive:** Anyone (by email)
**Permissions:** Can only invite as Member role

**Tenant Setting:** `allow_peer_invitations: boolean`

### 3.3 Invitation Attributes

| Attribute | Type | Description |
|-----------|------|-------------|
| `id` | UUID | Unique invitation ID |
| `token` | String | 32-byte random token (URL-safe Base64) |
| `email` | String | Invitee's email address |
| `role` | Enum | Pre-assigned role (admin/manager/member) |
| `tenant_id` | UUID | Target tenant |
| `inviter_id` | UUID | User who sent the invitation |
| `status` | Enum | pending/accepted/expired/revoked |
| `expires_at` | DateTime | Expiration timestamp |
| `accepted_at` | DateTime | When invitation was accepted |
| `accepted_by_id` | UUID | User ID of acceptor (after registration) |
| `message` | String | Optional personal message |
| `metadata` | JSON | Additional data (pre-shared folders, etc.) |

---

## 4. User Flows

### 4.1 Admin Invites New User

```
┌─────────────────────────────────────────────────────────────────┐
│                     ADMIN INVITATION FLOW                       │
└─────────────────────────────────────────────────────────────────┘

ADMIN (Web Dashboard)                    SYSTEM                    NEW USER
      │                                    │                          │
      │ 1. Enter email, select role        │                          │
      │───────────────────────────────────▶│                          │
      │                                    │                          │
      │                                    │ 2. Validate email        │
      │                                    │    Check not existing    │
      │                                    │    Generate token        │
      │                                    │    Create invitation     │
      │                                    │                          │
      │ 3. Confirmation                    │                          │
      │◀───────────────────────────────────│                          │
      │                                    │                          │
      │                                    │ 4. Send invitation email │
      │                                    │───────────────────────────────────▶│
      │                                    │                          │
      │                                    │                          │ 5. Click link
      │                                    │◀──────────────────────────────────│
      │                                    │                          │
      │                                    │ 6. Validate token        │
      │                                    │    Show registration     │
      │                                    │───────────────────────────────────▶│
      │                                    │                          │
      │                                    │                          │ 7. Enter name,
      │                                    │                          │    password
      │                                    │◀──────────────────────────────────│
      │                                    │                          │
      │                                    │ 8. Create user           │
      │                                    │    Generate keys         │
      │                                    │    Mark invite accepted  │
      │                                    │    Send welcome email    │
      │                                    │───────────────────────────────────▶│
      │                                    │                          │
      │ 9. Notification (optional)         │                          │ 10. Logged in
      │◀───────────────────────────────────│                          │     to app
```

### 4.2 Mobile App Flow (Deep Link)

```
┌─────────────────────────────────────────────────────────────────┐
│                    MOBILE DEEP LINK FLOW                        │
└─────────────────────────────────────────────────────────────────┘

1. User receives email with invitation link:
   https://app.securesharing.example/invite/abc123token

2. User taps link on mobile device:

   ┌─────────────────┐
   │ App Installed?  │
   └────────┬────────┘
            │
      ┌─────┴─────┐
      │           │
      ▼           ▼
    [YES]       [NO]
      │           │
      ▼           ▼
   App Opens   App Store
   with token  (then app
               opens with
               deferred
               deep link)
      │           │
      └─────┬─────┘
            ▼
   ┌─────────────────┐
   │ Invitation      │
   │ Accept Screen   │
   │                 │
   │ "You've been    │
   │ invited by      │
   │ John Doe to     │
   │ join Acme Corp" │
   │                 │
   │ [Accept]        │
   └─────────────────┘
            │
            ▼
   ┌─────────────────┐
   │ Registration    │
   │ Form            │
   │                 │
   │ Name: [______]  │
   │ Password: [___] │
   │ Confirm: [____] │
   │                 │
   │ [Create Account]│
   └─────────────────┘
            │
            ▼
   ┌─────────────────┐
   │ Key Generation  │
   │ (PQC keys)      │
   │                 │
   │ "Setting up     │
   │ encryption..."  │
   └─────────────────┘
            │
            ▼
   ┌─────────────────┐
   │ Onboarding      │
   │ Complete        │
   │                 │
   │ "Welcome to     │
   │ SecureSharing!" │
   └─────────────────┘
```

### 4.3 Existing User Login (No Changes)

```
┌─────────────────────────────────────────────────────────────────┐
│                    EXISTING USER LOGIN                          │
└─────────────────────────────────────────────────────────────────┘

User opens app
      │
      ▼
┌─────────────────┐
│ Login Screen    │
│                 │
│ Email: [______] │
│ Password: [___] │
│                 │
│ [Sign In]       │
│                 │
│ ─────────────── │
│ Don't have an   │
│ account?        │
│ Contact your    │  ◀── No public registration link
│ administrator   │
└─────────────────┘
```

---

## 5. Data Model

### 5.1 Database Schema

```sql
-- New table: invitations
CREATE TABLE invitations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Token (indexed for lookup)
    token VARCHAR(64) NOT NULL UNIQUE,
    token_hash VARCHAR(64) NOT NULL,  -- SHA-256 hash for secure lookup

    -- Invitation details
    email VARCHAR(255) NOT NULL,
    role VARCHAR(50) NOT NULL DEFAULT 'member',
    message TEXT,

    -- Relationships
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    inviter_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Status tracking
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    -- pending, accepted, expired, revoked

    -- Timestamps
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),

    -- Acceptance tracking
    accepted_at TIMESTAMP WITH TIME ZONE,
    accepted_by_id UUID REFERENCES users(id),

    -- Additional metadata
    metadata JSONB DEFAULT '{}',

    -- Constraints
    CONSTRAINT valid_status CHECK (status IN ('pending', 'accepted', 'expired', 'revoked')),
    CONSTRAINT valid_role CHECK (role IN ('admin', 'manager', 'member'))
);

-- Indexes
CREATE INDEX idx_invitations_token_hash ON invitations(token_hash);
CREATE INDEX idx_invitations_email ON invitations(email);
CREATE INDEX idx_invitations_tenant_id ON invitations(tenant_id);
CREATE INDEX idx_invitations_inviter_id ON invitations(inviter_id);
CREATE INDEX idx_invitations_status ON invitations(status);
CREATE INDEX idx_invitations_expires_at ON invitations(expires_at)
    WHERE status = 'pending';

-- Tenant settings for invitation policy
ALTER TABLE tenants ADD COLUMN IF NOT EXISTS invitation_settings JSONB DEFAULT '{
    "allow_peer_invitations": false,
    "invitation_expiry_hours": 168,
    "max_pending_invitations": 100,
    "require_email_domain": null
}';
```

### 5.2 Elixir Schema

```elixir
defmodule SecureSharing.Accounts.Invitation do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "invitations" do
    field :token, :string, virtual: true  # Only set on creation
    field :token_hash, :string
    field :email, :string
    field :role, Ecto.Enum, values: [:admin, :manager, :member], default: :member
    field :message, :string
    field :status, Ecto.Enum, values: [:pending, :accepted, :expired, :revoked], default: :pending
    field :expires_at, :utc_datetime
    field :accepted_at, :utc_datetime
    field :metadata, :map, default: %{}

    belongs_to :tenant, SecureSharing.Tenants.Tenant
    belongs_to :inviter, SecureSharing.Accounts.User
    belongs_to :accepted_by, SecureSharing.Accounts.User

    timestamps()
  end

  @required_fields [:email, :role, :tenant_id, :inviter_id, :expires_at]
  @optional_fields [:message, :metadata]

  def create_changeset(invitation, attrs) do
    invitation
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/)
    |> validate_email_not_registered()
    |> validate_inviter_can_invite_role()
    |> generate_token()
    |> unique_constraint(:token_hash)
    |> foreign_key_constraint(:tenant_id)
    |> foreign_key_constraint(:inviter_id)
  end

  defp generate_token(changeset) do
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    token_hash = :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)

    changeset
    |> put_change(:token, token)
    |> put_change(:token_hash, token_hash)
  end
end
```

### 5.3 Kotlin Data Classes (Android)

```kotlin
// Domain model
data class Invitation(
    val id: String,
    val email: String,
    val role: UserRole,
    val tenantId: String,
    val tenantName: String,
    val inviterName: String,
    val message: String?,
    val expiresAt: Instant,
    val status: InvitationStatus
)

enum class InvitationStatus {
    PENDING, ACCEPTED, EXPIRED, REVOKED
}

// API DTOs
data class InvitationInfoResponse(
    val data: InvitationInfo
)

data class InvitationInfo(
    val id: String,
    val email: String,
    val role: String,
    @SerializedName("tenant_name") val tenantName: String,
    @SerializedName("inviter_name") val inviterName: String,
    val message: String?,
    @SerializedName("expires_at") val expiresAt: String,
    val valid: Boolean,
    @SerializedName("error_reason") val errorReason: String?  // expired, revoked, already_used
)

data class AcceptInvitationRequest(
    val token: String,
    @SerializedName("display_name") val displayName: String,
    val password: String,
    @SerializedName("public_keys") val publicKeys: PublicKeysDto,
    @SerializedName("encrypted_master_key") val encryptedMasterKey: String,
    @SerializedName("encrypted_private_keys") val encryptedPrivateKeys: String,
    @SerializedName("key_derivation_salt") val keyDerivationSalt: String
)
```

---

## 6. API Design

### 6.1 Endpoints Overview

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `POST` | `/api/invitations` | Required | Create invitation |
| `GET` | `/api/invitations` | Required | List tenant invitations |
| `GET` | `/api/invitations/:id` | Required | Get invitation details |
| `DELETE` | `/api/invitations/:id` | Required | Revoke invitation |
| `POST` | `/api/invitations/:id/resend` | Required | Resend invitation email |
| `GET` | `/api/invite/:token` | None | Get invitation info (public) |
| `POST` | `/api/invite/:token/accept` | None | Accept invitation (register) |

### 6.2 Create Invitation

```http
POST /api/invitations
Authorization: Bearer <token>
Content-Type: application/json

{
    "email": "newuser@example.com",
    "role": "member",
    "message": "Welcome to the team!"  // optional
}
```

**Response (201 Created):**
```json
{
    "data": {
        "id": "550e8400-e29b-41d4-a716-446655440000",
        "email": "newuser@example.com",
        "role": "member",
        "status": "pending",
        "expires_at": "2026-01-26T12:00:00Z",
        "inviter": {
            "id": "123...",
            "display_name": "John Doe"
        },
        "created_at": "2026-01-19T12:00:00Z"
    }
}
```

**Error Responses:**
- `400` - Invalid email format
- `403` - Not authorized to invite (wrong role)
- `409` - Email already registered in tenant
- `422` - Email domain not allowed (if restricted)
- `429` - Too many pending invitations

### 6.3 Get Invitation Info (Public)

```http
GET /api/invite/abc123token
```

**Response (200 OK):**
```json
{
    "data": {
        "id": "550e8400-e29b-41d4-a716-446655440000",
        "email": "newuser@example.com",
        "role": "member",
        "tenant_name": "Acme Corporation",
        "inviter_name": "John Doe",
        "message": "Welcome to the team!",
        "expires_at": "2026-01-26T12:00:00Z",
        "valid": true
    }
}
```

**Invalid Invitation Response:**
```json
{
    "data": {
        "valid": false,
        "error_reason": "expired"  // or "revoked", "already_used", "not_found"
    }
}
```

### 6.4 Accept Invitation (Register)

```http
POST /api/invite/abc123token/accept
Content-Type: application/json

{
    "display_name": "Jane Smith",
    "password": "securepassword123",
    "public_keys": {
        "kem": "base64...",
        "sign": "base64...",
        "ml_kem": "base64...",
        "ml_dsa": "base64..."
    },
    "encrypted_master_key": "base64...",
    "encrypted_private_keys": "base64...",
    "key_derivation_salt": "base64..."
}
```

**Response (201 Created):**
```json
{
    "data": {
        "user": {
            "id": "user-uuid",
            "email": "newuser@example.com",
            "display_name": "Jane Smith",
            "tenant_id": "tenant-uuid",
            "role": "member"
        },
        "access_token": "jwt...",
        "refresh_token": "jwt..."
    }
}
```

### 6.5 List Invitations (Admin)

```http
GET /api/invitations?status=pending&page=1&per_page=20
Authorization: Bearer <token>
```

**Response:**
```json
{
    "data": [
        {
            "id": "...",
            "email": "user1@example.com",
            "role": "member",
            "status": "pending",
            "inviter": { "id": "...", "display_name": "John" },
            "created_at": "...",
            "expires_at": "..."
        }
    ],
    "pagination": {
        "page": 1,
        "per_page": 20,
        "total": 5,
        "total_pages": 1
    }
}
```

---

## 7. Security Considerations

### 7.1 Token Security

```
Token Generation:
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│   token = crypto.strong_rand_bytes(32)  # 256 bits entropy     │
│   token_url = Base64.url_encode(token)  # URL-safe             │
│   token_hash = SHA256(token)            # Stored in DB         │
│                                                                 │
│   Only the hash is stored; token sent via email once           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

Token Lookup (constant-time):
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│   input_hash = SHA256(input_token)                              │
│   invitation = DB.find_by(token_hash: input_hash)               │
│                                                                 │
│   Prevents timing attacks on token comparison                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 7.2 Rate Limiting

| Action | Limit | Window |
|--------|-------|--------|
| Create invitation (per user) | 20 | 1 hour |
| Create invitation (per tenant) | 100 | 1 hour |
| Accept invitation (per IP) | 10 | 1 hour |
| Get invitation info (per IP) | 60 | 1 minute |
| Resend invitation (per invitation) | 3 | 24 hours |

### 7.3 Validation Rules

```elixir
# Invitation creation validations
defp validate_invitation(changeset, inviter, tenant) do
  changeset
  |> validate_email_not_registered_in_tenant()
  |> validate_no_pending_invitation_for_email()
  |> validate_inviter_role_can_invite(inviter)
  |> validate_tenant_invitation_limit(tenant)
  |> validate_email_domain_allowed(tenant)
end

# Role hierarchy enforcement
defp can_invite_role?(inviter_role, target_role) do
  role_level = %{admin: 3, manager: 2, member: 1}

  # Can only invite same level or below
  role_level[inviter_role] >= role_level[target_role]
end
```

### 7.4 Expiration & Cleanup

```elixir
# Default expiration: 7 days (configurable per tenant)
defp default_expiration(tenant) do
  hours = tenant.invitation_settings["invitation_expiry_hours"] || 168
  DateTime.add(DateTime.utc_now(), hours * 3600, :second)
end

# Scheduled cleanup job (Oban)
defmodule SecureSharing.Workers.ExpireInvitationsWorker do
  use Oban.Worker, queue: :maintenance, crontab: "0 * * * *"  # Every hour

  @impl true
  def perform(_job) do
    Invitations.expire_old_invitations()
  end
end
```

### 7.5 Audit Logging

All invitation actions are logged:

```elixir
# Audit events
:invitation_created
:invitation_accepted
:invitation_revoked
:invitation_expired
:invitation_resent
```

---

## 8. Mobile Deep Linking

### 8.1 URL Scheme

```
Web URL:      https://app.securesharing.example/invite/{token}
Android:      securesharing://invite/{token}
iOS:          securesharing://invite/{token}
Universal:    https://app.securesharing.example/invite/{token}
```

### 8.2 Android Configuration

**AndroidManifest.xml:**
```xml
<activity
    android:name=".presentation.auth.InvitationActivity"
    android:exported="true">

    <!-- Custom scheme -->
    <intent-filter>
        <action android:name="android.intent.action.VIEW" />
        <category android:name="android.intent.category.DEFAULT" />
        <category android:name="android.intent.category.BROWSABLE" />
        <data
            android:scheme="securesharing"
            android:host="invite" />
    </intent-filter>

    <!-- App Links (Universal Links) -->
    <intent-filter android:autoVerify="true">
        <action android:name="android.intent.action.VIEW" />
        <category android:name="android.intent.category.DEFAULT" />
        <category android:name="android.intent.category.BROWSABLE" />
        <data
            android:scheme="https"
            android:host="app.securesharing.example"
            android:pathPrefix="/invite" />
    </intent-filter>
</activity>
```

**assetlinks.json (hosted at /.well-known/assetlinks.json):**
```json
[{
    "relation": ["delegate_permission/common.handle_all_urls"],
    "target": {
        "namespace": "android_app",
        "package_name": "com.securesharing",
        "sha256_cert_fingerprints": ["YOUR_APP_SIGNING_CERT_FINGERPRINT"]
    }
}]
```

### 8.3 iOS Configuration

**Info.plist:**
```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>securesharing</string>
        </array>
    </dict>
</array>

<key>LSApplicationQueriesSchemes</key>
<array>
    <string>securesharing</string>
</array>
```

**Entitlements (for Universal Links):**
```xml
<key>com.apple.developer.associated-domains</key>
<array>
    <string>applinks:app.securesharing.example</string>
</array>
```

**apple-app-site-association (hosted at /.well-known/):**
```json
{
    "applinks": {
        "apps": [],
        "details": [{
            "appID": "TEAM_ID.com.securesharing",
            "paths": ["/invite/*"]
        }]
    }
}
```

### 8.4 Deferred Deep Linking

For users who don't have the app installed:

```
1. User clicks invite link
2. No app installed → Redirect to App Store / Play Store
3. User installs app
4. App opens and retrieves deferred deep link
5. Invitation flow continues
```

**Implementation options:**
- Firebase Dynamic Links
- Branch.io
- Custom solution with clipboard/pasteboard

---

## 9. Email Templates

### 9.1 Invitation Email

```
Subject: You've been invited to join {tenant_name} on SecureSharing

─────────────────────────────────────────────────────────

Hi there,

{inviter_name} has invited you to join {tenant_name} on SecureSharing.

{message}  (if provided)

SecureSharing is a secure file sharing platform with
post-quantum encryption to protect your sensitive files.

[ Accept Invitation ]
    ↑
    Button links to: https://app.securesharing.example/invite/{token}

This invitation expires on {expires_at}.

─────────────────────────────────────────────────────────

If you didn't expect this invitation, you can safely ignore this email.

SecureSharing - Secure File Sharing
```

### 9.2 Welcome Email (After Registration)

```
Subject: Welcome to {tenant_name}!

─────────────────────────────────────────────────────────

Welcome, {display_name}!

Your SecureSharing account is ready. You're now a member
of {tenant_name}.

What's next?
• Download the mobile app (iOS / Android links)
• Set up biometric unlock for easy access
• Start sharing files securely

[ Open SecureSharing ]

─────────────────────────────────────────────────────────

Need help? Contact your administrator or visit our help center.

SecureSharing - Secure File Sharing
```

### 9.3 Invitation Accepted Notification (To Inviter)

```
Subject: {user_name} accepted your invitation

─────────────────────────────────────────────────────────

Hi {inviter_name},

Good news! {user_name} ({email}) has accepted your
invitation to join {tenant_name}.

They are now a {role} in your organization.

─────────────────────────────────────────────────────────

SecureSharing - Secure File Sharing
```

---

## 10. Admin Dashboard

### 10.1 Invitation Management UI

```
┌─────────────────────────────────────────────────────────────────┐
│  Invitations                                        [ + Invite ]│
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Filter: [All ▼] [Pending ○] [Accepted ○] [Expired ○]          │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ EMAIL              ROLE     STATUS    INVITED BY   EXPIRES  ││
│  ├─────────────────────────────────────────────────────────────┤│
│  │ alice@example.com  Member   Pending   John Doe     5 days   ││
│  │                                            [ Resend ] [ ✕ ] ││
│  ├─────────────────────────────────────────────────────────────┤│
│  │ bob@example.com    Manager  Accepted  Jane Smith   -        ││
│  │                                            Joined Jan 15    ││
│  ├─────────────────────────────────────────────────────────────┤│
│  │ carol@example.com  Member   Expired   John Doe     -        ││
│  │                                            [ Resend ]       ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                 │
│  Showing 3 of 3 invitations                                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 10.2 Invite Dialog

```
┌─────────────────────────────────────────────────────────────────┐
│  Invite New User                                          [ × ] │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Email address                                                  │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ newuser@example.com                                         ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                 │
│  Role                                                           │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ Member ▼                                                    ││
│  │ ┌───────────────────────────────────────────────────────┐   ││
│  │ │ ○ Admin    - Full access, can manage users            │   ││
│  │ │ ○ Manager  - Can manage files and invite members      │   ││
│  │ │ ● Member   - Standard access to shared files          │   ││
│  │ └───────────────────────────────────────────────────────┘   ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                 │
│  Personal message (optional)                                    │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ Welcome to the team! Looking forward to working with you.  ││
│  └─────────────────────────────────────────────────────────────┘│
│                                                                 │
│                              [ Cancel ]  [ Send Invitation ]    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 11. Migration Strategy

### 11.1 If Existing Users Exist

Since this is likely a new deployment, migration may not be needed. However, if there are existing users:

```
Phase 1: Add invitation system alongside existing registration
Phase 2: Disable public registration (feature flag)
Phase 3: Remove registration UI/endpoints
```

### 11.2 Feature Flags

```elixir
# config/config.exs
config :secure_sharing, :features,
  allow_public_registration: false,  # Set to false to enforce invitation-only
  allow_peer_invitations: true       # Per-tenant override available
```

---

## 12. Future Enhancements

### 12.1 v1.1 - Bulk Invitations

```
- CSV upload for bulk invitations
- Progress tracking for large batches
- Partial success handling
```

### 12.2 v1.2 - SSO/SAML Integration

```
- SAML-based auto-provisioning
- Just-in-time user creation from IdP
- Directory sync (Azure AD, Okta, etc.)
```

### 12.3 v1.3 - Invitation Links

```
- Shareable invitation links (not email-specific)
- Limited use count
- Domain restrictions
- Useful for onboarding teams quickly
```

### 12.4 v1.4 - Pre-shared Access

```
- Invite user with pre-shared folders
- Automatic share creation on acceptance
- Onboarding templates
```

---

## Appendix A: State Machine

```
                    ┌─────────┐
                    │ Created │
                    └────┬────┘
                         │
                         ▼
                    ┌─────────┐
         ┌─────────│ Pending │─────────┐
         │         └────┬────┘         │
         │              │              │
         ▼              ▼              ▼
    ┌─────────┐   ┌──────────┐   ┌─────────┐
    │ Revoked │   │ Accepted │   │ Expired │
    └─────────┘   └──────────┘   └─────────┘
         │              │              │
         └──────────────┴──────────────┘
                         │
                         ▼
                    (Terminal)
```

---

## Appendix B: Error Codes

| Code | Message | Description |
|------|---------|-------------|
| `INV001` | Invitation not found | Token doesn't match any invitation |
| `INV002` | Invitation expired | Past expiration date |
| `INV003` | Invitation revoked | Admin cancelled the invitation |
| `INV004` | Invitation already used | User already registered |
| `INV005` | Email already registered | User exists in tenant |
| `INV006` | Not authorized to invite | Role restrictions |
| `INV007` | Invalid email domain | Domain not in allowlist |
| `INV008` | Invitation limit reached | Tenant quota exceeded |
| `INV009` | Cannot invite self | Email matches inviter |

---

## Appendix C: Checklist

### Backend
- [ ] Create `invitations` table migration
- [ ] Implement `Invitation` schema
- [ ] Implement `Invitations` context
- [ ] Create invitation API endpoints
- [ ] Implement token generation/validation
- [ ] Add rate limiting
- [ ] Add audit logging
- [ ] Create email templates
- [ ] Add Oban worker for expiration
- [ ] Disable public registration endpoint
- [ ] Update tests

### Android
- [ ] Add deep link handling
- [ ] Create invitation accept screen
- [ ] Create registration-from-invitation flow
- [ ] Update login screen (remove register link)
- [ ] Handle deferred deep links
- [ ] Add invitation API client
- [ ] Update tests

### iOS
- [ ] Add deep link handling
- [ ] Create invitation accept screen
- [ ] Create registration-from-invitation flow
- [ ] Update login screen
- [ ] Handle Universal Links
- [ ] Add invitation API client
- [ ] Update tests

### Web Admin
- [ ] Create invitation management page
- [ ] Create invite dialog
- [ ] Add invitation list/filter
- [ ] Add resend/revoke actions

### DevOps
- [ ] Set up App Links verification (Android)
- [ ] Set up Universal Links (iOS)
- [ ] Configure email templates
- [ ] Update rate limiting rules

---

*End of Design Document*
