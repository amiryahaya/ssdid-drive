# Share File Flow

**Version**: 1.0.0
**Status**: Draft
**Last Updated**: 2025-01

## 1. Overview

This document describes the flow for sharing a single file with another user. File sharing involves encapsulating the file's DEK for the recipient's public keys.

## 2. Prerequisites

- Grantor (sharer) is logged in with decrypted keys
- Grantor has share permission on the file (owner or admin)
- Recipient (grantee) is a registered user with public keys
- File DEK is accessible to grantor

> **API Path Convention**: Client code examples use `/api/v1/...` paths assuming the app proxies
> API requests to `https://api.securesharing.com/v1/...`. For direct API calls, remove the
> `/api/v1` prefix and use the API base URL directly.

## 3. Share File Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        SHARE FILE FLOW                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────┐         ┌─────────┐         ┌─────────┐                        │
│  │ Grantor │         │ Client  │         │ Server  │                        │
│  │ (Alice) │         │         │         │         │                        │
│  └────┬────┘         └────┬────┘         └────┬────┘                        │
│       │                   │                   │                              │
│       │  1. Share File    │                   │                              │
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
│       │──────────────────▶│                   │                              │
│       │                   │                   │                              │
│       │                   │  6. Get File Details                            │
│       │                   │──────────────────▶│                              │
│       │                   │                   │                              │
│       │                   │  7. File metadata + wrapped DEK                 │
│       │                   │◀──────────────────│                              │
│       │                   │                   │                              │
│       │                   │  ┌────────────────────────────────┐             │
│       │                   │  │  8. CLIENT-SIDE OPERATIONS     │             │
│       │                   │  │                                │             │
│       │                   │  │  a. Unwrap DEK (via folder KEK)│             │
│       │                   │  │                                │             │
│       │                   │  │  b. Encapsulate DEK for Bob's  │             │
│       │                   │  │     public keys (KEM)          │             │
│       │                   │  │                                │             │
│       │                   │  │  c. Sign share grant           │             │
│       │                   │  │                                │             │
│       │                   │  └────────────────────────────────┘             │
│       │                   │                   │                              │
│       │                   │  9. Create Share Grant                          │
│       │                   │──────────────────▶│                              │
│       │                   │                   │                              │
│       │                   │                   │  ┌─────────────┐            │
│       │                   │                   │  │ 10. Verify  │            │
│       │                   │                   │  │ - Permission│            │
│       │                   │                   │  │ - Signature │            │
│       │                   │                   │  │ - No self   │            │
│       │                   │                   │  │ - Store     │            │
│       │                   │                   │  └─────────────┘            │
│       │                   │                   │                              │
│       │                   │  11. Share Created + Notify Bob                 │
│       │                   │◀──────────────────│                              │
│       │                   │                   │                              │
│       │  12. Success      │                   │                              │
│       │◀──────────────────│                   │                              │
│       │                   │                   │                              │
└─────────────────────────────────────────────────────────────────────────────┘

                              ┌─────────────────────────────────────────────┐
                              │                                             │
                              │  BOB'S VIEW (Later)                        │
                              │                                             │
                              │  1. Bob logs in                            │
                              │  2. Bob sees "Alice shared File.pdf"       │
                              │  3. Bob downloads file using share's       │
                              │     wrapped_key and kem_ciphertexts        │
                              │                                             │
                              └─────────────────────────────────────────────┘
```

## 4. Detailed Steps

### 4.1 Step 1-3: Find Recipient

```typescript
async function searchUsers(query: string): Promise<UserSearchResult[]> {
  const response = await fetch(
    `/api/v1/users/search?q=${encodeURIComponent(query)}`,
    {
      headers: {
        'Authorization': `Bearer ${sessionManager.getSession()}`
      }
    }
  );

  if (!response.ok) {
    throw new Error('User search failed');
  }

  const { data } = await response.json();
  return data.items;
}

// Response
interface UserSearchResult {
  id: string;
  email: string;
  display_name: string;
  public_keys: {
    ml_kem: string;
    kaz_kem: string;
  };
}
```

### 4.2 Step 4-5: Select Permission

```typescript
interface ShareOptions {
  granteeId: string;
  permission: 'read' | 'write' | 'admin';
  expiry?: Date;
}

