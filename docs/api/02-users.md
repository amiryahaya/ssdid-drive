# Users API

**Version**: 1.0.0
**Status**: Draft
**Last Updated**: 2025-01

## 1. Overview

User management endpoints for profile updates, key management, and user administration within a tenant.

**Base URL**: `https://api.securesharing.com/v1`

**Authentication**: All endpoints require `Authorization: Bearer <token>` header.

## 2. Endpoints

### 2.1 List Users (Admin)

List users in the tenant. Requires admin role.

```http
GET /users
Authorization: Bearer <token>
```

**Query Parameters**:
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `status` | string | - | Filter by status (`active`, `suspended`) |
| `role` | string | - | Filter by role (`member`, `admin`, `owner`) |
| `search` | string | - | Search by email or name |
| `limit` | integer | 20 | Items per page (max 100) |
| `offset` | integer | 0 | Pagination offset |

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "items": [
      {
        "id": "550e8400-e29b-41d4-a716-446655440000",
        "email": "user@example.com",
        "display_name": "John Doe",
        "status": "active",
        "role": "member",
        "recovery_setup_complete": true,
        "last_login_at": "2025-01-15T10:30:00.000Z",
        "created_at": "2025-01-01T00:00:00.000Z"
      }
    ],
    "pagination": {
      "total": 45,
      "limit": 20,
      "offset": 0,
      "has_more": true
    }
  }
}
```

---

### 2.2 Get User by ID

Get a specific user's public profile.

```http
GET /users/{user_id}
Authorization: Bearer <token>
```

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "email": "user@example.com",
    "display_name": "John Doe",
    "status": "active",
    "role": "member",
    "public_keys": {
      "ml_kem": "base64...",
      "ml_dsa": "base64...",
      "kaz_kem": "base64...",
      "kaz_sign": "base64..."
    },
    "created_at": "2025-01-01T00:00:00.000Z"
  }
}
```

---

### 2.3 Get User Public Keys

Get only a user's public keys (for sharing operations).

```http
GET /users/{user_id}/public-keys
Authorization: Bearer <token>
```

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "user_id": "550e8400-e29b-41d4-a716-446655440000",
    "public_keys": {
      "ml_kem": "base64...",
      "ml_dsa": "base64...",
      "kaz_kem": "base64...",
      "kaz_sign": "base64..."
    }
  }
}
```

---

### 2.4 Update Profile

Update current user's profile.

```http
PATCH /users/me
Authorization: Bearer <token>
Content-Type: application/json
```

**Request Body**:
```json
{
  "display_name": "John D."
}
```

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "email": "user@example.com",
    "display_name": "John D.",
    "status": "active",
    "updated_at": "2025-01-15T10:30:00.000Z"
  }
}
```

---

### 2.5 Update Keys (Key Rotation)

Update user's cryptographic keys. Used for key rotation.

```http
PUT /users/me/keys
Authorization: Bearer <token>
Content-Type: application/json
```

**Request Body**:
```json
{
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
  "rotation_signature": {
    "ml_dsa": "base64...",
    "kaz_sign": "base64..."
  }
}
```

**Notes**:
- `rotation_signature` signs the new public keys with old private keys
- This proves the user authorized the key change
- After rotation, all existing shares must be re-encrypted

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "message": "Keys updated successfully",
    "updated_at": "2025-01-15T10:30:00.000Z"
  }
}
```

---

### 2.6 Search Users

Search for users by email (for sharing). Returns public keys needed for key encapsulation.

```http
GET /users/search
Authorization: Bearer <token>
```

**Query Parameters**:
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `q` | string | Yes | Email prefix to search |
| `limit` | integer | No | Max results (default 10, max 50) |

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "items": [
      {
        "id": "550e8400-e29b-41d4-a716-446655440000",
        "email": "john@example.com",
        "display_name": "John Doe",
        "public_keys": {
          "ml_kem": "base64...",
          "kaz_kem": "base64..."
        }
      },
      {
        "id": "660e8400-e29b-41d4-a716-446655440001",
        "email": "john.smith@example.com",
        "display_name": "John Smith",
        "public_keys": {
          "ml_kem": "base64...",
          "kaz_kem": "base64..."
        }
      }
    ]
  }
}
```

**Notes**:
- Only KEM public keys are returned (needed for key encapsulation during sharing)
- Signing keys (`ml_dsa`, `kaz_sign`) are not included as they're not needed for sharing
- Use `GET /users/{user_id}/public-keys` to fetch all public keys if needed

---

### 2.7 Update User Role (Admin)

Change a user's role. Requires admin role.

```http
PATCH /users/{user_id}/role
Authorization: Bearer <token>
Content-Type: application/json
```

**Request Body**:
```json
{
  "role": "admin"
}
```

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "role": "admin",
    "updated_at": "2025-01-15T10:30:00.000Z"
  }
}
```

---

### 2.8 Suspend User (Admin)

Suspend a user account. Requires admin role.

```http
POST /users/{user_id}/suspend
Authorization: Bearer <token>
Content-Type: application/json
```

**Request Body**:
```json
{
  "reason": "Policy violation"
}
```

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "status": "suspended",
    "updated_at": "2025-01-15T10:30:00.000Z"
  }
}
```

---

### 2.9 Reactivate User (Admin)

Reactivate a suspended user. Requires admin role.

```http
POST /users/{user_id}/reactivate
Authorization: Bearer <token>
```

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "status": "active",
    "updated_at": "2025-01-15T10:30:00.000Z"
  }
}
```

---

### 2.10 Delete User (Owner)

Permanently delete a user. Requires owner role.

```http
DELETE /users/{user_id}
Authorization: Bearer <token>
```

**Query Parameters**:
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `confirm` | boolean | Yes | Must be `true` |

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "message": "User deleted",
    "deleted_at": "2025-01-15T10:30:00.000Z"
  }
}
```

---

### 2.11 Get User Storage Usage

Get storage statistics for a user.

```http
GET /users/{user_id}/storage
Authorization: Bearer <token>
```

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "user_id": "550e8400-e29b-41d4-a716-446655440000",
    "used_bytes": 1073741824,
    "file_count": 150,
    "folder_count": 25,
    "tenant_quota_bytes": 10737418240,
    "tenant_used_bytes": 5368709120
  }
}
```

## 3. Error Responses

| Code | HTTP | Description |
|------|------|-------------|
| `E_USER_NOT_FOUND` | 404 | User does not exist |
| `E_USER_SUSPENDED` | 403 | User account is suspended |
| `E_INSUFFICIENT_ROLE` | 403 | Requires higher role |
| `E_CANNOT_MODIFY_SELF` | 400 | Cannot change own role/status |
| `E_CANNOT_DELETE_OWNER` | 400 | Cannot delete tenant owner |
| `E_INVALID_ROLE` | 400 | Invalid role value |
| `E_KEY_ROTATION_INVALID` | 400 | Invalid rotation signature |
