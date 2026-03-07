# Sharing API

**Version**: 1.1.0
**Status**: Draft
**Last Updated**: 2026-01

## 1. Overview

Share management endpoints for granting, managing, and revoking access to files and folders. Shares are cryptographically signed by the grantor.

**Base URL**: `https://api.securesharing.com/v1`

**Authentication**: All endpoints require `Authorization: Bearer <token>` header.

## 2. Endpoints

### 2.1 Create Share

Grant access to a file or folder.

```http
POST /shares
Authorization: Bearer <token>
Content-Type: application/json
```

**Request Body**:
```json
{
  "resource_type": "file",
  "resource_id": "550e8400-e29b-41d4-a716-446655440000",
  "grantee_id": "660e8400-e29b-41d4-a716-446655440001",
  "wrapped_key": "base64...",
  "kem_ciphertexts": [
    {"algorithm": "ML-KEM-768", "ciphertext": "base64..."},
    {"algorithm": "KAZ-KEM", "ciphertext": "base64..."}
  ],
  "permission": "read",
  "recursive": false,
  "expiry": "2025-02-15T10:30:00.000Z",
  "signature": {
    "ml_dsa": "base64...",
    "kaz_sign": "base64..."
  }
}
```

**Request Fields**:
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `resource_type` | string | Yes | `file` or `folder` |
| `resource_id` | UUID | Yes | File or folder ID |
| `grantee_id` | UUID | Yes | User receiving access |
| `wrapped_key` | Base64 | Yes | DEK/KEK encrypted for grantee |
| `kem_ciphertexts` | array | Yes | KEM ciphertexts |
| `permission` | string | Yes | `read`, `write`, or `admin` |
| `recursive` | boolean | No | For folders: include children |
| `expiry` | ISO8601 | No | When share expires |
| `created_at` | ISO8601 | Yes | Client timestamp (for signature) |
| `signature` | object | Yes | Grantor's signature |

**Signature Payload** (see `crypto/05-signature-protocol.md` section 4.2):

The signature must cover ALL of the following fields in canonical order:
```
CanonicalSerialize({
  resourceType, resourceId, grantorId, granteeId,
  wrappedKey, kemCiphertexts, permission, recursive,
  expiry, createdAt
})
```

Server derives `grantorId` from the authenticated session.

**Response** `201 Created`:
```json
{
  "success": true,
  "data": {
    "id": "770e8400-e29b-41d4-a716-446655440002",
    "resource_type": "file",
    "resource_id": "550e8400-e29b-41d4-a716-446655440000",
    "grantor_id": "880e8400-e29b-41d4-a716-446655440003",
    "grantee_id": "660e8400-e29b-41d4-a716-446655440001",
    "permission": "read",
    "recursive": false,
    "expiry": "2025-02-15T10:30:00.000Z",
    "created_at": "2025-01-15T10:30:00.000Z"
  }
}
```

---

### 2.2 Get Share

Get share details.

```http
GET /shares/{share_id}
Authorization: Bearer <token>
```

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "id": "770e8400-e29b-41d4-a716-446655440002",
    "resource_type": "file",
    "resource_id": "550e8400-e29b-41d4-a716-446655440000",
    "grantor": {
      "id": "880e8400-e29b-41d4-a716-446655440003",
      "email": "alice@example.com",
      "display_name": "Alice",
      "public_keys": {
        "ml_dsa": "base64...",
        "kaz_sign": "base64..."
      }
    },
    "grantee_id": "660e8400-e29b-41d4-a716-446655440001",
    "wrapped_key": "base64...",
    "kem_ciphertexts": [
      {"algorithm": "ML-KEM-768", "ciphertext": "base64..."},
      {"algorithm": "KAZ-KEM", "ciphertext": "base64..."}
    ],
    "permission": "read",
    "recursive": false,
    "expiry": "2025-02-15T10:30:00.000Z",
    "signature": {
      "ml_dsa": "base64...",
      "kaz_sign": "base64..."
    },
    "created_at": "2025-01-15T10:30:00.000Z",
    "file": {
      "blob_hash": "a1b2c3d4e5f67890..."
    }
  }
}
```

> **Client Verification**: Clients MUST verify `signature` using `grantor.public_keys` before decrypting `wrapped_key`. For file shares, verify `file.blob_hash` matches downloaded blob. See [Signature Protocol](../crypto/05-signature-protocol.md) Section 4.2.

> **Note**: The `file` object is only present when `resource_type` is `file`. For folder shares, `file` is omitted.

---

### 2.3 List Shares Granted

List shares created by current user.

```http
GET /shares/granted
Authorization: Bearer <token>
```

**Query Parameters**:
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `resource_type` | string | - | Filter by `file` or `folder` |
| `resource_id` | UUID | - | Filter by specific resource |
| `grantee_id` | UUID | - | Filter by grantee |
| `limit` | integer | 20 | Items per page |
| `offset` | integer | 0 | Pagination offset |

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "items": [
      {
        "id": "770e8400-e29b-41d4-a716-446655440002",
        "resource_type": "file",
        "resource_id": "550e8400-e29b-41d4-a716-446655440000",
        "grantee": {
          "id": "660e8400-e29b-41d4-a716-446655440001",
          "email": "bob@example.com",
          "display_name": "Bob"
        },
        "permission": "read",
        "expiry": "2025-02-15T10:30:00.000Z",
        "created_at": "2025-01-15T10:30:00.000Z"
      }
    ],
    "pagination": {
      "total": 15,
      "limit": 20,
      "offset": 0,
      "has_more": false
    }
  }
}
```