// Permission levels
const PERMISSIONS = {
  read: {
    label: 'View Only',
    description: 'Can download and view the file'
  },
  write: {
    label: 'Edit',
    description: 'Can download and replace the file'
  },
  admin: {
    label: 'Full Access',
    description: 'Can edit and share with others'
  }
};
```

### 4.3 Step 6-7: Get File Details

```typescript
async function getFileForSharing(fileId: string): Promise<FileDetails> {
  const response = await fetch(`/api/v1/files/${fileId}`, {
    headers: {
      'Authorization': `Bearer ${sessionManager.getSession()}`
    }
  });

  if (!response.ok) {
    const error = await response.json();
    throw new ShareError(error.error.code, error.error.message);
  }

  const { data } = await response.json();

  // Verify share permission
  if (!canShare(data.access)) {
    throw new ShareError('E_PERMISSION_DENIED', 'Cannot share this file');
  }

  return data;
}

function canShare(access: AccessInfo): boolean {
  return access.permission === 'owner' || access.permission === 'admin';
}
```

### 4.4 Step 8: Client-Side Operations

```typescript
async function createShareGrant(
  fileId: string,
  fileDetails: FileDetails,
  grantee: UserSearchResult,
  options: ShareOptions
): Promise<ShareGrantRequest> {

  const keys = keyManager.getKeys();

  // 8a. Unwrap DEK via folder KEK chain
  const folderKek = await getFolderKek(fileDetails.folder_id);
  const wrappedDek = base64Decode(fileDetails.wrapped_dek);
  const dek = await aesKeyUnwrap(folderKek, wrappedDek);

  // 8b. Encapsulate DEK for grantee's public keys
  const granteePublicKeys = {
    ml_kem: base64Decode(grantee.public_keys.ml_kem),
    kaz_kem: base64Decode(grantee.public_keys.kaz_kem)
  };

  const { wrappedKey, kemCiphertexts } = await encapsulateKey(
    dek,
    granteePublicKeys
  );

  // Clear DEK from memory
  dek.fill(0);

  // 8c. Sign share grant
  // IMPORTANT: All fields must match crypto spec (05-signature-protocol.md section 4.2)
  const createdAt = new Date().toISOString();
  const signaturePayload = canonicalize({
    resource_type: 'file',
    resource_id: fileId,
    grantor_id: sessionManager.getUser().id,  // Must include grantor
    grantee_id: grantee.id,
    wrapped_key: base64Encode(wrappedKey),
    kem_ciphertexts: kemCiphertexts,
    permission: options.permission,
    recursive: false,  // Always false for file shares
    expiry: options.expiry?.toISOString() || null,
    created_at: createdAt  // Must include timestamp
  });

  const signature = await combinedSign(
    {
      ml_dsa: keys.privateKeys.ml_dsa,
      kaz_sign: keys.privateKeys.kaz_sign
    },
    signaturePayload
  );

  return {
    resource_type: 'file',
    resource_id: fileId,
    grantee_id: grantee.id,
    wrapped_key: base64Encode(wrappedKey),
    kem_ciphertexts: kemCiphertexts,
    permission: options.permission,
    recursive: false,
    expiry: options.expiry?.toISOString(),
    created_at: createdAt,  // Include for signature verification
    signature
  };
}
```

### 4.5 Step 9-11: Create Share on Server

```typescript
async function submitShareGrant(
  grant: ShareGrantRequest
): Promise<ShareGrant> {

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

  const { data } = await response.json();
  return data;
}

