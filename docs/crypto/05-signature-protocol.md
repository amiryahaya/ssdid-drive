# Digital Signature Protocol Specification

**Version**: 1.0.0
**Status**: Draft
**Last Updated**: 2025-01

## 1. Overview

Digital signatures in SecureSharing provide:
- **Authenticity**: Verify who created or shared content
- **Integrity**: Detect any modification to signed data
- **Non-repudiation**: Signers cannot deny their signatures

This document specifies the dual-signature approach using ML-DSA-65 and KAZ-SIGN.

## 2. Signature Key Pairs

### 2.1 Key Generation

Each user generates two signature key pairs during registration:

```
UserSignKeyGen():
    // NIST ML-DSA-65
    (ml_pk, ml_sk) ← ML-DSA-65.KeyGen()

    // Malaysian KAZ-SIGN
    (kaz_pk, kaz_sk) ← KAZ-SIGN.KeyGen()

    return {
        publicKeys: {
            ml_dsa: ml_pk,      // 1,952 bytes
            kaz_sign: kaz_pk    // 118 bytes
        },
        privateKeys: {
            ml_dsa: ml_sk,      // 4,032 bytes (encrypted by MK)
            kaz_sign: kaz_sk    // 64 bytes (encrypted by MK)
        }
    }
```

### 2.2 Key Sizes

| Algorithm | Public Key | Private Key | Signature |
|-----------|-----------|-------------|-----------|
| ML-DSA-65 | 1,952 bytes | 4,032 bytes | 3,309 bytes |
| KAZ-SIGN-256 | 118 bytes | 64 bytes | 356 bytes |

## 3. Signature Operations

### 3.1 Combined Sign

```
CombinedSign(ml_sk, kaz_sk, message):
    // IMPORTANT: This function always pre-hashes the message with SHA-256.
    // Callers should pass the structured signing payload directly (NOT pre-hashed).
    // The blob_hash field inside the payload is a separate commitment to the blob.
    // See "Hashing Pipeline" section below for details.

    message_hash ← SHA-256(message)

    // Sign the hash with both algorithms
    sig_ml ← ML-DSA-65.Sign(ml_sk, message_hash)
    sig_kaz ← KAZ-SIGN.Sign(kaz_sk, message_hash)

    return CombinedSignature {
        ml_dsa: sig_ml,
        kaz_sign: sig_kaz
    }
```

### 3.2 Combined Verify

```
CombinedVerify(ml_pk, kaz_pk, message, signature):
    // Hash the message (must match what CombinedSign did)
    message_hash ← SHA-256(message)

    // Verify both signatures against the hash
    valid_ml ← ML-DSA-65.Verify(ml_pk, message_hash, signature.ml_dsa)
    valid_kaz ← KAZ-SIGN.Verify(kaz_pk, message_hash, signature.kaz_sign)

    // BOTH must be valid
    return valid_ml AND valid_kaz
```

### 3.3 Hashing Pipeline

**CRITICAL FOR IMPLEMENTATION COMPATIBILITY**

