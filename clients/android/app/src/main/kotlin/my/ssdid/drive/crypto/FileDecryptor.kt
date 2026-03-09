package my.ssdid.drive.crypto

import android.content.Context
import android.util.Base64
import com.google.gson.Gson
import my.ssdid.drive.domain.model.FileMetadata
import my.ssdid.drive.domain.model.PublicKeys
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.InputStream
import java.io.OutputStream
import java.security.MessageDigest
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Handles file decryption for download.
 *
 * File decryption process:
 * 1. VERIFY SIGNATURE FIRST (mandatory - fail if invalid)
 * 2. Unwrap DEK using folder's KEK
 * 3. Decrypt metadata with DEK
 * 4. Stream decrypt file content
 *
 * SECURITY: Signature verification is MANDATORY before any decryption.
 * This ensures data integrity and authenticity.
 *
 * For chunked decryption (large files):
 * - File is processed in chunks
 * - Each chunk format: [nonce:12][ciphertext][tag:16]
 */
@Singleton
class FileDecryptor @Inject constructor(
    @ApplicationContext private val context: Context,
    private val cryptoManager: CryptoManager,
    private val keyManager: KeyManager,
    private val folderKeyManager: FolderKeyManager
) {
    private val gson = Gson()

    companion object {
        // Must match FileEncryptor chunk size
        const val CHUNK_SIZE = 4 * 1024 * 1024
        // Nonce size for AES-GCM
        const val NONCE_SIZE = 12
        // Tag size for AES-GCM
        const val TAG_SIZE = 16
        // Encrypted chunk overhead: nonce + tag
        const val ENCRYPTED_CHUNK_OVERHEAD = NONCE_SIZE + TAG_SIZE
        // Max encrypted chunk size
        const val MAX_ENCRYPTED_CHUNK_SIZE = CHUNK_SIZE + ENCRYPTED_CHUNK_OVERHEAD
        private val FILE_METADATA_AAD = "file-metadata".toByteArray(Charsets.UTF_8)
    }

    /**
     * Result of file decryption operation.
     */
    data class DecryptionResult(
        val metadata: FileMetadata,
        val decryptedSize: Long
    )

    /**
     * Sealed class for decryption errors.
     */
    sealed class DecryptionError : Exception() {
        data class SignatureVerificationFailed(override val message: String) : DecryptionError()
        data class FolderKekNotAvailable(val folderId: String) : DecryptionError()
        data class MetadataDecryptionFailed(override val message: String) : DecryptionError()
        data class ContentDecryptionFailed(override val message: String) : DecryptionError()
    }

    /**
     * Verify the file's signature.
     *
     * MUST be called before any decryption. Returns true if signature is valid.
     *
     * Supports both old format (without size fields) and new format (with blobSize/chunkCount).
     * Tries new format first for better security, falls back to legacy format for compatibility.
     *
     * @param encryptedMetadata Base64-encoded encrypted metadata
     * @param blobHash Hash of the encrypted blob
     * @param wrappedDek Base64-encoded wrapped DEK
     * @param signature Base64-encoded signature
     * @param uploaderPublicKeys Public keys of the file uploader
     * @param blobSize Size of the encrypted blob (optional for backward compatibility)
     * @param chunkCount Number of chunks (optional for backward compatibility)
     * @return true if signature is valid, false otherwise
     */
    fun verifySignature(
        encryptedMetadata: String,
        blobHash: String,
        wrappedDek: String,
        signature: String,
        uploaderPublicKeys: PublicKeys,
        blobSize: Long? = null,
        chunkCount: Int? = null
    ): Boolean {
        val config = cryptoManager.cryptoConfig

        // Decode Base64
        val encryptedMetadataBytes = Base64.decode(encryptedMetadata, Base64.NO_WRAP)
        val wrappedDekBytes = Base64.decode(wrappedDek, Base64.NO_WRAP)
        val signatureBytes = Base64.decode(signature, Base64.NO_WRAP)

        // Try new format first (with blobSize and chunkCount)
        if (blobSize != null && chunkCount != null) {
            val newFormatValid = verifySignatureWithFormat(
                encryptedMetadataBytes = encryptedMetadataBytes,
                blobHash = blobHash,
                wrappedDekBytes = wrappedDekBytes,
                signatureBytes = signatureBytes,
                uploaderPublicKeys = uploaderPublicKeys,
                blobSize = blobSize,
                chunkCount = chunkCount,
                config = config
            )
            if (newFormatValid) return true
        }

        // Fall back to legacy format (for backward compatibility with old files)
        return verifySignatureWithFormat(
            encryptedMetadataBytes = encryptedMetadataBytes,
            blobHash = blobHash,
            wrappedDekBytes = wrappedDekBytes,
            signatureBytes = signatureBytes,
            uploaderPublicKeys = uploaderPublicKeys,
            blobSize = null,
            chunkCount = null,
            config = config
        )
    }

    /**
     * Internal signature verification with configurable format.
     */
    private fun verifySignatureWithFormat(
        encryptedMetadataBytes: ByteArray,
        blobHash: String,
        wrappedDekBytes: ByteArray,
        signatureBytes: ByteArray,
        uploaderPublicKeys: PublicKeys,
        blobSize: Long?,
        chunkCount: Int?,
        config: CryptoConfig
    ): Boolean {
        // Recreate message hash
        val digest = MessageDigest.getInstance("SHA-256")
        digest.update(encryptedMetadataBytes)
        digest.update(blobHash.toByteArray())
        digest.update(wrappedDekBytes)

        // Include size fields if provided (new format)
        if (blobSize != null && chunkCount != null) {
            digest.update(java.nio.ByteBuffer.allocate(8).putLong(blobSize).array())
            digest.update(java.nio.ByteBuffer.allocate(4).putInt(chunkCount).array())
        }

        val message = digest.digest()

        // Verify based on algorithm
        return try {
            when (config.getAlgorithm()) {
                PqcAlgorithm.KAZ -> {
                    cryptoManager.kazVerify(message, signatureBytes, uploaderPublicKeys.sign)
                }
                PqcAlgorithm.NIST -> {
                    val mlDsaPublicKey = uploaderPublicKeys.mlDsa
                        ?: throw IllegalStateException("ML-DSA public key required for NIST mode")
                    cryptoManager.mlDsaVerify(message, signatureBytes, mlDsaPublicKey)
                }
                PqcAlgorithm.HYBRID -> {
                    val mlDsaPublicKey = uploaderPublicKeys.mlDsa
                        ?: throw IllegalStateException("ML-DSA public key required for HYBRID mode")
                    cryptoManager.combinedVerify(message, signatureBytes, uploaderPublicKeys.sign, mlDsaPublicKey)
                }
            }
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Decrypt file metadata only.
     *
     * Useful for displaying file info without downloading content.
     *
     * @param folderId Parent folder ID (must have KEK cached)
     * @param encryptedMetadata Base64-encoded encrypted metadata
     * @param wrappedDek Base64-encoded wrapped DEK
     * @return Decrypted FileMetadata
     */
    fun decryptMetadata(
        folderId: String,
        encryptedMetadata: String,
        wrappedDek: String
    ): FileMetadata {
        // Get folder KEK
        val folderKek = folderKeyManager.getCachedKek(folderId)
            ?: throw DecryptionError.FolderKekNotAvailable(folderId)

        // Unwrap DEK
        val wrappedDekBytes = Base64.decode(wrappedDek, Base64.NO_WRAP)
        val dek = cryptoManager.unwrapKey(wrappedDekBytes, folderKek)

        try {
            // Decrypt metadata
            val encryptedMetadataBytes = Base64.decode(encryptedMetadata, Base64.NO_WRAP)
            val metadataJson = try {
                cryptoManager.decryptAesGcmWithAad(
                    ciphertext = encryptedMetadataBytes,
                    key = dek,
                    aad = FILE_METADATA_AAD
                )
            } catch (e: Exception) {
                // Backward compatibility for metadata encrypted without AAD.
                cryptoManager.decryptAesGcm(encryptedMetadataBytes, dek)
            }
            return gson.fromJson(String(metadataJson, Charsets.UTF_8), FileMetadata::class.java)
        } finally {
            // Zeroize DEK
            cryptoManager.zeroize(dek)
        }
    }

    /**
     * Decrypt a file for download.
     *
     * IMPORTANT: Signature MUST be verified before calling this method.
     * Call verifySignature() first and ensure it returns true.
     *
     * @param folderId Parent folder ID (must have KEK cached)
     * @param encryptedMetadata Base64-encoded encrypted metadata
     * @param wrappedDek Base64-encoded wrapped DEK
     * @param inputStream Stream of encrypted file content
     * @param outputStream Stream to write decrypted data
     * @param encryptedSize Total size of encrypted content
     * @param onProgress Progress callback (bytesProcessed, totalBytes)
     * @return DecryptionResult with metadata and decrypted size
     */
    suspend fun decryptFile(
        folderId: String,
        encryptedMetadata: String,
        wrappedDek: String,
        inputStream: InputStream,
        outputStream: OutputStream,
        encryptedSize: Long,
        onProgress: ((Long, Long) -> Unit)? = null
    ): DecryptionResult {
        // Get folder KEK
        val folderKek = folderKeyManager.getCachedKek(folderId)
            ?: throw DecryptionError.FolderKekNotAvailable(folderId)

        // Unwrap DEK
        val wrappedDekBytes = Base64.decode(wrappedDek, Base64.NO_WRAP)
        val dek = cryptoManager.unwrapKey(wrappedDekBytes, folderKek)

        try {
            // Decrypt metadata
            val encryptedMetadataBytes = Base64.decode(encryptedMetadata, Base64.NO_WRAP)
            val metadataJson = try {
                cryptoManager.decryptAesGcmWithAad(
                    ciphertext = encryptedMetadataBytes,
                    key = dek,
                    aad = FILE_METADATA_AAD
                )
            } catch (e: Exception) {
                // Backward compatibility for metadata encrypted without AAD.
                cryptoManager.decryptAesGcm(encryptedMetadataBytes, dek)
            }
            val metadata = gson.fromJson(String(metadataJson, Charsets.UTF_8), FileMetadata::class.java)

            // Decrypt file content
            val decryptedSize = decryptFileContent(
                inputStream = inputStream,
                outputStream = outputStream,
                dek = dek,
                totalSize = encryptedSize,
                plaintextSize = metadata.size,
                onProgress = onProgress
            )

            return DecryptionResult(
                metadata = metadata,
                decryptedSize = decryptedSize
            )
        } finally {
            // Zeroize DEK
            cryptoManager.zeroize(dek)
        }
    }

    /**
     * Decrypt file content in chunks.
     *
     * @return Total decrypted size in bytes
     */
    private fun decryptFileContent(
        inputStream: InputStream,
        outputStream: OutputStream,
        dek: ByteArray,
        totalSize: Long,
        plaintextSize: Long,
        onProgress: ((Long, Long) -> Unit)?
    ): Long {
        var totalDecryptedSize = 0L
        var bytesProcessed = 0L
        val totalChunks = if (plaintextSize == 0L) 0 else {
            ((plaintextSize + CHUNK_SIZE - 1) / CHUNK_SIZE).toInt()
        }

        for (chunkIndex in 0 until totalChunks) {
            val plaintextChunkSize = if (chunkIndex == totalChunks - 1) {
                val remainder = (plaintextSize % CHUNK_SIZE).toInt()
                if (remainder == 0) CHUNK_SIZE else remainder
            } else {
                CHUNK_SIZE
            }
            val encryptedChunkSize = plaintextChunkSize + ENCRYPTED_CHUNK_OVERHEAD
            val encryptedChunk = readExact(inputStream, encryptedChunkSize)

            // Decrypt chunk with AES-GCM
            try {
                val decryptedChunk = cryptoManager.decryptAesGcm(encryptedChunk, dek)

                // Write decrypted chunk
                outputStream.write(decryptedChunk)

                totalDecryptedSize += decryptedChunk.size
                bytesProcessed += encryptedChunk.size

                onProgress?.invoke(bytesProcessed, totalSize)
            } catch (e: Exception) {
                throw DecryptionError.ContentDecryptionFailed("Failed to decrypt chunk: ${e.message}")
            }
        }

        outputStream.flush()

        return totalDecryptedSize
    }

    /**
     * Read a complete chunk from the input stream.
     *
     * Since encrypted chunks have variable sizes (depending on plaintext size),
     * we read up to MAX_ENCRYPTED_CHUNK_SIZE bytes.
     */
    private fun readExact(inputStream: InputStream, size: Int): ByteArray {
        if (size <= 0) return ByteArray(0)

        val buffer = ByteArray(size)
        var totalRead = 0

        while (totalRead < size) {
            val bytesRead = inputStream.read(buffer, totalRead, size - totalRead)
            if (bytesRead == -1) {
                throw DecryptionError.ContentDecryptionFailed("Unexpected EOF while reading encrypted chunk")
            }
            totalRead += bytesRead
        }

        return buffer
    }

    // ==================== Stream-Based Decryption with Derived Key ====================

    /**
     * Decrypt an input stream using a folder key and file ID.
     *
     * Derives the per-file DEK from the folder key and file ID using HKDF
     * (matching the derivation in [FileEncryptor.encryptStream]), then decrypts
     * the stream content using AES-256-GCM in chunks.
     *
     * @param inputStream Stream of encrypted data
     * @param folderKey The folder's KEK (32 bytes)
     * @param fileId Unique file identifier (used for key derivation)
     * @param plaintextSize Expected plaintext size (needed to compute chunk count)
     * @param outputStream Stream to write decrypted data
     * @param onProgress Optional progress callback (bytesProcessed, totalBytes)
     * @return Total decrypted size in bytes
     */
    fun decryptStream(
        inputStream: InputStream,
        folderKey: ByteArray,
        fileId: String,
        plaintextSize: Long,
        outputStream: OutputStream,
        onProgress: ((Long, Long) -> Unit)? = null
    ): Long {
        // Derive per-file key from folder key + file ID
        val dek = cryptoManager.deriveFileKey(folderKey, fileId)

        try {
            val encryptedSize = calculateEncryptedSize(plaintextSize)
            return decryptFileContent(
                inputStream = inputStream,
                outputStream = outputStream,
                dek = dek,
                totalSize = encryptedSize,
                plaintextSize = plaintextSize,
                onProgress = onProgress
            )
        } finally {
            // SECURITY: Zeroize derived DEK
            cryptoManager.zeroize(dek)
        }
    }

    /**
     * Calculate the total encrypted size from a known plaintext size.
     *
     * Each chunk adds [ENCRYPTED_CHUNK_OVERHEAD] bytes (nonce + auth tag).
     */
    private fun calculateEncryptedSize(plaintextSize: Long): Long {
        if (plaintextSize <= 0L) return 0L
        val totalChunks = (plaintextSize + CHUNK_SIZE - 1) / CHUNK_SIZE
        return plaintextSize + totalChunks * ENCRYPTED_CHUNK_OVERHEAD
    }

    /**
     * Unwrap DEK directly (for file operations like move).
     *
     * @param folderId Folder ID
     * @param wrappedDek Base64-encoded wrapped DEK
     * @return Unwrapped DEK bytes
     */
    fun unwrapDek(folderId: String, wrappedDek: String): ByteArray {
        val folderKek = folderKeyManager.getCachedKek(folderId)
            ?: throw DecryptionError.FolderKekNotAvailable(folderId)

        val wrappedDekBytes = Base64.decode(wrappedDek, Base64.NO_WRAP)
        return cryptoManager.unwrapKey(wrappedDekBytes, folderKek)
    }

    /**
     * Decrypt metadata with a provided DEK (for re-encryption scenarios).
     */
    fun decryptMetadataWithDek(encryptedMetadata: String, dek: ByteArray): FileMetadata {
        val encrypted = Base64.decode(encryptedMetadata, Base64.NO_WRAP)
        val decrypted = try {
            cryptoManager.decryptAesGcmWithAad(
                ciphertext = encrypted,
                key = dek,
                aad = FILE_METADATA_AAD
            )
        } catch (e: Exception) {
            // Backward compatibility for metadata encrypted without AAD.
            cryptoManager.decryptAesGcm(encrypted, dek)
        }
        val json = String(decrypted, Charsets.UTF_8)
        return gson.fromJson(json, FileMetadata::class.java)
    }

    /**
     * Verify blob hash matches the content.
     *
     * @param inputStream Stream of encrypted content
     * @param expectedHash Expected SHA-256 hash as hex string
     * @return true if hash matches
     */
    suspend fun verifyBlobHash(
        inputStream: InputStream,
        expectedHash: String
    ): Boolean {
        val digest = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(8192)

        while (true) {
            val bytesRead = inputStream.read(buffer)
            if (bytesRead == -1) break
            digest.update(buffer, 0, bytesRead)
        }

        val computedHash = digest.digest().joinToString("") { "%02x".format(it) }
        return computedHash == expectedHash
    }
}
