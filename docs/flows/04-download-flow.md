# File Download Flow

**Version**: 1.1.0
**Status**: Draft
**Last Updated**: 2026-01

## 1. Overview

This document describes the file download flow for SecureSharing. Download involves retrieving encrypted blobs, decrypting with the appropriate keys, and verifying integrity.

## 2. Prerequisites

- User is logged in with decrypted keys in memory
- User has read access to the file (owner or via share)
- Appropriate KEK/DEK chain is available

### Platform Notes

This document provides code examples for all supported platforms. Each section shows the implementation for:

| Platform | Crypto Library | HTTP Client | File Save | Notes |
|----------|---------------|-------------|-----------|-------|
| **Desktop (Rust/Tauri)** | Native Rust (`ring`, `pqcrypto`) | `reqwest` | `rfd::FileDialog` | Background downloads |
| **iOS (Swift)** | Rust via FFI | `URLSession` | `UIDocumentPickerViewController` | Background tasks |
| **Android (Kotlin)** | Rust via JNI | `OkHttp` | `DocumentFile`, Share sheet | DownloadManager support |

> **Note**: SecureSharing uses native clients exclusively. No web/browser client is provided.

> **API Path Convention**: Client code examples use `/api/v1/...` paths assuming the app proxies
> API requests to `https://api.securesharing.com/v1/...`. For direct API calls, remove the
> `/api/v1` prefix and use the API base URL directly.

## 3. Download Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        FILE DOWNLOAD FLOW                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────┐         ┌─────────┐         ┌─────────┐         ┌─────────┐   │
│  │  User   │         │ Client  │         │ Server  │         │ Storage │   │
│  └────┬────┘         └────┬────┘         └────┬────┘         └────┬────┘   │
│       │                   │                   │                   │         │
│       │  1. Request File  │                   │                   │         │
│       │──────────────────▶│                   │                   │         │
│       │                   │                   │                   │         │
│       │                   │  2. Get File Details                 │         │
│       │                   │──────────────────▶│                   │         │
│       │                   │                   │                   │         │
│       │                   │  3. File metadata + wrapped DEK      │         │
│       │                   │◀──────────────────│                   │         │
│       │                   │                   │                   │         │
│       │                   │  ┌────────────────────────────────┐  │         │
│       │                   │  │  4. DETERMINE ACCESS PATH      │  │         │
│       │                   │  │                                │  │         │
│       │                   │  │  Owner: Use folder KEK chain   │  │         │
│       │                   │  │  Share: Use share's wrapped key│  │         │
│       │                   │  │                                │  │         │
│       │                   │  └────────────────────────────────┘  │         │
│       │                   │                   │                   │         │
│       │                   │  5. Get Download URL              │           │
│       │                   │──────────────────▶│                   │         │
│       │                   │                   │                   │         │
│       │                   │  6. Pre-signed Download URL       │           │
│       │                   │◀──────────────────│                   │         │
│       │                   │                   │                   │         │
│       │                   │  7. Download encrypted blob                    │
│       │                   │◀──────────────────────────────────────│         │
│       │                   │                   │                   │         │
│       │  [Progress]       │                   │                   │         │
│       │◀─ ─ ─ ─ ─ ─ ─ ─ ─│                   │                   │         │
│       │                   │                   │                   │         │
│       │                   │  ┌────────────────────────────────┐  │         │
│       │                   │  │  8. CLIENT-SIDE VERIFICATION   │  │         │
│       │                   │  │     & DECRYPTION               │  │         │
│       │                   │  │                                │  │         │
│       │                   │  │  a. Verify blob hash           │  │         │
│       │                   │  │                                │  │         │
│       │                   │  │  b. *** VERIFY SIGNATURE ***   │  │         │
│       │                   │  │     (MANDATORY - fail if       │  │         │
│       │                   │  │      invalid, BEFORE decrypt)  │  │         │
│       │                   │  │                                │  │         │
│       │                   │  │  c. Unwrap DEK with KEK        │  │         │
│       │                   │  │                                │  │         │
│       │                   │  │  d. Decrypt chunks             │  │         │
│       │                   │  │     (AES-256-GCM)              │  │         │
│       │                   │  │                                │  │         │
│       │                   │  │  e. Verify plaintext checksum  │  │         │
│       │                   │  │                                │  │         │
│       │                   │  │  f. Decrypt metadata           │  │         │
│       │                   │  │                                │  │         │
│       │                   │  └────────────────────────────────┘  │         │
│       │                   │                   │                   │         │
│       │  9. Save File     │                   │                   │         │
│       │◀──────────────────│                   │                   │         │
│       │                   │                   │                   │         │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 4. Detailed Steps

### 4.1 Step 1-3: Get File Details

```typescript
async function getFileDetails(
  fileId: string,
  shareId?: string
): Promise<FileDetails> {

  let url = `/api/v1/files/${fileId}`;
  if (shareId) {
    url += `?via_share=${shareId}`;
  }

  const response = await fetch(url, {
    headers: {
      'Authorization': `Bearer ${sessionManager.getSession()}`
    }
  });

  if (!response.ok) {
    const error = await response.json();
    throw new DownloadError(error.error.code, error.error.message);
  }

  return (await response.json()).data;
}

// Response for owner access
interface FileDetailsOwner {
  id: string;
  owner_id: string;
  folder_id: string;
  encrypted_metadata: string;
  metadata_nonce: string;
  wrapped_dek: string;           // DEK wrapped by folder KEK
  blob_storage_key: string;
  blob_size: number;
  blob_hash: string;
  signature: CombinedSignature;
  access: {
    source: 'owner';
    permission: 'owner';
  };
}

// Response for share access
interface FileDetailsShare {
  id: string;
  owner: {
    id: string;
    email: string;
    display_name: string;
    public_keys: {              // REQUIRED for signature verification
      ml_dsa: string;           // Base64-encoded ML-DSA public key
      kaz_sign: string;         // Base64-encoded KAZ-SIGN public key
    };
  };
  encrypted_metadata: string;
  metadata_nonce: string;
  blob_size: number;
  blob_hash: string;            // Needed for signature verification
  wrapped_dek: string;          // ORIGINAL wrapped DEK (for signature verification)
  signature: CombinedSignature; // Owner's signature (MANDATORY verification)
  share: {
    id: string;
    wrapped_key: string;        // DEK re-wrapped for recipient (for decryption)
    kem_ciphertexts: KemCiphertext[];
    permission: 'read' | 'write' | 'admin';
  };
  created_at: string;
  updated_at: string;
}

// NOTE: wrapped_dek vs share.wrapped_key:
// - wrapped_dek: Original DEK wrapped by folder KEK - used for SIGNATURE VERIFICATION
// - share.wrapped_key: DEK re-wrapped for recipient via KEM - used for DECRYPTION
// The signature was created over wrapped_dek, so verification requires it.
//
// MANDATORY: Client must verify signature using owner.public_keys BEFORE decryption.

// ============================================================
// FILE SHARE LINK INTERFACES
// ============================================================

// Response for file share link access (unprotected)
interface ShareLinkFileDetails {
  id: string;
  resource_type: 'file';
  password_protected: false;
  permission: 'read';
  expiry: string | null;
  expired: boolean;
  download_count: number;
  max_downloads: number | null;
  owner: {
    id: string;
    public_keys: {              // REQUIRED for signature verification
      ml_dsa: string;
      kaz_sign: string;
    };
  };
  wrapped_key: string;          // DEK wrapped with URL-embedded key
  created_at: string;           // Included in signature payload
  signature: CombinedSignature; // Creator's signature (MANDATORY verification)
  file: ShareLinkFileInfo;
}

// Response for password-protected file link (before verification)
interface ShareLinkFileProtectedPending {
  id: string;
  resource_type: 'file';
  password_protected: true;
  password_verified: false;
  password_salt: string;        // Salt for Argon2id
  expiry: string | null;
  expired: boolean;
}

// Response after file share link password verification
// Includes ALL fields needed for share link signature verification
// See docs/crypto/05-signature-protocol.md Section 4.6 for signature payload
interface ShareLinkFileVerifyResult {
  verified: true;
  session_token: string;
  expires_at: string;
  // Signature payload fields
  resource_type: 'file';        // For signature verification
  permission: 'read';           // For signature verification
  expiry: string | null;        // For signature verification
  password_protected: true;     // Always true for this response (for signature verification)
  max_downloads: number | null; // For signature verification
  // Verification fields
  owner: {
    id: string;                 // = creatorId in signature payload
    public_keys: {
      ml_dsa: string;
      kaz_sign: string;
    };
  };
  wrapped_key: string;          // DEK wrapped with password-derived key
  created_at: string;           // For signature verification
  signature: CombinedSignature;
  file: ShareLinkFileInfo;
}

// File info in share link responses
// Includes all fields needed for file signature verification
interface ShareLinkFileInfo {
  id: string;
  encrypted_metadata: string;
  metadata_nonce: string;
  wrapped_dek: string;          // Original DEK wrapped by folder KEK (for signature verification)
  blob_size: number;
  blob_hash: string;            // Verify after download
  signature: CombinedSignature; // File owner's signature
  owner: {
    id: string;
    public_keys: {
      ml_dsa: string;
      kaz_sign: string;
    };
  };
}

// ============================================================
// FOLDER SHARE LINK INTERFACES
// ============================================================

// Response for folder share link access (unprotected)
// See Section 7.1 for folder share link flow
interface ShareLinkFolderDetails {
  id: string;
  resource_type: 'folder';
  password_protected: false;
  permission: 'read';
  expiry: string | null;
  expired: boolean;
  download_count: number;
  max_downloads: number | null;
  owner: {
    id: string;
    public_keys: {              // REQUIRED for signature verification
      ml_dsa: string;
      kaz_sign: string;
    };
  };
  wrapped_key: string;          // KEK wrapped with URL-embedded key
  created_at: string;           // Included in signature payload
  signature: CombinedSignature; // Creator's signature (MANDATORY verification)
  folder: ShareLinkFolderInfo;
}

// Response for password-protected folder link (before verification)
interface ShareLinkFolderProtectedPending {
  id: string;
  resource_type: 'folder';
  password_protected: true;
  password_verified: false;
  password_salt: string;        // Salt for Argon2id
  expiry: string | null;
  expired: boolean;
}

// Response after folder share link password verification
// Includes ALL fields needed for share link signature verification
// See docs/crypto/05-signature-protocol.md Section 4.6 for signature payload
interface ShareLinkFolderVerifyResult {
  verified: true;
  session_token: string;
  expires_at: string;
  // Signature payload fields
  resource_type: 'folder';      // For signature verification
  permission: 'read';           // For signature verification
  expiry: string | null;        // For signature verification
  password_protected: true;     // Always true for this response (for signature verification)
  max_downloads: number | null; // For signature verification
  // Verification fields
  owner: {
    id: string;                 // = creatorId in signature payload
    public_keys: {
      ml_dsa: string;
      kaz_sign: string;
    };
  };
  wrapped_key: string;          // KEK wrapped with password-derived key
  created_at: string;           // For signature verification
  signature: CombinedSignature;
  folder: ShareLinkFolderInfo;
}

// Folder info in share link responses
// Includes all fields needed for folder signature verification
interface ShareLinkFolderInfo {
  id: string;
  parent_id: string | null;
  encrypted_metadata: string;
  metadata_nonce: string;
  owner_key_access: {           // For signature verification
    wrapped_kek: string;
    kem_ciphertexts: Array<{ algorithm: string; ciphertext: string }>;
  };
  wrapped_kek: string | null;   // Original KEK wrapped by parent KEK (for signature verification)
  signature: CombinedSignature; // Folder owner's signature
  owner: {
    id: string;
    public_keys: {
      ml_dsa: string;
      kaz_sign: string;
    };
  };
  item_count: number;
  created_at: string;
}

// Discriminated union types for share link responses
type ShareLinkDetailsUnion = ShareLinkFileDetails | ShareLinkFolderDetails;
type ShareLinkProtectedPendingUnion = ShareLinkFileProtectedPending | ShareLinkFolderProtectedPending;
type ShareLinkVerifyResultUnion = ShareLinkFileVerifyResult | ShareLinkFolderVerifyResult;

// NOTE for share links:
// - wrapped_key: DEK (file) or KEK (folder) wrapped with URL key or password-derived key
// - NO kem_ciphertexts: Share links don't use KEM encapsulation
//
// FILE SHARE LINKS - TWO signature verifications are MANDATORY:
//   1. Share link signature: Verify `signature` using `owner.public_keys` (share link creator)
//   2. File signature: Verify `file.signature` using `file.owner.public_keys` (file owner)
//
// FOLDER SHARE LINKS - TWO signature verifications are MANDATORY:
//   1. Share link signature: Verify `signature` using `owner.public_keys` (share link creator)
//   2. Folder signature: Verify `folder.signature` using `folder.owner.public_keys` (folder owner)
//   3. For each file/subfolder accessed: verify its signature before trusting content
//
// Note: Share link owner and resource owner may be different (e.g., admin sharing someone else's resource).
// ALL applicable signatures MUST pass before decryption.
```

