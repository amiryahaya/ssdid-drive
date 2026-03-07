# File Encryption Protocol Specification

**Version**: 1.0.0
**Status**: Draft
**Last Updated**: 2025-01

## 1. Overview

This document specifies how files are encrypted client-side before upload to the server. The protocol ensures:
- Zero-knowledge: Server cannot decrypt file contents
- Integrity: Tampering is detected via authentication tags
- Efficiency: Large files handled via chunking
- Metadata protection: Filename and attributes encrypted

## 2. Encrypted File Format

### 2.1 Design Principles

The encrypted file format separates concerns between the **blob** (stored in object storage) and **metadata** (stored in database):

| Data | Storage Location | Rationale |
|------|-----------------|-----------|
| Encrypted file content | Object storage (blob) | Large, immutable content |
| Wrapped DEK | Database | Needed for key chain traversal |
| Encrypted metadata | Database | Enables server-side operations |
| Signature | Database | Verifiable without downloading blob |

This separation enables:
- Signature verification without downloading the blob
- Share operations referencing metadata independently
- Clean separation between content and access control

### 2.2 Blob Structure Overview

The encrypted blob contains only the header and encrypted chunks:

```
┌─────────────────────────────────────────────────────────────────┐
│                    ENCRYPTED BLOB (Object Storage)               │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  HEADER (64 bytes, fixed size)                             │  │
│  │  ─────────────────────────────                             │  │
│  │  • Magic bytes: "SSEC" (4 bytes)                          │  │
│  │  • Version: 1 (2 bytes, big-endian)                       │  │
│  │  • Algorithm suite: 1 (2 bytes, big-endian)               │  │
│  │  • Original file size (8 bytes, big-endian)               │  │
│  │  • Chunk size (4 bytes, big-endian)                       │  │
│  │  • Total chunks (4 bytes, big-endian)                     │  │
│  │  • Reserved (40 bytes, zero-filled)                        │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  CHUNK 0                                                   │  │
│  │  ─────────                                                 │  │
│  │  • Nonce (12 bytes)                                        │  │
│  │  • Ciphertext (≤ chunk_size bytes)                        │  │
│  │  • Authentication tag (16 bytes)                           │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  CHUNK 1                                                   │  │
│  │  ─────────                                                 │  │
│  │  • Nonce (12 bytes)                                        │  │
│  │  • Ciphertext (≤ chunk_size bytes)                        │  │
│  │  • Authentication tag (16 bytes)                           │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ... (more chunks)                                              │
│                                                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  CHUNK N (final)                                           │  │
│  │  ──────────────                                            │  │
│  │  • Nonce (12 bytes)                                        │  │
│  │  • Ciphertext (remaining bytes)                            │  │
│  │  • Authentication tag (16 bytes)                           │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 2.3 Database Record Structure

The following fields are stored in the database alongside the blob reference:

```
┌─────────────────────────────────────────────────────────────────┐
│                    FILE RECORD (Database)                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  blob_storage_key:     Path to blob in object storage            │
│  blob_size:            Size of encrypted blob in bytes           │
│  blob_hash:            SHA-256 of entire blob (hex)              │
│                                                                  │
│  wrapped_dek:          DEK wrapped by folder KEK (bytes)         │
│                                                                  │
│  encrypted_metadata:   AES-256-GCM encrypted JSON (bytes)        │
│  metadata_nonce:       12-byte nonce for metadata encryption     │
│                                                                  │
│  signature:            Combined ML-DSA + KAZ-SIGN signature      │
│    ml_dsa:             ML-DSA-65 signature (bytes)               │
│    kaz_sign:           KAZ-SIGN signature (bytes)                │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 2.4 Header Format (64 bytes, fixed)

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 4 | magic | `"SSEC"` (0x53 0x53 0x45 0x43) |
| 4 | 2 | version | Format version (currently 0x0001) |
| 6 | 2 | algorithm_suite | Algorithm suite ID (currently 0x0001) |
| 8 | 8 | original_size | Original file size in bytes |
| 16 | 4 | chunk_size | Plaintext chunk size (default: 4 MiB) |
| 20 | 4 | total_chunks | Number of chunks |
| 24 | 40 | reserved | Reserved for future use (zero-filled) |

