# Share Folder Flow

**Version**: 1.0.0
**Status**: Draft
**Last Updated**: 2025-01

## 1. Overview

This document describes the flow for sharing a folder with another user. Folder sharing involves encapsulating the folder's KEK, which automatically grants access to all files and subfolders within.

## 2. Prerequisites

- Grantor (sharer) is logged in with decrypted keys
- Grantor has share permission on the folder (owner or admin)
- Recipient (grantee) is a registered user with public keys
- Folder KEK is accessible to grantor

> **API Path Convention**: Client code examples use `/api/v1/...` paths assuming the app proxies
> API requests to `https://api.securesharing.com/v1/...`. For direct API calls, remove the
> `/api/v1` prefix and use the API base URL directly.

## 3. Share Folder Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       SHARE FOLDER FLOW                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────┐         ┌─────────┐         ┌─────────┐                        │
│  │ Grantor │         │ Client  │         │ Server  │                        │
│  │ (Alice) │         │         │         │         │                        │
│  └────┬────┘         └────┬────┘         └────┬────┘                        │
│       │                   │                   │                              │
│       │  1. Share Folder  │                   │                              │
│       │     "Projects"    │                   │                              │
│       │     with Bob      │                   │                              │
│       │──────────────────▶│                   │                              │
│       │                   │                   │                              │
│       │                   │  2. Search User (Bob)                           │
│       │                   │──────────────────▶│                              │
│       │                   │                   │                              │
│       │                   │  3. User found + Public Keys                    │
│       │                   │◀──────────────────│                              │
│       │                   │                   │                              │
│       │  4. Confirm       │                   │                              │
│       │     recipient     │                   │                              │
│       │◀──────────────────│                   │                              │
│       │                   │                   │                              │
│       │  5. Select        │                   │                              │
│       │     permission    │                   │                              │
│       │     + recursive?  │                   │                              │
│       │──────────────────▶│                   │                              │
│       │                   │                   │                              │
│       │                   │  6. Get Folder Details                          │
│       │                   │──────────────────▶│                              │
│       │                   │                   │                              │
│       │                   │  7. Folder metadata + owner_key_access          │
│       │                   │◀──────────────────│                              │
│       │                   │                   │                              │
│       │                   │  ┌────────────────────────────────┐             │
│       │                   │  │  8. CLIENT-SIDE OPERATIONS     │             │
│       │                   │  │                                │             │
│       │                   │  │  a. Decrypt folder KEK         │             │
│       │                   │  │     (via owner_key_access)     │             │
│       │                   │  │                                │             │
│       │                   │  │  b. Encapsulate KEK for Bob's  │             │
│       │                   │  │     public keys (KEM)          │             │
│       │                   │  │                                │             │
│       │                   │  │  c. Sign share grant           │             │
│       │                   │  │                                │             │
│       │                   │  └────────────────────────────────┘             │
│       │                   │                   │                              │
│       │                   │  9. Create Folder Share Grant                   │
│       │                   │──────────────────▶│                              │
│       │                   │                   │                              │
│       │                   │                   │  ┌─────────────┐            │
│       │                   │                   │  │ 10. Verify  │            │
│       │                   │                   │  │ - Permission│            │
│       │                   │                   │  │ - Signature │            │
│       │                   │                   │  │ - Store     │            │
│       │                   │                   │  │ - Notify    │            │
│       │                   │                   │  └─────────────┘            │
│       │                   │                   │                              │
│       │                   │  11. Share Created                              │
│       │                   │◀──────────────────│                              │
│       │                   │                   │                              │
│       │  12. Success      │                   │                              │
│       │◀──────────────────│                   │                              │
│       │                   │                   │                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 4. Access Chain After Sharing

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    BOB'S ACCESS AFTER SHARE                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Before (Alice's view):                                                     │
│  ──────────────────────                                                     │
│                                                                              │
│  Alice's Private Key                                                        │
│       │ decapsulates (from owner_key_access)                                │
│       ▼                                                                      │
│  KEK_projects                                                               │
│       │                                                                      │
│       ├──▶ file1.pdf (DEK wrapped by KEK_projects)                          │
│       ├──▶ file2.docx (DEK wrapped by KEK_projects)                         │
│       │                                                                      │
│       └──▶ Subfolder "Reports"                                              │
│             │ (KEK_reports wrapped by KEK_projects)                         │
│             │                                                               │
│             └──▶ report.xlsx (DEK wrapped by KEK_reports)                   │
│                                                                              │
│  ─────────────────────────────────────────────────────────────────────────  │
│                                                                              │
│  After Share (Bob's view):                                                  │
│  ─────────────────────────                                                  │
│                                                                              │
│  Bob's Private Key                                                          │
│       │ decapsulates (from share grant's wrapped_key)                       │
│       ▼                                                                      │
│  KEK_projects (same key, different encapsulation)                           │
│       │                                                                      │
│       ├──▶ file1.pdf ✓ (can decrypt - has KEK)                              │
│       ├──▶ file2.docx ✓ (can decrypt - has KEK)                             │
│       │                                                                      │
│       └──▶ Subfolder "Reports" ✓ (if recursive=true)                        │
│             │ (unwrap KEK_reports using KEK_projects)                       │
│             │                                                               │
│             └──▶ report.xlsx ✓ (can decrypt)                                │
│                                                                              │
│  NEW FILES ADDED LATER:                                                     │
│  ──────────────────────                                                     │
│                                                                              │
│  Alice adds new_file.txt to Projects folder                                 │
│       │                                                                      │
│       └──▶ DEK is wrapped by KEK_projects                                   │
│             │                                                               │
│             └──▶ Bob can automatically decrypt (has KEK_projects)           │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 5. Detailed Steps

### 5.1 Step 6-7: Get Folder Details and Verify Signature

```typescript
async function getFolderForSharing(folderId: string): Promise<FolderDetails> {
  const response = await fetch(`/api/v1/folders/${folderId}`, {
    headers: {
      'Authorization': `Bearer ${sessionManager.getSession()}`
    }
  });

  if (!response.ok) {
    const error = await response.json();
    throw new ShareError(error.error.code, error.error.message);
  }

  const { data } = await response.json();

  // MANDATORY: Verify folder signature before trusting metadata or KEK
  // See crypto/05-signature-protocol.md Section 4.4
  const signatureValid = await verifyFolderSignature(
    data.owner.public_keys,
    data.signature,
    {
      parentId: data.parent_id,
      encryptedMetadata: data.encrypted_metadata,
      metadataNonce: data.metadata_nonce,
      ownerKeyAccess: data.owner_key_access,
      wrappedKek: data.wrapped_kek,
      createdAt: data.created_at
    }
  );

  if (!signatureValid) {
    throw new ShareError('E_SIGNATURE_INVALID', 'Folder signature verification failed');
  }

  // Verify share permission
  if (!canShare(data.access)) {
    throw new ShareError('E_PERMISSION_DENIED', 'Cannot share this folder');
  }

  return data;
}

// Response includes owner public keys and signature for verification
interface FolderDetails {
  id: string;
  owner_id: string;
  parent_id: string | null;
  encrypted_metadata: string;
  metadata_nonce: string;
  owner_key_access: {
    wrapped_kek: string;
    kem_ciphertexts: KemCiphertext[];
  };
  wrapped_kek: string | null;  // For non-root: wrapped by parent KEK
  signature: {                 // Owner's signature (required for verification)
    ml_dsa: string;
    kaz_sign: string;
  };
  owner: {                     // Owner info (required for signature verification)
    id: string;
    public_keys: {
      ml_dsa: string;
      kaz_sign: string;
    };
  };
  is_root: boolean;
  item_count: number;
  created_at: string;
  updated_at: string;
  access: {
    source: 'owner' | 'share';
    permission: 'owner' | 'admin' | 'write' | 'read';
  };
}
```

### 5.2 Step 8: Client-Side Operations

```typescript
async function createFolderShareGrant(
  folderId: string,
  folderDetails: FolderDetails,
  grantee: UserSearchResult,
  options: FolderShareOptions
): Promise<ShareGrantRequest> {

  const keys = keyManager.getKeys();

  // 8a. Decrypt folder KEK via owner_key_access
  const kek = await decapsulateKey(
    folderDetails.owner_key_access,
    {
      ml_kem: keys.privateKeys.ml_kem,
      kaz_kem: keys.privateKeys.kaz_kem
    }
  );

  // 8b. Encapsulate KEK for grantee's public keys
  const granteePublicKeys = {
    ml_kem: base64Decode(grantee.public_keys.ml_kem),
    kaz_kem: base64Decode(grantee.public_keys.kaz_kem)
  };

  const { wrappedKey, kemCiphertexts } = await encapsulateKey(
    kek,
    granteePublicKeys
  );

  // Clear KEK from memory
  kek.fill(0);

  // 8c. Sign share grant
  const signaturePayload = canonicalize({
    resource_type: 'folder',
    resource_id: folderId,
    grantee_id: grantee.id,
    permission: options.permission,
    recursive: options.recursive,
    expiry: options.expiry?.toISOString() || null,
    wrapped_key: base64Encode(wrappedKey),
    kem_ciphertexts: kemCiphertexts
  });

  const signature = await combinedSign(
    {
      ml_dsa: keys.privateKeys.ml_dsa,
      kaz_sign: keys.privateKeys.kaz_sign
    },
    signaturePayload
  );

  return {
    resource_type: 'folder',
    resource_id: folderId,
    grantee_id: grantee.id,
    wrapped_key: base64Encode(wrappedKey),
    kem_ciphertexts: kemCiphertexts,
    permission: options.permission,
    recursive: options.recursive,
    expiry: options.expiry?.toISOString(),
    signature
  };
}
```

### 5.3 Recursive Share Options

```typescript
interface FolderShareOptions {
  granteeId: string;
  permission: 'read' | 'write' | 'admin';
  recursive: boolean;  // Include subfolders
  expiry?: Date;
}

// Explanation of recursive option
/*
  recursive: true
  - Grantee can access all files in folder
  - Grantee can access all subfolders
  - Grantee can access files in subfolders
  - New content added later is automatically accessible

  recursive: false
  - Grantee can access files directly in folder
  - Grantee CANNOT access subfolders
  - Use case: Share specific folder level only
*/
```

## 6. Complete Folder Share Implementation

```typescript
async function shareFolder(
  folderId: string,
  granteeEmail: string,
  permission: 'read' | 'write' | 'admin',
  recursive: boolean = true,
  expiry?: Date
): Promise<ShareGrant> {

  // Search for user
  const searchResults = await searchUsers(granteeEmail);
  const grantee = searchResults.find(
    u => u.email.toLowerCase() === granteeEmail.toLowerCase()
  );

  if (!grantee) {
    throw new ShareError('E_GRANTEE_NOT_FOUND', 'User not found');
  }

  // Prevent self-share
  const currentUser = sessionManager.getUser();
  if (grantee.id === currentUser.id) {
    throw new ShareError('E_CANNOT_SHARE_SELF', 'Cannot share with yourself');
  }

  // Get folder details
  const folderDetails = await getFolderForSharing(folderId);

  // Cannot share root folder
  if (folderDetails.is_root) {
    throw new ShareError('E_CANNOT_SHARE_ROOT', 'Cannot share root folder');
  }

  // Create share grant
  const grant = await createFolderShareGrant(
    folderId,
    folderDetails,
    grantee,
    { granteeId: grantee.id, permission, recursive, expiry }
  );

  // Submit to server
  const response = await fetch('/api/v1/shares', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${sessionManager.getSession()}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(grant)
  });

  if (!response.ok) {
    const error = await response.json();
    throw new ShareError(error.error.code, error.error.message);
  }

  return (await response.json()).data;
}
```

## 7. Recipient Access Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                BOB ACCESSING SHARED FOLDER                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────┐         ┌─────────┐         ┌─────────┐                        │
│  │   Bob   │         │ Client  │         │ Server  │                        │
│  └────┬────┘         └────┬────┘         └────┬────┘                        │
│       │                   │                   │                              │
│       │  1. View Shared   │                   │                              │
│       │     Folders       │                   │                              │
│       │──────────────────▶│                   │                              │
│       │                   │                   │                              │
│       │                   │  2. GET /folders/shared                         │
│       │                   │──────────────────▶│                              │
│       │                   │                   │                              │
│       │                   │  3. List of shares + wrapped KEKs               │
│       │                   │◀──────────────────│                              │
│       │                   │                   │                              │
│       │  4. Open "Projects"│                  │                              │
│       │     folder         │                  │                              │
│       │──────────────────▶│                   │                              │
│       │                   │                   │                              │
│       │                   │  5. GET /folders/{id}/contents                  │
│       │                   │     ?via_share={share_id}                       │
│       │                   │──────────────────▶│                              │
│       │                   │                   │                              │
│       │                   │  6. Folder contents + child wrapped keys        │
│       │                   │◀──────────────────│                              │
│       │                   │                   │                              │
│       │                   │  ┌────────────────────────────────┐             │
│       │                   │  │  7. DECRYPTION FLOW            │             │
│       │                   │  │                                │             │
│       │                   │  │  a. Decapsulate folder KEK     │             │
│       │                   │  │     from share grant           │             │
│       │                   │  │                                │             │
│       │                   │  │  b. Decrypt folder metadata    │             │
│       │                   │  │                                │             │
│       │                   │  │  For each file:                │             │
│       │                   │  │  c. Unwrap file DEK with KEK   │             │
│       │                   │  │  d. Decrypt file metadata      │             │
│       │                   │  │                                │             │
│       │                   │  │  For each subfolder:           │             │
│       │                   │  │  e. Unwrap subfolder KEK       │             │
│       │                   │  │  f. Decrypt subfolder metadata │             │
│       │                   │  │                                │             │
│       │                   │  └────────────────────────────────┘             │
│       │                   │                   │                              │
│       │  8. Display       │                   │                              │
│       │     contents      │                   │                              │
│       │◀──────────────────│                   │                              │
│       │                   │                   │                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Recipient Access Implementation

```typescript
async function accessSharedFolder(
  folderId: string,
  shareId: string
): Promise<DecryptedFolderContents> {

  // Get share details (includes wrapped KEK and grantor signature)
  const shareResponse = await fetch(`/api/v1/shares/${shareId}`, {
    headers: {
      'Authorization': `Bearer ${sessionManager.getSession()}`
    }
  });

  const { data: share } = await shareResponse.json();

  // MANDATORY: Verify share grant signature before trusting wrapped key
  // See crypto/05-signature-protocol.md Section 4.2
  const shareSignatureValid = await verifyShareSignature(
    share.grantor.public_keys,
    share.signature,
    {
      resourceType: share.resource_type,
      resourceId: share.resource_id,
      grantorId: share.grantor.id,
      granteeId: share.grantee_id,
      wrappedKey: share.wrapped_key,
      kemCiphertexts: share.kem_ciphertexts,
      permission: share.permission,
      recursive: share.recursive,
      expiry: share.expiry,
      createdAt: share.created_at
    }
  );

  if (!shareSignatureValid) {
    throw new ShareError('E_SIGNATURE_INVALID', 'Share grant signature verification failed');
  }

  // Get folder contents via share
  const response = await fetch(
    `/api/v1/folders/${folderId}/contents?via_share=${shareId}`,
    {
      headers: {
        'Authorization': `Bearer ${sessionManager.getSession()}`
      }
    }
  );

  const { data } = await response.json();

  // MANDATORY: Verify folder signature before trusting metadata or KEK structure
  // See crypto/05-signature-protocol.md Section 4.4
  const folderSignatureValid = await verifyFolderSignature(
    data.folder.owner.public_keys,
    data.folder.signature,
    {
      parentId: data.folder.parent_id,
      encryptedMetadata: data.folder.encrypted_metadata,
      metadataNonce: data.folder.metadata_nonce,
      ownerKeyAccess: data.folder.owner_key_access,
      wrappedKek: data.folder.wrapped_kek,
      createdAt: data.folder.created_at
    }
  );

  if (!folderSignatureValid) {
    throw new ShareError('E_SIGNATURE_INVALID', 'Folder signature verification failed');
  }

  // Decapsulate folder KEK using share grant's wrapped key
  const keys = keyManager.getKeys();
  const folderKek = await decapsulateKey(
    {
      wrapped_key: share.wrapped_key,
      kem_ciphertexts: share.kem_ciphertexts
    },
    {
      ml_kem: keys.privateKeys.ml_kem,
      kaz_kem: keys.privateKeys.kaz_kem
    }
  );

  // Decrypt folder metadata
  const folderMetadataAad = new TextEncoder().encode('folder-metadata');
  const folderMetadata = await decryptMetadata(
    data.folder.encrypted_metadata,
    data.folder.metadata_nonce,
    folderKek,
    folderMetadataAad  // AAD per docs/crypto/03-encryption-protocol.md Section 2.2
  );

  // Decrypt subfolders
  const subfolders = await Promise.all(
    data.subfolders.map(async (sf) => {
      // Unwrap subfolder KEK with parent KEK
      const subKek = await aesKeyUnwrap(
        folderKek,
        base64Decode(sf.wrapped_kek)
      );

      const folderMetadataAad = new TextEncoder().encode('folder-metadata');
      const metadata = await decryptMetadata(
        sf.encrypted_metadata,
        sf.metadata_nonce,
        subKek,
        folderMetadataAad  // AAD per docs/crypto/03-encryption-protocol.md Section 2.2
      );

      subKek.fill(0);

      return {
        id: sf.id,
        name: metadata.name,
        itemCount: sf.item_count
      };
    })
  );

  // Decrypt files
  const files = await Promise.all(
    data.files.map(async (f) => {
      // Unwrap file DEK with folder KEK
      const dek = await aesKeyUnwrap(
        folderKek,
        base64Decode(f.wrapped_dek)
      );

      const fileMetadataAad = new TextEncoder().encode('file-metadata');
      const metadata = await decryptMetadata(
        f.encrypted_metadata,
        f.metadata_nonce,
        dek,
        fileMetadataAad  // AAD per docs/crypto/03-encryption-protocol.md Section 2.2
      );

      dek.fill(0);

      return {
        id: f.id,
        name: metadata.filename,
        size: f.blob_size,
        type: metadata.mime_type
      };
    })
  );

  // Clear folder KEK
  folderKek.fill(0);

  return {
    folder: {
      id: folderId,
      name: folderMetadata.name
    },
    subfolders,
    files,
    permission: share.permission,
    recursive: share.recursive
  };
}
```

## 8. Cascading Access Control

```typescript
// When Bob navigates to a subfolder within the shared folder:

async function accessSharedSubfolder(
  subfolderId: string,
  parentShareId: string,
  cachedParentKek?: Uint8Array
): Promise<DecryptedFolderContents> {

  // Get the original share to verify recursive access
  const shareResponse = await fetch(`/api/v1/shares/${parentShareId}`, {
    headers: {
      'Authorization': `Bearer ${sessionManager.getSession()}`
    }
  });

  const { data: share } = await shareResponse.json();

  // MANDATORY: Verify share grant signature (if not already cached/verified)
  // See crypto/05-signature-protocol.md Section 4.2
  const shareSignatureValid = await verifyShareSignature(
    share.grantor.public_keys,
    share.signature,
    {
      resourceType: share.resource_type,
      resourceId: share.resource_id,
      grantorId: share.grantor.id,
      granteeId: share.grantee_id,
      wrappedKey: share.wrapped_key,
      kemCiphertexts: share.kem_ciphertexts,
      permission: share.permission,
      recursive: share.recursive,
      expiry: share.expiry,
      createdAt: share.created_at
    }
  );

  if (!shareSignatureValid) {
    throw new ShareError('E_SIGNATURE_INVALID', 'Share grant signature verification failed');
  }

  if (!share.recursive) {
    throw new ShareError('E_PERMISSION_DENIED', 'No access to subfolders');
  }

  // Get subfolder via share path
  const response = await fetch(
    `/api/v1/folders/${subfolderId}?via_share=${parentShareId}`,
    {
      headers: {
        'Authorization': `Bearer ${sessionManager.getSession()}`
      }
    }
  );

  const { data } = await response.json();

  // MANDATORY: Verify subfolder signature before trusting metadata or KEK
  // See crypto/05-signature-protocol.md Section 4.4
  const folderSignatureValid = await verifyFolderSignature(
    data.owner.public_keys,
    data.signature,
    {
      parentId: data.parent_id,
      encryptedMetadata: data.encrypted_metadata,
      metadataNonce: data.metadata_nonce,
      ownerKeyAccess: data.owner_key_access,
      wrappedKek: data.wrapped_kek,
      createdAt: data.created_at
    }
  );

  if (!folderSignatureValid) {
    throw new ShareError('E_SIGNATURE_INVALID', 'Folder signature verification failed');
  }

  // Need to decrypt KEK chain from shared folder down to this subfolder
  // Server returns the path of wrapped_keks

  const folderKek = await decryptKekChain(
    share,
    data.kek_chain,
    cachedParentKek
  );

  // ... decrypt contents using folderKek
}

async function decryptKekChain(
  share: ShareGrant,
  kekChain: KekChainEntry[],
  cachedRootKek?: Uint8Array
): Promise<Uint8Array> {

  // Start with shared folder's KEK
  let currentKek: Uint8Array;

  if (cachedRootKek) {
    currentKek = new Uint8Array(cachedRootKek);
  } else {
    // Decapsulate from share
    currentKek = await decapsulateKey(
      {
        wrapped_key: share.wrapped_key,
        kem_ciphertexts: share.kem_ciphertexts
      },
      keyManager.getKeys().privateKeys
    );
  }

  // Unwrap each level
  for (const entry of kekChain) {
    const nextKek = await aesKeyUnwrap(
      currentKek,
      base64Decode(entry.wrapped_kek)
    );
    currentKek.fill(0);
    currentKek = nextKek;
  }

  return currentKek;
}
```

## 9. Permission Inheritance

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    PERMISSION INHERITANCE                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  Alice shares "Projects" folder with Bob (permission: write, recursive)     │
│                                                                              │
│  Projects/                     Bob's Permission                             │
│  ├── file1.pdf                 write (inherits from folder)                 │
│  ├── file2.docx                write (inherits from folder)                 │
│  │                                                                          │
│  ├── Reports/                  write (recursive=true)                       │
│  │   ├── Q1.xlsx               write (inherits)                             │
│  │   └── Q2.xlsx               write (inherits)                             │
│  │                                                                          │
│  └── Archive/                  write (recursive=true)                       │
│      └── old.pdf               write (inherits)                             │
│                                                                              │
│  ─────────────────────────────────────────────────────────────────────────  │
│                                                                              │
│  What Bob CAN do (permission: write):                                       │
│  ✓ Download/view all files                                                  │
│  ✓ Upload new files to any folder                                           │
│  ✓ Replace existing files                                                   │
│  ✓ Create new subfolders                                                    │
│  ✗ Share with others (requires admin)                                       │
│  ✗ Delete files/folders (requires owner)                                    │
│                                                                              │
│  ─────────────────────────────────────────────────────────────────────────  │
│                                                                              │
│  If recursive=false:                                                        │
│                                                                              │
│  Projects/                     Bob's Permission                             │
│  ├── file1.pdf                 write ✓                                      │
│  ├── file2.docx                write ✓                                      │
│  │                                                                          │
│  ├── Reports/                  NO ACCESS ✗                                  │
│  └── Archive/                  NO ACCESS ✗                                  │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 10. Error Handling

| Error Code | Cause | Recovery |
|------------|-------|----------|
| `E_PERMISSION_DENIED` | No share permission | Request admin access |
| `E_GRANTEE_NOT_FOUND` | Recipient not found | Verify email |
| `E_CANNOT_SHARE_SELF` | Sharing with self | Choose different recipient |
| `E_CANNOT_SHARE_ROOT` | Cannot share root folder | Select subfolder |
| `E_SHARE_EXISTS` | Share already exists | Update existing share |
| `E_FOLDER_NOT_FOUND` | Folder doesn't exist | Verify folder ID |
| `E_CIRCULAR_REFERENCE` | Share would create cycle | Not applicable for shares |

## 11. Security Considerations

### 11.1 KEK Protection

- Folder KEK is decrypted only for encapsulation
- KEK is cleared from memory immediately after
- Child KEKs remain protected (wrapped by parent)

### 11.2 Access Scope

- Share only grants access to shared folder and below
- Cannot access parent folders
- Cannot access sibling folders

### 11.3 New Content

- New files automatically accessible (use same KEK)
- New subfolders automatically accessible (KEK wrapped by shared KEK)
- No need to re-share for new content

### 11.4 Revocation

- Revoking share removes access to entire subtree
- KEK rotation required for security after revocation
- See revoke-access-flow.md for details