### 4.2 Step 4: Determine Access Path

```typescript
async function getDekForFile(
  fileDetails: FileDetails
): Promise<Uint8Array> {

  if (fileDetails.access?.source === 'owner') {
    // Owner access: unwrap DEK via folder KEK chain
    return await getDekViaOwnership(fileDetails);
  } else if (fileDetails.share) {
    // Share access: decrypt DEK from share
    return await getDekViaShare(fileDetails.share);
  } else {
    throw new Error('No access path available');
  }
}

async function getDekViaOwnership(
  fileDetails: FileDetailsOwner
): Promise<Uint8Array> {

  // Get folder's KEK
  const folderKek = await getFolderKek(fileDetails.folder_id);

  // Unwrap DEK
  const wrappedDek = base64Decode(fileDetails.wrapped_dek);
  const dek = await aesKeyUnwrap(folderKek, wrappedDek);

  return dek;
}

async function getDekViaShare(
  share: ShareAccess
): Promise<Uint8Array> {

  // Decapsulate the wrapped key using our private keys
  const privateKeys = keyManager.getKeys().privateKeys;

  const dek = await decapsulateKey(
    {
      wrapped_key: share.wrapped_key,
      kem_ciphertexts: share.kem_ciphertexts
    },
    {
      ml_kem: privateKeys.ml_kem,
      kaz_kem: privateKeys.kaz_kem
    }
  );

  return dek;
}
```

### 4.3 Step 5-6: Get Download URL

```typescript
async function getDownloadUrl(fileId: string): Promise<DownloadInfo> {
  const response = await fetch(`/api/v1/files/${fileId}/download`, {
    headers: {
      'Authorization': `Bearer ${sessionManager.getSession()}`
    }
  });

  if (!response.ok) {
    const error = await response.json();
    throw new DownloadError(error.error.code, error.error.message);
  }

  const { data } = await response.json();

  return {
    url: data.download.url,
    expiresAt: new Date(data.download.expires_at),
    blobSize: data.file.blob_size,
    blobHash: data.file.blob_hash
  };
}
```

### 4.4 Step 7: Download Encrypted Blob

```typescript
async function downloadBlob(
  downloadInfo: DownloadInfo,
  onProgress?: ProgressCallback
): Promise<ArrayBuffer> {

  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    xhr.responseType = 'arraybuffer';

    xhr.addEventListener('progress', (event) => {
      if (event.lengthComputable) {
        onProgress?.({
          phase: 'downloading',
          loaded: event.loaded,
          total: event.total
        });
      }
    });

    xhr.addEventListener('load', () => {
      if (xhr.status >= 200 && xhr.status < 300) {
        resolve(xhr.response);
      } else {
        reject(new Error(`Download failed: ${xhr.status}`));
      }
    });

    xhr.addEventListener('error', () => {
      reject(new Error('Download failed: network error'));
    });

    xhr.open('GET', downloadInfo.url);
    xhr.send();
  });
}
```

### 4.5 Step 8: Client-Side Decryption

**Web (TypeScript)**
```typescript
async function decryptFile(
  encryptedBlob: ArrayBuffer,
  fileDetails: FileDetails,
  dek: Uint8Array,
  onProgress?: ProgressCallback
): Promise<DecryptedFile> {

  const blobData = new Uint8Array(encryptedBlob);

  // 8a. Verify blob hash FIRST (before any decryption)
  const actualHash = await calculateSha256Hex(blobData);
  if (actualHash !== fileDetails.blob_hash) {
    throw new IntegrityError('Blob hash mismatch - file may be corrupted');
  }

  // 8b. *** VERIFY SIGNATURE *** (MANDATORY - before any decryption)
  // See docs/crypto/05-signature-protocol.md Section 7.1
  // This step is NOT optional - failure to verify signatures is a security vulnerability
  await verifyFileSignature(fileDetails);

  // Parse header (64 bytes, fixed)
  // See docs/crypto/03-encryption-protocol.md Section 2.4 for specification
  const header = parseFileHeader(blobData.slice(0, 64));

  // 8c. DEK is already unwrapped (passed in)

  // Derive chunk key from DEK using HKDF
  // See docs/crypto/03-encryption-protocol.md Section 3.1 Step 7
  const chunkKey = await hkdfDerive(dek, "chunk-encryption", 32);

  // 8d. Decrypt chunks
  const decryptedChunks: Uint8Array[] = [];
  let offset = 64; // After header (fixed 64 bytes)
  let chunkIndex = 0;

  while (offset < blobData.length) {
    // Read chunk: nonce (12) + ciphertext + tag (16)
    // Nonce format: random(8) || chunk_index(4)
    const chunkNonce = blobData.slice(offset, offset + 12);
    offset += 12;

    // Calculate expected ciphertext size
    const isLastChunk = (chunkIndex === header.chunkCount - 1);
    const expectedPlaintextSize = isLastChunk
      ? (header.originalSize % header.chunkSize) || header.chunkSize
      : header.chunkSize;
    const ciphertextSize = expectedPlaintextSize + 16; // +16 for auth tag

    const ciphertext = blobData.slice(offset, offset + ciphertextSize);
    offset += ciphertextSize;

    // Build AAD: chunk index (4 bytes, big-endian)
    const aad = new Uint8Array(4);
    new DataView(aad.buffer).setUint32(0, chunkIndex, false);

    // Decrypt chunk
    const plaintext = await aesGcmDecryptWithAad(
      chunkKey,
      chunkNonce,
      ciphertext,
      aad
    );

    decryptedChunks.push(plaintext);
    chunkIndex++;

    onProgress?.({
      phase: 'decrypting',
      loaded: offset,
      total: blobData.length
    });
  }

  // Combine chunks
  const decryptedContent = concatenateChunks(decryptedChunks);

  // 8e. Verify plaintext checksum (if available in metadata)
  // This is done after metadata decryption

  // 8f. Decrypt metadata (from database, not blob)
  const metadata = await decryptMetadata(
    fileDetails.encrypted_metadata,
    fileDetails.metadata_nonce,
    dek
  );

  // Verify plaintext checksum if present
  if (metadata.checksum) {
    const actualChecksum = await calculateSha256Hex(decryptedContent);
    if (actualChecksum !== metadata.checksum) {
      throw new IntegrityError('Plaintext checksum mismatch');
    }
  }

  // Clear chunk key from memory
  chunkKey.fill(0);

  return {
    content: decryptedContent,
    metadata
  };
}
```

