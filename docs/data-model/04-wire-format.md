# Wire Format Specification

**Version**: 1.0.0
**Status**: Draft
**Last Updated**: 2025-01

## 1. Overview

This document specifies the JSON wire format for API requests and responses. All API communication uses JSON over HTTPS.

## 2. General Conventions

### 2.0 Base URL

All endpoint paths in this document are relative to the API base URL:

```
https://api.securesharing.com/v1
```

Example: `POST /auth/register` → `https://api.securesharing.com/v1/auth/register`

For client applications using same-origin requests, the equivalent path would be `/api/v1/auth/register` (proxied to the API).

### 2.1 Encoding

- **Character encoding**: UTF-8
- **Binary data**: Base64 (standard alphabet with padding)
- **Timestamps**: ISO 8601 with timezone (`2025-01-15T10:30:00.000Z`)
- **UUIDs**: Lowercase with hyphens (`550e8400-e29b-41d4-a716-446655440000`)

### 2.2 Field Naming

- Use `snake_case` for all field names
- Consistent naming: `created_at`, `updated_at`, `tenant_id`, etc.

### 2.3 Null vs Absent

- `null`: Field exists but has no value
- Absent: Field not included in response (for optional fields)

## 3. Request Formats

### 3.1 User Registration

```json
POST /auth/register
Content-Type: application/json

{
  "email": "user@example.com",
  "display_name": "John Doe",
  "public_keys": {
    "ml_kem": "base64...",
    "ml_dsa": "base64...",
    "kaz_kem": "base64...",
    "kaz_sign": "base64..."
  },
  "encrypted_master_key": "base64...",
  "mk_nonce": "base64...",
  "encrypted_private_keys": {
    "ml_kem": {
      "ciphertext": "base64...",
      "nonce": "base64..."
    },
    "ml_dsa": {
      "ciphertext": "base64...",
      "nonce": "base64..."
    },
    "kaz_kem": {
      "ciphertext": "base64...",
      "nonce": "base64..."
    },
    "kaz_sign": {
      "ciphertext": "base64...",
      "nonce": "base64..."
    }
  }
}
```

### 3.2 File Upload Initiation

```json
POST /files
Content-Type: application/json

{
  "folder_id": "550e8400-e29b-41d4-a716-446655440000",
  "encrypted_metadata": "base64...",
  "metadata_nonce": "base64...",
  "wrapped_dek": "base64...",
  "blob_size": 1048576,
  "blob_hash": "a1b2c3d4e5f6...",
  "signature": {
    "ml_dsa": "base64...",
    "kaz_sign": "base64..."
  }
}
```

### 3.2.1 Move File

```json
PATCH /files/{file_id}/move
Content-Type: application/json

{
  "target_folder_id": "990e8400-e29b-41d4-a716-446655440004",
  "wrapped_dek": "base64...",
  "signature": {
    "ml_dsa": "base64...",
    "kaz_sign": "base64..."
  }
}
```

**Signature Payload** (see `crypto/05-signature-protocol.md` Section 4.1.1):
```
CanonicalSerialize({
  blobHash, blobSize, wrappedDek (new), encryptedMetadata, metadataNonce
})
```

**Notes**:
- `wrapped_dek`: DEK re-wrapped with target folder's KEK
- Signature payload is identical to file upload, but with new `wrapped_dek`
- Server verifies signature before applying move

### 3.3 Create Folder

```json
POST /folders
Content-Type: application/json

{
  "parent_id": "550e8400-e29b-41d4-a716-446655440000",
  "encrypted_metadata": "base64...",
  "metadata_nonce": "base64...",
  "owner_key_access": {
    "wrapped_kek": "base64...",
    "kem_ciphertexts": [
      {
        "algorithm": "ML-KEM-768",
        "ciphertext": "base64..."
      },
      {
        "algorithm": "KAZ-KEM",
        "ciphertext": "base64..."
      }
    ]
  },
  "wrapped_kek": "base64...",
  "created_at": "2025-01-15T10:30:00.000Z",
  "signature": {
    "ml_dsa": "base64...",
    "kaz_sign": "base64..."
  }
}
```

**Signature Payload** (see `crypto/05-signature-protocol.md` Section 4.4):
```
CanonicalSerialize({
  parentId, encryptedMetadata, metadataNonce,
  ownerKeyAccess, wrappedKek, createdAt
})
```

