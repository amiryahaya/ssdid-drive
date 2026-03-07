# Invitations API

**Version**: 1.0.0
**Status**: Draft
**Last Updated**: 2026-01-19

## 1. Overview

The Invitations API enables invitation-only user onboarding for SecureSharing. Users can only join a tenant through invitations sent by administrators or existing users (if permitted by tenant policy).

### Base URL

```
https://api.securesharing.example/v1
```

### Authentication

| Endpoint | Authentication |
|----------|----------------|
| `POST /invitations` | Required (Bearer token) |
| `GET /invitations` | Required (Bearer token) |
| `GET /invitations/:id` | Required (Bearer token) |
| `DELETE /invitations/:id` | Required (Bearer token) |
| `POST /invitations/:id/resend` | Required (Bearer token) |
| `GET /invite/:token` | None (public) |
| `POST /invite/:token/accept` | None (public) |

## 2. Endpoints

### 2.1 Create Invitation

Creates a new invitation to join the tenant.

```http
POST /invitations
Authorization: Bearer <access_token>
Content-Type: application/json
```

#### Request Body

```json
{
  "email": "newuser@example.com",
  "role": "member",
  "message": "Welcome to the team!"
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `email` | string | Yes | Email address of invitee |
| `role` | string | Yes | Role to assign: `admin`, `manager`, `member` |
| `message` | string | No | Personal message included in invitation email |

#### Response (201 Created)

```json
{
  "success": true,
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "email": "newuser@example.com",
    "role": "member",
    "status": "pending",
    "expires_at": "2026-01-26T12:00:00Z",
    "inviter": {
      "id": "660e8400-e29b-41d4-a716-446655440000",
      "display_name": "John Doe"
    },
    "created_at": "2026-01-19T12:00:00Z"
  }
}
```

#### Role Hierarchy

Inviters can only assign roles at or below their own level:

| Inviter Role | Can Invite |
|--------------|------------|
| `admin` | `admin`, `manager`, `member` |
| `manager` | `member` (if peer invites enabled) |
| `member` | `member` (if peer invites enabled) |

#### Error Responses

| Status | Code | Description |
|--------|------|-------------|
| 400 | `INV001` | Invalid email format |
| 403 | `INV006` | Not authorized to invite this role |
| 409 | `INV005` | Email already registered in tenant |
| 422 | `INV007` | Email domain not allowed by tenant policy |
| 429 | `INV008` | Invitation limit reached |

---

### 2.2 List Invitations

Returns all invitations for the tenant (admin view).

```http
GET /invitations?status=pending&page=1&per_page=20
Authorization: Bearer <access_token>
```

#### Query Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `status` | string | all | Filter by status: `pending`, `accepted`, `expired`, `revoked` |
| `page` | integer | 1 | Page number |
| `per_page` | integer | 20 | Items per page (max 100) |

#### Response (200 OK)

```json
{
  "success": true,
  "data": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "email": "user1@example.com",
      "role": "member",
      "status": "pending",
      "inviter": {
        "id": "660e8400-e29b-41d4-a716-446655440000",
        "display_name": "John Doe"
      },
      "created_at": "2026-01-19T12:00:00Z",
      "expires_at": "2026-01-26T12:00:00Z"
    },
    {
      "id": "770e8400-e29b-41d4-a716-446655440000",
      "email": "user2@example.com",
      "role": "manager",
      "status": "accepted",
      "inviter": {
        "id": "660e8400-e29b-41d4-a716-446655440000",
        "display_name": "John Doe"
      },
      "created_at": "2026-01-15T10:00:00Z",
      "accepted_at": "2026-01-16T14:30:00Z",
      "accepted_by": {
        "id": "880e8400-e29b-41d4-a716-446655440000",
        "display_name": "Jane Smith"
      }
    }
  ],
  "pagination": {
    "page": 1,
    "per_page": 20,
    "total": 2,
    "total_pages": 1
  }
}
```

---

### 2.3 Get Invitation Details

Returns details of a specific invitation (admin view).

```http
GET /invitations/:id
Authorization: Bearer <access_token>
```

#### Response (200 OK)

```json
{
  "success": true,
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "email": "newuser@example.com",
    "role": "member",
    "status": "pending",
    "message": "Welcome to the team!",
    "inviter": {
      "id": "660e8400-e29b-41d4-a716-446655440000",
      "display_name": "John Doe",
      "email": "john@example.com"
    },
    "created_at": "2026-01-19T12:00:00Z",
    "expires_at": "2026-01-26T12:00:00Z",
    "resend_count": 0,
    "last_resent_at": null
  }
}
```

---

### 2.4 Revoke Invitation

Cancels a pending invitation.

```http
DELETE /invitations/:id
Authorization: Bearer <access_token>
```

#### Response (200 OK)

```json
{
  "success": true,
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "status": "revoked",
    "revoked_at": "2026-01-20T10:00:00Z"
  }
}
```

#### Error Responses

| Status | Code | Description |
|--------|------|-------------|
| 404 | `INV001` | Invitation not found |
| 409 | - | Invitation already accepted or expired |

---

### 2.5 Resend Invitation

Resends the invitation email.

```http
POST /invitations/:id/resend
Authorization: Bearer <access_token>
```

#### Response (200 OK)

```json
{
  "success": true,
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "resend_count": 1,
    "last_resent_at": "2026-01-20T10:00:00Z"
  }
}
```

#### Rate Limiting

- Maximum 3 resends per invitation per 24 hours

---

### 2.6 Get Invitation Info (Public)

Returns invitation details for the accept flow. This is a public endpoint.

```http
GET /invite/:token
```

#### Response (200 OK) - Valid Invitation

```json
{
  "success": true,
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

#### Response (200 OK) - Invalid Invitation

```json
{
  "success": true,
  "data": {
    "valid": false,
    "error_reason": "expired"
  }
}
```

| `error_reason` | Description |
|----------------|-------------|
| `not_found` | Token doesn't match any invitation |
| `expired` | Invitation has expired |
| `revoked` | Invitation was cancelled |
| `already_used` | Invitation already accepted |

---

### 2.7 Accept Invitation (Register)

Accepts an invitation and creates a new user account. This endpoint performs registration with pre-assigned tenant and role.

```http
POST /invite/:token/accept
Content-Type: application/json
```

#### Request Body

```json
{
  "display_name": "Jane Smith",
  "password": "securepassword123",
  "public_keys": {
    "ml_kem": "base64...",
    "ml_dsa": "base64...",
    "kaz_kem": "base64...",
    "kaz_sign": "base64..."
  },
  "encrypted_master_key": "base64...",
  "mk_nonce": "base64...",
  "encrypted_private_keys": {
    "ml_kem": {"ciphertext": "base64...", "nonce": "base64..."},
    "ml_dsa": {"ciphertext": "base64...", "nonce": "base64..."},
    "kaz_kem": {"ciphertext": "base64...", "nonce": "base64..."},
    "kaz_sign": {"ciphertext": "base64...", "nonce": "base64..."}
  },
  "key_derivation_salt": "base64...",
  "root_folder": {
    "encrypted_metadata": "base64...",
    "metadata_nonce": "base64...",
    "owner_key_access": {
      "wrapped_kek": "base64...",
      "kem_ciphertexts": [
        {"algorithm": "ML-KEM-768", "ciphertext": "base64..."},
        {"algorithm": "KAZ-KEM", "ciphertext": "base64..."}
      ]
    },
    "created_at": "2026-01-20T10:00:00.000Z",
    "signature": {
      "ml_dsa": "base64...",
      "kaz_sign": "base64..."
    }
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `display_name` | string | Yes | User's display name |
| `password` | string | Yes | Account password (for key derivation) |
| `public_keys` | object | Yes | PQC public keys (ML-KEM, ML-DSA, KAZ-KEM, KAZ-SIGN) |
| `encrypted_master_key` | string | Yes | Master key encrypted with password-derived key |
| `mk_nonce` | string | Yes | Nonce for master key encryption |
| `encrypted_private_keys` | object | Yes | PQC private keys encrypted with master key |
| `key_derivation_salt` | string | Yes | Salt used for Argon2id key derivation |
| `root_folder` | object | Yes | Root folder creation data with signature |

#### Response (201 Created)

```json
{
  "success": true,
  "data": {
    "user": {
      "id": "990e8400-e29b-41d4-a716-446655440000",
      "email": "newuser@example.com",
      "display_name": "Jane Smith",
      "tenant_id": "110e8400-e29b-41d4-a716-446655440000",
      "role": "member",
      "status": "active",
      "created_at": "2026-01-20T10:00:00Z"
    },
    "root_folder": {
      "id": "220e8400-e29b-41d4-a716-446655440000",
      "is_root": true,
      "created_at": "2026-01-20T10:00:00Z"
    },
    "session": {
      "access_token": "eyJhbGciOiJFZERTQSIsInR5cCI6IkpXVCJ9...",
      "token_type": "Bearer",
      "expires_in": 3600,
      "expires_at": "2026-01-20T11:00:00Z",
      "refresh_token": "dGhpcyBpcyBhIHJlZnJlc2ggdG9rZW4..."
    }
  }
}
```

#### Error Responses

| Status | Code | Description |
|--------|------|-------------|
| 400 | - | Invalid request body |
| 404 | `INV001` | Invitation not found |
| 410 | `INV002` | Invitation expired |
| 410 | `INV003` | Invitation revoked |
| 409 | `INV004` | Invitation already used |
| 422 | - | Invalid signature or key format |

---

## 3. Data Model

### 3.1 Invitation Object

```typescript
interface Invitation {
  id: string;                    // UUID
  email: string;                 // Invitee email
  role: "admin" | "manager" | "member";
  status: "pending" | "accepted" | "expired" | "revoked";
  message?: string;              // Personal message

  // Relationships
  tenant_id: string;             // Target tenant
  inviter_id: string;            // User who sent invitation
  accepted_by_id?: string;       // User who accepted (after registration)

  // Timestamps
  created_at: string;            // ISO 8601
  expires_at: string;            // ISO 8601
  accepted_at?: string;          // ISO 8601
  revoked_at?: string;           // ISO 8601

  // Tracking
  resend_count: number;
  last_resent_at?: string;       // ISO 8601
}
```

### 3.2 Invitation Status State Machine

```
                    +----------+
                    | Created  |
                    +----+-----+
                         |
                         v
                    +----------+
         +----------| Pending  |----------+
         |          +----+-----+          |
         |               |                |
         v               v                v
    +---------+    +----------+    +---------+
    | Revoked |    | Accepted |    | Expired |
    +---------+    +----------+    +---------+
         |               |                |
         +---------------+----------------+
                         |
                         v
                    (Terminal)
```

---

## 4. Token Security

### 4.1 Token Generation

```
Token = Base64URL(crypto.randomBytes(32))  // 256 bits entropy
TokenHash = SHA256(Token)                   // Stored in database
```

- Raw token is sent via email only once
- Only the hash is stored in the database
- Token lookup uses constant-time comparison via hash

### 4.2 Token Validation

```elixir
def validate_token(input_token) do
  input_hash = :crypto.hash(:sha256, input_token) |> Base.encode16(case: :lower)

  case Repo.get_by(Invitation, token_hash: input_hash) do
    nil -> {:error, :not_found}
    %{status: :accepted} -> {:error, :already_used}
    %{status: :revoked} -> {:error, :revoked}
    %{expires_at: exp} when exp < now -> {:error, :expired}
    invitation -> {:ok, invitation}
  end
end
```

---

## 5. Rate Limiting

| Action | Limit | Window |
|--------|-------|--------|
| Create invitation (per user) | 20 | 1 hour |
| Create invitation (per tenant) | 100 | 1 hour |
| Accept invitation (per IP) | 10 | 1 hour |
| Get invitation info (per IP) | 60 | 1 minute |
| Resend invitation (per invitation) | 3 | 24 hours |

---

## 6. Tenant Settings

Tenant-level configuration for invitation behavior:

```json
{
  "invitation_settings": {
    "allow_peer_invitations": false,
    "invitation_expiry_hours": 168,
    "max_pending_invitations": 100,
    "require_email_domain": null
  }
}
```

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `allow_peer_invitations` | boolean | false | Allow non-admins to invite |
| `invitation_expiry_hours` | integer | 168 (7 days) | Invitation validity period |
| `max_pending_invitations` | integer | 100 | Max pending invitations per tenant |
| `require_email_domain` | string | null | Restrict invitations to email domain |

---

## 7. Error Codes

| Code | HTTP Status | Message |
|------|-------------|---------|
| `INV001` | 404 | Invitation not found |
| `INV002` | 410 | Invitation expired |
| `INV003` | 410 | Invitation revoked |
| `INV004` | 409 | Invitation already used |
| `INV005` | 409 | Email already registered in tenant |
| `INV006` | 403 | Not authorized to invite this role |
| `INV007` | 422 | Email domain not allowed |
| `INV008` | 429 | Invitation limit reached |
| `INV009` | 400 | Cannot invite self |

---

## 8. Webhooks

Invitation events trigger webhooks if configured:

| Event | Payload |
|-------|---------|
| `invitation.created` | Full invitation object |
| `invitation.accepted` | Invitation + new user info |
| `invitation.revoked` | Invitation ID + revoked_at |
| `invitation.expired` | Invitation ID + expires_at |

---

## 9. Related Documentation

- [Registration Flow](../flows/01-registration-flow.md) - Standard registration process
- [Invitation Flow](../flows/09-invitation-flow.md) - Invitation-based onboarding
- [Invitation System Design](../design/invitation-system.md) - Full design document
- [Notifications API](./08-notifications.md) - `tenant_invitation` notification type