**Desktop (Rust/Tauri)**
```rust
use aes_gcm::{Aes256Gcm, KeyInit, Nonce};
use aes_gcm::aead::Aead;
use hkdf::Hkdf;
use sha2::{Sha256, Sha384, Digest};
use zeroize::Zeroize;

pub struct DecryptedFile {
    pub content: Vec<u8>,
    pub metadata: FileMetadata,
}

pub async fn decrypt_file(
    encrypted_blob: &[u8],
    file_details: &FileDetails,
    dek: &[u8],
    progress_callback: Option<Box<dyn Fn(DecryptProgress) + Send>>,
) -> Result<DecryptedFile, CryptoError> {
    // 8a. Verify blob hash FIRST (before any decryption)
    let actual_hash = sha256_hex(encrypted_blob);
    if actual_hash != file_details.blob_hash {
        return Err(CryptoError::BlobHashMismatch);
    }

    // 8b. *** VERIFY SIGNATURE *** (MANDATORY - before any decryption)
    verify_file_signature(file_details).await?;

    // Parse header (64 bytes, fixed)
    let header = parse_file_header(&encrypted_blob[..64])?;

    // Derive chunk key from DEK using HKDF-SHA384
    let hkdf = Hkdf::<Sha384>::new(None, dek);
    let mut chunk_key = [0u8; 32];
    hkdf.expand(b"chunk-encryption", &mut chunk_key)
        .map_err(|_| CryptoError::HkdfExpandFailed)?;

    // 8d. Decrypt chunks
    let cipher = Aes256Gcm::new_from_slice(&chunk_key)
        .map_err(|_| CryptoError::CipherInitFailed)?;

    let mut decrypted_chunks: Vec<Vec<u8>> = Vec::new();
    let mut offset = 64usize; // After header
    let mut chunk_index = 0u32;

    while offset < encrypted_blob.len() {
        // Read nonce (12 bytes)
        let chunk_nonce = &encrypted_blob[offset..offset + 12];
        offset += 12;

        // Calculate expected ciphertext size
        let is_last_chunk = chunk_index == header.chunk_count - 1;
        let expected_plaintext_size = if is_last_chunk {
            let remainder = header.original_size % header.chunk_size as u64;
            if remainder == 0 { header.chunk_size as usize } else { remainder as usize }
        } else {
            header.chunk_size as usize
        };
        let ciphertext_size = expected_plaintext_size + 16; // +16 for tag

        let ciphertext = &encrypted_blob[offset..offset + ciphertext_size];
        offset += ciphertext_size;

        // Build AAD: chunk index (4 bytes, big-endian)
        let aad = chunk_index.to_be_bytes();

        // Decrypt chunk
        let plaintext = cipher
            .decrypt_with_aad(
                Nonce::from_slice(chunk_nonce),
                ciphertext,
                &aad
            )
            .map_err(|_| CryptoError::DecryptionFailed)?;

        decrypted_chunks.push(plaintext);
        chunk_index += 1;

        if let Some(ref cb) = progress_callback {
            cb(DecryptProgress {
                phase: "decrypting",
                loaded: offset,
                total: encrypted_blob.len(),
            });
        }
    }

    // Combine chunks
    let decrypted_content: Vec<u8> = decrypted_chunks.into_iter().flatten().collect();

    // 8f. Decrypt metadata (AAD must match encryption)
    let metadata_aad = b"file-metadata";
    let metadata = decrypt_metadata(
        &file_details.encrypted_metadata,
        &file_details.metadata_nonce,
        dek,
        metadata_aad
    )?;

    // 8e. Verify plaintext checksum if present
    if let Some(ref expected_checksum) = metadata.checksum {
        let actual_checksum = sha256_hex(&decrypted_content);
        if &actual_checksum != expected_checksum {
            return Err(CryptoError::PlaintextChecksumMismatch);
        }
    }

    // Clear chunk key from memory
    chunk_key.zeroize();

    Ok(DecryptedFile {
        content: decrypted_content,
        metadata,
    })
}

fn parse_file_header(header_data: &[u8]) -> Result<FileHeader, CryptoError> {
    // Verify magic bytes "SSEC"
    if &header_data[0..4] != b"SSEC" {
        return Err(CryptoError::InvalidFileFormat);
    }

    let version = u16::from_be_bytes([header_data[4], header_data[5]]);
    if version > 1 {
        return Err(CryptoError::UnsupportedVersion(version));
    }

    let algorithm_suite = u16::from_be_bytes([header_data[6], header_data[7]]);
    if algorithm_suite != 1 {
        return Err(CryptoError::UnsupportedAlgorithm(algorithm_suite));
    }

    let original_size = u64::from_be_bytes(header_data[8..16].try_into().unwrap());
    let chunk_size = u32::from_be_bytes(header_data[16..20].try_into().unwrap());
    let chunk_count = u32::from_be_bytes(header_data[20..24].try_into().unwrap());

    Ok(FileHeader {
        version,
        algorithm_suite,
        original_size,
        chunk_size,
        chunk_count,
    })
}
```

**iOS (Swift)**
```swift
import Foundation
import CryptoKit
import SecureSharingCrypto  // Rust FFI wrapper

struct DecryptedFile {
    let content: Data
    let metadata: FileMetadata
}

func decryptFile(
    encryptedBlob: Data,
    fileDetails: FileDetails,
    dek: Data,
    progressCallback: ((DecryptProgress) -> Void)? = nil
) throws -> DecryptedFile {
    // 8a. Verify blob hash FIRST (before any decryption)
    let actualHash = sha256Hex(data: encryptedBlob)
    guard actualHash == fileDetails.blobHash else {
        throw CryptoError.blobHashMismatch
    }

    // 8b. *** VERIFY SIGNATURE *** (MANDATORY - before any decryption)
    try verifyFileSignature(fileDetails: fileDetails)

    // Parse header (64 bytes, fixed)
    let header = try parseFileHeader(Data(encryptedBlob.prefix(64)))

    // Derive chunk key from DEK using HKDF-SHA384
    let chunkKey = deriveKeyHKDF(
        inputKey: dek,
        info: "chunk-encryption".data(using: .utf8)!,
        outputLength: 32
    )

    // 8d. Decrypt chunks
    var decryptedChunks: [Data] = []
    var offset = 64  // After header
    var chunkIndex: UInt32 = 0

    while offset < encryptedBlob.count {
        // Read nonce (12 bytes)
        let chunkNonce = encryptedBlob.subdata(in: offset..<offset+12)
        offset += 12

        // Calculate expected ciphertext size
        let isLastChunk = chunkIndex == header.chunkCount - 1
        let expectedPlaintextSize: Int
        if isLastChunk {
            let remainder = Int(header.originalSize % UInt64(header.chunkSize))
            expectedPlaintextSize = remainder == 0 ? Int(header.chunkSize) : remainder
        } else {
            expectedPlaintextSize = Int(header.chunkSize)
        }
        let ciphertextSize = expectedPlaintextSize + 16  // +16 for tag

        let ciphertext = encryptedBlob.subdata(in: offset..<offset+ciphertextSize)
        offset += ciphertextSize

        // Build AAD: chunk index (4 bytes, big-endian)
        var aad = Data(count: 4)
        aad.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: chunkIndex.bigEndian, as: UInt32.self)
        }

        // Decrypt chunk using native CryptoKit
        let nonce = try AES.GCM.Nonce(data: chunkNonce)
        let sealedBox = try AES.GCM.SealedBox(
            nonce: nonce,
            ciphertext: ciphertext.dropLast(16),
            tag: ciphertext.suffix(16)
        )

        let plaintext = try AES.GCM.open(
            sealedBox,
            using: SymmetricKey(data: chunkKey),
            authenticating: aad
        )

        decryptedChunks.append(plaintext)
        chunkIndex += 1

        progressCallback?(DecryptProgress(
            phase: .decrypting,
            loaded: offset,
            total: encryptedBlob.count
        ))
    }

    // Combine chunks
    let decryptedContent = decryptedChunks.reduce(Data()) { $0 + $1 }

    // 8f. Decrypt metadata (AAD must match encryption)
    let metadataAad = "file-metadata".data(using: .utf8)!
    let metadata = try decryptMetadata(
        encryptedMetadata: fileDetails.encryptedMetadata,
        nonce: fileDetails.metadataNonce,
        dek: dek,
        aad: metadataAad
    )

    // 8e. Verify plaintext checksum if present
    if let expectedChecksum = metadata.checksum {
        let actualChecksum = sha256Hex(data: decryptedContent)
        guard actualChecksum == expectedChecksum else {
            throw CryptoError.plaintextChecksumMismatch
        }
    }

    return DecryptedFile(
        content: decryptedContent,
        metadata: metadata
    )
}

private func parseFileHeader(_ headerData: Data) throws -> FileHeader {
    // Verify magic bytes "SSEC"
    guard headerData.prefix(4) == Data("SSEC".utf8) else {
        throw CryptoError.invalidFileFormat
    }

    let version = headerData.subdata(in: 4..<6).withUnsafeBytes {
        $0.load(as: UInt16.self).bigEndian
    }
    guard version <= 1 else {
        throw CryptoError.unsupportedVersion(version)
    }

    let algorithmSuite = headerData.subdata(in: 6..<8).withUnsafeBytes {
        $0.load(as: UInt16.self).bigEndian
    }
    guard algorithmSuite == 1 else {
        throw CryptoError.unsupportedAlgorithm(algorithmSuite)
    }

    let originalSize = headerData.subdata(in: 8..<16).withUnsafeBytes {
        $0.load(as: UInt64.self).bigEndian
    }
    let chunkSize = headerData.subdata(in: 16..<20).withUnsafeBytes {
        $0.load(as: UInt32.self).bigEndian
    }
    let chunkCount = headerData.subdata(in: 20..<24).withUnsafeBytes {
        $0.load(as: UInt32.self).bigEndian
    }

    return FileHeader(
        version: version,
        algorithmSuite: algorithmSuite,
        originalSize: originalSize,
        chunkSize: chunkSize,
        chunkCount: chunkCount
    )
}
```

