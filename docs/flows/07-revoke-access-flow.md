# Revoke Access Flow

**Version**: 1.0.0
**Status**: Draft
**Last Updated**: 2025-01

## 1. Overview

This document describes the flow for revoking access to shared files and folders. Revocation involves deleting share grants and optionally rotating encryption keys to ensure revoked users cannot access content.

## 2. Prerequisites

- Revoker is logged in with decrypted keys
- Revoker has permission to revoke (grantor, owner, or admin)
- Share grant exists in the system

> **API Path Convention**: Client code examples use `/api/v1/...` paths assuming the app proxies
> API requests to `https://api.securesharing.com/v1/...`. For direct API calls, remove the
> `/api/v1` prefix and use the API base URL directly.

## 3. Basic Revoke Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       BASIC REVOKE FLOW                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────┐         ┌─────────┐         ┌─────────┐                        │
│  │ Revoker │         │ Client  │         │ Server  │                        │
│  │ (Alice) │         │         │         │         │                        │
│  └────┬────┘         └────┬────┘         └────┬────┘                        │
│       │                   │                   │                              │
│       │  1. Revoke Bob's  │                   │                              │
│       │     access        │                   │                              │
│       │──────────────────▶│                   │                              │
│       │                   │                   │                              │
│       │                   │  2. DELETE /shares/{share_id}                   │
│       │                   │──────────────────▶│                              │
│       │                   │                   │                              │
│       │                   │                   │  ┌─────────────┐            │
│       │                   │                   │  │ 3. Verify   │            │
│       │                   │                   │  │ - Permission│            │
│       │                   │                   │  │ - Delete    │            │
│       │                   │                   │  │   share     │            │
│       │                   │                   │  │ - Audit log │            │
│       │                   │                   │  └─────────────┘            │
│       │                   │                   │                              │
│       │                   │  4. Share Revoked │                              │
│       │                   │◀──────────────────│                              │
│       │                   │                   │                              │
│       │  5. Success       │                   │                              │
│       │◀──────────────────│                   │                              │
│       │                   │                   │                              │
│       │                   │                   │                              │
│       │  [NOTE: Bob's access is removed, but if Bob cached the DEK/KEK      │
│       │   locally, they could still decrypt cached encrypted content.       │
│       │   For complete security, key rotation is required.]                 │
│       │                   │                   │                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 4. Revoke with Key Rotation (Secure)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                  REVOKE WITH KEY ROTATION (FILE)                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────┐         ┌─────────┐         ┌─────────┐         ┌─────────┐   │
│  │ Revoker │         │ Client  │         │ Server  │         │ Storage │   │
│  │ (Alice) │         │         │         │         │         │         │   │
│  └────┬────┘         └────┬────┘         └────┬────┘         └────┬────┘   │
│       │                   │                   │                   │         │
│       │  1. Revoke + Rotate                  │                   │         │
│       │──────────────────▶│                   │                   │         │
│       │                   │                   │                   │         │
│       │                   │  2. Get file details                 │         │
│       │                   │──────────────────▶│                   │         │
│       │                   │                   │                   │         │
│       │                   │  3. File metadata │                   │         │
│       │                   │◀──────────────────│                   │         │
│       │                   │                   │                   │         │
│       │                   │  4. Get download URL                 │         │
│       │                   │──────────────────▶│                   │         │
│       │                   │                   │                   │         │
│       │                   │  5. Download encrypted blob                    │
│       │                   │◀──────────────────────────────────────│         │
│       │                   │                   │                   │         │
│       │                   │  ┌────────────────────────────────┐  │         │
│       │                   │  │  6. CLIENT-SIDE RE-ENCRYPTION  │  │         │
│       │                   │  │                                │  │         │
│       │                   │  │  a. Decrypt with old DEK       │  │         │
│       │                   │  │                                │  │         │
│       │                   │  │  b. Generate new DEK           │  │         │
│       │                   │  │                                │  │         │
│       │                   │  │  c. Re-encrypt with new DEK    │  │         │
│       │                   │  │                                │  │         │
│       │                   │  │  d. Wrap new DEK with folder   │  │         │
│       │                   │  │     KEK                        │  │         │
│       │                   │  │                                │  │         │
│       │                   │  │  e. Re-wrap for remaining      │  │         │
│       │                   │  │     share recipients           │  │         │
│       │                   │  │                                │  │         │
│       │                   │  │  f. Sign new package           │  │         │
│       │                   │  │                                │  │         │
│       │                   │  └────────────────────────────────┘  │         │
│       │                   │                   │                   │         │
│       │                   │  7. Upload new encrypted blob                  │
│       │                   │──────────────────────────────────────▶│         │
│       │                   │                   │                   │         │
│       │                   │  8. Update file + delete share                 │
│       │                   │──────────────────▶│                   │         │
│       │                   │                   │                   │         │
│       │                   │                   │  ┌─────────────┐  │         │
│       │                   │                   │  │ 9. Atomic   │  │         │
│       │                   │                   │  │ - Update file│ │         │
│       │                   │                   │  │ - Delete old │ │         │
│       │                   │                   │  │   share      │ │         │
│       │                   │                   │  │ - Update     │ │         │
│       │                   │                   │  │   remaining  │ │         │
│       │                   │                   │  │   shares     │ │         │
│       │                   │                   │  │ - Delete old │ │         │
│       │                   │                   │  │   blob       │ │         │
│       │                   │                   │  └─────────────┘  │         │
│       │                   │                   │                   │         │
│       │                   │  10. Revocation complete             │         │
│       │                   │◀──────────────────│                   │         │
│       │                   │                   │                   │         │
│       │  11. Success      │                   │                   │         │
│       │◀──────────────────│                   │                   │         │
│       │                   │                   │                   │         │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 5. Implementation