---

### 2.4 List Shares Received

List shares received by current user.

```http
GET /shares/received
Authorization: Bearer <token>
```

**Query Parameters**:
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `resource_type` | string | - | Filter by `file` or `folder` |
| `grantor_id` | UUID | - | Filter by grantor |
| `limit` | integer | 20 | Items per page |
| `offset` | integer | 0 | Pagination offset |

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "items": [
      {
        "id": "770e8400-e29b-41d4-a716-446655440002",
        "resource_type": "folder",
        "resource_id": "550e8400-e29b-41d4-a716-446655440000",
        "grantor": {
          "id": "880e8400-e29b-41d4-a716-446655440003",
          "email": "alice@example.com",
          "display_name": "Alice",
          "public_keys": {
            "ml_dsa": "base64...",
            "kaz_sign": "base64..."
          }
        },
        "wrapped_key": "base64...",
        "kem_ciphertexts": [
          {"algorithm": "ML-KEM-768", "ciphertext": "base64..."},
          {"algorithm": "KAZ-KEM", "ciphertext": "base64..."}
        ],
        "permission": "write",
        "recursive": true,
        "expiry": null,
        "signature": {
          "ml_dsa": "base64...",
          "kaz_sign": "base64..."
        },
        "created_at": "2025-01-15T10:30:00.000Z"
      }
    ],
    "pagination": {
      "total": 8,
      "limit": 20,
      "offset": 0,
      "has_more": false
    }
  }
}
```

> **Client Verification**: Clients MUST verify `signature` using `grantor.public_keys` before decrypting `wrapped_key`. For file shares, verify `file.blob_hash` matches downloaded blob. See [Signature Protocol](../crypto/05-signature-protocol.md) Section 4.2.

> **Note**: For file shares, each item includes a `file` object with `blob_hash`. The example above shows a folder share (no `file` object).

---

### 2.5 List Shares for Resource

List all shares for a specific resource.

```http
GET /shares/resource/{resource_type}/{resource_id}
Authorization: Bearer <token>
```

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "resource": {
      "type": "folder",
      "id": "550e8400-e29b-41d4-a716-446655440000"
    },
    "shares": [
      {
        "id": "770e8400-e29b-41d4-a716-446655440002",
        "grantee": {
          "id": "660e8400-e29b-41d4-a716-446655440001",
          "email": "bob@example.com",
          "display_name": "Bob"
        },
        "permission": "read",
        "recursive": true,
        "expiry": null,
        "created_at": "2025-01-15T10:30:00.000Z"
      },
      {
        "id": "880e8400-e29b-41d4-a716-446655440004",
        "grantee": {
          "id": "990e8400-e29b-41d4-a716-446655440005",
          "email": "carol@example.com",
          "display_name": "Carol"
        },
        "permission": "write",
        "recursive": false,
        "expiry": "2025-03-01T00:00:00.000Z",
        "created_at": "2025-01-20T10:30:00.000Z"
      }
    ]
  }
}
```

---

### 2.6 Update Share Permission

Update a share's permission level.

```http
PATCH /shares/{share_id}
Authorization: Bearer <token>
Content-Type: application/json
```

**Request Body**:
```json
{
  "permission": "write",
  "expiry": "2025-03-15T10:30:00.000Z",
  "updated_at": "2025-01-15T10:30:00.000Z",
  "signature": {
    "ml_dsa": "base64...",
    "kaz_sign": "base64..."
  }
}
```

**Request Fields**:
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `permission` | string | No | New permission level |
| `expiry` | ISO8601 | No | New expiry time (null to remove) |
| `updated_at` | ISO8601 | Yes | Client timestamp (for signature) |
| `signature` | object | Yes | Updater's signature |