**Algorithm Suite IDs**:
| ID | Description |
|----|-------------|
| 0x0001 | AES-256-GCM + HKDF-SHA384 + ML-DSA-65 + KAZ-SIGN |

### 2.5 Chunk Format

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 12 | nonce | Unique nonce for this chunk |
| 12 | var | ciphertext | Encrypted chunk data |
| var | 16 | tag | AES-GCM authentication tag |

## 3. Encryption Process

### 3.1 Algorithm

```
EncryptFile(plaintext_file, folder_KEK, user_sign_keys):

    // 1. Generate random DEK
    DEK ← CSPRNG(32 bytes)

    // 2. Wrap DEK with folder KEK
    wrapped_dek ← AES-256-KWP.Wrap(folder_KEK, DEK)

    // 3. Prepare metadata
    metadata ← {
        filename: original_filename,
        mimeType: detected_mime_type,
        size: plaintext_file.length,
        createdAt: current_timestamp,
        modifiedAt: file_modified_time,
        checksum: SHA-256(plaintext_file)
    }

    // 4. Encrypt metadata (stored in database, NOT in blob)
    meta_nonce ← CSPRNG(12 bytes)
    encrypted_meta ← AES-256-GCM.Encrypt(
        key = DEK,
        nonce = meta_nonce,
        plaintext = JSON.stringify(metadata),
        aad = "file-metadata"
    )

    // AAD values for different metadata types:
    // | Metadata Type   | AAD String        | Key Used |
    // |-----------------|-------------------|----------|
    // | File metadata   | "file-metadata"   | DEK      |
    // | Folder metadata | "folder-metadata" | KEK      |
    //
    // AAD provides domain separation and ensures ciphertext cannot be
    // reused across different contexts.

    // 5. Calculate chunk parameters
    chunk_size ← 4 * 1024 * 1024  // 4 MiB
    total_chunks ← ceil(plaintext_file.length / chunk_size)

    // 6. Write header (64 bytes, fixed)
    header ← BuildHeader(
        original_size = plaintext_file.length,
        chunk_size = chunk_size,
        total_chunks = total_chunks
    )
    blob.write(header)

    // 7. Derive chunk key from DEK using HKDF
    chunk_key ← HKDF-SHA384(
        ikm = DEK,
        salt = empty,
        info = "chunk-encryption",
        length = 32
    )

    // 8. Encrypt each chunk
    for i in 0..total_chunks:
        chunk_plaintext ← plaintext_file.read(chunk_size)

        // Generate nonce: random prefix (8 bytes) + chunk index (4 bytes)
        nonce ← CSPRNG(8 bytes) || BigEndian(i, 4 bytes)

        // AAD includes chunk index to prevent reordering
        aad ← BigEndian(i, 4 bytes)

        (ciphertext, tag) ← AES-256-GCM.Encrypt(
            key = chunk_key,
            nonce = nonce,
            plaintext = chunk_plaintext,
            aad = aad
        )

        blob.write(nonce || ciphertext || tag)

    // 9. Calculate blob hash
    blob_hash ← SHA-256(blob.bytes)

    // 10. Sign the file package (covers metadata and blob hash)
    signature_payload ← Canonicalize({
        blob_hash: hex(blob_hash),
        blob_size: blob.length,
        wrapped_dek: base64(wrapped_dek),
        encrypted_metadata: base64(encrypted_meta),
        metadata_nonce: base64(meta_nonce)
    })
    signature ← CombinedSign(user_sign_keys, signature_payload)

    // 11. Securely erase keys from memory
    DEK.zeroize()
    chunk_key.zeroize()

    // 12. Return blob and database fields separately
    return {
        blob: blob.bytes,
        database_fields: {
            blob_hash: hex(blob_hash),
            blob_size: blob.length,
            wrapped_dek: wrapped_dek,
            encrypted_metadata: encrypted_meta,
            metadata_nonce: meta_nonce,
            signature: signature
        }
    }
```

### 3.2 Chunking Strategy

