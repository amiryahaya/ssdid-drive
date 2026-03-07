# Files API

**Version**: 1.1.0
**Status**: Draft
**Last Updated**: 2026-01

## 1. Overview

File management endpoints for uploading, downloading, and managing encrypted files. All file content is encrypted client-side before upload.

**Encryption Format**: See [docs/crypto/03-encryption-protocol.md](../crypto/03-encryption-protocol.md) for the canonical file encryption specification.

**Storage Separation**:
- **Blob** (object storage): Encrypted file content with fixed 64-byte header + encrypted chunks
- **Database**: Metadata, wrapped DEK, and signature

**Base URL**: `https://api.securesharing.com/v1`

**Authentication**: All endpoints require `Authorization: Bearer <token>` header.

## 2. Endpoints

### 2.1 Initiate File Upload

Create a file record and get a pre-signed upload URL.

```http
POST /files
Authorization: Bearer <token>
Content-Type: application/json
```

**Request Body**:
```json
{
  "folder_id": "550e8400-e29b-41d4-a716-446655440000",
  "encrypted_metadata": "base64...",
  "metadata_nonce": "base64...",
  "wrapped_dek": "base64...",
  "blob_size": 10485760,
  "blob_hash": "a1b2c3d4e5f67890abcdef1234567890abcdef1234567890abcdef1234567890",
  "signature": {
    "ml_dsa": "base64...",
    "kaz_sign": "base64..."
  }
}
```

**Request Fields**:
| Field | Type | Description |
|-------|------|-------------|
| `folder_id` | UUID | Parent folder |
| `encrypted_metadata` | Base64 | AES-GCM encrypted metadata |
| `metadata_nonce` | Base64 | 12-byte nonce |
| `wrapped_dek` | Base64 | DEK wrapped by folder KEK |
| `blob_size` | integer | Size of encrypted blob |
| `blob_hash` | hex | SHA-256 of encrypted blob |
| `signature` | object | Combined signature of the package |

**Response** `201 Created`:
```json
{
  "success": true,
  "data": {
    "file": {
      "id": "660e8400-e29b-41d4-a716-446655440001",
      "owner_id": "770e8400-e29b-41d4-a716-446655440002",
      "folder_id": "550e8400-e29b-41d4-a716-446655440000",
      "blob_storage_key": "tenant-abc/user-123/files/660e8400.enc",
      "blob_size": 10485760,
      "version": 1,
      "created_at": "2025-01-15T10:30:00.000Z"
    },
    "upload": {
      "url": "https://storage.securesharing.com/upload/...",
      "method": "PUT",
      "headers": {
        "Content-Type": "application/octet-stream",
        "Content-Length": "10485760"
      },
      "expires_at": "2025-01-15T11:30:00.000Z"
    }
  }
}
```

---

### 2.2 Confirm Upload Complete

Confirm that blob upload succeeded.

```http
POST /files/{file_id}/confirm
Authorization: Bearer <token>
```

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "file": {
      "id": "660e8400-e29b-41d4-a716-446655440001",
      "status": "confirmed",
      "blob_verified": true
    }
  }
}
```

---

### 2.3 Get File Details

Get file metadata and download information.

```http
GET /files/{file_id}
Authorization: Bearer <token>
```

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "id": "660e8400-e29b-41d4-a716-446655440001",
    "owner_id": "770e8400-e29b-41d4-a716-446655440002",
    "folder_id": "550e8400-e29b-41d4-a716-446655440000",
    "encrypted_metadata": "base64...",
    "metadata_nonce": "base64...",
    "wrapped_dek": "base64...",
    "blob_storage_key": "tenant-abc/user-123/files/660e8400.enc",
    "blob_size": 10485760,
    "blob_hash": "a1b2c3d4e5f67890abcdef1234567890abcdef1234567890abcdef1234567890",
    "signature": {
      "ml_dsa": "base64...",
      "kaz_sign": "base64..."
    },
    "version": 1,
    "created_at": "2025-01-15T10:30:00.000Z",
    "updated_at": "2025-01-15T10:30:00.000Z",
    "access": {
      "source": "owner",
      "permission": "owner"
    }
  }
}
```

**Access Information** (see `data-model/01-entities.md` section 6.2):
- `source`: How user has access (`owner`, `share`)
- `permission`: Effective access level (`owner`, `admin`, `write`, `read`)

> **Note**: `owner` is an access level, not a share permission. It indicates the user
> owns this resource. Share permissions are limited to `read`, `write`, `admin`.

---

### 2.4 Get File Download URL

Get pre-signed URL to download encrypted blob.