**Signature Payload** (see `crypto/05-signature-protocol.md` section 4.5):

The signature must cover ALL of the following fields:
```
CanonicalSerialize({
  shareId,
  originalCreatedAt,  // From the original share grant
  permission,
  expiry,
  updatedAt
})
```

Server retrieves `originalCreatedAt` from the existing share record.

**Notes**:
- Only grantor or resource admin can update
- Cannot modify `recursive`, `wrappedKey`, `kemCiphertexts`, or `granteeId`
- To change those fields, revoke and create a new share

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "id": "770e8400-e29b-41d4-a716-446655440002",
    "permission": "write",
    "expiry": "2025-03-15T10:30:00.000Z",
    "updated_at": "2025-01-15T10:30:00.000Z"
  }
}
```

---

### 2.7 Revoke Share

Revoke a share (delete it).

```http
DELETE /shares/{share_id}
Authorization: Bearer <token>
```

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "message": "Share revoked",
    "revoked_at": "2025-01-15T10:30:00.000Z"
  }
}
```

---

### 2.8 Bulk Revoke Shares

Revoke multiple shares at once.

```http
POST /shares/revoke-bulk
Authorization: Bearer <token>
Content-Type: application/json
```

**Request Body**:
```json
{
  "share_ids": [
    "770e8400-e29b-41d4-a716-446655440002",
    "880e8400-e29b-41d4-a716-446655440003"
  ]
}
```

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "revoked": 2,
    "failed": 0
  }
}
```

---

### 2.9 Revoke All Shares for Resource

Revoke all shares for a specific resource.

```http
DELETE /shares/resource/{resource_type}/{resource_id}
Authorization: Bearer <token>
```

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "revoked_count": 5,
    "revoked_at": "2025-01-15T10:30:00.000Z"
  }
}
```

---

### 2.10 Verify Share Signature

Verify a share's cryptographic signature.