### 5.1 Basic Revoke

```typescript
async function revokeShare(shareId: string): Promise<void> {
  const response = await fetch(`/api/v1/shares/${shareId}`, {
    method: 'DELETE',
    headers: {
      'Authorization': `Bearer ${sessionManager.getSession()}`
    }
  });

  if (!response.ok) {
    const error = await response.json();
    throw new RevokeError(error.error.code, error.error.message);
  }
}
```

### 5.2 Bulk Revoke

```typescript
async function revokeMultipleShares(shareIds: string[]): Promise<BulkResult> {
  const response = await fetch('/api/v1/shares/revoke-bulk', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${sessionManager.getSession()}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ share_ids: shareIds })
  });

  const { data } = await response.json();
  return {
    revoked: data.revoked,
    failed: data.failed
  };
}
```

### 5.3 Revoke All for Resource

```typescript
async function revokeAllSharesForResource(
  resourceType: 'file' | 'folder',
  resourceId: string
): Promise<void> {

  const response = await fetch(
    `/api/v1/shares/resource/${resourceType}/${resourceId}`,
    {
      method: 'DELETE',
      headers: {
        'Authorization': `Bearer ${sessionManager.getSession()}`
      }
    }
  );

  if (!response.ok) {
    const error = await response.json();
    throw new RevokeError(error.error.code, error.error.message);
  }
}
```

### 5.4 Revoke with File Re-encryption