**Default Chunk Size**: 4 MiB (4,194,304 bytes)

**Rationale**:
- Large enough for efficient I/O
- Small enough for memory-constrained devices
- Allows streaming without loading entire file

**Chunk Size Selection**:
| File Size | Recommended Chunk Size |
|-----------|----------------------|
| < 4 MiB | Single chunk (file size) |
| 4 MiB - 1 GiB | 4 MiB |
| 1 GiB - 10 GiB | 16 MiB |
| > 10 GiB | 64 MiB |

### 3.3 Nonce Generation

```
GenerateChunkNonce(chunk_index):
    random_prefix ← CSPRNG(8 bytes)
    index_suffix ← BigEndian(chunk_index, 4 bytes)
    return random_prefix || index_suffix
```

**Nonce Layout** (12 bytes total):
```
┌────────────────────────────────────────────────────────┐
│  Bytes 0-7        │  Bytes 8-11                        │
│  Random prefix    │  Chunk index (big-endian)          │
│  (8 bytes)        │  (4 bytes)                         │
└────────────────────────────────────────────────────────┘
```

**Properties**:
- 12 bytes total (96 bits) as required by AES-GCM
- Random prefix prevents cross-file nonce collision
- Index suffix ensures uniqueness within file
- Each file uses a derived chunk key (via HKDF), not DEK directly

## 4. Decryption Process

### 4.1 Algorithm

```
DecryptFile(blob, db_record, folder_KEK, owner_public_keys):
    // Input:
    //   blob: Encrypted file content from object storage
    //   db_record: {wrapped_dek, encrypted_metadata, metadata_nonce,
    //               blob_hash, blob_size, signature}
    //   folder_KEK: Folder's Key Encryption Key
    //   owner_public_keys: Owner's public keys for signature verification

    // 1. Verify blob hash FIRST
    actual_hash ← SHA-256(blob)
    if actual_hash ≠ db_record.blob_hash:
        return Error("Blob hash mismatch - file corrupted")

    // 2. Verify signature BEFORE any decryption
    signature_payload ← Canonicalize({
        blob_hash: db_record.blob_hash,
        blob_size: db_record.blob_size,
        wrapped_dek: base64(db_record.wrapped_dek),
        encrypted_metadata: base64(db_record.encrypted_metadata),
        metadata_nonce: base64(db_record.metadata_nonce)
    })
    if not CombinedVerify(owner_public_keys, signature_payload, db_record.signature):
        return Error("Signature verification failed")

    // 3. Parse and verify blob header
    header ← ParseHeader(blob[0:64])
    if header.magic ≠ "SSEC":
        return Error("Invalid file format")
    if header.version > SUPPORTED_VERSION:
        return Error("Unsupported version")

    // 4. Unwrap DEK using folder KEK
    DEK ← AES-256-KWP.Unwrap(folder_KEK, db_record.wrapped_dek)

    // 5. Decrypt metadata (from database, not blob)
    metadata_json ← AES-256-GCM.Decrypt(
        key = DEK,
        nonce = db_record.metadata_nonce,
        ciphertext = db_record.encrypted_metadata,
        aad = "file-metadata"
    )
    metadata ← JSON.parse(metadata_json)

    // 6. Derive chunk key from DEK using HKDF
    chunk_key ← HKDF-SHA384(
        ikm = DEK,
        salt = empty,
        info = "chunk-encryption",
        length = 32
    )

    // 7. Decrypt chunks
    output ← new Buffer()
    offset ← 64  // Skip header
    for i in 0..header.total_chunks:
        // Read chunk: nonce (12) + ciphertext + tag (16)
        chunk_nonce ← blob[offset : offset + 12]
        offset += 12

        // Calculate expected plaintext size
        is_last_chunk ← (i == header.total_chunks - 1)
        plaintext_size ← is_last_chunk
            ? (header.original_size % header.chunk_size) or header.chunk_size
            : header.chunk_size
        ciphertext_size ← plaintext_size + 16  // +16 for auth tag

        chunk_ciphertext ← blob[offset : offset + ciphertext_size]
        offset += ciphertext_size

        // AAD is chunk index (4 bytes, big-endian)
        aad ← BigEndian(i, 4 bytes)

        plaintext ← AES-256-GCM.Decrypt(
            key = chunk_key,
            nonce = chunk_nonce,
            ciphertext = chunk_ciphertext,
            aad = aad
        )

        output.write(plaintext)

    // 8. Verify plaintext checksum
    if SHA-256(output) ≠ metadata.checksum:
        return Error("Checksum mismatch - file corrupted")

    // 9. Securely erase keys from memory
    DEK.zeroize()
    chunk_key.zeroize()

    return {
        content: output,
        metadata: metadata
    }
```