```http
POST /shares/{share_id}/verify
Authorization: Bearer <token>
```

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "valid": true,
    "verified_at": "2025-01-15T10:30:00.000Z",
    "grantor": {
      "id": "880e8400-e29b-41d4-a716-446655440003",
      "email": "alice@example.com"
    }
  }
}
```

**Response (Invalid)** `200 OK`:
```json
{
  "success": true,
  "data": {
    "valid": false,
    "reason": "signature_mismatch"
  }
}
```

---

### 2.11 Create Share Link (URL Sharing)

Create a shareable link (for external sharing).

```http
POST /shares/link
Authorization: Bearer <token>
Content-Type: application/json
```

**Request Body**:
```json
{
  "resource_type": "file",
  "resource_id": "550e8400-e29b-41d4-a716-446655440000",
  "wrapped_key": "base64...",
  "permission": "read",
  "expiry": "2025-02-15T10:30:00.000Z",
  "password_protected": true,
  "password_salt": "base64...",
  "password_hash": "base64...",
  "max_downloads": 10,
  "created_at": "2025-01-15T10:30:00.000Z",
  "signature": {
    "ml_dsa": "base64...",
    "kaz_sign": "base64..."
  }
}
```

**Request Fields**:
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `resource_type` | string | Yes | `file` or `folder` |
| `resource_id` | UUID | Yes | File or folder ID |
| `wrapped_key` | Base64 | Yes | DEK (for files) or KEK (for folders) wrapped for link access |
| `permission` | string | Yes | `read` only for links |
| `expiry` | ISO8601 | No | When link expires |
| `password_protected` | boolean | Yes | Whether password is required |
| `password_salt` | Base64 | If protected | Random salt for Argon2id |
| `password_hash` | Base64 | If protected | `Argon2id(password, salt)` for verification |
| `max_downloads` | integer | No | Maximum download count |
| `created_at` | ISO8601 | Yes | Client timestamp (for signature) |
| `signature` | object | Yes | Creator's signature |

**Signature Payload** (see `crypto/05-signature-protocol.md`):
```
CanonicalSerialize({
  resourceType, resourceId, creatorId, wrappedKey,
  permission, expiry, passwordProtected, maxDownloads, createdAt
})
```

**Notes**:
- Creates anonymous share accessible via link
- `wrapped_key`:
  - **Files**: DEK wrapped with password-derived key (if protected) or symmetric key embedded in URL fragment (if not)
  - **Folders**: KEK wrapped similarly; grants access to all folder contents
- `password_hash`: Server stores this to verify password on access (client computes `Argon2id(password, salt)`)
- Recipient decrypts with link + password
- **Folder links**: Provide browse access to folder contents; each file/subfolder is decrypted using the shared KEK

**Response** `201 Created`:
```json
{
  "success": true,
  "data": {
    "id": "aa0e8400-e29b-41d4-a716-446655440006",
    "link": "https://securesharing.com/s/abc123xyz",
    "expiry": "2025-02-15T10:30:00.000Z",
    "password_protected": true,
    "max_downloads": 10,
    "download_count": 0
  }
}
```

---

### 2.12 Get Share Link

Retrieve share link details (anonymous access supported).

```http
GET /shares/link/{token}
```

**Notes**:
- No authentication required for public links
- Returns minimal info until password verified (if protected)

**Response** `200 OK` (unprotected link):
```json
{
  "success": true,
  "data": {
    "id": "aa0e8400-e29b-41d4-a716-446655440006",
    "resource_type": "file",
    "password_protected": false,
    "permission": "read",
    "expiry": "2025-02-15T10:30:00.000Z",
    "expired": false,
    "download_count": 3,
    "max_downloads": 10,
    "owner": {
      "id": "880e8400-e29b-41d4-a716-446655440003",
      "public_keys": {
        "ml_dsa": "base64...",
        "kaz_sign": "base64..."
      }
    },
    "wrapped_key": "base64...",
    "created_at": "2025-01-15T10:30:00.000Z",
    "signature": {
      "ml_dsa": "base64...",
      "kaz_sign": "base64..."
    },
    "file": {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "encrypted_metadata": "base64...",
      "metadata_nonce": "base64...",
      "wrapped_dek": "base64...",
      "blob_size": 1048576,
      "blob_hash": "a1b2c3d4e5f67890...",
      "signature": {
        "ml_dsa": "base64...",
        "kaz_sign": "base64..."
      },
      "owner": {
        "id": "770e8400-e29b-41d4-a716-446655440003",
        "public_keys": {
          "ml_dsa": "base64...",
          "kaz_sign": "base64..."
        }
      }
    }
  }
}
```

**Response Fields** (file link):
| Field | Type | Description |
|-------|------|-------------|
| `wrapped_key` | Base64 | DEK wrapped with key embedded in URL fragment |
| `created_at` | ISO8601 | Creation timestamp (included in signature payload) |
| `signature` | object | Creator's signature over share link parameters |
| `owner.public_keys` | object | Creator's public keys for share link signature verification |
| `file` | object | File details (present when `resource_type: "file"`) |
| `file.wrapped_dek` | Base64 | Original DEK wrapped by folder KEK (for file signature verification) |
| `file.blob_hash` | hex | SHA-256 of encrypted blob (verify after download) |
| `file.signature` | object | File owner's signature (for file authenticity verification) |
| `file.owner` | object | File owner's info and public keys (for file signature verification) |

> **Client Verification**: Clients MUST perform TWO signature verifications:
> 1. **Share Link Signature**: Verify `signature` using `owner.public_keys` to authenticate the share link itself
> 2. **File Signature**: Verify `file.signature` using `file.owner.public_keys` to authenticate the file content
>
> See [Signature Protocol](../crypto/05-signature-protocol.md) Sections 4.6 (share link) and 4.1 (file).
>
> **Note**: Share links do NOT use KEM encapsulation. The key is wrapped with either a symmetric key embedded in the URL fragment (unprotected) or a password-derived key (protected).

**Response** `200 OK` (folder link, unprotected):
```json
{
  "success": true,
  "data": {
    "id": "bb0e8400-e29b-41d4-a716-446655440007",
    "resource_type": "folder",
    "password_protected": false,
    "permission": "read",
    "expiry": "2025-02-15T10:30:00.000Z",
    "expired": false,
    "download_count": 5,
    "max_downloads": null,
    "owner": {
      "id": "880e8400-e29b-41d4-a716-446655440003",
      "public_keys": {
        "ml_dsa": "base64...",
        "kaz_sign": "base64..."
      }
    },
    "wrapped_key": "base64...",
    "created_at": "2025-01-15T10:30:00.000Z",
    "signature": {
      "ml_dsa": "base64...",
      "kaz_sign": "base64..."
    },
    "folder": {
      "id": "cc0e8400-e29b-41d4-a716-446655440008",
      "parent_id": "dd0e8400-e29b-41d4-a716-446655440009",
      "encrypted_metadata": "base64...",
      "metadata_nonce": "base64...",
      "owner_key_access": {
        "wrapped_kek": "base64...",
        "kem_ciphertexts": [
          {"algorithm": "ML-KEM-768", "ciphertext": "base64..."},
          {"algorithm": "KAZ-KEM", "ciphertext": "base64..."}
        ]
      },
      "wrapped_kek": "base64...",
      "signature": {
        "ml_dsa": "base64...",
        "kaz_sign": "base64..."
      },
      "owner": {
        "id": "ee0e8400-e29b-41d4-a716-44665544000a",
        "public_keys": {
          "ml_dsa": "base64...",
          "kaz_sign": "base64..."
        }
      },
      "item_count": 12,
      "created_at": "2025-01-10T00:00:00.000Z"
    }
  }
}
```

**Response Fields** (folder link):
| Field | Type | Description |
|-------|------|-------------|
| `wrapped_key` | Base64 | KEK wrapped with key embedded in URL fragment |
| `folder` | object | Folder details (present when `resource_type: "folder"`) |
| `folder.parent_id` | UUID | Parent folder ID (for signature verification) |
| `folder.owner_key_access` | object | KEK wrapped for owner (for signature verification) |
| `folder.wrapped_kek` | Base64 | KEK wrapped by parent's KEK (for signature verification) |
| `folder.signature` | object | Folder owner's signature |
| `folder.owner` | object | Folder owner's info and public keys |
| `folder.item_count` | integer | Number of items in folder (files + subfolders) |
| `folder.created_at` | ISO8601 | Creation timestamp (for signature verification) |

> **Mandatory Verification**: Clients MUST verify BOTH signatures before accessing folder contents:
> 1. Share link signature: Verify `signature` using `owner.public_keys` (share link creator)
> 2. Folder signature: Verify `folder.signature` using `folder.owner.public_keys` (folder owner)
>
> See [Signature Protocol](../crypto/05-signature-protocol.md) Sections 4.4 (folder) and 4.6 (share link).

> **Folder Access**: After verification, use `GET /shares/link/{token}/contents` to list and access folder contents. Each file's DEK and subfolder's KEK are wrapped by this folder's KEK.

**Response** `200 OK` (password-protected, not verified):
```json
{
  "success": true,
  "data": {
    "id": "aa0e8400-e29b-41d4-a716-446655440006",
    "resource_type": "file",
    "password_protected": true,
    "password_verified": false,
    "password_salt": "base64...",
    "expiry": "2025-02-15T10:30:00.000Z",
    "expired": false
  }
}
```

---

### 2.13 Verify Share Link Password

Verify password for a protected share link.

```http
POST /shares/link/{token}/verify
Content-Type: application/json
```

**Request Body**:
```json
{
  "password_hash": "base64..."
}
```

**Notes**:
- `password_hash`: Client computes `Argon2id(password, password_salt)` and sends hash
- Server verifies hash matches stored value
- Returns session token for subsequent requests

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "verified": true,
    "session_token": "link-session-abc123",
    "expires_at": "2025-01-15T11:30:00.000Z",
    "resource_type": "file",
    "permission": "read",
    "expiry": "2025-02-15T10:30:00.000Z",
    "password_protected": true,
    "max_downloads": 10,
    "owner": {
      "id": "880e8400-e29b-41d4-a716-446655440003",
      "public_keys": {
        "ml_dsa": "base64...",
        "kaz_sign": "base64..."
      }
    },
    "wrapped_key": "base64...",
    "created_at": "2025-01-15T10:30:00.000Z",
    "signature": {
      "ml_dsa": "base64...",
      "kaz_sign": "base64..."
    },
    "file": {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "encrypted_metadata": "base64...",
      "metadata_nonce": "base64...",
      "wrapped_dek": "base64...",
      "blob_size": 1048576,
      "blob_hash": "a1b2c3d4e5f67890...",
      "signature": {
        "ml_dsa": "base64...",
        "kaz_sign": "base64..."
      },
      "owner": {
        "id": "770e8400-e29b-41d4-a716-446655440003",
        "public_keys": {
          "ml_dsa": "base64...",
          "kaz_sign": "base64..."
        }
      }
    }
  }
}
```

