# File Upload Flow

**Version**: 1.0.0
**Status**: Draft
**Last Updated**: 2025-01

## 1. Overview

This document describes the file upload flow for SecureSharing. File upload involves client-side encryption, metadata encryption, and secure upload to server storage.

## 2. Prerequisites

- User is logged in with decrypted keys in memory
- User has write access to target folder
- Target folder's KEK is available (owned or shared)

### Platform Notes

This document provides code examples for all supported platforms. Each section shows the implementation for:

| Platform | Crypto Library | File APIs | HTTP Client | Notes |
|----------|---------------|-----------|-------------|-------|
| **Desktop (Rust/Tauri)** | Native Rust (`ring`, `pqcrypto`) | `std::fs`, `tokio::fs` | `reqwest` | Production ready |
| **iOS (Swift)** | Rust via FFI | `FileManager`, `Data` | `URLSession` | Background uploads supported |
| **Android (Kotlin)** | Rust via JNI | `ContentResolver`, `InputStream` | `OkHttp` | WorkManager for background |

> **Note**: SecureSharing uses native clients exclusively. No web/browser client is provided.

> **API Path Convention**: Client code examples use `/api/v1/...` paths assuming the app proxies
> API requests to `https://api.securesharing.com/v1/...`. For direct API calls, remove the
> `/api/v1` prefix and use the API base URL directly.

## 3. Upload Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         FILE UPLOAD FLOW                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────┐         ┌─────────┐         ┌─────────┐         ┌─────────┐   │
│  │  User   │         │ Client  │         │ Server  │         │ Storage │   │
│  └────┬────┘         └────┬────┘         └────┬────┘         └────┬────┘   │
│       │                   │                   │                   │         │
│       │  1. Select File   │                   │                   │         │
│       │──────────────────▶│                   │                   │         │
│       │                   │                   │                   │         │
│       │                   │  ┌────────────────────────────────┐  │         │
│       │                   │  │  2. CLIENT-SIDE ENCRYPTION     │  │         │
│       │                   │  │                                │  │         │
│       │                   │  │  a. Generate random DEK        │  │         │
│       │                   │  │                                │  │         │
│       │                   │  │  b. Encrypt file in chunks     │  │         │
│       │                   │  │     (AES-256-GCM)              │  │         │
│       │                   │  │                                │  │         │
│       │                   │  │  c. Calculate blob hash        │  │         │
│       │                   │  │     (SHA-256 of ciphertext)    │  │         │
│       │                   │  │                                │  │         │
│       │                   │  │  d. Encrypt metadata           │  │         │
│       │                   │  │     (filename, size, type)     │  │         │
│       │                   │  │                                │  │         │
│       │                   │  │  e. Wrap DEK with folder KEK   │  │         │
│       │                   │  │                                │  │         │
│       │                   │  │  f. Sign the package           │  │         │
│       │                   │  │                                │  │         │
│       │                   │  └────────────────────────────────┘  │         │
│       │                   │                   │                   │         │
│       │                   │  3. Initiate Upload               │           │
│       │                   │──────────────────▶│                   │         │
│       │                   │                   │                   │         │
│       │                   │                   │  ┌─────────────┐  │         │
│       │                   │                   │  │ 4. Validate │  │         │
│       │                   │                   │  │ - Quota     │  │         │
│       │                   │                   │  │ - Folder    │  │         │
│       │                   │                   │  │ - Signature │  │         │
│       │                   │                   │  └─────────────┘  │         │
│       │                   │                   │                   │         │
│       │                   │  5. Pre-signed Upload URL         │           │
│       │                   │◀──────────────────│                   │         │
│       │                   │                   │                   │         │
│       │                   │  6. Upload encrypted blob                      │
│       │                   │──────────────────────────────────────▶│         │
│       │                   │                   │                   │         │
│       │  [Progress]       │                   │                   │         │
│       │◀─ ─ ─ ─ ─ ─ ─ ─ ─│                   │                   │         │
│       │                   │                   │                   │         │
│       │                   │  7. Upload complete (ETag)                     │
│       │                   │◀──────────────────────────────────────│         │
│       │                   │                   │                   │         │
│       │                   │  8. Confirm upload                │           │
│       │                   │──────────────────▶│                   │         │
│       │                   │                   │                   │         │
│       │                   │                   │  ┌─────────────┐  │         │
│       │                   │                   │  │ 9. Verify   │  │         │
│       │                   │                   │  │ blob exists │  │         │
│       │                   │                   │  │ + hash match│  │         │
│       │                   │                   │  └─────────────┘  │         │
│       │                   │                   │                   │         │
│       │                   │  10. File Created Response        │           │
│       │                   │◀──────────────────│                   │         │
│       │                   │                   │                   │         │
│       │  11. Success      │                   │                   │         │
│       │◀──────────────────│                   │                   │         │
│       │                   │                   │                   │         │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 4. Detailed Steps

### 4.1 Step 1: File Selection

**Web (TypeScript)**
```typescript
// User selects file via file picker or drag-and-drop
async function handleFileSelect(files: FileList): Promise<void> {
  for (const file of files) {
    await uploadFile(file, targetFolderId);
  }
}

// Drag-and-drop handler
function setupDropZone(element: HTMLElement, onFiles: (files: FileList) => void) {
  element.addEventListener('dragover', (e) => {
    e.preventDefault();
    element.classList.add('drag-over');
  });

  element.addEventListener('drop', (e) => {
    e.preventDefault();
    element.classList.remove('drag-over');
    if (e.dataTransfer?.files.length) {
      onFiles(e.dataTransfer.files);
    }
  });
}

interface FileInfo {
  name: string;
  size: number;
  type: string;
  lastModified: number;
  content: File;
}
```

