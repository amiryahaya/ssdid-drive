# Recovery API

**Version**: 1.0.0
**Status**: Draft
**Last Updated**: 2025-01

## 1. Overview

Key recovery endpoints for Shamir secret sharing based master key recovery. Enables users to recover access when they lose their primary authentication.

**Base URL**: `https://api.securesharing.com/v1`

**Authentication**: Most endpoints require `Authorization: Bearer <token>` header. Recovery initiation uses alternative authentication.

## 2. Recovery Share Management

### 2.1 Setup Recovery Shares

Distribute Shamir shares to trustees.

```http
POST /recovery/shares/setup
Authorization: Bearer <token>
Content-Type: application/json
```

**Request Body**:
```json
{
  "threshold": 3,
  "shares": [
    {
      "trustee_id": "550e8400-e29b-41d4-a716-446655440000",
      "share_index": 1,
      "encrypted_share": {
        "wrapped_value": "base64...",
        "kem_ciphertexts": [
          {"algorithm": "ML-KEM-768", "ciphertext": "base64..."},
          {"algorithm": "KAZ-KEM", "ciphertext": "base64..."}
        ]
      },
      "signature": {
        "ml_dsa": "base64...",
        "kaz_sign": "base64..."
      }
    },
    {
      "trustee_id": "660e8400-e29b-41d4-a716-446655440001",
      "share_index": 2,
      "encrypted_share": { /* ... */ },
      "signature": { /* ... */ }
    },
    {
      "trustee_id": "770e8400-e29b-41d4-a716-446655440002",
      "share_index": 3,
      "encrypted_share": { /* ... */ },
      "signature": { /* ... */ }
    },
    {
      "trustee_id": "880e8400-e29b-41d4-a716-446655440003",
      "share_index": 4,
      "encrypted_share": { /* ... */ },
      "signature": { /* ... */ }
    },
    {
      "trustee_id": "990e8400-e29b-41d4-a716-446655440004",
      "share_index": 5,
      "encrypted_share": { /* ... */ },
      "signature": { /* ... */ }
    }
  ]
}
```

**Response** `201 Created`:
```json
{
  "success": true,
  "data": {
    "threshold": 3,
    "total_shares": 5,
    "shares": [
      {
        "id": "aa0e8400-e29b-41d4-a716-446655440005",
        "trustee_id": "550e8400-e29b-41d4-a716-446655440000",
        "share_index": 1,
        "acknowledged": false
      }
      // ... more shares
    ],
    "setup_complete": false
  }
}
```

---

### 2.2 List Recovery Shares

Get current recovery share configuration.

```http
GET /recovery/shares
Authorization: Bearer <token>
```

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "threshold": 3,
    "total_shares": 5,
    "shares": [
      {
        "id": "aa0e8400-e29b-41d4-a716-446655440005",
        "share_index": 1,
        "trustee": {
          "id": "550e8400-e29b-41d4-a716-446655440000",
          "email": "trustee1@example.com",
          "display_name": "Trustee One"
        },
        "acknowledged": true,
        "acknowledged_at": "2025-01-10T10:30:00.000Z"
      },
      {
        "id": "bb0e8400-e29b-41d4-a716-446655440006",
        "share_index": 2,
        "trustee": {
          "id": "660e8400-e29b-41d4-a716-446655440001",
          "email": "trustee2@example.com",
          "display_name": "Trustee Two"
        },
        "acknowledged": true,
        "acknowledged_at": "2025-01-11T14:20:00.000Z"
      }
      // ... more shares
    ],
    "setup_complete": true
  }
}
```

---

### 2.3 Acknowledge Recovery Share (Trustee)

Trustee acknowledges receipt of their share.

```http
POST /recovery/shares/{share_id}/acknowledge
Authorization: Bearer <token>
Content-Type: application/json
```

**Request Body**:
```json
{
  "signature": {
    "ml_dsa": "base64...",
    "kaz_sign": "base64..."
  }
}
```

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "id": "aa0e8400-e29b-41d4-a716-446655440005",
    "acknowledged": true,
    "acknowledged_at": "2025-01-15T10:30:00.000Z"
  }
}
```

---

### 2.4 Get Shares Held as Trustee

List recovery shares where current user is trustee.