### 3.4 Create Share

```json
POST /shares
Content-Type: application/json

{
  "resource_type": "file",
  "resource_id": "550e8400-e29b-41d4-a716-446655440000",
  "grantee_id": "660e8400-e29b-41d4-a716-446655440001",
  "wrapped_key": "base64...",
  "kem_ciphertexts": [
    {
      "algorithm": "ML-KEM-768",
      "ciphertext": "base64..."
    },
    {
      "algorithm": "KAZ-KEM",
      "ciphertext": "base64..."
    }
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

### 3.5 Create Share Link

```json
POST /shares/link
Content-Type: application/json

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

**Notes**:
- `wrapped_key`: DEK wrapped with password-derived key (if protected) or symmetric key embedded in link (if not)
- `password_salt`: Random salt for Argon2id (required if `password_protected`)
- `password_hash`: Argon2id(password, salt) stored for server-side verification
- `signature`: Creator's signature over the link parameters (required)

### 3.6 Verify Share Link Password

```json
POST /shares/link/{token}/verify
Content-Type: application/json

{
  "password_hash": "base64..."
}
```

**Notes**:
- Client computes `Argon2id(password, password_salt)` using salt from GET response
- Server verifies hash matches stored value

### 3.7 Initiate Recovery

```json
POST /recovery/requests
Content-Type: application/json

{
  "reason": "device_lost",
  "verification_method": "org_admin",
  "new_public_keys": {
    "ml_kem": "base64...",
    "ml_dsa": "base64...",
    "kaz_kem": "base64...",
    "kaz_sign": "base64..."
  }
}
```

### 3.8 Submit Recovery Approval

```json
POST /recovery/requests/{request_id}/approvals
Content-Type: application/json

{
  "share_index": 2,
  "reencrypted_share": {
    "wrapped_value": "base64...",
    "kem_ciphertexts": [
      {
        "algorithm": "ML-KEM-768",
        "ciphertext": "base64..."
      },
      {
        "algorithm": "KAZ-KEM",
        "ciphertext": "base64..."
      }
    ]
  },
  "signature": {
    "ml_dsa": "base64...",
    "kaz_sign": "base64..."
  }
}
```

## 4. Response Formats

### 4.1 Success Response

```json
{
  "success": true,
  "data": {
    // Response payload
  }
}
```

### 4.2 Error Response

```json
{
  "success": false,
  "error": {
    "code": "E_RESOURCE_NOT_FOUND",
    "message": "The requested file does not exist",
    "details": {
      "resource_type": "file",
      "resource_id": "550e8400-e29b-41d4-a716-446655440000"
    }
  }
}
```

### 4.3 User Response

```json
{
  "success": true,
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "tenant_id": "660e8400-e29b-41d4-a716-446655440001",
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
    "recovery_setup_complete": true,
    "last_login_at": "2025-01-15T10:30:00.000Z",
    "created_at": "2025-01-01T00:00:00.000Z",
    "updated_at": "2025-01-15T10:30:00.000Z"
  }
}
```

### 4.4 File Response

```json
{
  "success": true,
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "owner_id": "660e8400-e29b-41d4-a716-446655440001",
    "folder_id": "770e8400-e29b-41d4-a716-446655440002",
    "encrypted_metadata": "base64...",
    "metadata_nonce": "base64...",
    "wrapped_dek": "base64...",
    "blob_storage_key": "tenant-abc/user-123/files/550e8400.enc",
    "blob_size": 1048576,
    "blob_hash": "a1b2c3d4e5f67890abcdef1234567890abcdef1234567890abcdef1234567890",
    "signature": {
      "ml_dsa": "base64...",
      "kaz_sign": "base64..."
    },
    "version": 1,
    "created_at": "2025-01-15T10:30:00.000Z",
    "updated_at": "2025-01-15T10:30:00.000Z"
  }
}
```

### 4.5 File Upload Response

```json
{
  "success": true,
  "data": {
    "file": {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      // ... other file fields
    },
    "upload_url": "https://storage.example.com/upload?token=xyz...",
    "upload_headers": {
      "Content-Type": "application/octet-stream",
      "x-amz-content-sha256": "UNSIGNED-PAYLOAD"
    },
    "expires_at": "2025-01-15T11:30:00.000Z"
  }
}
```