```http
GET /files/{file_id}/download
Authorization: Bearer <token>
```

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
      "blob_size": 10485760,
      "blob_hash": "a1b2c3d4e5f67890..."
    }
  }
}
```

---

### 2.5 Get File with Share Access

Get file via share grant (includes share's wrapped key and owner's public keys for signature verification).

```http
GET /files/{file_id}?via_share={share_id}
Authorization: Bearer <token>
```

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "id": "660e8400-e29b-41d4-a716-446655440001",
    "owner": {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "email": "alice@example.com",
      "display_name": "Alice",
      "public_keys": {
        "ml_dsa": "base64...",
        "kaz_sign": "base64..."
      }
    },
    "encrypted_metadata": "base64...",
    "metadata_nonce": "base64...",
    "blob_size": 10485760,
    "blob_hash": "a1b2c3d4e5f67890abcdef...",
    "wrapped_dek": "base64...",
    "signature": {
      "ml_dsa": "base64...",
      "kaz_sign": "base64..."
    },
    "share": {
      "id": "880e8400-e29b-41d4-a716-446655440003",
      "grantor": {
        "id": "990e8400-e29b-41d4-a716-446655440004",
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
      "permission": "read",
      "expiry": null,
      "created_at": "2025-01-12T00:00:00.000Z",
      "signature": {
        "ml_dsa": "base64...",
        "kaz_sign": "base64..."
      }
    },
    "created_at": "2025-01-15T10:30:00.000Z",
    "updated_at": "2025-01-15T10:30:00.000Z"
  }
}
```

**Response Fields** (share access):
| Field | Type | Description |
|-------|------|-------------|
| `owner` | object | File owner with public keys for signature verification |
| `owner.public_keys` | object | Owner's ML-DSA and KAZ-SIGN public keys |
| `wrapped_dek` | Base64 | Original DEK wrapped by folder KEK (for file signature verification) |
| `signature` | object | Owner's signature over file package |
| `blob_hash` | string | SHA-256 hash of encrypted blob (verify after download) |
| `share.grantor` | object | Grantor's info and public keys (for share grant signature verification) |
| `share.wrapped_key` | Base64 | DEK re-wrapped for recipient via KEM (for decryption) |
| `share.kem_ciphertexts` | array | KEM ciphertexts for decapsulation |
| `share.permission` | string | Permission level (`read`, `write`, `admin`) |
| `share.expiry` | ISO8601 \| null | Share expiration (for share signature verification) |
| `share.created_at` | ISO8601 | Share creation timestamp (for share signature verification) |
| `share.signature` | object | Grantor's signature over share grant |

> **Mandatory Verification**: Clients MUST verify TWO signatures BEFORE decryption:
> 1. **Share Grant Signature**: Verify `share.signature` using `share.grantor.public_keys`
>    to authenticate that the share was created by someone with permission to share.
> 2. **File Signature**: Verify `signature` using `owner.public_keys` and verify `blob_hash`
>    matches the downloaded blob to authenticate the file content.
>
> See [Signature Protocol](../crypto/05-signature-protocol.md) Sections 4.2 (share grants) and 4.1 (files).

> **Note on `wrapped_dek` vs `share.wrapped_key`**:
> - `wrapped_dek`: Original DEK wrapped by folder KEK (used for **file signature verification**)
> - `share.wrapped_key`: DEK re-wrapped for the recipient via KEM (used for **decryption**)
>
> The file signature was created over `wrapped_dek`. Recipients must verify both
> signatures, then decrypt using `share.wrapped_key`.

---

### 2.6 Update File (Re-upload)

Update file content. Creates new version.

```http
PUT /files/{file_id}
Authorization: Bearer <token>
Content-Type: application/json
```

**Request Body**:
```json
{
  "encrypted_metadata": "base64...",
  "metadata_nonce": "base64...",
  "wrapped_dek": "base64...",
  "blob_size": 12582912,
  "blob_hash": "b2c3d4e5f67890abcdef...",
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
    "file": {
      "id": "660e8400-e29b-41d4-a716-446655440001",
      "version": 2,
      "blob_size": 12582912
    },
    "upload": {
      "url": "https://storage.securesharing.com/upload/...",
      "expires_at": "2025-01-15T11:30:00.000Z"
    }
  }
}
```

---

### 2.7 Move File

Move file to a different folder.

```http
PATCH /files/{file_id}/move
Authorization: Bearer <token>
Content-Type: application/json
```

**Request Body**:
```json
{
  "target_folder_id": "990e8400-e29b-41d4-a716-446655440004",
  "wrapped_dek": "base64...",
  "signature": {
    "ml_dsa": "base64...",
    "kaz_sign": "base64..."
  }
}
```

**Request Fields**:
| Field | Type | Description |
|-------|------|-------------|
| `target_folder_id` | UUID | Destination folder ID |
| `wrapped_dek` | Base64 | DEK re-wrapped with target folder's KEK |
| `signature` | object | Owner's signature over updated file state |

**Signature Payload** (see `crypto/05-signature-protocol.md` Section 4.1.1):
```
CanonicalSerialize({
  blobHash, blobSize, wrappedDek (new), encryptedMetadata, metadataNonce
})
```

> **Note**: The signature payload is identical to file upload (Section 4.1), but with
> the new `wrapped_dek`. All other fields (blobHash, blobSize, etc.) remain unchanged.