```http
GET /recovery/trustee/shares
Authorization: Bearer <token>
```

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "items": [
      {
        "id": "aa0e8400-e29b-41d4-a716-446655440005",
        "user": {
          "id": "cc0e8400-e29b-41d4-a716-446655440007",
          "email": "john@example.com",
          "display_name": "John"
        },
        "share_index": 2,
        "encrypted_share": {
          "wrapped_value": "base64...",
          "kem_ciphertexts": [ /* ... */ ]
        },
        "acknowledged": true,
        "created_at": "2025-01-05T10:30:00.000Z"
      }
    ]
  }
}
```

## 3. Recovery Request Flow

### 3.1 Initiate Recovery Request

Start the recovery process (uses alternative auth).

```http
POST /recovery/requests
Content-Type: application/json
```

**Request Body**:
```json
{
  "tenant_id": "dd0e8400-e29b-41d4-a716-446655440008",
  "email": "john@example.com",
  "reason": "device_lost",
  "verification": {
    "method": "org_admin",
    "admin_id": "ee0e8400-e29b-41d4-a716-446655440009",
    "verification_code": "ABC123"
  },
  "new_public_keys": {
    "ml_kem": "base64...",
    "ml_dsa": "base64...",
    "kaz_kem": "base64...",
    "kaz_sign": "base64..."
  }
}
```

**Verification Methods**:
| Method | Description |
|--------|-------------|
| `org_admin` | Admin verifies identity |
| `video_call` | Video verification scheduled |
| `in_person` | Physical identity verification |
| `backup_codes` | One-time recovery codes |

**Response** `201 Created`:
```json
{
  "success": true,
  "data": {
    "request": {
      "id": "ff0e8400-e29b-41d4-a716-44665544000a",
      "user_id": "cc0e8400-e29b-41d4-a716-446655440007",
      "status": "pending",
      "reason": "device_lost",
      "approvals_required": 3,
      "approvals_received": 0,
      "expires_at": "2025-01-18T10:30:00.000Z",
      "created_at": "2025-01-15T10:30:00.000Z"
    },
    "trustees_notified": 5,
    "temporary_token": "temp-token-for-polling"
  }
}
```

---

### 3.2 Get Recovery Request Status

Check recovery request status.

```http
GET /recovery/requests/{request_id}
Authorization: Bearer <temporary_token>
```

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "id": "ff0e8400-e29b-41d4-a716-44665544000a",
    "status": "pending",
    "approvals_required": 3,
    "approvals_received": 2,
    "expires_at": "2025-01-18T10:30:00.000Z",
    "trustees": [
      {
        "trustee_id": "550e8400-e29b-41d4-a716-446655440000",
        "display_name": "Trustee One",
        "share_index": 1,
        "approved": true,
        "approved_at": "2025-01-15T12:00:00.000Z"
      },
      {
        "trustee_id": "660e8400-e29b-41d4-a716-446655440001",
        "display_name": "Trustee Two",
        "share_index": 2,
        "approved": true,
        "approved_at": "2025-01-15T14:30:00.000Z"
      },
      {
        "trustee_id": "770e8400-e29b-41d4-a716-446655440002",
        "display_name": "Trustee Three",
        "share_index": 3,
        "approved": false
      }
    ]
  }
}
```

---

### 3.3 Submit Recovery Approval (Trustee)

Trustee approves recovery and submits re-encrypted share.

```http
POST /recovery/requests/{request_id}/approve
Authorization: Bearer <token>
Content-Type: application/json
```

**Request Body**:
```json
{
  "share_index": 2,
  "reencrypted_share": {
    "wrapped_value": "base64...",
    "kem_ciphertexts": [
      {"algorithm": "ML-KEM-768", "ciphertext": "base64..."},
      {"algorithm": "KAZ-KEM", "ciphertext": "base64..."}
    ]
  },
  "signature": {
    "ml_dsa": "base64...",
    "kaz_sign": "base64..."
  }
}
```