### 4.6 Folder Contents Response

```json
{
  "success": true,
  "data": {
    "folder": {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "owner_id": "660e8400-e29b-41d4-a716-446655440001",
      "parent_id": "770e8400-e29b-41d4-a716-446655440002",
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
        "id": "660e8400-e29b-41d4-a716-446655440001",
        "public_keys": {
          "ml_dsa": "base64...",
          "kaz_sign": "base64..."
        }
      },
      "is_root": false,
      "item_count": 5,
      "created_at": "2025-01-15T10:30:00.000Z",
      "updated_at": "2025-01-15T10:30:00.000Z"
    },
    "subfolders": [
      {
        "id": "880e8400-e29b-41d4-a716-446655440003",
        "parent_id": "550e8400-e29b-41d4-a716-446655440000",
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
          "id": "660e8400-e29b-41d4-a716-446655440001",
          "public_keys": {
            "ml_dsa": "base64...",
            "kaz_sign": "base64..."
          }
        },
        "item_count": 5,
        "created_at": "2025-01-15T10:30:00.000Z"
      }
    ],
    "files": [
      {
        "id": "990e8400-e29b-41d4-a716-446655440004",
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
          "id": "660e8400-e29b-41d4-a716-446655440001",
          "public_keys": {
            "ml_dsa": "base64...",
            "kaz_sign": "base64..."
          }
        }
      }
    ],
    "shares": [
      // Array of share grants for resources in this folder
    ]
  }
}
```

> **Client Verification**: Clients MUST verify `signature` using `owner.public_keys` for the
> folder, each subfolder, and each file BEFORE trusting metadata or keys.
> See [Signature Protocol](../crypto/05-signature-protocol.md) Sections 4.1 (files) and 4.4 (folders).

### 4.6.1 Folder Share Access Response

When accessing a folder via share grant (`GET /folders/{id}?via_share={share_id}`):

```json
{
  "success": true,
  "data": {
    "id": "770e8400-e29b-41d4-a716-446655440002",
    "parent_id": "550e8400-e29b-41d4-a716-446655440000",
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
      "id": "660e8400-e29b-41d4-a716-446655440001",
      "public_keys": {
        "ml_dsa": "base64...",
        "kaz_sign": "base64..."
      }
    },
    "created_at": "2025-01-15T10:30:00.000Z",
    "share": {
      "id": "aa0e8400-e29b-41d4-a716-446655440005",
      "wrapped_key": "base64...",
      "kem_ciphertexts": [
        {"algorithm": "ML-KEM-768", "ciphertext": "base64..."},
        {"algorithm": "KAZ-KEM", "ciphertext": "base64..."}
      ],
      "permission": "read",
      "recursive": true
    }
  }
}
```

**Notes**:
- `wrapped_kek`: Original KEK wrapped by parent's KEK (for **signature verification**)
- `share.wrapped_key`: KEK re-wrapped for recipient via KEM (for **decryption**)
- All fields needed for folder signature verification are included

> **Client Verification**: Verify `signature` using `owner.public_keys` BEFORE decrypting
> the folder KEK via `share.wrapped_key`.

### 4.7 Paginated Response

```json
{
  "success": true,
  "data": {
    "items": [
      // Array of items
    ],
    "pagination": {
      "total": 150,
      "limit": 20,
      "offset": 40,
      "has_more": true
    }
  }
}
```

### 4.8 Share Grant Response

```json
{
  "success": true,
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "resource_type": "file",
    "resource_id": "660e8400-e29b-41d4-a716-446655440001",
    "grantor_id": "770e8400-e29b-41d4-a716-446655440002",
    "grantee_id": "880e8400-e29b-41d4-a716-446655440003",
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
    "created_at": "2025-01-15T10:30:00.000Z"
  }
}
```

### 4.9 Recovery Request Response