**Desktop (Rust/Tauri)**
```rust
use std::path::PathBuf;
use tauri::api::dialog::FileDialogBuilder;
use tokio::fs;

pub struct FileInfo {
    pub name: String,
    pub size: u64,
    pub mime_type: String,
    pub last_modified: u64,
    pub path: PathBuf,
}

/// Open file picker dialog and return selected files
pub async fn select_files(multiple: bool) -> Result<Vec<FileInfo>, Error> {
    let (tx, rx) = tokio::sync::oneshot::channel();

    let mut builder = FileDialogBuilder::new()
        .set_title("Select files to upload");

    if multiple {
        builder = builder.pick_files(move |paths| {
            let _ = tx.send(paths);
        });
    } else {
        builder = builder.pick_file(move |path| {
            let _ = tx.send(path.map(|p| vec![p]));
        });
    }

    let paths = rx.await?.ok_or(Error::Cancelled)?;
    let mut files = Vec::new();

    for path in paths {
        let metadata = fs::metadata(&path).await?;
        let name = path.file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("unknown")
            .to_string();

        // Detect MIME type
        let mime_type = mime_guess::from_path(&path)
            .first_or_octet_stream()
            .to_string();

        files.push(FileInfo {
            name,
            size: metadata.len(),
            mime_type,
            last_modified: metadata.modified()?
                .duration_since(std::time::UNIX_EPOCH)?
                .as_secs(),
            path,
        });
    }

    Ok(files)
}

/// Read file content as bytes
pub async fn read_file_content(path: &PathBuf) -> Result<Vec<u8>, Error> {
    fs::read(path).await.map_err(Into::into)
}
```

**iOS (Swift)**
```swift
import UIKit
import UniformTypeIdentifiers

struct FileInfo {
    let name: String
    let size: Int64
    let mimeType: String
    let lastModified: Date
    let url: URL
}

class FilePicker: NSObject, UIDocumentPickerDelegate {
    private var continuation: CheckedContinuation<[FileInfo], Error>?

    func selectFiles(allowMultiple: Bool = false) async throws -> [FileInfo] {
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            DispatchQueue.main.async {
                let documentPicker = UIDocumentPickerViewController(
                    forOpeningContentTypes: [.item],
                    asCopy: true
                )
                documentPicker.allowsMultipleSelection = allowMultiple
                documentPicker.delegate = self

                UIApplication.shared.windows.first?.rootViewController?
                    .present(documentPicker, animated: true)
            }
        }
    }

    func documentPicker(
        _ controller: UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL]
    ) {
        Task {
            do {
                var files: [FileInfo] = []

                for url in urls {
                    // Start accessing security-scoped resource
                    guard url.startAccessingSecurityScopedResource() else {
                        throw FilePickerError.accessDenied
                    }
                    defer { url.stopAccessingSecurityScopedResource() }

                    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)

                    let mimeType = UTType(filenameExtension: url.pathExtension)?
                        .preferredMIMEType ?? "application/octet-stream"

                    files.append(FileInfo(
                        name: url.lastPathComponent,
                        size: attributes[.size] as? Int64 ?? 0,
                        mimeType: mimeType,
                        lastModified: attributes[.modificationDate] as? Date ?? Date(),
                        url: url
                    ))
                }

                continuation?.resume(returning: files)
            } catch {
                continuation?.resume(throwing: error)
            }
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        continuation?.resume(throwing: FilePickerError.cancelled)
    }
}

/// Read file content as Data
func readFileContent(url: URL) throws -> Data {
    return try Data(contentsOf: url)
}
```

**Android (Kotlin)**
```kotlin
import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

data class FileInfo(
    val name: String,
    val size: Long,
    val mimeType: String,
    val lastModified: Long,
    val uri: Uri
)

class FilePicker(private val activity: Activity) {
    private var pendingContinuation: CancellableContinuation<List<FileInfo>>? = null

    private val launcher: ActivityResultLauncher<Intent> =
        (activity as ComponentActivity).registerForActivityResult(
            ActivityResultContracts.StartActivityForResult()
        ) { result ->
            if (result.resultCode == Activity.RESULT_OK) {
                val files = parseSelectedFiles(result.data)
                pendingContinuation?.resume(files)
            } else {
                pendingContinuation?.resumeWithException(
                    FilePickerException("File selection cancelled")
                )
            }
            pendingContinuation = null
        }

    suspend fun selectFiles(allowMultiple: Boolean = false): List<FileInfo> =
        suspendCancellableCoroutine { continuation ->
            pendingContinuation = continuation

            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
                if (allowMultiple) {
                    putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                }
            }

            launcher.launch(intent)

            continuation.invokeOnCancellation {
                pendingContinuation = null
            }
        }

    private fun parseSelectedFiles(data: Intent?): List<FileInfo> {
        val files = mutableListOf<FileInfo>()
        val contentResolver = activity.contentResolver

        // Handle multiple selection
        val clipData = data?.clipData
        if (clipData != null) {
            for (i in 0 until clipData.itemCount) {
                val uri = clipData.getItemAt(i).uri
                getFileInfo(uri)?.let { files.add(it) }
            }
        } else {
            // Single selection
            data?.data?.let { uri ->
                getFileInfo(uri)?.let { files.add(it) }
            }
        }

        return files
    }

    private fun getFileInfo(uri: Uri): FileInfo? {
        val contentResolver = activity.contentResolver

        return contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            if (!cursor.moveToFirst()) return null

            val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)

            val name = if (nameIndex >= 0) cursor.getString(nameIndex) else "unknown"
            val size = if (sizeIndex >= 0) cursor.getLong(sizeIndex) else 0L
            val mimeType = contentResolver.getType(uri) ?: "application/octet-stream"

            FileInfo(
                name = name,
                size = size,
                mimeType = mimeType,
                lastModified = System.currentTimeMillis(),
                uri = uri
            )
        }
    }
}

/// Read file content as ByteArray
fun readFileContent(activity: Activity, uri: Uri): ByteArray {
    return activity.contentResolver.openInputStream(uri)?.use { stream ->
        stream.readBytes()
    } ?: throw FilePickerException("Cannot read file")
}
```