### 4.2 Streaming Decryption

For large files, decrypt chunk-by-chunk without loading entire file:

```
StreamDecryptFile(encrypted_file, folder_KEK, owner_public_keys):

    // Verify signature first
    if not VerifySignature(...):
        return Error(...)

    // Unwrap DEK once
    DEK ← AES-256-KWP.Unwrap(folder_KEK, header.wrapped_dek)

    // Return iterator
    return ChunkIterator {
        next():
            chunk ← ReadNextChunk()
            return AES-256-GCM.Decrypt(DEK, chunk...)
    }
```

## 5. Metadata Schema

### 5.1 Required Fields

```typescript
interface FileMetadata {
  // Core identification
  filename: string;           // Original filename (UTF-8)
  mimeType: string;           // MIME type (e.g., "application/pdf")

  // Size information
  size: number;               // Original file size in bytes

  // Timestamps (ISO 8601)
  createdAt: string;          // When file was encrypted
  modifiedAt: string;         // Original file modification time

  // Integrity
  checksum: string;           // SHA-256 of original file (hex)
}
```

### 5.2 Optional Fields

```typescript
interface ExtendedMetadata extends FileMetadata {
  // Additional attributes
  description?: string;       // User-provided description
  tags?: string[];            // User-defined tags

  // Media-specific
  width?: number;             // Image/video width
  height?: number;            // Image/video height
  duration?: number;          // Audio/video duration (seconds)

  // Document-specific
  pageCount?: number;         // PDF page count
  author?: string;            // Document author

  // Application data
  appData?: Record<string, unknown>;  // Custom application metadata
}
```

### 5.3 Metadata Size Limit

- Maximum metadata size: 64 KiB (65,536 bytes) after JSON encoding
- Reject files with larger metadata

## 6. Error Handling

### 6.1 Encryption Errors

| Error Code | Description | Recovery |
|------------|-------------|----------|
| `E_DEK_GEN_FAILED` | DEK generation failed | Retry with new entropy |
| `E_KEK_WRAP_FAILED` | KEK wrapping failed | Check KEK availability |
| `E_CHUNK_ENCRYPT_FAILED` | Chunk encryption failed | Check memory, retry |
| `E_SIGN_FAILED` | Signature generation failed | Check private key |

### 6.2 Decryption Errors

| Error Code | Description | Recovery |
|------------|-------------|----------|
| `E_INVALID_FORMAT` | Not a valid encrypted file | Check file source |
| `E_VERSION_UNSUPPORTED` | Future format version | Update client |
| `E_SIGNATURE_INVALID` | Signature verification failed | File tampered |
| `E_DEK_UNWRAP_FAILED` | Cannot unwrap DEK | Check KEK access |
| `E_CHUNK_DECRYPT_FAILED` | Chunk decryption failed | File corrupted |
| `E_CHECKSUM_MISMATCH` | Final checksum wrong | File corrupted |

## 7. Security Considerations

### 7.1 Nonce Uniqueness

**Critical**: AES-GCM security breaks completely if nonces are reused with the same key.

**Mitigations**:
1. Random 8-byte prefix per chunk ensures collision probability < 2^-64
2. Chunk index suffix ensures uniqueness within file
3. Each file has unique DEK, so cross-file collision harmless

### 7.2 Authentication Order

**Always verify signature BEFORE decryption** to prevent:
- Padding oracle attacks
- Chosen-ciphertext attacks
- Wasted computation on invalid files