The signing pipeline involves multiple hashing operations at different levels:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         SIGNATURE HASHING PIPELINE                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  For FILE UPLOADS:                                                          │
│  ─────────────────                                                          │
│                                                                              │
│  encrypted_blob                                                              │
│       │                                                                      │
│       │ SHA-256                                                              │
│       ▼                                                                      │
│  blob_hash (32 bytes, hex-encoded in payload)                               │
│       │                                                                      │
│       │ Included in structured payload                                       │
│       ▼                                                                      │
│  signature_payload = Canonicalize({                                          │
│      blob_hash: hex(blob_hash),     ← NOT the raw hash bytes                │
│      blob_size: ...,                                                         │
│      wrapped_dek: base64(...),                                               │
│      encrypted_metadata: base64(...),                                        │
│      metadata_nonce: base64(...)                                             │
│  })                                                                          │
│       │                                                                      │
│       │ SHA-256 (inside CombinedSign)                                        │
│       ▼                                                                      │
│  message_hash = SHA-256(signature_payload)                                   │
│       │                                                                      │
│       │ ML-DSA-65.Sign / KAZ-SIGN.Sign                                      │
│       ▼                                                                      │
│  signature                                                                   │
│                                                                              │
│  TOTAL HASH OPERATIONS:                                                      │
│  • blob_hash = SHA-256(encrypted_blob)     ← Commitment to blob content     │
│  • message_hash = SHA-256(signature_payload) ← CombinedSign internal hash   │
│                                                                              │
│  These are DIFFERENT hashes at different semantic levels:                    │
│  • blob_hash commits to the encrypted content                               │
│  • message_hash is what the signature algorithms sign                       │
│                                                                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  For STRUCTURED DATA (shares, folders, etc.):                               │
│  ────────────────────────────────────────────                               │
│                                                                              │
│  structured_data (grant fields, folder fields, etc.)                        │
│       │                                                                      │
│       │ CanonicalSerialize                                                   │
│       ▼                                                                      │
│  serialized_payload (bytes)                                                  │
│       │                                                                      │
│       │ SHA-256 (inside CombinedSign)                                        │
│       ▼                                                                      │
│  message_hash = SHA-256(serialized_payload)                                  │
│       │                                                                      │
│       │ ML-DSA-65.Sign / KAZ-SIGN.Sign                                      │
│       ▼                                                                      │
│  signature                                                                   │
│                                                                              │
│  TOTAL HASH OPERATIONS: Just one (inside CombinedSign)                      │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Implementation Rules:**

1. **Never pre-hash before calling CombinedSign** - the function does this internally
2. **Pass the full structured payload** - not a hash of it
3. **blob_hash is a field value, not a pre-hash** - it's hex-encoded inside the JSON structure
4. **Verification must use identical pipeline** - same serialization, same hashing

## 4. What Gets Signed

### 4.1 File Uploads

**Signed Data**: Canonicalized structure containing blob hash and metadata references

The signature covers a structured payload that includes:
- Hash of the encrypted blob (commitment to content)
- Blob size (for integrity)
- Wrapped DEK (binding key to content)
- Encrypted metadata and nonce (binding metadata to signature)

```
SignFileUpload(blob, wrapped_dek, encrypted_metadata, metadata_nonce, user_sign_keys):
    // 1. Hash the encrypted blob (large data → fixed-size commitment)
    blob_hash ← SHA-256(blob)

    // 2. Build structured signature payload
    // NOTE: Pass this structure to CombinedSign, NOT the blob_hash directly
    signature_payload ← Canonicalize({
        blob_hash: hex(blob_hash),           // Hex string, not raw bytes
        blob_size: blob.length,
        wrapped_dek: base64(wrapped_dek),
        encrypted_metadata: base64(encrypted_metadata),
        metadata_nonce: base64(metadata_nonce)
    })

    // 3. Create combined signature
    // CombinedSign will SHA-256 the payload internally
    signature ← CombinedSign(
        user_sign_keys.ml_dsa_sk,
        user_sign_keys.kaz_sign_sk,
        signature_payload                    // Full payload, NOT blob_hash
    )

    return signature
```

**Verification** (before decryption):
```
VerifyFileSignature(blob, db_record, owner_public_keys):
    // 1. Hash the blob
    blob_hash ← SHA-256(blob)

    // 2. Reconstruct the exact signature payload
    signature_payload ← Canonicalize({
        blob_hash: hex(blob_hash),
        blob_size: blob.length,
        wrapped_dek: base64(db_record.wrapped_dek),
        encrypted_metadata: base64(db_record.encrypted_metadata),
        metadata_nonce: base64(db_record.metadata_nonce)
    })

    // 3. Verify (CombinedVerify will SHA-256 the payload internally)
    return CombinedVerify(
        owner_public_keys.ml_dsa_pk,
        owner_public_keys.kaz_sign_pk,
        signature_payload,                   // Full payload, NOT blob_hash
        db_record.signature
    )
```

> **Implementation Note**: The `blob_hash` field is a hex-encoded string inside the
> canonicalized JSON, not the raw 32-byte hash. This ensures consistent serialization
> across implementations. See Section 3.3 for the complete hashing pipeline.

#### 4.1.1 File Move

When moving a file to a different folder, the `wrapped_dek` must be re-wrapped with
the target folder's KEK. Since `wrapped_dek` is part of the file signature payload,
a new signature is required covering the updated state.