### 4.2 Step 2: Client-Side Encryption

**Web (TypeScript)**
```typescript
async function encryptFile(
  file: File,
  folderKek: Uint8Array,
  userSignKeys: SignKeyPairs
): Promise<EncryptedFilePackage> {

  // 2a. Generate random DEK
  const dek = crypto.getRandomValues(new Uint8Array(32));

  // 2b. Encrypt file in chunks
  const { encryptedBlob, blobHash } = await encryptFileContent(file, dek);

  // 2c. Hash is calculated during encryption (above)

  // 2d. Encrypt metadata
  const metadata: FileMetadata = {
    filename: file.name,
    mimeType: file.type || 'application/octet-stream',
    size: file.size,
    modifiedAt: new Date(file.lastModified).toISOString(),
    createdAt: new Date().toISOString(),
    checksum: await calculateSha256(file)  // SHA-256 of plaintext for verification
  };

  const metadataNonce = crypto.getRandomValues(new Uint8Array(12));
  const metadataAad = new TextEncoder().encode('file-metadata');
  const encryptedMetadata = await aesGcmEncrypt(
    dek,
    metadataNonce,
    new TextEncoder().encode(JSON.stringify(metadata)),
    metadataAad  // AAD per docs/crypto/03-encryption-protocol.md Section 2.2
  );

  // 2e. Wrap DEK with folder KEK
  // AES-256-KWP (Key Wrap with Padding) is deterministic - no nonce needed
  // See docs/crypto/03-encryption-protocol.md Section 3.1
  const wrappedDek = await aesKeyWrap(folderKek, dek);

  // 2f. Sign the package
  const signaturePayload = canonicalize({
    blob_hash: blobHash,
    blob_size: encryptedBlob.size,
    wrapped_dek: base64Encode(wrappedDek),
    encrypted_metadata: base64Encode(encryptedMetadata),
    metadata_nonce: base64Encode(metadataNonce)
  });

  const signature = await combinedSign(userSignKeys, signaturePayload);

  // Clear DEK from memory
  dek.fill(0);

  return {
    encryptedBlob,
    blobHash,
    encryptedMetadata: base64Encode(encryptedMetadata),
    metadataNonce: base64Encode(metadataNonce),
    wrappedDek: base64Encode(wrappedDek),
    signature
  };
}
```

**Desktop (Rust/Tauri)**
```rust
use aes_gcm::{Aes256Gcm, KeyInit, Nonce};
use aes_gcm::aead::Aead;
use hkdf::Hkdf;
use rand::{RngCore, rngs::OsRng};
use sha2::{Sha256, Sha384, Digest};
use pqcrypto_mldsa::mldsa65;
use kaz_crypto::kaz_sign;
use zeroize::Zeroize;

pub struct EncryptedFilePackage {
    pub encrypted_blob: Vec<u8>,
    pub blob_hash: String,
    pub encrypted_metadata: Vec<u8>,
    pub metadata_nonce: Vec<u8>,
    pub wrapped_dek: Vec<u8>,
    pub signature: CombinedSignature,
}

pub async fn encrypt_file(
    file_path: &PathBuf,
    folder_kek: &[u8],
    sign_keys: &SignKeyPairs,
    progress_callback: Option<Box<dyn Fn(EncryptProgress) + Send>>,
) -> Result<EncryptedFilePackage, CryptoError> {
    // 2a. Generate random DEK (256-bit)
    let mut dek = [0u8; 32];
    OsRng.fill_bytes(&mut dek);

    // 2b. Encrypt file in chunks
    let (encrypted_blob, blob_hash, plaintext_hash) =
        encrypt_file_content(file_path, &dek, progress_callback).await?;

    // 2d. Encrypt metadata
    let metadata = fs::metadata(file_path).await?;
    let file_name = file_path.file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("unknown");

    let mime_type = mime_guess::from_path(file_path)
        .first_or_octet_stream()
        .to_string();

    let metadata_json = serde_json::json!({
        "filename": file_name,
        "mimeType": mime_type,
        "size": metadata.len(),
        "modifiedAt": metadata.modified()?
            .duration_since(std::time::UNIX_EPOCH)?
            .as_secs(),
        "createdAt": std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)?
            .as_secs(),
        "checksum": plaintext_hash
    });

    let metadata_bytes = serde_json::to_vec(&metadata_json)?;

    let mut metadata_nonce = [0u8; 12];
    OsRng.fill_bytes(&mut metadata_nonce);

    let cipher = Aes256Gcm::new_from_slice(&dek)
        .map_err(|_| CryptoError::CipherInitFailed)?;
    let metadata_aad = b"file-metadata";  // AAD per encryption protocol Section 2.2
    let encrypted_metadata = cipher
        .encrypt(
            Nonce::from_slice(&metadata_nonce),
            Payload { msg: &metadata_bytes, aad: metadata_aad }
        )
        .map_err(|_| CryptoError::EncryptionFailed)?;

    // 2e. Wrap DEK with folder KEK using AES-256-KWP
    let wrapped_dek = aes_kw::wrap(folder_kek, &dek)
        .map_err(|_| CryptoError::KeyWrapFailed)?;

    // 2f. Sign the package
    let signature_payload = canonicalize_json(&serde_json::json!({
        "blob_hash": blob_hash,
        "blob_size": encrypted_blob.len(),
        "wrapped_dek": base64::encode(&wrapped_dek),
        "encrypted_metadata": base64::encode(&encrypted_metadata),
        "metadata_nonce": base64::encode(&metadata_nonce)
    }))?;

    let signature = combined_sign(sign_keys, &signature_payload)?;

    // Clear DEK from memory
    dek.zeroize();

    Ok(EncryptedFilePackage {
        encrypted_blob,
        blob_hash,
        encrypted_metadata,
        metadata_nonce: metadata_nonce.to_vec(),
        wrapped_dek,
        signature,
    })
}

fn combined_sign(
    sign_keys: &SignKeyPairs,
    message: &[u8],
) -> Result<CombinedSignature, CryptoError> {
    // Sign with ML-DSA-65
    let ml_dsa_sig = mldsa65::detached_sign(message, &sign_keys.ml_dsa_private);

    // Sign with KAZ-SIGN
    let kaz_sign_sig = kaz_sign::sign(message, &sign_keys.kaz_sign_private);

    Ok(CombinedSignature {
        ml_dsa: ml_dsa_sig.as_bytes().to_vec(),
        kaz_sign: kaz_sign_sig.as_bytes().to_vec(),
    })
}
```