```typescript
async function revokeWithReencryption(
  shareId: string,
  fileId: string
): Promise<void> {

  // Get file details and current shares
  const fileDetails = await getFileDetails(fileId);
  const shares = await getSharesForResource('file', fileId);

  // Filter out the share being revoked
  const remainingShares = shares.filter(s => s.id !== shareId);

  // Download encrypted file
  const downloadInfo = await getDownloadUrl(fileId);
  const encryptedBlob = await downloadBlob(downloadInfo);

  // Decrypt with old DEK
  const folderKek = await getFolderKek(fileDetails.folder_id);
  const oldDek = await aesKeyUnwrap(
    folderKek,
    base64Decode(fileDetails.wrapped_dek)
  );

  const { content: plaintext, metadata } = await decryptFile(
    encryptedBlob,
    fileDetails.blob_hash,
    oldDek,
    fileDetails.encrypted_metadata,
    fileDetails.metadata_nonce
  );

  // Generate new DEK and re-encrypt
  const newDek = crypto.getRandomValues(new Uint8Array(32));
  const { encryptedBlob: newEncryptedBlob, blobHash: newBlobHash } =
    await encryptFileContent(new Blob([plaintext]), newDek);

  // Encrypt metadata with new DEK
  const newMetadataNonce = crypto.getRandomValues(new Uint8Array(12));
  const metadataAad = new TextEncoder().encode('file-metadata');
  const newEncryptedMetadata = await aesGcmEncrypt(
    newDek,
    newMetadataNonce,
    new TextEncoder().encode(JSON.stringify(metadata)),
    metadataAad  // AAD per docs/crypto/03-encryption-protocol.md Section 2.2
  );

  // Wrap new DEK with folder KEK
  const newWrappedDek = await aesKeyWrap(folderKek, newDek);

  // Re-encapsulate for remaining share recipients
  const updatedShares = await Promise.all(
    remainingShares.map(async (share) => {
      const granteeKeys = await getUserPublicKeys(share.grantee_id);
      const { wrappedKey, kemCiphertexts } = await encapsulateKey(
        newDek,
        {
          ml_kem: base64Decode(granteeKeys.ml_kem),
          kaz_kem: base64Decode(granteeKeys.kaz_kem)
        }
      );

      return {
        share_id: share.id,
        wrapped_key: base64Encode(wrappedKey),
        kem_ciphertexts: kemCiphertexts
      };
    })
  );

  // Sign new package
  const signature = await signFilePackage({
    blob_hash: newBlobHash,
    blob_size: newEncryptedBlob.size,
    wrapped_dek: base64Encode(newWrappedDek),
    encrypted_metadata: base64Encode(newEncryptedMetadata),
    metadata_nonce: base64Encode(newMetadataNonce)
  });

  // Clear keys
  oldDek.fill(0);
  newDek.fill(0);

  // Upload new blob
  const uploadSession = await initiateFileUpdate(fileId, {
    encrypted_metadata: base64Encode(newEncryptedMetadata),
    metadata_nonce: base64Encode(newMetadataNonce),
    wrapped_dek: base64Encode(newWrappedDek),
    blob_size: newEncryptedBlob.size,
    blob_hash: newBlobHash,
    signature
  });

  await uploadBlob(newEncryptedBlob, uploadSession.uploadUrl, uploadSession.headers);

  // Atomic update on server
  await fetch(`/api/v1/files/${fileId}/rotate-key`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${sessionManager.getSession()}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      revoke_share_id: shareId,
      updated_shares: updatedShares
    })
  });
}
```

## 6. Folder KEK Rotation

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    FOLDER KEK ROTATION                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  When revoking folder access, KEK rotation ensures the revoked user         │
│  cannot decrypt any cached content.                                          │
│                                                                              │
│  BEFORE ROTATION:                                                           │
│  ────────────────                                                           │
│                                                                              │
│  Folder "Projects" (KEK_old)                                                │
│  ├── file1.pdf (DEK_1 wrapped by KEK_old)                                   │
│  ├── file2.docx (DEK_2 wrapped by KEK_old)                                  │
│  └── Reports/ (KEK_reports wrapped by KEK_old)                              │
│       └── report.xlsx (DEK_3 wrapped by KEK_reports)                        │
│                                                                              │
│  Bob has: KEK_old (via share)                                               │
│                                                                              │
│  ─────────────────────────────────────────────────────────────────────────  │
│                                                                              │
│  AFTER ROTATION:                                                            │
│  ───────────────                                                            │
│                                                                              │
│  Folder "Projects" (KEK_new)                                                │
│  ├── file1.pdf (DEK_1 wrapped by KEK_new)  ← re-wrapped                     │
│  ├── file2.docx (DEK_2 wrapped by KEK_new) ← re-wrapped                     │
│  └── Reports/ (KEK_reports wrapped by KEK_new) ← re-wrapped                 │
│       └── report.xlsx (DEK_3 wrapped by KEK_reports) ← unchanged            │
│                                                                              │
│  Bob has: KEK_old (INVALID - cannot unwrap new wrapped DEKs)                │
│                                                                              │
│  NOTE: Only direct children need re-wrapping. Nested content uses           │
│  the same child KEKs, just re-wrapped at the top level.                     │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### KEK Rotation Implementation