**Android (Kotlin)**
```kotlin
import java.nio.ByteBuffer
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec
import com.securesharing.crypto.NativeCrypto

data class DecryptedFile(
    val content: ByteArray,
    val metadata: FileMetadata
)

class FileDecryptor(
    private val nativeCrypto: NativeCrypto
) {
    fun decryptFile(
        encryptedBlob: ByteArray,
        fileDetails: FileDetails,
        dek: ByteArray,
        progressCallback: ((DecryptProgress) -> Unit)? = null
    ): DecryptedFile {
        // 8a. Verify blob hash FIRST (before any decryption)
        val actualHash = sha256Hex(encryptedBlob)
        if (actualHash != fileDetails.blobHash) {
            throw CryptoException("Blob hash mismatch - file may be corrupted")
        }

        // 8b. *** VERIFY SIGNATURE *** (MANDATORY - before any decryption)
        verifyFileSignature(fileDetails)

        // Parse header (64 bytes, fixed)
        val header = parseFileHeader(encryptedBlob.sliceArray(0 until 64))

        // Derive chunk key from DEK using HKDF-SHA384
        val chunkKey = nativeCrypto.hkdfSha384(
            ikm = dek,
            salt = null,
            info = "chunk-encryption".toByteArray(),
            length = 32
        )

        // 8d. Decrypt chunks
        val decryptedChunks = mutableListOf<ByteArray>()
        var offset = 64  // After header
        var chunkIndex = 0

        while (offset < encryptedBlob.size) {
            // Read nonce (12 bytes)
            val chunkNonce = encryptedBlob.sliceArray(offset until offset + 12)
            offset += 12

            // Calculate expected ciphertext size
            val isLastChunk = chunkIndex == header.chunkCount - 1
            val expectedPlaintextSize = if (isLastChunk) {
                val remainder = (header.originalSize % header.chunkSize).toInt()
                if (remainder == 0) header.chunkSize else remainder
            } else {
                header.chunkSize
            }
            val ciphertextSize = expectedPlaintextSize + 16  // +16 for tag

            val ciphertext = encryptedBlob.sliceArray(offset until offset + ciphertextSize)
            offset += ciphertextSize

            // Build AAD: chunk index (4 bytes, big-endian)
            val aad = ByteBuffer.allocate(4).putInt(chunkIndex).array()

            // Decrypt chunk
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            val keySpec = SecretKeySpec(chunkKey, "AES")
            val gcmSpec = GCMParameterSpec(128, chunkNonce)

            cipher.init(Cipher.DECRYPT_MODE, keySpec, gcmSpec)
            cipher.updateAAD(aad)
            val plaintext = cipher.doFinal(ciphertext)

            decryptedChunks.add(plaintext)
            chunkIndex++

            progressCallback?.invoke(DecryptProgress(
                phase = "decrypting",
                loaded = offset,
                total = encryptedBlob.size
            ))
        }

        // Combine chunks
        val totalSize = decryptedChunks.sumOf { it.size }
        val decryptedContent = ByteArray(totalSize)
        var destOffset = 0
        for (chunk in decryptedChunks) {
            System.arraycopy(chunk, 0, decryptedContent, destOffset, chunk.size)
            destOffset += chunk.size
        }

        // 8f. Decrypt metadata (AAD must match encryption)
        val metadataAad = "file-metadata".toByteArray(Charsets.UTF_8)
        val metadata = decryptMetadata(
            encryptedMetadata = fileDetails.encryptedMetadata,
            nonce = fileDetails.metadataNonce,
            dek = dek,
            aad = metadataAad
        )

        // 8e. Verify plaintext checksum if present
        metadata.checksum?.let { expectedChecksum ->
            val actualChecksum = sha256Hex(decryptedContent)
            if (actualChecksum != expectedChecksum) {
                throw CryptoException("Plaintext checksum mismatch")
            }
        }

        // Clear chunk key from memory
        chunkKey.fill(0)

        return DecryptedFile(
            content = decryptedContent,
            metadata = metadata
        )
    }

    private fun parseFileHeader(headerData: ByteArray): FileHeader {
        // Verify magic bytes "SSEC"
        val magic = String(headerData.sliceArray(0 until 4), Charsets.US_ASCII)
        if (magic != "SSEC") {
            throw CryptoException("Invalid file format - not a SecureSharing file")
        }

        val buffer = ByteBuffer.wrap(headerData)
        buffer.position(4)

        val version = buffer.short.toInt() and 0xFFFF
        if (version > 1) {
            throw CryptoException("Unsupported file format version: $version")
        }

        val algorithmSuite = buffer.short.toInt() and 0xFFFF
        if (algorithmSuite != 1) {
            throw CryptoException("Unsupported algorithm suite: $algorithmSuite")
        }

        val originalSize = buffer.long
        val chunkSize = buffer.int
        val chunkCount = buffer.int

        return FileHeader(
            version = version,
            algorithmSuite = algorithmSuite,
            originalSize = originalSize,
            chunkSize = chunkSize,
            chunkCount = chunkCount
        )
    }
}
```

function parseFileHeader(headerData: Uint8Array): FileHeader {
  // SSEC file format header (64 bytes, fixed)
  // See docs/crypto/03-encryption-protocol.md Section 2.4 for specification
  const view = new DataView(headerData.buffer);

  // Verify magic bytes (offset 0, 4 bytes)
  const magic = String.fromCharCode(...headerData.slice(0, 4));
  if (magic !== 'SSEC') {
    throw new Error('Invalid file format - not a SecureSharing file');
  }

  // Parse header fields
  const version = view.getUint16(4, false);          // Offset 4, 2 bytes
  const algorithmSuite = view.getUint16(6, false);   // Offset 6, 2 bytes
  const originalSize = Number(view.getBigUint64(8, false));  // Offset 8, 8 bytes
  const chunkSize = view.getUint32(16, false);       // Offset 16, 4 bytes
  const chunkCount = view.getUint32(20, false);      // Offset 20, 4 bytes
  // Reserved: offset 24-63, 40 bytes (ignored)

  // Validate version
  if (version > 1) {
    throw new Error(`Unsupported file format version: ${version}`);
  }

  // Validate algorithm suite
  if (algorithmSuite !== 1) {
    throw new Error(`Unsupported algorithm suite: ${algorithmSuite}`);
  }

  return {
    version,
    algorithmSuite,
    originalSize,
    chunkSize,
    chunkCount
  };
}