**iOS (Swift)**
```swift
import Foundation
import CryptoKit
import SecureSharingCrypto  // Rust FFI wrapper

struct EncryptedFilePackage {
    let encryptedBlob: Data
    let blobHash: String
    let encryptedMetadata: Data
    let metadataNonce: Data
    let wrappedDek: Data
    let signature: CombinedSignature
}

func encryptFile(
    fileURL: URL,
    folderKek: Data,
    signKeys: SignKeyPairs,
    progressCallback: ((EncryptProgress) -> Void)? = nil
) throws -> EncryptedFilePackage {
    // 2a. Generate random DEK (256-bit)
    var dek = SymmetricKey(size: .bits256)

    // 2b. Encrypt file in chunks
    let dekData = dek.withUnsafeBytes { Data($0) }
    let (encryptedBlob, blobHash, plaintextHash) = try encryptFileContent(
        fileURL: fileURL,
        dek: dekData,
        progressCallback: progressCallback
    )

    // 2d. Encrypt metadata
    let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
    let mimeType = UTType(filenameExtension: fileURL.pathExtension)?
        .preferredMIMEType ?? "application/octet-stream"

    let metadata: [String: Any] = [
        "filename": fileURL.lastPathComponent,
        "mimeType": mimeType,
        "size": attributes[.size] as? Int64 ?? 0,
        "modifiedAt": ISO8601DateFormatter().string(from: attributes[.modificationDate] as? Date ?? Date()),
        "createdAt": ISO8601DateFormatter().string(from: Date()),
        "checksum": plaintextHash
    ]

    let metadataData = try JSONSerialization.data(withJSONObject: metadata)
    let metadataNonce = AES.GCM.Nonce()

    let metadataAad = "file-metadata".data(using: .utf8)!  // AAD per encryption protocol Section 2.2
    let sealedMetadata = try AES.GCM.seal(
        metadataData,
        using: dek,
        nonce: metadataNonce,
        authenticating: metadataAad
    )
    let encryptedMetadata = sealedMetadata.ciphertext + sealedMetadata.tag

    // 2e. Wrap DEK with folder KEK using AES-256-KWP
    let wrappedDek = SecureSharingCrypto.aesKeyWrap(key: folderKek, data: dekData)

    // 2f. Sign the package
    let signaturePayload = canonicalizeJSON([
        "blob_hash": blobHash,
        "blob_size": encryptedBlob.count,
        "wrapped_dek": wrappedDek.base64EncodedString(),
        "encrypted_metadata": encryptedMetadata.base64EncodedString(),
        "metadata_nonce": Data(metadataNonce).base64EncodedString()
    ])

    let signature = try combinedSign(signKeys: signKeys, message: signaturePayload)

    return EncryptedFilePackage(
        encryptedBlob: encryptedBlob,
        blobHash: blobHash,
        encryptedMetadata: encryptedMetadata,
        metadataNonce: Data(metadataNonce),
        wrappedDek: wrappedDek,
        signature: signature
    )
}

private func combinedSign(signKeys: SignKeyPairs, message: Data) throws -> CombinedSignature {
    // Sign with ML-DSA-65 (via Rust FFI)
    let mlDsaSig = SecureSharingCrypto.mlDsa65Sign(
        privateKey: signKeys.mlDsaPrivate,
        message: message
    )

    // Sign with KAZ-SIGN (via Rust FFI)
    let kazSignSig = SecureSharingCrypto.kazSignSign(
        privateKey: signKeys.kazSignPrivate,
        message: message
    )

    return CombinedSignature(
        mlDsa: mlDsaSig,
        kazSign: kazSignSig
    )
}
```