**Response** `200 OK` (folder link, password verified):
```json
{
  "success": true,
  "data": {
    "verified": true,
    "session_token": "link-session-def456",
    "expires_at": "2025-01-15T11:30:00.000Z",
    "resource_type": "folder",
    "permission": "read",
    "expiry": "2025-02-15T10:30:00.000Z",
    "password_protected": true,
    "max_downloads": null,
    "owner": {
      "id": "880e8400-e29b-41d4-a716-446655440003",
      "public_keys": {
        "ml_dsa": "base64...",
        "kaz_sign": "base64..."
      }
    },
    "wrapped_key": "base64...",
    "created_at": "2025-01-15T10:30:00.000Z",
    "signature": {
      "ml_dsa": "base64...",
      "kaz_sign": "base64..."
    },
    "folder": {
      "id": "cc0e8400-e29b-41d4-a716-446655440008",
      "parent_id": "dd0e8400-e29b-41d4-a716-446655440009",
      "encrypted_metadata": "base64...",
      "metadata_nonce": "base64...",
      "owner_key_access": {
        "wrapped_kek": "base64...",
        "kem_ciphertexts": [
          {"algorithm": "ML-KEM-768", "ciphertext": "base64..."},
          {"algorithm": "KAZ-KEM", "ciphertext": "base64..."}
        ]
      },
      "wrapped_kek": "base64...",
      "signature": {
        "ml_dsa": "base64...",
        "kaz_sign": "base64..."
      },
      "owner": {
        "id": "ee0e8400-e29b-41d4-a716-44665544000a",
        "public_keys": {
          "ml_dsa": "base64...",
          "kaz_sign": "base64..."
        }
      },
      "item_count": 12,
      "created_at": "2025-01-10T00:00:00.000Z"
    }
  }
}
```