async function decryptMetadata(
  encryptedMetadata: string,
  nonce: string,
  dek: Uint8Array
): Promise<FileMetadata> {
  const ciphertext = base64Decode(encryptedMetadata);
  const nonceBytes = base64Decode(nonce);
  const metadataAad = new TextEncoder().encode('file-metadata');

  // AAD must match encryption (docs/crypto/03-encryption-protocol.md Section 2.2)
  const plaintext = await aesGcmDecrypt(dek, nonceBytes, ciphertext, metadataAad);
  const json = new TextDecoder().decode(plaintext);

  return JSON.parse(json);
}

function concatenateChunks(chunks: Uint8Array[]): Uint8Array {
  const totalLength = chunks.reduce((sum, chunk) => sum + chunk.length, 0);
  const result = new Uint8Array(totalLength);
  let offset = 0;

  for (const chunk of chunks) {
    result.set(chunk, offset);
    offset += chunk.length;
  }

  return result;
}
```

### 4.6 Step 9: Save File

```typescript
async function saveFile(
  decryptedFile: DecryptedFile,
  suggestedName?: string
): Promise<void> {

  const filename = suggestedName || decryptedFile.metadata.filename;
  const mimeType = decryptedFile.metadata.mimeType;

  // Create blob with correct MIME type
  const blob = new Blob([decryptedFile.content], { type: mimeType });

  // Trigger download
  if ('showSaveFilePicker' in window) {
    // Modern File System Access API
    try {
      const handle = await window.showSaveFilePicker({
        suggestedName: filename,
        types: [{
          description: 'File',
          accept: { [mimeType]: [`.${getExtension(filename)}`] }
        }]
      });

      const writable = await handle.createWritable();
      await writable.write(blob);
      await writable.close();
    } catch (err) {
      if (err.name !== 'AbortError') throw err;
    }
  } else {
    // Fallback: anchor click
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  }
}
```

## 5. Complete Download Implementation

```typescript
async function downloadFile(
  fileId: string,
  options?: DownloadOptions
): Promise<void> {

  const { shareId, onProgress, signal } = options || {};

  try {
    // Get file details
    onProgress?.({ phase: 'fetching', loaded: 0, total: 1 });

    const fileDetails = await getFileDetails(fileId, shareId);

    // Check for cancellation
    if (signal?.aborted) {
      throw new Error('Download cancelled');
    }

    // Get DEK
    onProgress?.({ phase: 'decrypting_key', loaded: 0, total: 1 });

    const dek = await getDekForFile(fileDetails);

    // Get download URL
    const downloadInfo = await getDownloadUrl(fileId);

    // Check for cancellation
    if (signal?.aborted) {
      dek.fill(0);
      throw new Error('Download cancelled');
    }

    // Download blob
    const encryptedBlob = await downloadBlob(downloadInfo, onProgress);

    // Check for cancellation
    if (signal?.aborted) {
      dek.fill(0);
      throw new Error('Download cancelled');
    }

    // Decrypt file
    const decryptedFile = await decryptFile(
      encryptedBlob,
      downloadInfo.blobHash,
      dek,
      fileDetails.encrypted_metadata,
      fileDetails.metadata_nonce,
      onProgress
    );

    // Clear DEK from memory
    dek.fill(0);

    // Save file
    onProgress?.({ phase: 'saving', loaded: 1, total: 1 });
    await saveFile(decryptedFile);

    onProgress?.({ phase: 'complete', loaded: 1, total: 1 });

  } catch (error) {
    onProgress?.({ phase: 'error', error: error.message });
    throw error;
  }
}
```

## 6. Streaming Download (Large Files)

For very large files, use streaming decryption to avoid memory issues.

```typescript
async function downloadFileStreaming(
  fileId: string,
  options?: DownloadOptions
): Promise<void> {

  const { shareId, onProgress } = options || {};

  // Get file details and DEK
  const fileDetails = await getFileDetails(fileId, shareId);
  const dek = await getDekForFile(fileDetails);

  // Derive chunk key from DEK using HKDF
  // See docs/crypto/03-encryption-protocol.md Section 3.1 Step 7
  const chunkKey = await hkdfDerive(dek, "chunk-encryption", 32);

  // Get download URL
  const downloadInfo = await getDownloadUrl(fileId);

  // Decrypt metadata first
  const metadata = await decryptMetadata(
    fileDetails.encrypted_metadata,
    fileDetails.metadata_nonce,
    dek
  );

  // Create writable stream for output
  const fileHandle = await window.showSaveFilePicker({
    suggestedName: metadata.filename
  });
  const writable = await fileHandle.createWritable();

  // Stream download and decrypt
  const response = await fetch(downloadInfo.url);
  const reader = response.body.getReader();

  let headerProcessed = false;
  let header: FileHeader;
  let chunkIndex = 0;
  let buffer = new Uint8Array(0);
  let bytesProcessed = 0;

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      // Append to buffer
      buffer = concatenate(buffer, value);
      bytesProcessed += value.length;

      // Process header first
      if (!headerProcessed && buffer.length >= 64) {
        header = parseFileHeader(buffer.slice(0, 64));
        buffer = buffer.slice(64);
        headerProcessed = true;
      }

      // Process complete chunks
      while (headerProcessed && hasCompleteChunk(buffer, header, chunkIndex)) {
        const { chunk, remaining } = extractChunk(buffer, header, chunkIndex);
        buffer = remaining;

        // Decrypt chunk
        const decrypted = await decryptChunk(chunk, chunkKey, chunkIndex);

        // Write to file
        await writable.write(decrypted);

        chunkIndex++;
        onProgress?.({
          phase: 'decrypting',
          loaded: bytesProcessed,
          total: downloadInfo.blobSize
        });
      }
    }

    // Process any remaining data
    if (buffer.length > 0 && headerProcessed) {
      const decrypted = await decryptChunk(buffer, chunkKey, chunkIndex);
      await writable.write(decrypted);
    }

    await writable.close();
    dek.fill(0);
    chunkKey.fill(0);

    onProgress?.({ phase: 'complete', loaded: 1, total: 1 });

  } catch (error) {
    await writable.abort();
    dek.fill(0);
    chunkKey.fill(0);
    throw error;
  }
}
```

## 7. Download via Share Link

For anonymous share links (URL sharing):

```typescript
async function downloadViaShareLink(
  shareToken: string,
  password?: string
): Promise<void> {

  // Step 1: Get share link details
  const response = await fetch(`/api/v1/shares/link/${shareToken}`);

  if (!response.ok) {
    const error = await response.json();
    throw new DownloadError(error.error.code, error.error.message);
  }

  const { data: shareLink } = await response.json();

  // Check if link has expired or exhausted
  if (shareLink.expired) {
    throw new DownloadError('E_LINK_EXPIRED', 'Share link has expired');
  }

  let wrappedKey: string;
  let fileDetails: ShareLinkFileInfo;
  let linkSession: string | undefined;
  let ownerPublicKeys: { ml_dsa: string; kaz_sign: string };
  let signature: CombinedSignature;
  let createdAt: string;

  // Step 2: Handle password-protected vs unprotected links
  if (shareLink.password_protected) {
    // For protected links, initial response only contains:
    // { password_protected: true, password_verified: false, password_salt: "..." }

    if (!password) {
      // Prompt user for password
      password = await promptPassword();
    }

    // Derive password hash for verification
    const passwordHash = await argon2id(password, {
      salt: base64Decode(shareLink.password_salt),
      memory: 65536,
      iterations: 3,
      parallelism: 4,
      hashLength: 32
    });

    // Step 2a: Verify password with server
    // See docs/api/05-sharing.md Section 2.13
    const verifyResponse = await fetch(`/api/v1/shares/link/${shareToken}/verify`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        password_hash: base64Encode(passwordHash)
      })
    });

    if (!verifyResponse.ok) {
      const error = await verifyResponse.json();
      if (error.error.code === 'E_INVALID_PASSWORD') {
        // Wrong password - prompt again
        return downloadViaShareLink(shareToken, await promptPassword('Invalid password'));
      }
      throw new DownloadError(error.error.code, error.error.message);
    }

    const { data: verifyResult } = await verifyResponse.json() as { data: ShareLinkFileVerifyResult };

    // Store session token for download request
    linkSession = verifyResult.session_token;

    // Get wrapped_key, signature, and file details from verify response
    wrappedKey = verifyResult.wrapped_key;
    fileDetails = verifyResult.file;
    ownerPublicKeys = verifyResult.owner.public_keys;
    signature = verifyResult.signature;
    createdAt = verifyResult.created_at;

    // Step 2b: MANDATORY - Verify signature before decryption
    // See docs/crypto/05-signature-protocol.md Section 4.6
    // All signature payload fields come from verifyResult (not shareLink pre-verify response)
    const signatureValid = await verifyShareLinkSignature(
      ownerPublicKeys,
      signature,
      {
        resourceType: 'file',
        resourceId: fileDetails.id,
        creatorId: verifyResult.owner.id,
        wrappedKey,
        permission: verifyResult.permission,
        expiry: verifyResult.expiry,
        passwordProtected: verifyResult.password_protected,
        maxDownloads: verifyResult.max_downloads,
        createdAt
      }
    );

    if (!signatureValid) {
      throw new DownloadError('E_SIGNATURE_INVALID', 'Share link signature verification failed');
    }

    // Step 2c: MANDATORY - Verify FILE signature before decryption
    // This verifies the file content was created by the file owner
    // See docs/crypto/05-signature-protocol.md Section 4.1
    const fileSignatureValid = await verifyFileSignatureFromShareLink(fileDetails);

    if (!fileSignatureValid) {
      throw new DownloadError('E_SIGNATURE_INVALID', 'File signature verification failed');
    }

    // Derive key from password to unwrap DEK
    const passwordKey = passwordHash;  // Same value used for verification
    const dek = await aesKeyUnwrap(passwordKey, base64Decode(wrappedKey));
    passwordKey.fill(0);

    // Step 3: Get download URL (with session)
    const downloadInfo = await getShareLinkDownloadUrl(shareToken, linkSession);

    // Step 4: Download and decrypt
    await downloadAndDecryptShareLink(downloadInfo, dek, fileDetails);
    dek.fill(0);

  } else {
    // Unprotected links return wrapped_key, signature, and file details directly
    const typedShareLink = shareLink as ShareLinkFileDetails;
    wrappedKey = typedShareLink.wrapped_key;
    fileDetails = typedShareLink.file;
    ownerPublicKeys = typedShareLink.owner.public_keys;
    signature = typedShareLink.signature;
    createdAt = typedShareLink.created_at;

    // Step 2b: MANDATORY - Verify signature before decryption
    // See docs/crypto/05-signature-protocol.md Section 4.6
    const signatureValid = await verifyShareLinkSignature(
      ownerPublicKeys,
      signature,
      {
        resourceType: 'file',
        resourceId: fileDetails.id,
        creatorId: typedShareLink.owner.id,
        wrappedKey,
        permission: 'read',
        expiry: typedShareLink.expiry,
        passwordProtected: false,
        maxDownloads: typedShareLink.max_downloads,
        createdAt
      }
    );

    if (!signatureValid) {
      throw new DownloadError('E_SIGNATURE_INVALID', 'Share link signature verification failed');
    }

    // Step 2c: MANDATORY - Verify FILE signature before decryption
    // This verifies the file content was created by the file owner
    // See docs/crypto/05-signature-protocol.md Section 4.1
    const fileSignatureValid = await verifyFileSignatureFromShareLink(fileDetails);

    if (!fileSignatureValid) {
      throw new DownloadError('E_SIGNATURE_INVALID', 'File signature verification failed');
    }

    // For unprotected links, key is in URL fragment
    // wrapped_key is DEK wrapped with a random key embedded in URL
    const urlKey = getKeyFromUrlFragment();  // Get from window.location.hash
    let dek: Uint8Array;

    if (urlKey) {
      // Unwrap DEK using key from URL fragment
      dek = await aesKeyUnwrap(base64Decode(urlKey), base64Decode(wrappedKey));
    } else {
      throw new DownloadError('E_MISSING_KEY', 'URL key fragment is required for unprotected links');
    }

    // Step 3: Get download URL (no session needed)
    const downloadInfo = await getShareLinkDownloadUrl(shareToken);

    // Step 4: Download and decrypt
    await downloadAndDecryptShareLink(downloadInfo, dek, fileDetails);
    dek.fill(0);
  }
}