### 7.3 Chunk Order Verification

The `aad` field includes chunk index, preventing:
- Chunk reordering attacks
- Chunk duplication attacks
- Chunk deletion (caught by chunk count mismatch)

### 7.4 Memory Safety

```rust
// Ensure DEK is zeroed even on panic
let dek = scopeguard::guard(generate_dek(), |mut dek| {
    dek.zeroize();
});
```

## 8. Implementation Constants

```typescript
const ENCRYPTION_CONSTANTS = {
  // Magic bytes
  MAGIC: new Uint8Array([0x53, 0x53, 0x45, 0x43]), // "SSEC"

  // Version
  CURRENT_VERSION: 1,

  // Algorithm suite
  ALGORITHM_SUITE_V1: 1,  // AES-256-GCM + HKDF-SHA384 + ML-DSA-65 + KAZ-SIGN

  // Header
  HEADER_SIZE: 64,  // Fixed header size in bytes

  // Chunk sizes
  DEFAULT_CHUNK_SIZE: 4 * 1024 * 1024,      // 4 MiB
  MIN_CHUNK_SIZE: 64 * 1024,                 // 64 KiB
  MAX_CHUNK_SIZE: 64 * 1024 * 1024,          // 64 MiB

  // Limits
  MAX_METADATA_SIZE: 64 * 1024,              // 64 KiB
  MAX_FILE_SIZE: 5 * 1024 * 1024 * 1024 * 1024, // 5 TiB

  // AES-GCM parameters
  NONCE_SIZE: 12,
  TAG_SIZE: 16,
  KEY_SIZE: 32,

  // HKDF parameters
  CHUNK_KEY_INFO: "chunk-encryption",

  // AAD
  METADATA_AAD: "file-metadata",
  // Chunk AAD is just the 4-byte big-endian chunk index
};
```

## 9. Wire Format Examples

### 9.1 Header Example (hex dump)

```
# BLOB HEADER (64 bytes, fixed)
53 53 45 43                 # Magic: "SSEC" (4 bytes)
00 01                       # Version: 1 (2 bytes)
00 01                       # Algorithm suite: 1 (2 bytes)
00 00 00 00 00 B0 00 00     # Original size: 11,534,336 bytes (8 bytes)
00 40 00 00                 # Chunk size: 4 MiB (4 bytes)
00 00 00 03                 # Total chunks: 3 (4 bytes)
00 00 00 00 00 00 00 00     # Reserved (40 bytes, all zeros)
00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00
00 00 00 00 00 00 00 00
```

### 9.2 Chunk Example (hex dump)

```
[12 bytes nonce]            # random(8) || chunk_index(4), e.g., XX XX XX XX XX XX XX XX 00 00 00 00
[variable ciphertext]       # Encrypted chunk data (same size as plaintext)
[16 bytes tag]              # AES-GCM authentication tag
```

### 9.3 Database Record Example (JSON)

```json
{
  "blob_storage_key": "tenant-abc/user-123/files/660e8400.enc",
  "blob_size": 11535424,
  "blob_hash": "a1b2c3d4e5f67890abcdef1234567890abcdef1234567890abcdef1234567890",
  "wrapped_dek": "base64-encoded-wrapped-dek...",
  "encrypted_metadata": "base64-encoded-encrypted-metadata...",
  "metadata_nonce": "base64-encoded-12-byte-nonce",
  "signature": {
    "ml_dsa": "base64-encoded-ml-dsa-signature...",
    "kaz_sign": "base64-encoded-kaz-sign-signature..."
  }
}
```

### 9.4 Signature Payload Example (Canonicalized JSON)

The signature covers this canonicalized JSON structure:

```json
{
  "blob_hash": "a1b2c3d4e5f67890abcdef1234567890abcdef1234567890abcdef1234567890",
  "blob_size": 11535424,
  "encrypted_metadata": "base64-encoded-encrypted-metadata...",
  "metadata_nonce": "base64-encoded-12-byte-nonce",
  "wrapped_dek": "base64-encoded-wrapped-dek..."
}
```

Note: Keys are sorted alphabetically for canonicalization.