**Response Fields** (all fields needed for signature verification):
| Field | Type | Description |
|-------|------|-------------|
| `session_token` | string | Token for authenticated link access (include in subsequent requests) |
| `resource_type` | string | `"file"` or `"folder"` (signature payload) |
| `permission` | string | `"read"` (signature payload) |
| `expiry` | ISO8601 \| null | Link expiration (signature payload) |
| `password_protected` | boolean | Always `true` for this response (signature payload) |
| `max_downloads` | int \| null | Download limit (signature payload) |
| `owner.id` | UUID | Creator ID (signature payload `creatorId`) |
| `owner.public_keys` | object | Creator's public keys for share link signature verification |
| `wrapped_key` | Base64 | DEK (file) or KEK (folder) wrapped with password-derived key |
| `created_at` | ISO8601 | Creation timestamp (signature payload) |
| `signature` | object | Creator's signature over share link parameters |
| `file` / `folder` | object | Resource details; `.id` = signature payload `resourceId` |
| `file.wrapped_dek` | Base64 | Original DEK wrapped by folder KEK (for file signature verification) |
| `file.signature` | object | File owner's signature (for file authenticity verification) |
| `file.owner` | object | File owner's info and public keys (for file signature verification) |
| `folder.parent_id` | UUID | Parent folder ID (for folder signature verification) |
| `folder.owner_key_access` | object | KEK wrapped for owner (for folder signature verification) |
| `folder.wrapped_kek` | Base64 | KEK wrapped by parent's KEK (for folder signature verification) |
| `folder.signature` | object | Folder owner's signature (for folder authenticity verification) |
| `folder.owner` | object | Folder owner's info and public keys (for folder signature verification) |
| `folder.created_at` | ISO8601 | Folder creation timestamp (for folder signature verification) |

> **Client Verification**: After password verification, clients MUST perform TWO signature verifications:
> 1. **Share Link Signature**: Verify `signature` using `owner.public_keys` to authenticate the share link itself
> 2. **Resource Signature**: Verify `file.signature` / `folder.signature` using the resource owner's public keys to authenticate the content
>
> See [Signature Protocol](../crypto/05-signature-protocol.md) Sections 4.6 (share link), 4.1 (file), and 4.4 (folder).

**Response** `401 Unauthorized` (wrong password):
```json
{
  "success": false,
  "error": {
    "code": "E_INVALID_PASSWORD",
    "message": "Invalid password"
  }
}
```

---

### 2.14 Get Share Link Download URL

Get pre-signed download URL for share link.

```http
GET /shares/link/{token}/download
```

**Headers** (for password-protected links):
```
X-Link-Session: link-session-abc123
```