// Helper: Verify share link signature
// See docs/crypto/05-signature-protocol.md Section 4.6
async function verifyShareLinkSignature(
  ownerPublicKeys: { ml_dsa: string; kaz_sign: string },
  signature: CombinedSignature,
  payload: {
    resourceType: string;
    resourceId: string;
    creatorId: string;
    wrappedKey: string;
    permission: string;
    expiry: string | null;
    passwordProtected: boolean;
    maxDownloads: number | null;
    createdAt: string;
  }
): Promise<boolean> {
  // Canonicalize the payload (same as what creator signed)
  const signaturePayload = canonicalize({
    resourceType: payload.resourceType,
    resourceId: payload.resourceId,
    creatorId: payload.creatorId,
    wrappedKey: payload.wrappedKey,
    permission: payload.permission,
    expiry: payload.expiry,
    passwordProtected: payload.passwordProtected,
    maxDownloads: payload.maxDownloads,
    createdAt: payload.createdAt
  });

  // Verify both signatures (must pass both for hybrid security)
  const mlDsaValid = await mlDsaVerify(
    base64Decode(ownerPublicKeys.ml_dsa),
    signaturePayload,
    base64Decode(signature.ml_dsa)
  );

  const kazSignValid = await kazSignVerify(
    base64Decode(ownerPublicKeys.kaz_sign),
    signaturePayload,
    base64Decode(signature.kaz_sign)
  );

  return mlDsaValid && kazSignValid;
}

// Helper: Verify file signature from share link response
// See docs/crypto/05-signature-protocol.md Section 4.1
async function verifyFileSignatureFromShareLink(
  fileDetails: ShareLinkFileInfo
): Promise<boolean> {
  // File signature covers: blob_hash, blob_size, wrapped_dek, encrypted_metadata, metadata_nonce
  // This is the ORIGINAL signature created by the file owner during upload
  const signaturePayload = canonicalize({
    blobHash: fileDetails.blob_hash,
    blobSize: fileDetails.blob_size,
    wrappedDek: fileDetails.wrapped_dek,
    encryptedMetadata: fileDetails.encrypted_metadata,
    metadataNonce: fileDetails.metadata_nonce
  });

  // Verify both signatures using the file OWNER's public keys
  // Note: file.owner may be different from share link owner
  const mlDsaValid = await mlDsaVerify(
    base64Decode(fileDetails.owner.public_keys.ml_dsa),
    signaturePayload,
    base64Decode(fileDetails.signature.ml_dsa)
  );

  const kazSignValid = await kazSignVerify(
    base64Decode(fileDetails.owner.public_keys.kaz_sign),
    signaturePayload,
    base64Decode(fileDetails.signature.kaz_sign)
  );

  return mlDsaValid && kazSignValid;
}

// Helper: Get download URL for share link
async function getShareLinkDownloadUrl(
  shareToken: string,
  linkSession?: string
): Promise<DownloadInfo> {
  const headers: Record<string, string> = {};

  // Protected links require session token
  if (linkSession) {
    headers['X-Link-Session'] = linkSession;
  }

  const response = await fetch(`/api/v1/shares/link/${shareToken}/download`, {
    headers
  });

  if (!response.ok) {
    const error = await response.json();
    throw new DownloadError(error.error.code, error.error.message);
  }

  const { data } = await response.json();
  return {
    url: data.download.url,
    expiresAt: new Date(data.download.expires_at),
    blobSize: data.file.blob_size,
    blobHash: data.file.blob_hash
  };
}

// Helper: Download and decrypt share link file
async function downloadAndDecryptShareLink(
  downloadInfo: DownloadInfo,
  dek: Uint8Array,
  fileDetails: ShareLinkFileInfo
): Promise<void> {
  const encryptedBlob = await downloadBlob(downloadInfo);

  const decryptedFile = await decryptFile(
    encryptedBlob,
    downloadInfo.blobHash,
    dek,
    fileDetails.encrypted_metadata,
    fileDetails.metadata_nonce
  );

  await saveFile(decryptedFile);
}