**Android (Kotlin)**
```kotlin
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec
import com.securesharing.crypto.NativeCrypto
import org.json.JSONObject

data class EncryptedFilePackage(
    val encryptedBlob: ByteArray,
    val blobHash: String,
    val encryptedMetadata: ByteArray,
    val metadataNonce: ByteArray,
    val wrappedDek: ByteArray,
    val signature: CombinedSignature
)

class FileEncryptor(
    private val context: Context,
    private val nativeCrypto: NativeCrypto
) {
    private val secureRandom = SecureRandom()

    fun encryptFile(
        fileUri: Uri,
        folderKek: ByteArray,
        signKeys: SignKeyPairs,
        progressCallback: ((EncryptProgress) -> Unit)? = null
    ): EncryptedFilePackage {
        // 2a. Generate random DEK (256-bit)
        val dek = ByteArray(32)
        secureRandom.nextBytes(dek)

        // 2b. Encrypt file in chunks
        val (encryptedBlob, blobHash, plaintextHash) = encryptFileContent(
            context,
            fileUri,
            dek,
            progressCallback
        )

        // 2d. Encrypt metadata
        val contentResolver = context.contentResolver
        val cursor = contentResolver.query(fileUri, null, null, null, null)
        val fileName = cursor?.use {
            if (it.moveToFirst()) {
                val nameIndex = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (nameIndex >= 0) it.getString(nameIndex) else "unknown"
            } else "unknown"
        } ?: "unknown"

        val fileSize = cursor?.use {
            if (it.moveToFirst()) {
                val sizeIndex = it.getColumnIndex(OpenableColumns.SIZE)
                if (sizeIndex >= 0) it.getLong(sizeIndex) else 0L
            } else 0L
        } ?: 0L

        val mimeType = contentResolver.getType(fileUri) ?: "application/octet-stream"

        val metadata = JSONObject().apply {
            put("filename", fileName)
            put("mimeType", mimeType)
            put("size", fileSize)
            put("modifiedAt", System.currentTimeMillis())
            put("createdAt", System.currentTimeMillis())
            put("checksum", plaintextHash)
        }

        val metadataBytes = metadata.toString().toByteArray(Charsets.UTF_8)
        val metadataNonce = ByteArray(12).also { secureRandom.nextBytes(it) }
        val metadataAad = "file-metadata".toByteArray(Charsets.UTF_8)  // AAD per encryption protocol Section 2.2

        val encryptedMetadata = encryptAesGcm(dek, metadataNonce, metadataBytes, metadataAad)

        // 2e. Wrap DEK with folder KEK using AES-256-KWP
        val wrappedDek = nativeCrypto.aesKeyWrap(folderKek, dek)

        // 2f. Sign the package
        val signaturePayload = canonicalizeJson(JSONObject().apply {
            put("blob_hash", blobHash)
            put("blob_size", encryptedBlob.size)
            put("wrapped_dek", Base64.encodeToString(wrappedDek, Base64.NO_WRAP))
            put("encrypted_metadata", Base64.encodeToString(encryptedMetadata, Base64.NO_WRAP))
            put("metadata_nonce", Base64.encodeToString(metadataNonce, Base64.NO_WRAP))
        })

        val signature = combinedSign(signKeys, signaturePayload)

        // Clear DEK from memory
        dek.fill(0)

        return EncryptedFilePackage(
            encryptedBlob = encryptedBlob,
            blobHash = blobHash,
            encryptedMetadata = encryptedMetadata,
            metadataNonce = metadataNonce,
            wrappedDek = wrappedDek,
            signature = signature
        )
    }

    private fun encryptAesGcm(key: ByteArray, nonce: ByteArray, plaintext: ByteArray): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        val keySpec = SecretKeySpec(key, "AES")
        val gcmSpec = GCMParameterSpec(128, nonce)

        cipher.init(Cipher.ENCRYPT_MODE, keySpec, gcmSpec)
        return cipher.doFinal(plaintext)
    }

    private fun combinedSign(signKeys: SignKeyPairs, message: ByteArray): CombinedSignature {
        // Sign with ML-DSA-65 (via Rust JNI)
        val mlDsaSig = nativeCrypto.mlDsa65Sign(signKeys.mlDsaPrivate, message)

        // Sign with KAZ-SIGN (via Rust JNI)
        val kazSignSig = nativeCrypto.kazSignSign(signKeys.kazSignPrivate, message)

        return CombinedSignature(
            mlDsa = mlDsaSig,
            kazSign = kazSignSig
        )
    }
}
```

### 4.3 Chunked Encryption Implementation