**Notes**:
- For unprotected links: no session required
- For protected links: requires valid session token from password verification
- Increments download counter

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "download": {
      "url": "https://storage.securesharing.com/download/...",
      "method": "GET",
      "headers": {},
      "expires_at": "2025-01-15T11:30:00.000Z"
    },
    "file": {
      "blob_size": 1048576,
      "blob_hash": "a1b2c3d4e5f67890..."
    },
    "download_count": 4,
    "max_downloads": 10
  }
}
```

---

### 2.15 Get Share Link Folder Contents

List contents of a folder accessed via share link.

```http
GET /shares/link/{token}/contents
```

**Headers** (for password-protected links):
```
X-Link-Session: link-session-abc123
```

**Query Parameters**:
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `path` | string | `/` | Subfolder path within shared folder |

**Notes**:
- Only valid for folder share links (`resource_type: "folder"`)
- Returns wrapped keys for each item (DEKs for files, KEKs for subfolders)
- All keys are wrapped by the parent folder's KEK (which client obtained from share link)
- Does NOT increment download counter (browsing only)

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "folder": {
      "id": "cc0e8400-e29b-41d4-a716-446655440008",
      "parent_id": "bb0e8400-e29b-41d4-a716-446655440007",
      "encrypted_metadata": "base64...",
      "metadata_nonce": "base64...",
      "owner_key_access": {
        "wrapped_kek": "base64...",
        "kem_ciphertexts": [
          {"algorithm": "ML-KEM-768", "ciphertext": "base64..."},
          {"algorithm": "KAZ-KEM", "ciphertext": "base64..."}
        ]
      },
      "wrapped_kek": "base64...",
      "signature": {
        "ml_dsa": "base64...",
        "kaz_sign": "base64..."
      },
      "owner": {
        "id": "ff0e8400-e29b-41d4-a716-446655440011",
        "public_keys": {
          "ml_dsa": "base64...",
          "kaz_sign": "base64..."
        }
      },
      "created_at": "2025-01-15T10:30:00.000Z"
    },
    "path": "/",
    "items": {
      "files": [
        {
          "id": "dd0e8400-e29b-41d4-a716-446655440009",
          "encrypted_metadata": "base64...",
          "metadata_nonce": "base64...",
          "wrapped_dek": "base64...",
          "blob_size": 1048576,
          "blob_hash": "a1b2c3d4e5f67890...",
          "signature": {
            "ml_dsa": "base64...",
            "kaz_sign": "base64..."
          },
          "owner": {
            "id": "ff0e8400-e29b-41d4-a716-446655440011",
            "public_keys": {
              "ml_dsa": "base64...",
              "kaz_sign": "base64..."
            }
          }
        }
      ],
      "subfolders": [
        {
          "id": "ee0e8400-e29b-41d4-a716-446655440010",
          "parent_id": "cc0e8400-e29b-41d4-a716-446655440008",
          "encrypted_metadata": "base64...",
          "metadata_nonce": "base64...",
          "owner_key_access": {
            "wrapped_kek": "base64...",
            "kem_ciphertexts": [
              {"algorithm": "ML-KEM-768", "ciphertext": "base64..."},
              {"algorithm": "KAZ-KEM", "ciphertext": "base64..."}
            ]
          },
          "wrapped_kek": "base64...",
          "signature": {
            "ml_dsa": "base64...",
            "kaz_sign": "base64..."
          },
          "owner": {
            "id": "ff0e8400-e29b-41d4-a716-446655440011",
            "public_keys": {
              "ml_dsa": "base64...",
              "kaz_sign": "base64..."
            }
          },
          "item_count": 5,
          "created_at": "2025-01-15T10:30:00.000Z"
        }
      ]
    }
  }
}
```

**Response Fields**:
| Field | Type | Description |
|-------|------|-------------|
| `folder.signature` | object | Current folder's owner signature |
| `folder.owner` | object | Current folder's owner public keys |
| `items.files[].wrapped_dek` | Base64 | File's DEK wrapped by folder KEK |
| `items.files[].signature` | object | File owner's signature (for verification) |
| `items.files[].owner` | object | File owner's public keys (for verification) |
| `items.subfolders[].wrapped_kek` | Base64 | Subfolder's KEK wrapped by parent KEK |
| `items.subfolders[].signature` | object | Subfolder owner's signature (for verification) |
| `items.subfolders[].owner` | object | Subfolder owner's public keys (for verification) |

> **Client Verification**: Clients MUST verify `signature` using `owner.public_keys` for the
> folder, each subfolder, and each file BEFORE trusting metadata or keys.
> See [Signature Protocol](../crypto/05-signature-protocol.md) Sections 4.1 (files) and 4.4 (folders).

**Decryption Flow**:
1. Client unwraps folder KEK using link key (from URL fragment or password)
2. For files: unwrap `wrapped_dek` with folder KEK, decrypt file
3. For subfolders: unwrap `wrapped_kek` with folder KEK, use to access subfolder contents

**Response** `400 Bad Request` (not a folder link):
```json
{
  "success": false,
  "error": {
    "code": "E_NOT_FOLDER_LINK",
    "message": "This endpoint is only valid for folder share links"
  }
}
```

---

### 2.16 Download File via Folder Share Link

Download a specific file from within a shared folder.