// Helper: Extract key from URL fragment (for unprotected links)
function getKeyFromUrlFragment(): string | null {
  const hash = window.location.hash;
  if (hash && hash.length > 1) {
    return hash.substring(1);  // Remove leading #
  }
  return null;
}
```

### 7.1 Folder Share Links

For folder share links, the flow differs from file links:
1. Client receives KEK (not DEK) in `wrapped_key`
2. Client browses folder contents via `/contents` endpoint
3. Each file download requires unwrapping that file's DEK with the folder KEK

```typescript
async function accessFolderShareLink(
  shareToken: string,
  password?: string
): Promise<void> {

  // Step 1: Get share link details (same as file links)
  const response = await fetch(`/api/v1/shares/link/${shareToken}`);
  const { data: shareLink } = await response.json();

  if (shareLink.resource_type !== 'folder') {
    throw new Error('Expected folder share link');
  }

  let folderKek: Uint8Array;
  let linkSession: string | undefined;

  // Fields needed for signature verification (extracted from either pre-verify or verify response)
  // Uses ShareLinkFolderDetails (unprotected) or ShareLinkFolderVerifyResult (protected)
  let ownerPublicKeys: { ml_dsa: string; kaz_sign: string };
  let ownerId: string;
  let signature: CombinedSignature;
  let createdAt: string;
  let wrappedKey: string;
  let permission: string;
  let expiry: string | null;
  let passwordProtected: boolean;
  let maxDownloads: number | null;
  let folder: ShareLinkFolderInfo;

  // Step 2: Handle authentication and get KEK
  if (shareLink.password_protected) {
    if (!password) {
      password = await promptPassword();
    }

    const passwordHash = await argon2id(password, {
      salt: base64Decode(shareLink.password_salt),
      memory: 65536,
      iterations: 3,
      parallelism: 4,
      hashLength: 32
    });

    const verifyResponse = await fetch(`/api/v1/shares/link/${shareToken}/verify`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ password_hash: base64Encode(passwordHash) })
    });

    const { data: verifyResult } = await verifyResponse.json();
    linkSession = verifyResult.session_token;

    // Extract all fields from verification response (protected links)
    ownerPublicKeys = verifyResult.owner.public_keys;
    ownerId = verifyResult.owner.id;
    signature = verifyResult.signature;
    createdAt = verifyResult.created_at;
    wrappedKey = verifyResult.wrapped_key;
    permission = verifyResult.permission;
    expiry = verifyResult.expiry;
    passwordProtected = verifyResult.password_protected;
    maxDownloads = verifyResult.max_downloads;
    folder = verifyResult.folder;

    // Unwrap KEK using password-derived key
    folderKek = await aesKeyUnwrap(passwordHash, base64Decode(wrappedKey));

  } else {
    // Unprotected link - key is in URL fragment
    const urlKey = getKeyFromUrlFragment();
    if (!urlKey) {
      throw new Error('URL key fragment required for unprotected links');
    }

    // Extract all fields from pre-verify response (unprotected links)
    ownerPublicKeys = shareLink.owner.public_keys;
    ownerId = shareLink.owner.id;
    signature = shareLink.signature;
    createdAt = shareLink.created_at;
    wrappedKey = shareLink.wrapped_key;
    permission = shareLink.permission;
    expiry = shareLink.expiry;
    passwordProtected = shareLink.password_protected;
    maxDownloads = shareLink.max_downloads;
    folder = shareLink.folder;

    // Unwrap KEK using key from URL
    folderKek = await aesKeyUnwrap(base64Decode(urlKey), base64Decode(wrappedKey));
  }

  // Step 3: MANDATORY - Verify signature before accessing contents
  const signatureValid = await verifyShareLinkSignature(
    ownerPublicKeys,
    signature,
    {
      resourceType: 'folder',
      resourceId: folder.id,
      creatorId: ownerId,
      wrappedKey,
      permission,
      expiry,
      passwordProtected,
      maxDownloads,
      createdAt
    }
  );

  if (!signatureValid) {
    folderKek.fill(0);
    throw new DownloadError('E_SIGNATURE_INVALID', 'Share link signature verification failed');
  }

  // Step 3b: MANDATORY - Verify FOLDER signature before decryption
  // This verifies the folder was created by the folder owner
  // See docs/crypto/05-signature-protocol.md Section 4.4
  const folderSignatureValid = await verifyFolderSignature(folder);

  if (!folderSignatureValid) {
    folderKek.fill(0);
    throw new DownloadError('E_SIGNATURE_INVALID', 'Folder signature verification failed');
  }

  // Step 4: Decrypt folder metadata (only after BOTH signatures verified)
  const folderMetadataAad = new TextEncoder().encode('folder-metadata');
  const folderMetadata = await decryptMetadata(
    folder.encrypted_metadata,
    folder.metadata_nonce,
    folderKek,
    folderMetadataAad
  );

  console.log(`Accessing shared folder: ${folderMetadata.name}`);

  // Step 5: Browse folder contents
  await browseFolderShareLink(shareToken, folderKek, linkSession);

  folderKek.fill(0);
}

// Browse and download files from folder share link
async function browseFolderShareLink(
  shareToken: string,
  folderKek: Uint8Array,
  linkSession?: string,
  path: string = '/'
): Promise<void> {

  const headers: Record<string, string> = {};
  if (linkSession) {
    headers['X-Link-Session'] = linkSession;
  }

  // Get folder contents
  const response = await fetch(
    `/api/v1/shares/link/${shareToken}/contents?path=${encodeURIComponent(path)}`,
    { headers }
  );

  const { data: contents } = await response.json();

  // Decrypt folder metadata for current path
  const folderMetadataAad = new TextEncoder().encode('folder-metadata');
  const currentFolderMetadata = await decryptMetadata(
    contents.folder.encrypted_metadata,
    contents.folder.metadata_nonce,
    folderKek,
    folderMetadataAad
  );

  console.log(`Folder: ${currentFolderMetadata.name} (${path})`);

  // List files
  const fileMetadataAad = new TextEncoder().encode('file-metadata');
  for (const file of contents.items.files) {
    // Unwrap file DEK with folder KEK
    const fileDek = await aesKeyUnwrap(folderKek, base64Decode(file.wrapped_dek));

    // Decrypt file metadata
    const fileMetadata = await decryptMetadata(
      file.encrypted_metadata,
      file.metadata_nonce,
      fileDek,
      fileMetadataAad
    );

    console.log(`  File: ${fileMetadata.filename} (${file.blob_size} bytes)`);

    fileDek.fill(0);
  }

  // List subfolders
  for (const subfolder of contents.items.subfolders) {
    // MANDATORY: Verify subfolder signature before trusting KEK
    // See docs/crypto/05-signature-protocol.md Section 4.4
    const subfolderSignatureValid = await verifySubfolderSignature(subfolder);

    if (!subfolderSignatureValid) {
      console.error(`  Subfolder ${subfolder.id}: SIGNATURE INVALID - skipping`);
      continue;
    }

    // Unwrap subfolder KEK with parent KEK (only after signature verified)
    const subfolderKek = await aesKeyUnwrap(folderKek, base64Decode(subfolder.wrapped_kek));

    // Decrypt subfolder metadata
    const subfolderMetadata = await decryptMetadata(
      subfolder.encrypted_metadata,
      subfolder.metadata_nonce,
      subfolderKek,
      folderMetadataAad
    );

    console.log(`  Subfolder: ${subfolderMetadata.name}/ (${subfolder.item_count} items)`);

    subfolderKek.fill(0);
  }
}

// Download specific file from folder share link
async function downloadFileFromFolderShareLink(
  shareToken: string,
  fileId: string,
  folderKek: Uint8Array,
  fileItem: ShareLinkFolderFileItem,
  linkSession?: string
): Promise<void> {

  // Step 1: MANDATORY - Verify file signature before download
  // Each file has its own signature from the file owner
  // See docs/crypto/05-signature-protocol.md Section 4.1
  const fileSignatureValid = await verifyFileSignatureForFolderItem(fileItem);

  if (!fileSignatureValid) {
    throw new DownloadError('E_SIGNATURE_INVALID', 'File signature verification failed');
  }

  // Step 2: Unwrap file DEK with folder KEK
  const fileDek = await aesKeyUnwrap(folderKek, base64Decode(fileItem.wrapped_dek));

  // Step 3: Get download URL
  const headers: Record<string, string> = {};
  if (linkSession) {
    headers['X-Link-Session'] = linkSession;
  }

  const response = await fetch(
    `/api/v1/shares/link/${shareToken}/download/${fileId}`,
    { headers }
  );

  const { data: downloadData } = await response.json();

  // Step 4: Download encrypted blob
  const encryptedBlob = await downloadBlob({
    url: downloadData.download.url,
    blobSize: downloadData.file.blob_size,
    blobHash: downloadData.file.blob_hash
  });

  // Step 5: Verify blob hash
  const actualHash = await sha256Hex(encryptedBlob);
  if (actualHash !== downloadData.file.blob_hash) {
    fileDek.fill(0);
    throw new DownloadError('E_HASH_MISMATCH', 'Downloaded file hash does not match');
  }

  // Step 6: Decrypt file
  const fileMetadataAad = new TextEncoder().encode('file-metadata');
  const metadata = await decryptMetadata(
    fileItem.encrypted_metadata,
    fileItem.metadata_nonce,
    fileDek,
    fileMetadataAad
  );

  const decryptedContent = await decryptFileContent(encryptedBlob, fileDek);

  // Step 7: Save file
  await saveFile({
    content: decryptedContent,
    metadata
  });

  fileDek.fill(0);
}

// Helper: Verify file signature for file item within folder share link
// See docs/crypto/05-signature-protocol.md Section 4.1
async function verifyFileSignatureForFolderItem(
  fileItem: ShareLinkFolderFileItem
): Promise<boolean> {
  // File signature covers: blob_hash, blob_size, wrapped_dek, encrypted_metadata, metadata_nonce
  const signaturePayload = canonicalize({
    blobHash: fileItem.blob_hash,
    blobSize: fileItem.blob_size,
    wrappedDek: fileItem.wrapped_dek,
    encryptedMetadata: fileItem.encrypted_metadata,
    metadataNonce: fileItem.metadata_nonce
  });

  // Verify both signatures using the file OWNER's public keys
  const mlDsaValid = await mlDsaVerify(
    base64Decode(fileItem.owner.public_keys.ml_dsa),
    signaturePayload,
    base64Decode(fileItem.signature.ml_dsa)
  );

  const kazSignValid = await kazSignVerify(
    base64Decode(fileItem.owner.public_keys.kaz_sign),
    signaturePayload,
    base64Decode(fileItem.signature.kaz_sign)
  );

  return mlDsaValid && kazSignValid;
}