```
SignFileMove(file, new_folder_id, new_wrapped_dek, user_sign_keys):
    // Note: blob_hash, blob_size, encrypted_metadata, and metadata_nonce are UNCHANGED
    // Only wrapped_dek changes (re-wrapped with new folder's KEK)

    signature_payload ← Canonicalize({
        blobHash: file.blobHash,                    // Unchanged - hex string
        blobSize: file.blobSize,                    // Unchanged
        wrappedDek: base64(new_wrapped_dek),        // NEW: re-wrapped with target folder KEK
        encryptedMetadata: file.encryptedMetadata,  // Unchanged
        metadataNonce: file.metadataNonce           // Unchanged
    })

    return CombinedSign(
        user_sign_keys.ml_dsa_sk,
        user_sign_keys.kaz_sign_sk,
        signature_payload
    )
```

**Key Points:**
- The signature payload structure is **identical** to file upload (Section 4.1)
- Only `wrapped_dek` changes; all other fields remain the same
- After move, the file stores this new signature, replacing the previous one
- Verification uses the same `VerifyFileSignature` function

**Why require a new signature on move?**
1. `wrapped_dek` is part of the signed payload - changing it invalidates the signature
2. Ensures cryptographic binding between file content and its encryption key
3. Prevents attacks where an attacker substitutes a different `wrapped_dek`
4. Maintains consistency with folder move operations (Section 4.4.2)

### 4.2 Share Grants

**Signed Data**: Canonical serialization of share grant fields

```
SignShareGrant(grant, grantor_sign_keys):
    // Canonical serialization
    grant_bytes ← CanonicalSerialize({
        resourceType: grant.resourceType,
        resourceId: grant.resourceId,
        grantorId: grant.grantorId,
        granteeId: grant.granteeId,
        wrappedKey: grant.wrappedKey,
        kemCiphertexts: grant.kemCiphertexts,
        permission: grant.permission,
        recursive: grant.recursive,
        expiry: grant.expiry,
        createdAt: grant.createdAt
    })

    return CombinedSign(
        grantor_sign_keys.ml_dsa_sk,
        grantor_sign_keys.kaz_sign_sk,
        grant_bytes
    )
```

### 4.3 Recovery Share Approvals

**Signed Data**: Recovery request identifier and share data

```
SignRecoveryApproval(request_id, share_data, trustee_sign_keys):
    approval_bytes ← CanonicalSerialize({
        requestId: request_id,
        shareIndex: share_data.index,
        encryptedShare: share_data.encrypted,
        timestamp: current_timestamp
    })

    return CombinedSign(
        trustee_sign_keys.ml_dsa_sk,
        trustee_sign_keys.kaz_sign_sk,
        approval_bytes
    )
```

### 4.4 Folder Operations

**Signed Data**: Folder metadata and KEK-related data

The signature covers folder content and key material. Like file uploads, the folder `id`
is NOT included because it's generated by the server after signature submission.

```
SignFolderCreation(folder, user_sign_keys):
    folder_bytes ← CanonicalSerialize({
        parentId: folder.parentId,               // Parent folder ID (null for root)
        encryptedMetadata: folder.encryptedMetadata,
        metadataNonce: folder.metadataNonce,
        ownerKeyAccess: folder.ownerKeyAccess,   // KEK wrapped for owner
        wrappedKek: folder.wrappedKek,           // KEK wrapped by parent KEK (null for root)
        createdAt: folder.createdAt
    })

    return CombinedSign(
        user_sign_keys.ml_dsa_sk,
        user_sign_keys.kaz_sign_sk,
        folder_bytes
    )
```

**Verification**: When retrieving a folder, clients MUST verify the signature using
the owner's public keys before trusting the folder metadata or KEK.

#### 4.4.1 Folder Metadata Update

When updating folder metadata (e.g., renaming), a new signature is required that
covers the updated state. The folder `id` IS included to bind the signature to
the specific folder being updated.