```http
GET /shares/link/{token}/download/{file_id}
```

**Headers** (for password-protected links):
```
X-Link-Session: link-session-abc123
```

**Notes**:
- File must be within the shared folder (direct child or in subfolder)
- Increments download counter on the share link
- Returns pre-signed download URL

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "download": {
      "url": "https://storage.securesharing.com/download/...",
      "method": "GET",
      "headers": {},
      "expires_at": "2025-01-15T11:30:00.000Z"
    },
    "file": {
      "id": "dd0e8400-e29b-41d4-a716-446655440009",
      "blob_size": 1048576,
      "blob_hash": "a1b2c3d4e5f67890..."
    },
    "download_count": 5,
    "max_downloads": null
  }
}
```

---

### 2.17 Revoke Share Link

Revoke (delete) a share link.

```http
DELETE /shares/link/{link_id}
Authorization: Bearer <token>
```

**Notes**:
- Only the link creator can revoke
- Uses link ID (UUID), not the token

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "message": "Share link revoked",
    "revoked_at": "2025-01-15T10:30:00.000Z"
  }
}
```

---

### 2.18 List Share Links

List share links created by current user.

```http
GET /shares/links
Authorization: Bearer <token>
```

**Query Parameters**:
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `resource_type` | string | - | Filter by `file` or `folder` |
| `resource_id` | UUID | - | Filter by specific resource |
| `limit` | integer | 20 | Items per page |
| `offset` | integer | 0 | Pagination offset |

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "items": [
      {
        "id": "aa0e8400-e29b-41d4-a716-446655440006",
        "resource_type": "file",
        "resource_id": "550e8400-e29b-41d4-a716-446655440000",
        "token": "abc123xyz",
        "link": "https://securesharing.com/s/abc123xyz",
        "permission": "read",
        "password_protected": true,
        "expiry": "2025-02-15T10:30:00.000Z",
        "max_downloads": 10,
        "download_count": 3,
        "created_at": "2025-01-15T10:30:00.000Z"
      }
    ],
    "pagination": {
      "total": 5,
      "limit": 20,
      "offset": 0,
      "has_more": false
    }
  }
}
```

---

## 3. Permission Levels

### 3.1 Share Permissions

These are the valid values for the `permission` field when creating or updating shares:

| Permission | Can Download | Can Upload | Can Share | Can Delete |
|------------|--------------|------------|-----------|------------|
| `read` | Yes | No | No | No |
| `write` | Yes | Yes | No | No |
| `admin` | Yes | Yes | Yes | No |

### 3.2 Access Levels (API Responses)

When retrieving files/folders, the `access.permission` field may also include `owner`:

| Access Level | Can Download | Can Upload | Can Share | Can Delete | Notes |
|--------------|--------------|------------|-----------|------------|-------|
| `read` | Yes | No | No | No | Via share |
| `write` | Yes | Yes | No | No | Via share |
| `admin` | Yes | Yes | Yes | No | Via share |
| `owner` | Yes | Yes | Yes | Yes | Resource owner |

> **IMPORTANT**: `owner` is NOT a valid share permission. It is only returned in
> `access.permission` to indicate the current user owns the resource. You cannot
> grant `owner` permission via sharing—use `admin` for full delegated access.

## 4. Recursive Sharing

When `recursive: true` for folder shares:
- Grantee can access all files in folder
- Grantee can access all subfolders
- Grantee can access files in subfolders
- New items added later are automatically accessible

## 5. Error Responses

| Code | HTTP | Description |
|------|------|-------------|
| `E_SHARE_NOT_FOUND` | 404 | Share does not exist |
| `E_SHARE_EXPIRED` | 400 | Share has expired |
| `E_SHARE_EXISTS` | 409 | Share already exists |
| `E_CANNOT_SHARE_SELF` | 400 | Cannot share with yourself |
| `E_PERMISSION_DENIED` | 403 | Cannot share with this permission |
| `E_SIGNATURE_INVALID` | 400 | Share signature invalid |
| `E_RESOURCE_NOT_FOUND` | 404 | File/folder not found |
| `E_GRANTEE_NOT_FOUND` | 404 | Grantee user not found |
| `E_LINK_MAX_DOWNLOADS` | 400 | Link download limit reached |
| `E_LINK_NOT_FOUND` | 404 | Share link does not exist |
| `E_LINK_EXPIRED` | 400 | Share link has expired |
| `E_INVALID_PASSWORD` | 401 | Incorrect link password |
| `E_SESSION_INVALID` | 401 | Invalid or missing link session |
| `E_SESSION_EXPIRED` | 401 | Link session has expired |