// Response
interface ShareGrant {
  id: string;
  resource_type: 'file';
  resource_id: string;
  grantor_id: string;
  grantee_id: string;
  permission: string;
  expiry?: string;
  created_at: string;
}
```

## 5. Complete Share Implementation

```typescript
async function shareFile(
  fileId: string,
  granteeEmail: string,
  permission: 'read' | 'write' | 'admin',
  expiry?: Date
): Promise<ShareGrant> {

  // Search for user
  const searchResults = await searchUsers(granteeEmail);

  if (searchResults.length === 0) {
    throw new ShareError('E_GRANTEE_NOT_FOUND', 'User not found');
  }

  // Find exact match
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

  // Get file details
  const fileDetails = await getFileForSharing(fileId);

  // Create share grant
  const grant = await createShareGrant(
    fileId,
    fileDetails,
    grantee,
    { granteeId: grantee.id, permission, expiry }
  );

  // Submit to server
  return await submitShareGrant(grant);
}
```

## 6. Share with Multiple Recipients

```typescript
async function shareFileWithMultiple(
  fileId: string,
  recipients: Array<{
    email: string;
    permission: 'read' | 'write' | 'admin';
  }>,
  expiry?: Date
): Promise<ShareResult[]> {

  // Get file details once
  const fileDetails = await getFileForSharing(fileId);

  // Resolve all recipients
  const resolvedRecipients = await Promise.all(
    recipients.map(async (r) => {
      const results = await searchUsers(r.email);
      const match = results.find(
        u => u.email.toLowerCase() === r.email.toLowerCase()
      );
      return match ? { ...match, permission: r.permission } : null;
    })
  );

  // Filter valid recipients
  const validRecipients = resolvedRecipients.filter(r => r !== null);

  if (validRecipients.length === 0) {
    throw new ShareError('E_NO_VALID_RECIPIENTS', 'No valid recipients found');
  }

  // Create shares for each recipient
  const results: ShareResult[] = [];

  for (const recipient of validRecipients) {
    try {
      const grant = await createShareGrant(
        fileId,
        fileDetails,
        recipient,
        { granteeId: recipient.id, permission: recipient.permission, expiry }
      );

      const share = await submitShareGrant(grant);
      results.push({ email: recipient.email, success: true, share });
    } catch (error) {
      results.push({
        email: recipient.email,
        success: false,
        error: error.message
      });
    }
  }

  return results;
}
```

## 7. Update Share Permission

```typescript
async function updateSharePermission(
  shareId: string,
  newPermission: 'read' | 'write' | 'admin',
  newExpiry?: Date
): Promise<ShareGrant> {

  // Get current share (need original created_at for signature)
  const shareResponse = await fetch(`/api/v1/shares/${shareId}`, {
    headers: {
      'Authorization': `Bearer ${sessionManager.getSession()}`
    }
  });

  if (!shareResponse.ok) {
    const error = await shareResponse.json();
    throw new ShareError(error.error.code, error.error.message);
  }

  const { data: currentShare } = await shareResponse.json();

  // Sign update request
  // IMPORTANT: Must match crypto spec (05-signature-protocol.md section 4.5)
  const keys = keyManager.getKeys();
  const updatedAt = new Date().toISOString();
  const signaturePayload = canonicalize({
    share_id: shareId,
    original_created_at: currentShare.created_at,  // Links to original grant
    permission: newPermission,
    expiry: newExpiry?.toISOString() || null,
    updated_at: updatedAt
  });

  const signature = await combinedSign(
    {
      ml_dsa: keys.privateKeys.ml_dsa,
      kaz_sign: keys.privateKeys.kaz_sign
    },
    signaturePayload
  );

  // Submit update
  const response = await fetch(`/api/v1/shares/${shareId}`, {
    method: 'PATCH',
    headers: {
      'Authorization': `Bearer ${sessionManager.getSession()}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      permission: newPermission,
      expiry: newExpiry?.toISOString(),
      updated_at: updatedAt,  // Include for signature verification
      signature
    })
  });

  if (!response.ok) {
    const error = await response.json();
    throw new ShareError(error.error.code, error.error.message);
  }

  return (await response.json()).data;
}
```

## 8. Create Share Link (URL Sharing)

For sharing with external users via URL:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     SHARE LINK CREATION FLOW                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────┐         ┌─────────┐         ┌─────────┐                        │
│  │ Grantor │         │ Client  │         │ Server  │                        │
│  └────┬────┘         └────┬────┘         └────┬────┘                        │
│       │                   │                   │                              │
│       │  1. Create Link   │                   │                              │
│       │──────────────────▶│                   │                              │
│       │                   │                   │                              │
│       │  2. Set Options   │                   │                              │
│       │  - Password?      │                   │                              │
│       │  - Expiry?        │                   │                              │
│       │  - Max downloads? │                   │                              │
│       │──────────────────▶│                   │                              │
│       │                   │                   │                              │
│       │                   │  ┌────────────────────────────────┐             │
│       │                   │  │  3. CLIENT-SIDE OPERATIONS     │             │
│       │                   │  │                                │             │
│       │                   │  │  If password:                  │             │
│       │                   │  │    - Generate salt             │             │
│       │                   │  │    - Derive key from password  │             │
│       │                   │  │    - Wrap DEK with password key│             │
│       │                   │  │  Else:                         │             │
│       │                   │  │    - Wrap DEK with random key  │             │
│       │                   │  │    - Include key in URL        │             │
│       │                   │  │                                │             │
│       │                   │  └────────────────────────────────┘             │
│       │                   │                   │                              │
│       │                   │  4. Create Share Link                           │
│       │                   │──────────────────▶│                              │
│       │                   │                   │                              │
│       │                   │  5. Link URL                                    │
│       │                   │◀──────────────────│                              │
│       │                   │                   │                              │
│       │  6. Share URL     │                   │                              │
│       │     (+ password)  │                   │                              │
│       │◀──────────────────│                   │                              │
│       │                   │                   │                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Share Link Implementation

```typescript
interface ShareLinkOptions {
  password?: string;
  expiry?: Date;
  maxDownloads?: number;
}

async function createShareLink(
  fileId: string,
  options: ShareLinkOptions
): Promise<ShareLink> {

  // Get file details
  const fileDetails = await getFileForSharing(fileId);

  // Get DEK
  const folderKek = await getFolderKek(fileDetails.folder_id);
  const dek = await aesKeyUnwrap(folderKek, base64Decode(fileDetails.wrapped_dek));

  let wrappedKey: Uint8Array;
  let passwordSalt: string | undefined;
  let passwordHash: string | undefined;
  let urlKey: string | undefined;

  if (options.password) {
    // Password-protected: derive key from password
    const salt = crypto.getRandomValues(new Uint8Array(16));
    passwordSalt = base64Encode(salt);

    const passwordKey = await argon2id(options.password, {
      salt,
      memory: 65536,
      iterations: 3,
      parallelism: 4,
      hashLength: 32
    });

    // Store hash for server-side password verification
    // (same value as passwordKey - server verifies by comparing hashes)
    passwordHash = base64Encode(passwordKey);

    wrappedKey = await aesKeyWrap(passwordKey, dek);
    passwordKey.fill(0);
  } else {
    // No password: include key in URL fragment
    const linkKey = crypto.getRandomValues(new Uint8Array(32));
    wrappedKey = await aesKeyWrap(linkKey, dek);
    urlKey = base64UrlEncode(linkKey);
    linkKey.fill(0);
  }

  dek.fill(0);

  // Prepare request with timestamp
  const createdAt = new Date().toISOString();
  const wrappedKeyB64 = base64Encode(wrappedKey);

  // Sign the share link creation
  // See docs/crypto/05-signature-protocol.md Section 4.6
  const signaturePayload = canonicalize({
    resourceType: 'file',
    resourceId: fileId,
    creatorId: keyManager.getUserId(),
    wrappedKey: wrappedKeyB64,
    permission: 'read',
    expiry: options.expiry?.toISOString() ?? null,
    passwordProtected: !!options.password,
    maxDownloads: options.maxDownloads ?? null,
    createdAt
  });

  const signature = await combinedSign(
    keyManager.getKeys().privateKeys,
    signaturePayload
  );

  // Create share link on server
  const response = await fetch('/api/v1/shares/link', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${sessionManager.getSession()}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      resource_type: 'file',
      resource_id: fileId,
      wrapped_key: wrappedKeyB64,
      permission: 'read',
      password_protected: !!options.password,
      password_salt: passwordSalt,
      password_hash: passwordHash,
      expiry: options.expiry?.toISOString(),
      max_downloads: options.maxDownloads,
      created_at: createdAt,
      signature: {
        ml_dsa: base64Encode(signature.mlDsa),
        kaz_sign: base64Encode(signature.kazSign)
      }
    })
  });

  const { data } = await response.json();

  // Construct final URL
  let shareUrl = data.link;
  if (urlKey) {
    shareUrl += `#${urlKey}`;  // Key in fragment (not sent to server)
  }

  return {
    id: data.id,
    url: shareUrl,
    passwordProtected: !!options.password,
    expiry: data.expiry,
    maxDownloads: data.max_downloads
  };
}
```

## 9. Error Handling

| Error Code | Cause | Recovery |
|------------|-------|----------|
| `E_PERMISSION_DENIED` | No share permission | Request admin access |
| `E_GRANTEE_NOT_FOUND` | Recipient not found | Verify email |
| `E_CANNOT_SHARE_SELF` | Sharing with self | Choose different recipient |
| `E_SHARE_EXISTS` | Share already exists | Update existing share |
| `E_FILE_NOT_FOUND` | File doesn't exist | Verify file ID |
| `E_SIGNATURE_INVALID` | Signature failed | Retry operation |
| `E_TENANT_MISMATCH` | Cross-tenant share | Not allowed |

## 10. Security Considerations

### 10.1 Key Protection

- DEK is decrypted only for encapsulation
- DEK is cleared from memory immediately after
- Recipient's public keys are verified

### 10.2 Signature Integrity

- Share grant is cryptographically signed
- Signature includes all grant parameters
- Server verifies signature before storing

### 10.3 Access Control

- Only owners/admins can share
- Server enforces permission hierarchy
- Cross-tenant sharing prevented

### 10.4 Share Links

- Password-protected links use key derivation
- Non-password links include key in URL fragment
- Fragment is not sent to server (client-only)
- Max downloads limit exposure