```typescript
async function rotateFolderKek(
  folderId: string,
  revokedShareId: string
): Promise<void> {

  // Get folder details
  const folderDetails = await getFolderDetails(folderId);

  // Get folder contents
  const contents = await getFolderContents(folderId);

  // Decrypt current KEK
  const oldKek = await decapsulateKey(
    folderDetails.owner_key_access,
    keyManager.getKeys().privateKeys
  );

  // Generate new KEK
  const newKek = crypto.getRandomValues(new Uint8Array(32));

  // Create new owner_key_access
  const { wrappedKey: newOwnerWrappedKek, kemCiphertexts: newOwnerKemCiphertexts } =
    await encapsulateKey(newKek, {
      ml_kem: keyManager.getKeys().publicKeys.ml_kem,
      kaz_kem: keyManager.getKeys().publicKeys.kaz_kem
    });

  // Re-wrap KEK for parent (if not root)
  let newWrappedKek: string | undefined;
  if (folderDetails.parent_id) {
    const parentKek = await getFolderKek(folderDetails.parent_id);
    newWrappedKek = base64Encode(await aesKeyWrap(parentKek, newKek));
    parentKek.fill(0);
  }

  // Re-wrap all direct children
  const rewrappedChildren: RewrappedChild[] = [];

  // Re-wrap subfolders
  for (const subfolder of contents.subfolders) {
    const childKek = await aesKeyUnwrap(oldKek, base64Decode(subfolder.wrapped_kek));
    const newChildWrappedKek = await aesKeyWrap(newKek, childKek);
    childKek.fill(0);

    rewrappedChildren.push({
      type: 'folder',
      id: subfolder.id,
      wrapped_kek: base64Encode(newChildWrappedKek)
    });
  }

  // Re-wrap files
  for (const file of contents.files) {
    const dek = await aesKeyUnwrap(oldKek, base64Decode(file.wrapped_dek));
    const newWrappedDek = await aesKeyWrap(newKek, dek);
    dek.fill(0);

    rewrappedChildren.push({
      type: 'file',
      id: file.id,
      wrapped_dek: base64Encode(newWrappedDek)
    });
  }

  // Get remaining shares (excluding revoked)
  const shares = await getSharesForResource('folder', folderId);
  const remainingShares = shares.filter(s => s.id !== revokedShareId);

  // Re-encapsulate for remaining recipients
  const updatedShares = await Promise.all(
    remainingShares.map(async (share) => {
      const granteeKeys = await getUserPublicKeys(share.grantee_id);
      const { wrappedKey, kemCiphertexts } = await encapsulateKey(
        newKek,
        {
          ml_kem: base64Decode(granteeKeys.ml_kem),
          kaz_kem: base64Decode(granteeKeys.kaz_kem)
        }
      );

      return {
        share_id: share.id,
        wrapped_key: base64Encode(wrappedKey),
        kem_ciphertexts: kemCiphertexts
      };
    })
  );

  // Clear keys
  oldKek.fill(0);
  newKek.fill(0);

  // Submit rotation to server
  await fetch(`/api/v1/folders/${folderId}/rotate-kek`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${sessionManager.getSession()}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      new_owner_key_access: {
        wrapped_kek: base64Encode(newOwnerWrappedKek),
        kem_ciphertexts: newOwnerKemCiphertexts
      },
      new_wrapped_kek: newWrappedKek,
      rewrapped_children: rewrappedChildren,
      revoke_share_id: revokedShareId,
      updated_shares: updatedShares
    })
  });
}
```