**Notes**:
- User must have write access to target folder
- Server verifies signature before applying move

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "id": "660e8400-e29b-41d4-a716-446655440001",
    "folder_id": "990e8400-e29b-41d4-a716-446655440004",
    "wrapped_dek": "base64...",
    "updated_at": "2025-01-15T10:30:00.000Z"
  }
}
```

---

### 2.8 Copy File

Copy file to another folder.

```http
POST /files/{file_id}/copy
Authorization: Bearer <token>
Content-Type: application/json
```

**Request Body**:
```json
{
  "target_folder_id": "990e8400-e29b-41d4-a716-446655440004",
  "wrapped_dek": "base64...",
  "signature": {
    "ml_dsa": "base64...",
    "kaz_sign": "base64..."
  }
}
```

**Response** `201 Created`:
```json
{
  "success": true,
  "data": {
    "file": {
      "id": "aa0e8400-e29b-41d4-a716-446655440005",
      "folder_id": "990e8400-e29b-41d4-a716-446655440004",
      "created_at": "2025-01-15T10:30:00.000Z"
    }
  }
}
```

---

### 2.9 Delete File

Delete a file (soft delete, recoverable for 30 days).

```http
DELETE /files/{file_id}
Authorization: Bearer <token>
```

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "message": "File deleted",
    "deleted_at": "2025-01-15T10:30:00.000Z",
    "permanent_deletion_at": "2025-02-14T10:30:00.000Z"
  }
}
```

---

### 2.10 List Deleted Files

List files in trash (deleted but not permanently removed).

```http
GET /files/trash
Authorization: Bearer <token>
```

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "items": [
      {
        "id": "660e8400-e29b-41d4-a716-446655440001",
        "encrypted_metadata": "base64...",
        "deleted_at": "2025-01-15T10:30:00.000Z",
        "permanent_deletion_at": "2025-02-14T10:30:00.000Z"
      }
    ]
  }
}
```

---

### 2.11 Restore File

Restore a deleted file from trash.

```http
POST /files/{file_id}/restore
Authorization: Bearer <token>
Content-Type: application/json
```

**Request Body**:
```json
{
  "target_folder_id": "550e8400-e29b-41d4-a716-446655440000"
}
```

**Response** `200 OK`:
```json
{
  "success": true,
  "data": {
    "file": {
      "id": "660e8400-e29b-41d4-a716-446655440001",
      "folder_id": "550e8400-e29b-41d4-a716-446655440000",
      "restored_at": "2025-01-15T10:30:00.000Z"
    }
  }
}
```

---

### 2.12 Permanently Delete File

Permanently delete file (no recovery possible).

```http
DELETE /files/{file_id}/permanent
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
    "message": "File permanently deleted"
  }
}
```

## 3. Multipart Upload (Large Files)

For files > 100MB, use multipart upload.

### 3.1 Initiate Multipart Upload

```http
POST /files/multipart
Authorization: Bearer <token>
Content-Type: application/json
```

**Request Body**:
```json
{
  "folder_id": "550e8400-e29b-41d4-a716-446655440000",
  "encrypted_metadata": "base64...",
  "metadata_nonce": "base64...",
  "wrapped_dek": "base64...",
  "blob_size": 1073741824,
  "part_size": 104857600,
  "total_parts": 11,
  "signature": {
    "ml_dsa": "base64...",
    "kaz_sign": "base64..."
  }
}
```

**Response** `201 Created`:
```json
{
  "success": true,
  "data": {
    "file_id": "660e8400-e29b-41d4-a716-446655440001",
    "upload_id": "multipart-upload-id",
    "parts": [
      {
        "part_number": 1,
        "upload_url": "https://storage.../part1",
        "size": 104857600
      },
      {
        "part_number": 2,
        "upload_url": "https://storage.../part2",
        "size": 104857600
      }
      // ... more parts
    ]
  }
}
```

### 3.2 Complete Multipart Upload

```http
POST /files/{file_id}/multipart/complete
Authorization: Bearer <token>
Content-Type: application/json
```

**Request Body**:
```json
{
  "upload_id": "multipart-upload-id",
  "parts": [
    {"part_number": 1, "etag": "etag1"},
    {"part_number": 2, "etag": "etag2"}
  ],
  "blob_hash": "final-sha256-hash"
}
```

## 4. Error Responses

| Code | HTTP | Description |
|------|------|-------------|
| `E_FILE_NOT_FOUND` | 404 | File does not exist |
| `E_FOLDER_NOT_FOUND` | 404 | Target folder not found |
| `E_QUOTA_EXCEEDED` | 402 | Storage quota exceeded |
| `E_UPLOAD_EXPIRED` | 400 | Upload URL expired |
| `E_HASH_MISMATCH` | 400 | Blob hash verification failed |
| `E_SIGNATURE_INVALID` | 400 | File signature invalid |
| `E_FILE_DELETED` | 410 | File is in trash |
| `E_PERMISSION_DENIED` | 403 | Insufficient permissions |