```json
{
  "success": true,
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "user_id": "660e8400-e29b-41d4-a716-446655440001",
    "status": "pending",
    "reason": "device_lost",
    "verification_method": "org_admin",
    "approvals_required": 3,
    "approvals_received": 1,
    "expires_at": "2025-01-18T10:30:00.000Z",
    "created_at": "2025-01-15T10:30:00.000Z",
    "trustees": [
      {
        "id": "770e8400-e29b-41d4-a716-446655440002",
        "display_name": "Admin User",
        "share_index": 1,
        "approved": true,
        "approved_at": "2025-01-15T11:00:00.000Z"
      },
      {
        "id": "880e8400-e29b-41d4-a716-446655440003",
        "display_name": "Manager",
        "share_index": 2,
        "approved": false
      }
    ]
  }
}
```

### 4.10 Share Link Response

```json
{
  "success": true,
  "data": {
    "id": "aa0e8400-e29b-41d4-a716-446655440006",
    "link": "https://securesharing.com/s/abc123xyz",
    "resource_type": "file",
    "expiry": "2025-02-15T10:30:00.000Z",
    "password_protected": true,
    "max_downloads": 10,
    "download_count": 0,
    "created_at": "2025-01-15T10:30:00.000Z"
  }
}
```

### 4.11 Share Link Details Response (Anonymous Access)

**Unprotected Link**:
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

**Notes**:
- `owner.public_keys`: Share link creator's public keys for share link signature verification
- `wrapped_key`: DEK wrapped with key embedded in URL fragment (client must extract from URL)
- `created_at`: Included in share link signature payload
- `signature`: Creator's signature over share link parameters
- `file.wrapped_dek`: Original DEK wrapped by folder KEK (for file signature verification)
- `file.blob_hash`: SHA-256 of encrypted blob (verify after download)
- `file.signature`: File owner's signature over file content
- `file.owner.public_keys`: File owner's public keys for file signature verification