**Notes**:
- Trustee decrypts their share with their keys
- Re-encrypts for user's NEW public keys
- Signs the approval

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "request_id": "ff0e8400-e29b-41d4-a716-44665544000a",
    "approvals_received": 3,
    "approvals_required": 3,
    "threshold_reached": true,
    "message": "Threshold reached. User can now complete recovery."
  }
}
```

---

### 3.4 List Pending Approvals (Trustee)

Get recovery requests pending trustee approval.

```http
GET /recovery/trustee/pending
Authorization: Bearer <token>
```

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "items": [
      {
        "request": {
          "id": "ff0e8400-e29b-41d4-a716-44665544000a",
          "status": "pending",
          "reason": "device_lost",
          "created_at": "2025-01-15T10:30:00.000Z",
          "expires_at": "2025-01-18T10:30:00.000Z"
        },
        "user": {
          "id": "cc0e8400-e29b-41d4-a716-446655440007",
          "email": "john@example.com",
          "display_name": "John"
        },
        "my_share": {
          "id": "aa0e8400-e29b-41d4-a716-446655440005",
          "share_index": 2,
          "encrypted_share": { /* ... */ }
        },
        "new_public_keys": {
          "ml_kem": "base64...",
          "ml_dsa": "base64...",
          "kaz_kem": "base64...",
          "kaz_sign": "base64..."
        }
      }
    ]
  }
}
```

---

### 3.5 Collect Approved Shares

Collect all approved shares after threshold reached.

```http
GET /recovery/requests/{request_id}/shares
Authorization: Bearer <temporary_token>
```

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "request_id": "ff0e8400-e29b-41d4-a716-44665544000a",
    "threshold": 3,
    "approvals": [
      {
        "trustee_id": "550e8400-e29b-41d4-a716-446655440000",
        "share_index": 1,
        "reencrypted_share": {
          "wrapped_value": "base64...",
          "kem_ciphertexts": [ /* ... */ ]
        },
        "signature": { /* ... */ }
      },
      {
        "trustee_id": "660e8400-e29b-41d4-a716-446655440001",
        "share_index": 2,
        "reencrypted_share": { /* ... */ },
        "signature": { /* ... */ }
      },
      {
        "trustee_id": "770e8400-e29b-41d4-a716-446655440002",
        "share_index": 3,
        "reencrypted_share": { /* ... */ },
        "signature": { /* ... */ }
      }
    ]
  }
}
```

---

### 3.6 Complete Recovery

Finalize recovery with new encrypted keys.

```http
POST /recovery/requests/{request_id}/complete
Authorization: Bearer <temporary_token>
Content-Type: application/json
```

**Request Body**:
```json
{
  "encrypted_master_key": "base64...",
  "mk_nonce": "base64...",
  "encrypted_private_keys": {
    "ml_kem": {"ciphertext": "base64...", "nonce": "base64..."},
    "ml_dsa": {"ciphertext": "base64...", "nonce": "base64..."},
    "kaz_kem": {"ciphertext": "base64...", "nonce": "base64..."},
    "kaz_sign": {"ciphertext": "base64...", "nonce": "base64..."}
  }
}
```

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "message": "Recovery completed",
    "user": {
      "id": "cc0e8400-e29b-41d4-a716-446655440007",
      "email": "john@example.com"
    },
    "session": {
      "token": "eyJhbGciOiJFZERTQSIs...",
      "expires_at": "2025-01-15T22:30:00.000Z"
    },
    "old_credentials_revoked": true,
    "recovery_shares_regeneration_required": true
  }
}
```

---

### 3.7 Cancel Recovery Request

Cancel a pending recovery request.

```http
DELETE /recovery/requests/{request_id}
Authorization: Bearer <temporary_token or admin_token>
```

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "message": "Recovery request cancelled",
    "cancelled_at": "2025-01-15T10:30:00.000Z"
  }
}
```

## 4. Error Responses

| Code | HTTP | Description |
|------|------|-------------|
| `E_RECOVERY_NOT_SETUP` | 400 | User hasn't set up recovery |
| `E_REQUEST_NOT_FOUND` | 404 | Recovery request not found |
| `E_REQUEST_EXPIRED` | 400 | Recovery request expired |
| `E_REQUEST_COMPLETED` | 400 | Request already completed |
| `E_THRESHOLD_NOT_REACHED` | 400 | Need more approvals |
| `E_ALREADY_APPROVED` | 400 | Trustee already approved |
| `E_NOT_TRUSTEE` | 403 | User is not a trustee |
| `E_VERIFICATION_FAILED` | 401 | Identity verification failed |
| `E_SHARE_INDEX_MISMATCH` | 400 | Wrong share index |
| `E_INVALID_SHARE` | 400 | Share verification failed |