```
SignFolderUpdate(folder, user_sign_keys):
    folder_bytes ← CanonicalSerialize({
        id: folder.id,                           // Folder ID (binds to specific folder)
        parentId: folder.parentId,               // Unchanged
        encryptedMetadata: folder.encryptedMetadata,  // Updated
        metadataNonce: folder.metadataNonce,     // Updated (new nonce required)
        ownerKeyAccess: folder.ownerKeyAccess,   // Unchanged
        wrappedKek: folder.wrappedKek,           // Unchanged
        originalCreatedAt: folder.createdAt,     // Original creation timestamp
        updatedAt: folder.updatedAt              // Update timestamp
    })

    return CombinedSign(
        user_sign_keys.ml_dsa_sk,
        user_sign_keys.kaz_sign_sk,
        folder_bytes
    )
```

**Note**: After an update, the folder stores this new signature, replacing the
creation signature. The `originalCreatedAt` field links to the creation event.

#### 4.4.2 Folder Move

When moving a folder to a new parent, the `parentId` and `wrappedKek` change.
A new signature is required covering the complete new state.

```
SignFolderMove(folder, new_parent_id, new_wrapped_kek, user_sign_keys):
    folder_bytes ← CanonicalSerialize({
        id: folder.id,                           // Folder ID
        parentId: new_parent_id,                 // New parent
        encryptedMetadata: folder.encryptedMetadata,  // Unchanged
        metadataNonce: folder.metadataNonce,     // Unchanged
        ownerKeyAccess: folder.ownerKeyAccess,   // Unchanged
        wrappedKek: new_wrapped_kek,             // Re-wrapped with new parent's KEK
        originalCreatedAt: folder.createdAt,     // Original creation timestamp
        updatedAt: folder.updatedAt              // Move timestamp
    })

    return CombinedSign(
        user_sign_keys.ml_dsa_sk,
        user_sign_keys.kaz_sign_sk,
        folder_bytes
    )
```

**Note**: Moving a folder also requires re-wrapping child folder KEKs if the
folder hierarchy uses cascading key wrapping. See `flows/06-share-folder-flow.md`.

### 4.5 Share Grant Updates

**Signed Data**: Share ID, updated fields, and reference to original grant

When updating a share's permission or expiry, a new signature is required that:
1. References the original share by ID
2. Includes all mutable fields (even if unchanged)
3. Includes the update timestamp
4. Does NOT re-sign the cryptographic material (wrapped key, KEM ciphertexts)

```
SignShareUpdate(share_id, original_created_at, updates, grantor_sign_keys):
    update_bytes ← CanonicalSerialize({
        shareId: share_id,
        originalCreatedAt: original_created_at,  // Links to original grant
        permission: updates.permission,
        expiry: updates.expiry,
        updatedAt: updates.updatedAt
    })

    return CombinedSign(
        grantor_sign_keys.ml_dsa_sk,
        grantor_sign_keys.kaz_sign_sk,
        update_bytes
    )
```