```typescript
const CHUNK_SIZE = 4 * 1024 * 1024;  // 4MB chunks
const HEADER_SIZE = 64;               // Fixed header size

async function encryptFileContent(
  file: File,
  dek: Uint8Array
): Promise<{ encryptedBlob: Blob; blobHash: string }> {

  const chunks: Uint8Array[] = [];
  let offset = 0;
  let chunkIndex = 0;

  // Derive chunk key from DEK using HKDF
  // See docs/crypto/03-encryption-protocol.md for specification
  const chunkKey = await hkdfDerive(dek, "chunk-encryption", 32);

  while (offset < file.size) {
    const chunkEnd = Math.min(offset + CHUNK_SIZE, file.size);
    const chunk = file.slice(offset, chunkEnd);
    const plaintext = new Uint8Array(await chunk.arrayBuffer());

    // Generate unique nonce for each chunk
    // Format: 8 bytes random prefix + 4 bytes chunk index (big-endian)
    // See docs/crypto/03-encryption-protocol.md Section 3.3
    const nonce = new Uint8Array(12);
    crypto.getRandomValues(nonce.subarray(0, 8));  // Random prefix
    new DataView(nonce.buffer).setUint32(8, chunkIndex, false);  // Chunk index suffix

    // Encrypt chunk with AAD = chunk index (4 bytes, big-endian)
    const aad = new Uint8Array(4);
    new DataView(aad.buffer).setUint32(0, chunkIndex, false);

    const encryptedChunk = await aesGcmEncryptWithAad(
      chunkKey,
      nonce,
      plaintext,
      aad
    );

    // Build chunk structure: nonce (12) + ciphertext + tag (16)
    const chunkData = new Uint8Array(12 + encryptedChunk.length);
    chunkData.set(nonce, 0);
    chunkData.set(encryptedChunk, 12);

    chunks.push(chunkData);
    offset = chunkEnd;
    chunkIndex++;

    // Report progress
    onProgress?.({
      phase: 'encrypting',
      loaded: offset,
      total: file.size
    });
  }

  // Build final blob with header (64 bytes fixed)
  const header = buildFileHeader(file.size, chunks.length, CHUNK_SIZE);
  const encryptedBlob = new Blob([header, ...chunks], {
    type: 'application/octet-stream'
  });

  // Calculate hash of entire encrypted blob
  const blobHash = await calculateBlobHash(encryptedBlob);

  // Clear chunk key from memory
  chunkKey.fill(0);

  return { encryptedBlob, blobHash };
}

function buildFileHeader(
  originalSize: number,
  chunkCount: number,
  chunkSize: number
): Uint8Array {
  // SSEC file format header (64 bytes, fixed)
  // See docs/crypto/03-encryption-protocol.md Section 2.4 for specification
  const header = new Uint8Array(64);
  const view = new DataView(header.buffer);

  // Offset 0: Magic bytes "SSEC" (4 bytes)
  header.set([0x53, 0x53, 0x45, 0x43], 0);

  // Offset 4: Version (2 bytes, big-endian)
  view.setUint16(4, 1, false);

  // Offset 6: Algorithm suite (2 bytes, big-endian)
  // 0x0001 = AES-256-GCM + HKDF-SHA384 + ML-DSA-65 + KAZ-SIGN
  view.setUint16(6, 1, false);

  // Offset 8: Original file size (8 bytes, big-endian)
  view.setBigUint64(8, BigInt(originalSize), false);

  // Offset 16: Chunk size (4 bytes, big-endian)
  view.setUint32(16, chunkSize, false);

  // Offset 20: Total chunks (4 bytes, big-endian)
  view.setUint32(20, chunkCount, false);

  // Offset 24-63: Reserved (40 bytes, zero-filled)
  // Already zero-filled by Uint8Array initialization

  return header;
}

async function calculateBlobHash(blob: Blob): Promise<string> {
  const buffer = await blob.arrayBuffer();
  const hash = await crypto.subtle.digest('SHA-256', buffer);
  return Array.from(new Uint8Array(hash))
    .map(b => b.toString(16).padStart(2, '0'))
    .join('');
}
```

### 4.4 Step 3-5: Initiate Upload

```typescript
async function initiateUpload(
  folderId: string,
  encryptedPackage: EncryptedFilePackage,
  sessionToken: string
): Promise<UploadSession> {

  const response = await fetch('/api/v1/files', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${sessionToken}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      folder_id: folderId,
      encrypted_metadata: encryptedPackage.encryptedMetadata,
      metadata_nonce: encryptedPackage.metadataNonce,
      wrapped_dek: encryptedPackage.wrappedDek,
      blob_size: encryptedPackage.encryptedBlob.size,
      blob_hash: encryptedPackage.blobHash,
      signature: encryptedPackage.signature
    })
  });

  if (!response.ok) {
    const error = await response.json();
    throw new UploadError(error.error.code, error.error.message);
  }

  const { data } = await response.json();

  return {
    fileId: data.file.id,
    uploadUrl: data.upload.url,
    uploadHeaders: data.upload.headers,
    expiresAt: new Date(data.upload.expires_at)
  };
}
```

### 4.5 Step 6-7: Upload Blob to Storage

```typescript
async function uploadBlob(
  blob: Blob,
  uploadUrl: string,
  headers: Record<string, string>,
  onProgress?: (progress: UploadProgress) => void
): Promise<string> {

  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();

    xhr.upload.addEventListener('progress', (event) => {
      if (event.lengthComputable) {
        onProgress?.({
          phase: 'uploading',
          loaded: event.loaded,
          total: event.total
        });
      }
    });

    xhr.addEventListener('load', () => {
      if (xhr.status >= 200 && xhr.status < 300) {
        const etag = xhr.getResponseHeader('ETag');
        resolve(etag || '');
      } else {
        reject(new Error(`Upload failed: ${xhr.status}`));
      }
    });

    xhr.addEventListener('error', () => {
      reject(new Error('Upload failed: network error'));
    });

    xhr.open('PUT', uploadUrl);

    // Set required headers
    for (const [key, value] of Object.entries(headers)) {
      xhr.setRequestHeader(key, value);
    }

    xhr.send(blob);
  });
}
```

### 4.6 Step 8-10: Confirm Upload