> **Client Verification**: Clients MUST perform TWO signature verifications:
> 1. **Share Link Signature**: Verify `signature` using `owner.public_keys` to authenticate the share link itself
> 2. **File Signature**: Verify `file.signature` using `file.owner.public_keys` to authenticate the file content
>
> Note: Share link owner and file owner may be different (e.g., admin sharing someone else's file).

**Password-Protected Link (before verification)**:
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

### 4.12 Share Link Verification Response

After password verification, returns all fields needed for signature verification.

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

**Signature Payload Reconstruction**:

All fields needed to reconstruct the share link signature payload are included:
- `resource_type` → `resourceType`
- `file.id` or `folder.id` → `resourceId`
- `owner.id` → `creatorId`
- `wrapped_key` → `wrappedKey`
- `permission` → `permission`
- `expiry` → `expiry`
- `password_protected` → `passwordProtected`
- `max_downloads` → `maxDownloads`
- `created_at` → `createdAt`

**Notes**:
- `session_token`: Include in subsequent requests for authenticated link access
- `wrapped_key`: DEK (file) or KEK (folder) wrapped with password-derived key
- `file.wrapped_dek`: Original DEK for file signature verification
- `file.signature`: File owner's signature (for file authenticity verification)
- `file.owner.public_keys`: File owner's public keys for file signature verification
- Client MUST verify BOTH share link signature AND file signature before decryption

### 4.13 Share Link Download Response

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
      "blob_hash": "a1b2c3d4e5f67890abcdef1234567890abcdef1234567890abcdef1234567890"
    },
    "download_count": 4,
    "max_downloads": 10
  }
}
```

## 5. Error Codes

### 5.1 Authentication Errors (4xx)

| Code | HTTP | Description |
|------|------|-------------|
| `E_UNAUTHORIZED` | 401 | Missing or invalid authentication |
| `E_TOKEN_EXPIRED` | 401 | Auth token has expired |
| `E_FORBIDDEN` | 403 | Insufficient permissions |
| `E_TENANT_SUSPENDED` | 403 | Tenant account is suspended |
| `E_USER_SUSPENDED` | 403 | User account is suspended |

### 5.2 Resource Errors (4xx)

| Code | HTTP | Description |
|------|------|-------------|
| `E_NOT_FOUND` | 404 | Resource not found |
| `E_FILE_NOT_FOUND` | 404 | File does not exist |
| `E_FOLDER_NOT_FOUND` | 404 | Folder does not exist |
| `E_USER_NOT_FOUND` | 404 | User does not exist |
| `E_SHARE_NOT_FOUND` | 404 | Share grant does not exist |
| `E_CONFLICT` | 409 | Resource already exists |
| `E_SHARE_EXISTS` | 409 | Share already exists |
| `E_LINK_NOT_FOUND` | 404 | Share link does not exist |
| `E_LINK_EXPIRED` | 400 | Share link has expired |
| `E_LINK_MAX_DOWNLOADS` | 400 | Share link download limit reached |
| `E_INVALID_PASSWORD` | 401 | Invalid share link password |
| `E_SESSION_INVALID` | 401 | Invalid or missing link session |
| `E_SESSION_EXPIRED` | 401 | Link session has expired |

### 5.3 Validation Errors (4xx)

| Code | HTTP | Description |
|------|------|-------------|
| `E_VALIDATION_FAILED` | 400 | Request validation failed |
| `E_INVALID_JSON` | 400 | Malformed JSON body |
| `E_INVALID_BASE64` | 400 | Invalid Base64 encoding |
| `E_INVALID_UUID` | 400 | Invalid UUID format |
| `E_SIGNATURE_INVALID` | 400 | Signature verification failed |
| `E_SHARE_EXPIRED` | 400 | Share grant has expired |

### 5.4 Limit Errors (4xx)

| Code | HTTP | Description |
|------|------|-------------|
| `E_QUOTA_EXCEEDED` | 402 | Storage quota exceeded |
| `E_USER_LIMIT_EXCEEDED` | 402 | User limit for tenant exceeded |
| `E_RATE_LIMITED` | 429 | Too many requests |

### 5.5 Server Errors (5xx)

| Code | HTTP | Description |
|------|------|-------------|
| `E_INTERNAL_ERROR` | 500 | Unexpected server error |
| `E_STORAGE_ERROR` | 502 | Object storage unavailable |
| `E_DATABASE_ERROR` | 503 | Database unavailable |

## 6. Query Parameters

### 6.1 Pagination

```
GET /files?limit=20&offset=40
```

| Parameter | Type | Default | Max | Description |
|-----------|------|---------|-----|-------------|
| `limit` | integer | 20 | 100 | Items per page |
| `offset` | integer | 0 | - | Items to skip |

### 6.2 Sorting

```
GET /files?sort_by=created_at&sort_order=desc
```

| Parameter | Values | Default | Description |
|-----------|--------|---------|-------------|
| `sort_by` | `created_at`, `updated_at`, `name` | `created_at` | Sort field |
| `sort_order` | `asc`, `desc` | `desc` | Sort direction |

### 6.3 Filtering

```
GET /audit?event_type=file.upload&start_time=2025-01-01T00:00:00Z
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `event_type` | string | Filter by event type |
| `resource_type` | string | Filter by resource type |
| `resource_id` | UUID | Filter by resource ID |
| `start_time` | ISO 8601 | Events after this time |
| `end_time` | ISO 8601 | Events before this time |

## 7. WebSocket Events

### 7.1 Connection

```
wss://api.example.com/ws?token=<session_token>
```

### 7.2 Event Format

```json
{
  "type": "file.uploaded",
  "timestamp": "2025-01-15T10:30:00.000Z",
  "data": {
    "file_id": "550e8400-e29b-41d4-a716-446655440000",
    "folder_id": "660e8400-e29b-41d4-a716-446655440001"
  }
}
```

### 7.3 Event Types

| Type | Description |
|------|-------------|
| `file.uploaded` | New file uploaded |
| `file.deleted` | File deleted |
| `folder.created` | New folder created |
| `folder.deleted` | Folder deleted |
| `share.created` | New share granted |
| `share.revoked` | Share revoked |
| `share_link.created` | Share link created |
| `share_link.accessed` | Share link accessed |
| `share_link.downloaded` | File downloaded via share link |
| `share_link.revoked` | Share link revoked |
| `recovery.requested` | Recovery request initiated |
| `recovery.approved` | Recovery approval submitted |
| `recovery.completed` | Recovery completed |

## 8. Content Types

### 8.1 Request

```
Content-Type: application/json
```

### 8.2 Response

```
Content-Type: application/json; charset=utf-8
```

### 8.3 File Upload

```
Content-Type: application/octet-stream
```

### 8.4 File Download

```
Content-Type: application/octet-stream
Content-Disposition: attachment; filename="encrypted.bin"
```