## 7. Revocation Decision Tree

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    REVOCATION DECISION TREE                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Revoke Access Request                                                      │
│       │                                                                      │
│       ▼                                                                      │
│  ┌─────────────────────────────────────┐                                    │
│  │ Is the content sensitive enough     │                                    │
│  │ to warrant key rotation?            │                                    │
│  └───────────────┬─────────────────────┘                                    │
│                  │                                                           │
│        ┌────────┴────────┐                                                  │
│        │                 │                                                   │
│       YES               NO                                                   │
│        │                 │                                                   │
│        ▼                 ▼                                                   │
│  ┌───────────┐    ┌───────────┐                                             │
│  │ Is it a   │    │ Simple    │                                             │
│  │ file or   │    │ Revoke    │                                             │
│  │ folder?   │    │ (delete   │                                             │
│  └─────┬─────┘    │ share)    │                                             │
│        │          └───────────┘                                             │
│   ┌────┴────┐                                                               │
│   │         │                                                                │
│  FILE    FOLDER                                                             │
│   │         │                                                                │
│   ▼         ▼                                                                │
│ ┌─────────────┐  ┌─────────────────────────────────────┐                    │
│ │ Re-encrypt  │  │ How deep is the folder?             │                    │
│ │ file with   │  └───────────────┬─────────────────────┘                    │
│ │ new DEK     │                  │                                          │
│ └─────────────┘          ┌───────┴───────┐                                  │
│                          │               │                                   │
│                       SHALLOW          DEEP                                  │
│                       (few items)    (many items)                           │
│                          │               │                                   │
│                          ▼               ▼                                   │
│                    ┌───────────┐   ┌────────────────┐                       │
│                    │ Full KEK  │   │ KEK rotation   │                       │
│                    │ rotation  │   │ only (no file  │                       │
│                    │ + re-wrap │   │ re-encryption) │                       │
│                    │ all       │   │                │                       │
│                    └───────────┘   │ [Files keep    │                       │
│                                    │  same DEK,     │                       │
│                                    │  wrapped by    │                       │
│                                    │  new KEK]      │                       │
│                                    └────────────────┘                       │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Decision Implementation

```typescript
interface RevocationOptions {
  rotateKeys: boolean;
  reencryptFiles: boolean;  // Only if rotateKeys is true
}

async function revokeWithOptions(
  shareId: string,
  options: RevocationOptions
): Promise<void> {

  const share = await getShare(shareId);

  if (!options.rotateKeys) {
    // Simple revoke
    await revokeShare(shareId);
    return;
  }

  if (share.resource_type === 'file') {
    // File: always re-encrypt with new DEK
    await revokeWithReencryption(shareId, share.resource_id);
  } else {
    // Folder: rotate KEK
    if (options.reencryptFiles) {
      // Full rotation including re-encryption of all files
      await rotateFolderKekWithReencryption(share.resource_id, shareId);
    } else {
      // Just KEK rotation (faster, but files keep same DEK)
      await rotateFolderKek(share.resource_id, shareId);
    }
  }
}
```

## 8. Error Handling

| Error Code | Cause | Recovery |
|------------|-------|----------|
| `E_SHARE_NOT_FOUND` | Share doesn't exist | Already revoked |
| `E_PERMISSION_DENIED` | Cannot revoke this share | Need owner/admin |
| `E_KEK_ROTATION_INCOMPLETE` | Children not re-wrapped | Retry rotation |
| `E_FILE_NOT_FOUND` | File deleted during rotation | Skip file |

## 9. Security Considerations

### 9.1 Timing

- Revoke should be processed immediately
- Key rotation should complete atomically
- Old keys should be invalidated before new keys active

### 9.2 Caching

- Revoked user may have cached decrypted content
- Key rotation prevents future decryption of updated content
- Cannot revoke already-downloaded plaintext

### 9.3 Audit

- All revocations should be logged
- Include who revoked, when, and what
- Track key rotation events

### 9.4 Re-share Prevention

- After revocation, recipient cannot re-share
- Signature verification prevents forged shares
- Server validates grantor still has access