```typescript
async function confirmUpload(
  fileId: string,
  sessionToken: string
): Promise<FileRecord> {

  const response = await fetch(`/api/v1/files/${fileId}/confirm`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${sessionToken}`
    }
  });

  if (!response.ok) {
    const error = await response.json();
    throw new UploadError(error.error.code, error.error.message);
  }

  const { data } = await response.json();

  return {
    id: data.file.id,
    status: data.file.status,
    verified: data.file.blob_verified
  };
}
```

## 5. Complete Upload Implementation

```typescript
async function uploadFile(
  file: File,
  folderId: string,
  options?: UploadOptions
): Promise<FileRecord> {

  const { onProgress, signal } = options || {};

  try {
    // Get folder KEK
    const folderKek = await getFolderKek(folderId);

    // Get user signing keys
    const signKeys = keyManager.getKeys().privateKeys;

    // Encrypt file
    onProgress?.({ phase: 'encrypting', loaded: 0, total: file.size });

    const encryptedPackage = await encryptFile(file, folderKek, {
      ml_dsa: signKeys.ml_dsa,
      kaz_sign: signKeys.kaz_sign
    });

    // Check for cancellation
    if (signal?.aborted) {
      throw new Error('Upload cancelled');
    }

    // Initiate upload
    onProgress?.({ phase: 'initiating', loaded: 0, total: 1 });

    const uploadSession = await initiateUpload(
      folderId,
      encryptedPackage,
      sessionManager.getSession()
    );

    // Upload blob
    await uploadBlob(
      encryptedPackage.encryptedBlob,
      uploadSession.uploadUrl,
      uploadSession.uploadHeaders,
      onProgress
    );

    // Confirm upload
    onProgress?.({ phase: 'confirming', loaded: 1, total: 1 });

    const fileRecord = await confirmUpload(
      uploadSession.fileId,
      sessionManager.getSession()
    );

    onProgress?.({ phase: 'complete', loaded: 1, total: 1 });

    return fileRecord;

  } catch (error) {
    onProgress?.({ phase: 'error', error: error.message });
    throw error;
  }
}
```

## 6. Large File Upload (Multipart)

For files > 100MB, use multipart upload.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     MULTIPART UPLOAD FLOW                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────┐         ┌─────────┐         ┌─────────┐         ┌─────────┐   │
│  │ Client  │         │ Server  │         │ Storage │                        │
│  └────┬────┘         └────┬────┘         └────┬────┘                        │
│       │                   │                   │                              │
│       │  1. Initiate Multipart               │                              │
│       │──────────────────▶│                   │                              │
│       │                   │                   │                              │
│       │  2. Upload ID + Part URLs            │                              │
│       │◀──────────────────│                   │                              │
│       │                   │                   │                              │
│       │  3. Upload Part 1 ────────────────────────────────────▶│            │
│       │  4. Upload Part 2 ────────────────────────────────────▶│ (parallel)│
│       │  5. Upload Part 3 ────────────────────────────────────▶│            │
│       │                   │                   │                              │
│       │  6. Complete Multipart               │                              │
│       │──────────────────▶│                   │                              │
│       │                   │                   │                              │
│       │                   │  7. Assemble parts│                              │
│       │                   │──────────────────▶│                              │
│       │                   │                   │                              │
│       │  8. File Created  │                   │                              │
│       │◀──────────────────│                   │                              │
│       │                   │                   │                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Multipart Implementation

```typescript
const MULTIPART_THRESHOLD = 100 * 1024 * 1024;  // 100MB
const MULTIPART_PART_SIZE = 100 * 1024 * 1024;  // 100MB per part
const MAX_CONCURRENT_PARTS = 4;

async function uploadLargeFile(
  file: File,
  folderId: string,
  options?: UploadOptions
): Promise<FileRecord> {

  const { onProgress } = options || {};

  // Encrypt entire file first
  const folderKek = await getFolderKek(folderId);
  const signKeys = keyManager.getKeys().privateKeys;

  const encryptedPackage = await encryptFile(file, folderKek, {
    ml_dsa: signKeys.ml_dsa,
    kaz_sign: signKeys.kaz_sign
  });

  const encryptedBlob = encryptedPackage.encryptedBlob;
  const totalParts = Math.ceil(encryptedBlob.size / MULTIPART_PART_SIZE);

  // Initiate multipart upload
  const multipartSession = await initiateMultipartUpload(
    folderId,
    encryptedPackage,
    totalParts
  );

  // Upload parts in parallel with concurrency limit
  const partResults: PartResult[] = [];
  const uploadQueue: Promise<PartResult>[] = [];

  for (let i = 0; i < totalParts; i++) {
    const start = i * MULTIPART_PART_SIZE;
    const end = Math.min(start + MULTIPART_PART_SIZE, encryptedBlob.size);
    const partBlob = encryptedBlob.slice(start, end);
    const partUrl = multipartSession.parts[i].upload_url;

    const uploadPromise = uploadPart(partBlob, partUrl, i + 1)
      .then(etag => ({ partNumber: i + 1, etag }));

    uploadQueue.push(uploadPromise);

    // Limit concurrency
    if (uploadQueue.length >= MAX_CONCURRENT_PARTS) {
      const completed = await Promise.race(uploadQueue);
      partResults.push(completed);
      uploadQueue.splice(uploadQueue.indexOf(completed), 1);
    }

    // Report progress
    onProgress?.({
      phase: 'uploading',
      loaded: partResults.length * MULTIPART_PART_SIZE,
      total: encryptedBlob.size
    });
  }

  // Wait for remaining parts
  const remaining = await Promise.all(uploadQueue);
  partResults.push(...remaining);

  // Complete multipart upload
  return await completeMultipartUpload(
    multipartSession.fileId,
    multipartSession.uploadId,
    partResults.sort((a, b) => a.partNumber - b.partNumber),
    encryptedPackage.blobHash
  );
}

