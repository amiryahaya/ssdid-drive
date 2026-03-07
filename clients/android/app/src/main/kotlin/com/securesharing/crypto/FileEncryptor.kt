package com.securesharing.crypto

import android.content.Context
import android.net.Uri
import android.util.Base64
import com.google.gson.Gson
import com.securesharing.domain.model.FileMetadata
import com.securesharing.util.BufferPool
import com.securesharing.util.SentryConfig
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.InputStream
import java.io.OutputStream
import java.security.MessageDigest
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Handles file encryption for upload.
 *
 * File encryption process:
 * 1. Generate DEK (Data Encryption Key) - 32 bytes random
 * 2. Encrypt file content with DEK using AES-256-GCM
 * 3. Encrypt metadata (filename, mimeType, size) with DEK
 * 4. Wrap DEK with folder's KEK
 * 5. Sign the package (metadata hash + content hash)
 *
 * For chunked encryption (large files):
 * - File is split into chunks (default 4MB)
 * - Each chunk has its own nonce
 * - Chunk format: [nonce:12][ciphertext][tag:16]
 *
 * Performance optimizations:
 * - Uses BufferPool to reuse buffers across encryption operations
 * - Streaming encryption to minimize memory usage
 */
@Singleton
class FileEncryptor @Inject constructor(
    @ApplicationContext private val context: Context,
    private val cryptoManager: CryptoManager,
    private val keyManager: KeyManager,
    private val folderKeyManager: FolderKeyManager,
    private val bufferPool: BufferPool
) {
    private val gson = Gson()

    companion object {
        // 4MB chunk size for large files
        const val CHUNK_SIZE = 4 * 1024 * 1024
        // Nonce size for AES-GCM
        const val NONCE_SIZE = 12
        // Tag size for AES-GCM
        const val TAG_SIZE = 16
        private val FILE_METADATA_AAD = "file-metadata".toByteArray(Charsets.UTF_8)
    }

    /**
     * Result of file encryption operation.
     *
     * SECURITY: Call [zeroize] when done with this result to clear the DEK from memory.
     * The DEK is included for cases where it needs to be re-wrapped (e.g., file move).
     */
    data class EncryptionResult(
        val dek: ByteArray,
        val wrappedDek: String,
        val encryptedMetadata: String,
        val signature: String,
        val blobSize: Long,
        val blobHash: String,
        val chunkCount: Int
    ) {
        /**
         * Securely zeroize the DEK in this result.
         * Call this when done using the result.
         */
        fun zeroize() {
            SecureMemory.zeroize(dek)
        }
    }

    /**
     * Encrypt a file for upload.
     *
     * SECURITY: The returned EncryptionResult contains the DEK. Caller MUST call
     * [EncryptionResult.zeroize] when done with the result to clear sensitive data.
     *
     * @param uri Source file URI
     * @param fileName Original filename
     * @param mimeType File MIME type
     * @param folderId Parent folder ID (must have KEK cached)
     * @param outputStream Stream to write encrypted data
     * @param onProgress Progress callback (bytesProcessed, totalBytes)
     * @return EncryptionResult with all required metadata
     */
    suspend fun encryptFile(
        uri: Uri,
        fileName: String,
        mimeType: String,
        folderId: String,
        outputStream: OutputStream,
        onProgress: ((Long, Long) -> Unit)? = null
    ): EncryptionResult {
        SentryConfig.addFileBreadcrumb(
            message = "Starting file encryption",
            operation = "encrypt",
            fileType = mimeType
        )

        // Get folder KEK
        val folderKek = folderKeyManager.getCachedKek(folderId)
            ?: throw IllegalStateException("Folder KEK not available for $folderId")

        // Generate DEK
        val dek = cryptoManager.generateKey()

        // Use try-finally to ensure DEK is zeroized on error
        var success = false
        try {
            // Get file size
            val fileSize = getFileSize(uri)

            // Create metadata
            val metadata = FileMetadata(
                name = fileName,
                mimeType = mimeType,
                size = fileSize
            )

            // Encrypt metadata with DEK
            val metadataJson = gson.toJson(metadata)
            val encryptedMetadataBytes = cryptoManager.encryptAesGcmWithAad(
                plaintext = metadataJson.toByteArray(),
                key = dek,
                aad = FILE_METADATA_AAD
            )
            val encryptedMetadata = Base64.encodeToString(encryptedMetadataBytes, Base64.NO_WRAP)

            // Wrap DEK with folder KEK
            val wrappedDekBytes = cryptoManager.wrapKey(dek, folderKek)
            val wrappedDek = Base64.encodeToString(wrappedDekBytes, Base64.NO_WRAP)

            // Encrypt file content using use{} for proper resource management
            val (blobSize, blobHash, chunkCount) = context.contentResolver.openInputStream(uri)?.use { inputStream ->
                encryptFileContent(
                    inputStream = inputStream,
                    outputStream = outputStream,
                    dek = dek,
                    totalSize = fileSize,
                    onProgress = onProgress
                )
            } ?: throw IllegalStateException("Cannot open file")

            // Create signature (includes blobSize and chunkCount for integrity)
            val signature = createSignature(
                encryptedMetadata = encryptedMetadataBytes,
                blobHash = blobHash,
                wrappedDek = wrappedDekBytes,
                blobSize = blobSize,
                chunkCount = chunkCount
            )

            success = true

            SentryConfig.addFileBreadcrumb(
                message = "File encryption completed",
                operation = "encrypt",
                fileType = mimeType,
                sizeBytes = blobSize
            )

            return EncryptionResult(
                dek = dek,
                wrappedDek = wrappedDek,
                encryptedMetadata = encryptedMetadata,
                signature = Base64.encodeToString(signature, Base64.NO_WRAP),
                blobSize = blobSize,
                blobHash = blobHash,
                chunkCount = chunkCount
            )
        } finally {
            // SECURITY: If encryption failed, zeroize DEK immediately
            // On success, caller is responsible for calling EncryptionResult.zeroize()
            if (!success) {
                SecureMemory.zeroize(dek)
                SentryConfig.addFileBreadcrumb(
                    message = "File encryption failed",
                    operation = "encrypt",
                    fileType = mimeType
                )
            }
        }
    }

    /**
     * Encrypt file content in chunks.
     *
     * Uses BufferPool to reuse buffers across encryption operations,
     * reducing garbage collection pressure for large files.
     *
     * @return Triple of (encrypted size, hash of ciphertext, chunk count)
     */
    private fun encryptFileContent(
        inputStream: InputStream,
        outputStream: OutputStream,
        dek: ByteArray,
        totalSize: Long,
        onProgress: ((Long, Long) -> Unit)?
    ): Triple<Long, String, Int> {
        // Use pooled buffer for reduced GC pressure
        val buffer = bufferPool.acquire(CHUNK_SIZE)
        try {
            val digest = MessageDigest.getInstance("SHA-256")
            var totalEncryptedSize = 0L
            var bytesProcessed = 0L
            var chunkCount = 0

            while (true) {
                val bytesRead = inputStream.read(buffer)
                if (bytesRead == -1) break

                // Get the actual chunk data
                val chunkData = if (bytesRead < buffer.size) {
                    buffer.copyOf(bytesRead)
                } else {
                    buffer
                }

                // Encrypt chunk with AES-GCM
                val encryptedChunk = cryptoManager.encryptAesGcm(chunkData, dek)

                // Write encrypted chunk
                outputStream.write(encryptedChunk)
                digest.update(encryptedChunk)

                totalEncryptedSize += encryptedChunk.size
                bytesProcessed += bytesRead
                chunkCount++

                onProgress?.invoke(bytesProcessed, totalSize)
            }

            outputStream.flush()

            val hashBytes = digest.digest()
            val blobHash = hashBytes.joinToString("") { "%02x".format(it) }

            return Triple(totalEncryptedSize, blobHash, chunkCount)
        } finally {
            // Return buffer to pool
            bufferPool.release(buffer)
        }
    }

    /**
     * Create signature over the encrypted package.
     *
     * Signs: SHA-256(encryptedMetadata || blobHash || wrappedDek || blobSize || chunkCount)
     *
     * SECURITY: Including blobSize and chunkCount prevents metadata tampering where
     * an attacker could modify size fields without invalidating the signature.
     */
    private fun createSignature(
        encryptedMetadata: ByteArray,
        blobHash: String,
        wrappedDek: ByteArray,
        blobSize: Long = 0,
        chunkCount: Int = 0
    ): ByteArray {
        val keys = keyManager.getUnlockedKeys()
        val config = cryptoManager.cryptoConfig

        // Create message to sign - include all integrity-critical fields
        val digest = MessageDigest.getInstance("SHA-256")
        digest.update(encryptedMetadata)
        digest.update(blobHash.toByteArray())
        digest.update(wrappedDek)
        // SECURITY: Include size metadata to prevent tampering
        digest.update(java.nio.ByteBuffer.allocate(8).putLong(blobSize).array())
        digest.update(java.nio.ByteBuffer.allocate(4).putInt(chunkCount).array())
        val message = digest.digest()

        // Sign based on tenant algorithm
        return when (config.getAlgorithm()) {
            PqcAlgorithm.KAZ -> {
                cryptoManager.kazSign(message, keys.kazSignPrivateKey)
            }
            PqcAlgorithm.NIST -> {
                cryptoManager.mlDsaSign(message, keys.mlDsaPrivateKey)
            }
            PqcAlgorithm.HYBRID -> {
                cryptoManager.combinedSign(message, keys.kazSignPrivateKey, keys.mlDsaPrivateKey)
            }
        }
    }

    /**
     * Encrypt metadata only (for re-encryption during move).
     */
    fun encryptMetadataWithDek(metadata: FileMetadata, dek: ByteArray): String {
        val json = gson.toJson(metadata)
        val encrypted = cryptoManager.encryptAesGcmWithAad(
            plaintext = json.toByteArray(),
            key = dek,
            aad = FILE_METADATA_AAD
        )
        return Base64.encodeToString(encrypted, Base64.NO_WRAP)
    }

    /**
     * Re-wrap DEK with a new folder's KEK (for move operation).
     */
    fun rewrapDek(dek: ByteArray, newFolderKek: ByteArray): String {
        val wrapped = cryptoManager.wrapKey(dek, newFolderKek)
        return Base64.encodeToString(wrapped, Base64.NO_WRAP)
    }

    /**
     * Result of metadata update operation.
     */
    data class MetadataUpdateResult(
        val encryptedMetadata: String,
        val signature: String
    )

    /**
     * Update file metadata (e.g., for rename operation).
     * Unwraps the DEK, encrypts new metadata, and creates a new signature.
     *
     * @param folderId Folder ID to get KEK for unwrapping DEK
     * @param wrappedDek The wrapped DEK (Base64 encoded)
     * @param newName New file name
     * @param mimeType File MIME type
     * @param size File size
     * @return MetadataUpdateResult with new encrypted metadata and signature
     */
    suspend fun updateMetadata(
        folderId: String,
        wrappedDek: String,
        newName: String,
        mimeType: String,
        size: Long,
        blobHash: String,
        blobSize: Long,
        chunkCount: Int
    ): MetadataUpdateResult {
        // Get folder KEK
        val folderKek = folderKeyManager.getCachedKek(folderId)
            ?: throw IllegalStateException("Folder KEK not available for $folderId")

        // Unwrap DEK
        val wrappedDekBytes = Base64.decode(wrappedDek, Base64.NO_WRAP)
        val dek = cryptoManager.unwrapKey(wrappedDekBytes, folderKek)

        try {
            // Create new metadata
            val metadata = FileMetadata(
                name = newName,
                mimeType = mimeType,
                size = size
            )

            // Encrypt metadata with DEK
            val metadataJson = gson.toJson(metadata)
            val encryptedMetadataBytes = cryptoManager.encryptAesGcmWithAad(
                plaintext = metadataJson.toByteArray(),
                key = dek,
                aad = FILE_METADATA_AAD
            )
            val encryptedMetadata = Base64.encodeToString(encryptedMetadataBytes, Base64.NO_WRAP)

            // Create new signature (metadata update only, blob hash unchanged)
            val signature = createSignature(
                encryptedMetadata = encryptedMetadataBytes,
                blobHash = blobHash,
                wrappedDek = wrappedDekBytes,
                blobSize = blobSize,
                chunkCount = chunkCount
            )

            return MetadataUpdateResult(
                encryptedMetadata = encryptedMetadata,
                signature = Base64.encodeToString(signature, Base64.NO_WRAP)
            )
        } finally {
            // SECURITY: Zeroize DEK
            SecureMemory.zeroize(dek)
        }
    }

    /**
     * Sign an existing file package when wrapped DEK changes (e.g., move).
     */
    fun signFilePackage(
        encryptedMetadata: String,
        blobHash: String,
        wrappedDek: String,
        blobSize: Long,
        chunkCount: Int
    ): String {
        val encryptedMetadataBytes = Base64.decode(encryptedMetadata, Base64.NO_WRAP)
        val wrappedDekBytes = Base64.decode(wrappedDek, Base64.NO_WRAP)
        val signature = createSignature(
            encryptedMetadata = encryptedMetadataBytes,
            blobHash = blobHash,
            wrappedDek = wrappedDekBytes,
            blobSize = blobSize,
            chunkCount = chunkCount
        )
        return Base64.encodeToString(signature, Base64.NO_WRAP)
    }

    /**
     * Encrypt a file from an InputStream (for files already on disk).
     *
     * SECURITY: The returned EncryptionResult contains the DEK. Caller MUST call
     * [EncryptionResult.zeroize] when done with the result to clear sensitive data.
     *
     * @param inputStream Source input stream
     * @param fileName Original filename
     * @param mimeType File MIME type
     * @param fileSize Size of the file
     * @param folderId Parent folder ID (must have KEK cached)
     * @param outputStream Stream to write encrypted data
     * @param onProgress Progress callback (bytesProcessed, totalBytes)
     * @return EncryptionResult with all required metadata
     */
    suspend fun encryptFileFromStream(
        inputStream: InputStream,
        fileName: String,
        mimeType: String,
        fileSize: Long,
        folderId: String,
        outputStream: OutputStream,
        onProgress: ((Long, Long) -> Unit)? = null
    ): EncryptionResult {
        SentryConfig.addFileBreadcrumb(
            message = "Starting file encryption from stream",
            operation = "encrypt",
            fileType = mimeType,
            sizeBytes = fileSize
        )

        // Get folder KEK
        val folderKek = folderKeyManager.getCachedKek(folderId)
            ?: throw IllegalStateException("Folder KEK not available for $folderId")

        // Generate DEK
        val dek = cryptoManager.generateKey()

        var success = false
        try {
            // Create metadata
            val metadata = FileMetadata(
                name = fileName,
                mimeType = mimeType,
                size = fileSize
            )

            // Encrypt metadata with DEK
            val metadataJson = gson.toJson(metadata)
            val encryptedMetadataBytes = cryptoManager.encryptAesGcmWithAad(
                plaintext = metadataJson.toByteArray(),
                key = dek,
                aad = FILE_METADATA_AAD
            )
            val encryptedMetadata = Base64.encodeToString(encryptedMetadataBytes, Base64.NO_WRAP)

            // Wrap DEK with folder KEK
            val wrappedDekBytes = cryptoManager.wrapKey(dek, folderKek)
            val wrappedDek = Base64.encodeToString(wrappedDekBytes, Base64.NO_WRAP)

            // Encrypt file content
            val (blobSize, blobHash, chunkCount) = encryptFileContent(
                inputStream = inputStream,
                outputStream = outputStream,
                dek = dek,
                totalSize = fileSize,
                onProgress = onProgress
            )

            // Create signature (includes blobSize and chunkCount for integrity)
            val signature = createSignature(
                encryptedMetadata = encryptedMetadataBytes,
                blobHash = blobHash,
                wrappedDek = wrappedDekBytes,
                blobSize = blobSize,
                chunkCount = chunkCount
            )

            success = true

            SentryConfig.addFileBreadcrumb(
                message = "File encryption from stream completed",
                operation = "encrypt",
                fileType = mimeType,
                sizeBytes = blobSize
            )

            return EncryptionResult(
                dek = dek,
                wrappedDek = wrappedDek,
                encryptedMetadata = encryptedMetadata,
                signature = Base64.encodeToString(signature, Base64.NO_WRAP),
                blobSize = blobSize,
                blobHash = blobHash,
                chunkCount = chunkCount
            )
        } finally {
            if (!success) {
                SecureMemory.zeroize(dek)
                SentryConfig.addFileBreadcrumb(
                    message = "File encryption from stream failed",
                    operation = "encrypt",
                    fileType = mimeType
                )
            }
        }
    }

    private fun getFileSize(uri: Uri): Long {
        val resolver = context.contentResolver
        val descriptorSize = resolver.openAssetFileDescriptor(uri, "r")?.use { it.length }

        if (descriptorSize != null && descriptorSize >= 0) {
            return descriptorSize
        }

        return resolver.openInputStream(uri)?.use { it.available().toLong() }
            ?: throw IllegalStateException("Cannot read file size")
    }
}