// Interface for folder contents file item (matches API response)
interface ShareLinkFolderFileItem {
  id: string;
  encrypted_metadata: string;
  metadata_nonce: string;
  wrapped_dek: string;
  blob_size: number;
  blob_hash: string;
  signature: CombinedSignature;
  owner: {
    id: string;
    public_keys: {
      ml_dsa: string;
      kaz_sign: string;
    };
  };
}

// Interface for folder contents subfolder item (matches API response)
interface ShareLinkFolderSubfolderItem {
  id: string;
  parent_id: string;
  encrypted_metadata: string;
  metadata_nonce: string;
  owner_key_access: {
    wrapped_kek: string;
    kem_ciphertexts: { algorithm: string; ciphertext: string }[];
  };
  wrapped_kek: string;
  signature: CombinedSignature;
  owner: {
    id: string;
    public_keys: {
      ml_dsa: string;
      kaz_sign: string;
    };
  };
  item_count: number;
  created_at: string;
}

// Helper: Verify subfolder signature within folder share link
// See docs/crypto/05-signature-protocol.md Section 4.4
async function verifySubfolderSignature(
  subfolder: ShareLinkFolderSubfolderItem
): Promise<boolean> {
  // Folder signature covers: parentId, encryptedMetadata, metadataNonce,
  // ownerKeyAccess, wrappedKek, createdAt
  const signaturePayload = canonicalize({
    parentId: subfolder.parent_id,
    encryptedMetadata: subfolder.encrypted_metadata,
    metadataNonce: subfolder.metadata_nonce,
    ownerKeyAccess: subfolder.owner_key_access,
    wrappedKek: subfolder.wrapped_kek,
    createdAt: subfolder.created_at
  });

  // Verify both signatures using the subfolder OWNER's public keys
  const mlDsaValid = await mlDsaVerify(
    base64Decode(subfolder.owner.public_keys.ml_dsa),
    signaturePayload,
    base64Decode(subfolder.signature.ml_dsa)
  );

  const kazSignValid = await kazSignVerify(
    base64Decode(subfolder.owner.public_keys.kaz_sign),
    signaturePayload,
    base64Decode(subfolder.signature.kaz_sign)
  );

  return mlDsaValid && kazSignValid;
}

// Helper: Verify folder signature from share link
// Used when accessing a folder via share link
// See docs/crypto/05-signature-protocol.md Section 4.4
async function verifyFolderSignature(
  folder: ShareLinkFolderInfo
): Promise<boolean> {
  // Folder signature covers: parentId, encryptedMetadata, metadataNonce,
  // ownerKeyAccess, wrappedKek, createdAt
  const signaturePayload = canonicalize({
    parentId: folder.parent_id,
    encryptedMetadata: folder.encrypted_metadata,
    metadataNonce: folder.metadata_nonce,
    ownerKeyAccess: folder.owner_key_access,
    wrappedKek: folder.wrapped_kek,
    createdAt: folder.created_at
  });

  // Verify both signatures using the folder OWNER's public keys
  const mlDsaValid = await mlDsaVerify(
    base64Decode(folder.owner.public_keys.ml_dsa),
    signaturePayload,
    base64Decode(folder.signature.ml_dsa)
  );

  const kazSignValid = await kazSignVerify(
    base64Decode(folder.owner.public_keys.kaz_sign),
    signaturePayload,
    base64Decode(folder.signature.kaz_sign)
  );

  return mlDsaValid && kazSignValid;
}
```

**Key Differences: File vs Folder Share Links**

| Aspect | File Share Link | Folder Share Link |
|--------|-----------------|-------------------|
| `wrapped_key` contains | DEK | KEK |
| Access pattern | Direct download | Browse then download |
| Contents endpoint | Not used | `/contents` to list items |
| Download endpoint | `/download` | `/download/{file_id}` |
| Key hierarchy | Link key → DEK → file | Link key → KEK → DEK → file |
| Subfolder access | N/A | Unwrap child KEK with parent KEK |

## 8. Error Handling

| Error Code | Cause | Recovery |
|------------|-------|----------|
| `E_FILE_NOT_FOUND` | File doesn't exist | Check file ID |
| `E_FILE_DELETED` | File is in trash | Restore or use different file |
| `E_PERMISSION_DENIED` | No read access | Request access |
| `E_SHARE_EXPIRED` | Share has expired | Request new share |
| `E_HASH_MISMATCH` | File corrupted | Report to owner |
| `E_DECRYPTION_FAILED` | Key mismatch | May need re-share |
| `E_DOWNLOAD_FAILED` | Storage error | Retry |

### Error Recovery

```typescript
async function downloadWithRetry(
  fileId: string,
  maxRetries: number = 3
): Promise<void> {

  let lastError: Error;

  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      return await downloadFile(fileId);
    } catch (error) {
      lastError = error;

      // Don't retry certain errors
      if (isNonRetryableError(error)) {
        throw error;
      }

      // Wait before retry
      const delay = Math.min(1000 * Math.pow(2, attempt), 30000);
      await sleep(delay);
    }
  }

  throw lastError;
}

function isNonRetryableError(error: Error): boolean {
  const nonRetryableCodes = [
    'E_FILE_NOT_FOUND',
    'E_FILE_DELETED',
    'E_PERMISSION_DENIED',
    'E_SHARE_EXPIRED',
    'E_HASH_MISMATCH',
    'E_DECRYPTION_FAILED'
  ];

  return nonRetryableCodes.includes(error.code);
}
```

## 9. Security Considerations

### 9.1 Key Handling

- DEK is derived/decapsulated only when needed
- DEK is cleared from memory after decryption
- Chunk keys derived per-file, not reused

### 9.2 Integrity Verification

- Blob hash verified before decryption
- **Signature verified before decryption (MANDATORY)** - see Section 10
- Each chunk has authentication tag
- Plaintext checksum verified if available

### 9.3 Memory Safety

- Streaming decryption for large files
- Intermediate buffers cleared after use
- No plaintext written to disk (except final save)

## 10. Signature Verification (MANDATORY)

**CRITICAL SECURITY REQUIREMENT**: Signature verification MUST be performed BEFORE any decryption. This is NOT optional. See [docs/crypto/05-signature-protocol.md](../crypto/05-signature-protocol.md) Section 7.1.

### 10.1 Why Signature Verification is Mandatory

| Without Verification | Risk |
|---------------------|------|
| Skip signature check | Attacker can substitute malicious encrypted content |
| Verify after decryption | Already processed potentially malicious data |
| Verify only blob hash | Hash doesn't prove authenticity (attacker can compute hash of malicious content) |

**Signature verification ensures**:
- File was created by the claimed owner
- Content hasn't been tampered with since signing
- Attacker cannot substitute their own encrypted content

### 10.2 Verification Implementation

```typescript
async function verifyFileSignature(
  fileDetails: FileDetails
): Promise<void> {
  // MANDATORY: This function MUST be called before decryption
  // See docs/crypto/05-signature-protocol.md

  // 1. Get owner's public keys
  // For share access: keys are included in response (fileDetails.owner.public_keys)
  // For owner access: use own keys from keyManager
  let ownerKeys: SignPublicKeys;

  if ('owner' in fileDetails && fileDetails.owner?.public_keys) {
    // Share access: owner's public keys included in API response
    ownerKeys = {
      mlDsa: base64Decode(fileDetails.owner.public_keys.ml_dsa),
      kazSign: base64Decode(fileDetails.owner.public_keys.kaz_sign)
    };
  } else if (fileDetails.access?.source === 'owner') {
    // Owner access: use own keys
    ownerKeys = keyManager.getKeys().publicKeys.sign;
  } else {
    throw new SignatureError('E_SIGNER_NOT_FOUND', 'Cannot verify: owner keys unavailable');
  }

  // 2. Reconstruct signature payload (must match upload format exactly)
  // See docs/crypto/03-encryption-protocol.md Section 3.1 Step 10
  const signaturePayload = canonicalize({
    blob_hash: fileDetails.blob_hash,
    blob_size: fileDetails.blob_size,
    wrapped_dek: fileDetails.wrapped_dek,
    encrypted_metadata: fileDetails.encrypted_metadata,
    metadata_nonce: fileDetails.metadata_nonce
  });

  // 3. Verify BOTH signatures (ML-DSA and KAZ-SIGN)
  const valid = await combinedVerify(
    ownerKeys,
    signaturePayload,
    fileDetails.signature
  );

  // 4. FAIL if signature is invalid - do NOT proceed to decryption
  if (!valid) {
    throw new SignatureError(
      'E_SIGNATURE_INVALID',
      'File signature verification failed - file may be tampered or corrupted'
    );
  }

  // Signature valid - safe to proceed with decryption
}
```

### 10.3 Integration with Download Flow

The `verifyFileSignature` function is called automatically by `decryptFile`. It is NOT optional:

```typescript
// In decryptFile function (see Section 4.5):
// Step 8a: Verify blob hash
// Step 8b: *** VERIFY SIGNATURE *** (MANDATORY)
await verifyFileSignature(fileDetails);  // Throws if invalid
// Step 8c: Only after signature verification passes, proceed to decrypt
```