async function uploadPart(
  blob: Blob,
  url: string,
  partNumber: number
): Promise<string> {
  const response = await fetch(url, {
    method: 'PUT',
    body: blob,
    headers: {
      'Content-Type': 'application/octet-stream'
    }
  });

  if (!response.ok) {
    throw new Error(`Part ${partNumber} upload failed`);
  }

  return response.headers.get('ETag') || '';
}
```

## 7. Resume Interrupted Upload

```typescript
interface UploadCheckpoint {
  fileId: string;
  uploadId: string;
  completedParts: PartResult[];
  encryptedBlobHash: string;
  expiresAt: Date;
}

async function resumeUpload(
  checkpoint: UploadCheckpoint,
  encryptedBlob: Blob,
  onProgress?: ProgressCallback
): Promise<FileRecord> {

  // Verify checkpoint is still valid
  if (new Date() > checkpoint.expiresAt) {
    throw new Error('Upload session expired, please restart');
  }

  // Get list of completed parts from server
  const status = await getMultipartStatus(
    checkpoint.fileId,
    checkpoint.uploadId
  );

  // Identify remaining parts
  const completedPartNumbers = new Set(
    status.completedParts.map(p => p.partNumber)
  );

  const totalParts = Math.ceil(encryptedBlob.size / MULTIPART_PART_SIZE);
  const remainingParts: number[] = [];

  for (let i = 1; i <= totalParts; i++) {
    if (!completedPartNumbers.has(i)) {
      remainingParts.push(i);
    }
  }

  // Get new URLs for remaining parts
  const newUrls = await getPartUploadUrls(
    checkpoint.fileId,
    checkpoint.uploadId,
    remainingParts
  );

  // Upload remaining parts
  const partResults = [...status.completedParts];

  for (const partNumber of remainingParts) {
    const start = (partNumber - 1) * MULTIPART_PART_SIZE;
    const end = Math.min(start + MULTIPART_PART_SIZE, encryptedBlob.size);
    const partBlob = encryptedBlob.slice(start, end);

    const etag = await uploadPart(
      partBlob,
      newUrls[partNumber],
      partNumber
    );

    partResults.push({ partNumber, etag });

    onProgress?.({
      phase: 'uploading',
      loaded: partResults.length * MULTIPART_PART_SIZE,
      total: encryptedBlob.size
    });
  }

  // Complete upload
  return await completeMultipartUpload(
    checkpoint.fileId,
    checkpoint.uploadId,
    partResults.sort((a, b) => a.partNumber - b.partNumber),
    checkpoint.encryptedBlobHash
  );
}
```

## 8. Error Handling

| Error Code | Cause | Recovery |
|------------|-------|----------|
| `E_QUOTA_EXCEEDED` | Storage quota full | Delete files or upgrade |
| `E_FILE_TOO_LARGE` | File exceeds size limit | Reduce file size |
| `E_FOLDER_NOT_FOUND` | Target folder invalid | Verify folder exists |
| `E_PERMISSION_DENIED` | No write access | Request access |
| `E_UPLOAD_EXPIRED` | Pre-signed URL expired | Re-initiate upload |
| `E_HASH_MISMATCH` | Blob corrupted | Re-upload |
| `E_SIGNATURE_INVALID` | Signature verification failed | Re-sign and retry |

### Retry Strategy

```typescript
async function uploadWithRetry(
  file: File,
  folderId: string,
  maxRetries: number = 3
): Promise<FileRecord> {

  let lastError: Error;

  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      return await uploadFile(file, folderId);
    } catch (error) {
      lastError = error;

      // Don't retry certain errors
      if (isNonRetryableError(error)) {
        throw error;
      }

      // Wait before retry (exponential backoff)
      const delay = Math.min(1000 * Math.pow(2, attempt), 30000);
      await sleep(delay);
    }
  }

  throw lastError;
}

function isNonRetryableError(error: Error): boolean {
  const nonRetryableCodes = [
    'E_QUOTA_EXCEEDED',
    'E_FILE_TOO_LARGE',
    'E_PERMISSION_DENIED',
    'E_FOLDER_NOT_FOUND'
  ];

  return nonRetryableCodes.includes(error.code);
}
```

## 9. Security Considerations

### 9.1 Key Handling

- DEK is generated fresh for each file
- DEK is cleared from memory after wrapping
- Folder KEK is only held in memory during upload

### 9.2 Integrity

- Blob hash ensures upload wasn't corrupted
- Signature prevents tampering with metadata
- Server verifies blob existence before confirmation

### 9.3 Privacy

- Filename encrypted in metadata
- File type encrypted in metadata
- Server only sees encrypted blob and size

## 10. Progress Reporting

```typescript
interface UploadProgress {
  phase: 'encrypting' | 'initiating' | 'uploading' | 'confirming' | 'complete' | 'error';
  loaded?: number;
  total?: number;
  error?: string;
}

// Usage
uploadFile(file, folderId, {
  onProgress: (progress) => {
    switch (progress.phase) {
      case 'encrypting':
        console.log(`Encrypting: ${progress.loaded}/${progress.total}`);
        break;
      case 'uploading':
        const percent = (progress.loaded / progress.total * 100).toFixed(1);
        console.log(`Uploading: ${percent}%`);
        break;
      case 'complete':
        console.log('Upload complete!');
        break;
      case 'error':
        console.error(`Upload failed: ${progress.error}`);
        break;
    }
  }
});
```