**Why include `originalCreatedAt`?**
- Binds update to the specific original grant
- Prevents replay attacks (can't apply old updates to new grants)
- Allows verification without fetching full original grant

**Mutable vs Immutable Fields:**

| Field | Mutable | Notes |
|-------|---------|-------|
| `permission` | Yes | Can upgrade or downgrade |
| `expiry` | Yes | Can extend or shorten |
| `recursive` | No | Cannot change after creation |
| `wrappedKey` | No | Requires new share grant |
| `kemCiphertexts` | No | Requires new share grant |
| `granteeId` | No | Requires new share grant |

### 4.6 Share Links

**Signed Data**: Canonical serialization of share link parameters

Share links (URL-based anonymous sharing) are signed by the creator to ensure:
- **Integrity**: Link parameters cannot be modified by the server
- **Authenticity**: Proves who created the link
- **Binding**: Cryptographically binds `wrapped_key` to specific file and permissions

> **Note**: Unlike share grants, share links do NOT use KEM encapsulation. The `wrapped_key` is either:
> - Wrapped with a random key embedded in the URL fragment (unprotected links)
> - Wrapped with a password-derived key (protected links)

```
SignShareLink(link_params, creator_sign_keys):
    link_bytes ← CanonicalSerialize({
        resourceType: link_params.resourceType,     // "file" or "folder"
        resourceId: link_params.resourceId,         // UUID of resource
        creatorId: link_params.creatorId,           // Creator's user ID
        wrappedKey: link_params.wrappedKey,         // Base64-encoded wrapped DEK/KEK
        permission: link_params.permission,         // "read" (links are read-only)
        expiry: link_params.expiry,                 // ISO 8601 or null
        passwordProtected: link_params.passwordProtected,  // boolean
        maxDownloads: link_params.maxDownloads,     // integer or null
        createdAt: link_params.createdAt            // ISO 8601 timestamp
    })

    return CombinedSign(
        creator_sign_keys.ml_dsa_sk,
        creator_sign_keys.kaz_sign_sk,
        link_bytes
    )
```

**Verification** (before decryption):

```
VerifyShareLinkSignature(link_data, creator_public_keys):
    // Reconstruct the exact payload that was signed
    link_bytes ← CanonicalSerialize({
        resourceType: link_data.resourceType,
        resourceId: link_data.resourceId,
        creatorId: link_data.creatorId,
        wrappedKey: link_data.wrappedKey,
        permission: link_data.permission,
        expiry: link_data.expiry,
        passwordProtected: link_data.passwordProtected,
        maxDownloads: link_data.maxDownloads,
        createdAt: link_data.createdAt
    })

    return CombinedVerify(
        creator_public_keys.ml_dsa_pk,
        creator_public_keys.kaz_sign_pk,
        link_bytes,
        link_data.signature
    )
```

**Fields Included in Signature:**

| Field | Type | Purpose |
|-------|------|---------|
| `resourceType` | string | Prevents cross-resource attacks |
| `resourceId` | UUID | Binds to specific file/folder |
| `creatorId` | UUID | Identifies signer for key lookup |
| `wrappedKey` | Base64 | Binds key material to signature |
| `permission` | `"read"` | Always "read" for links (prevents escalation) |
| `expiry` | ISO 8601 \| null | Prevents expiry tampering |
| `passwordProtected` | boolean | Prevents protection bypass |
| `maxDownloads` | int \| null | Prevents limit tampering |
| `createdAt` | ISO 8601 | Timestamp binding, replay prevention |

**Why NOT include `passwordHash` in signature?**

The `password_hash` (Argon2id output) is stored server-side for password verification but is NOT included in the signature payload because:
1. It's derived from user input at access time, not creation time
2. Including it would require the accessor to know the password before verification
3. The `passwordProtected` boolean is sufficient to indicate protection status

**Security Properties:**

| Attack | Mitigation |
|--------|------------|
| Server modifies `wrapped_key` | Signature verification fails |
| Server extends `expiry` | Signature verification fails |
| Server removes password protection | `passwordProtected=true` in signed payload |
| Attacker replays old link | `createdAt` + server-side revocation check |
| Cross-file key substitution | `resourceId` bound in signature |

## 5. Canonical Serialization

To ensure signature consistency across implementations:

### 5.1 Rules

1. **Field Order**: Alphabetical by field name
2. **String Encoding**: UTF-8
3. **Numbers**: Big-endian, fixed-width based on type
4. **Booleans**: 0x00 (false) or 0x01 (true)
5. **Arrays**: Length prefix (4 bytes) + concatenated elements
6. **Optional Fields**: 0x00 if absent, 0x01 + value if present
7. **Bytes**: Length prefix (4 bytes) + raw bytes

### 5.2 Example

```typescript
function canonicalSerialize(obj: Record<string, unknown>): Uint8Array {
  const fields = Object.keys(obj).sort();
  const parts: Uint8Array[] = [];

  for (const field of fields) {
    const value = obj[field];
    parts.push(encodeString(field));
    parts.push(encodeValue(value));
  }

  return concat(parts);
}

function encodeValue(value: unknown): Uint8Array {
  if (value === null || value === undefined) {
    return new Uint8Array([0x00]); // Absent
  }
  if (typeof value === "boolean") {
    return new Uint8Array([0x01, value ? 0x01 : 0x00]);
  }
  if (typeof value === "string") {
    const bytes = new TextEncoder().encode(value);
    return concat([
      new Uint8Array([0x02]),
      uint32BE(bytes.length),
      bytes
    ]);
  }
  if (typeof value === "number") {
    return concat([
      new Uint8Array([0x03]),
      uint64BE(value)
    ]);
  }
  if (value instanceof Uint8Array) {
    return concat([
      new Uint8Array([0x04]),
      uint32BE(value.length),
      value
    ]);
  }
  if (Array.isArray(value)) {
    const encoded = value.map(encodeValue);
    return concat([
      new Uint8Array([0x05]),
      uint32BE(value.length),
      ...encoded
    ]);
  }
  // Object
  return concat([
    new Uint8Array([0x06]),
    canonicalSerialize(value as Record<string, unknown>)
  ]);
}
```

## 6. Signature Wire Format

### 6.1 Combined Signature Structure

```
Combined Signature Format:
┌─────────────────────────────────────────────────────────────────┐
│  Version (1 byte) = 0x01                                        │
├─────────────────────────────────────────────────────────────────┤
│  ML-DSA Signature Length (2 bytes, big-endian) = 3,309         │
├─────────────────────────────────────────────────────────────────┤
│  ML-DSA-65 Signature (3,309 bytes)                              │
├─────────────────────────────────────────────────────────────────┤
│  KAZ-SIGN Signature Length (2 bytes, big-endian) = 356         │
├─────────────────────────────────────────────────────────────────┤
│  KAZ-SIGN-256 Signature (356 bytes)                             │
└─────────────────────────────────────────────────────────────────┘
```

### 6.2 TypeScript Interface

```typescript
interface CombinedSignature {
  version: 1;
  mlDsa: {
    algorithm: "ML-DSA-65";
    signature: Uint8Array;  // 3,309 bytes
  };
  kazSign: {
    algorithm: "KAZ-SIGN-256";
    signature: Uint8Array;  // 356 bytes
  };
}
```

## 7. Verification Requirements

### 7.1 File Verification

**When**: Before decryption (fail fast)

```
VerifyBeforeDecrypt(blob, db_record, expected_owner_id):
    // 1. Get owner's public keys
    owner_keys ← Server.getUserPublicKeys(expected_owner_id)

    // 2. Verify blob hash matches database record
    actual_blob_hash ← SHA-256(blob)
    if hex(actual_blob_hash) ≠ db_record.blob_hash:
        return Error("E_BLOB_HASH_MISMATCH")

    // 3. Reconstruct signature payload (must match signing exactly)
    signature_payload ← Canonicalize({
        blob_hash: db_record.blob_hash,      // Use stored hex string
        blob_size: db_record.blob_size,
        wrapped_dek: base64(db_record.wrapped_dek),
        encrypted_metadata: base64(db_record.encrypted_metadata),
        metadata_nonce: base64(db_record.metadata_nonce)
    })

    // 4. Verify combined signature
    // CombinedVerify will SHA-256 the payload internally
    if not CombinedVerify(owner_keys, signature_payload, db_record.signature):
        return Error("E_SIGNATURE_INVALID")

    // 5. Proceed to decryption
    return OK
```

### 7.2 Share Grant Verification

**When**: Before decapsulation

```
VerifyShareGrant(grant):
    // 1. Get grantor's public keys
    grantor_keys ← Server.getUserPublicKeys(grant.grantorId)

    // 2. Serialize grant fields (same as signing)
    grant_bytes ← CanonicalSerialize(grant.without_signature)

    // 3. Verify combined signature
    if not CombinedVerify(grantor_keys, grant_bytes, grant.signature):
        return Error("E_SIGNATURE_INVALID")

    // 4. Check expiry
    if grant.expiry and now() > parseTime(grant.expiry):
        return Error("E_GRANT_EXPIRED")

    return OK
```

### 7.3 Share Update Verification

**When**: Before applying share updates (server-side)

```
VerifyShareUpdate(share_id, update_request, update_signature):
    // 1. Fetch original share grant
    original_grant ← Server.getShare(share_id)
    if not original_grant:
        return Error("E_SHARE_NOT_FOUND")

    // 2. Verify requester has permission to update
    requester_id ← getCurrentUserId()
    if requester_id != original_grant.grantorId:
        // Check if requester is resource admin
        if not hasAdminPermission(requester_id, original_grant.resourceId):
            return Error("E_PERMISSION_DENIED")

    // 3. Get updater's public keys (original grantor or admin)
    updater_keys ← Server.getUserPublicKeys(requester_id)

    // 4. Serialize update fields (same as signing)
    update_bytes ← CanonicalSerialize({
        shareId: share_id,
        originalCreatedAt: original_grant.createdAt,
        permission: update_request.permission,
        expiry: update_request.expiry,
        updatedAt: update_request.updatedAt
    })

    // 5. Verify combined signature
    if not CombinedVerify(updater_keys, update_bytes, update_signature):
        return Error("E_SIGNATURE_INVALID")

    // 6. Validate permission transitions
    if not isValidPermissionChange(original_grant.permission, update_request.permission):
        return Error("E_INVALID_PERMISSION_CHANGE")

    return OK
```

**Permission Change Rules:**
- Owner/Admin can change to any permission level
- Original grantor can change to any permission level
- Cannot elevate permission beyond what grantor has on the resource

**Signature Storage:**
- Server stores the latest update signature
- Original grant signature is preserved separately
- Audit log records all signature changes

## 8. Security Considerations

### 8.1 Dual-Signature Requirement

Both signatures must verify:
- Prevents downgrade attacks
- Defense in depth against algorithm compromise
- Maintains security if either algorithm is broken

### 8.2 Hash-then-Sign

Always hash before signing:
- Reduces signature input size
- Prevents length-extension attacks
- Consistent signing regardless of message size

### 8.3 Signature Malleability

ML-DSA-65 signatures are deterministic, but:
- Never compare signatures directly for equality
- Always verify against the message
- Log signature verification results for audit

### 8.4 Time Attacks

Signature verification must be constant-time:
- Use verified implementations (liboqs, etc.)
- Don't short-circuit on first invalid byte
- Return same error regardless of failure point

## 9. Signature Operations Summary

| Operation | Signed Data | Signer |
|-----------|-------------|--------|
| File Upload | Canonicalize({blob_hash, blob_size, wrapped_dek, ...}) | File owner |
| File Move | Canonicalize({blob_hash, blob_size, wrapped_dek (new), ...}) | File owner |
| Share Grant | CanonicalSerialize(grant_fields) | Grantor |
| Share Update | CanonicalSerialize(update_fields) | Grantor or Admin |
| Folder Create | CanonicalSerialize(folder_fields) | Folder owner |
| Folder Update | CanonicalSerialize(folder_fields + id + updatedAt) | Folder owner |
| Folder Move | CanonicalSerialize(folder_fields + id + updatedAt) | Folder owner |
| Recovery Approval | CanonicalSerialize(approval_fields) | Trustee |
| Key Rotation | CanonicalSerialize(rotation_fields) | User |

> **Note**: All signed data is passed to `CombinedSign`, which internally applies SHA-256
> before signing. The `blob_hash` in file uploads is a hex-encoded string field, not a
> pre-hash of the signing input. See Section 3.3 for the complete hashing pipeline.

**Signed Fields by Operation:**

| Operation | Fields Included |
|-----------|-----------------|
| Share Grant | resourceType, resourceId, grantorId, granteeId, wrappedKey, kemCiphertexts, permission, recursive, expiry, createdAt |
| Share Update | shareId, originalCreatedAt, permission, expiry, updatedAt |

## 10. Error Codes

| Code | Description | Action |
|------|-------------|--------|
| `E_SIGNATURE_INVALID` | Signature verification failed | Reject operation |
| `E_SIGNER_NOT_FOUND` | Signer's public keys unavailable | Fetch keys, retry |
| `E_ALGORITHM_MISMATCH` | Wrong signature algorithm | Check format |
| `E_SIGNATURE_MALFORMED` | Cannot parse signature | Check encoding |

## 11. Implementation Checklist

- [ ] Use SHA-256 pre-hash for all signatures
- [ ] Verify BOTH ML-DSA and KAZ-SIGN
- [ ] Implement canonical serialization exactly as specified
- [ ] Verify signatures BEFORE any decryption
- [ ] Use constant-time comparison internally
- [ ] Log all signature verification failures
- [ ] Handle missing public keys gracefully
