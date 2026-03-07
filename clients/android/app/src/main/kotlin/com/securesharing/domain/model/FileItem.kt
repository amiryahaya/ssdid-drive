package com.securesharing.domain.model

import java.time.Instant

/**
 * Domain model representing a file.
 */
data class FileItem(
    val id: String,
    val folderId: String,
    val ownerId: String,
    val tenantId: String,
    val name: String,              // Decrypted name
    val mimeType: String,          // Decrypted MIME type
    val size: Long,                // File size in bytes
    val status: FileStatus,
    val createdAt: Instant,
    val updatedAt: Instant
) {
    /**
     * Check if this file is owned by the given user.
     */
    fun isOwnedBy(userId: String): Boolean = ownerId == userId

    /**
     * Get a human-readable file size.
     */
    fun formattedSize(): String {
        return when {
            size < 1024 -> "$size B"
            size < 1024 * 1024 -> "${size / 1024} KB"
            size < 1024 * 1024 * 1024 -> "${size / (1024 * 1024)} MB"
            else -> "${size / (1024 * 1024 * 1024)} GB"
        }
    }

    /**
     * Check if this is an image file.
     */
    fun isImage(): Boolean = mimeType.startsWith("image/")

    /**
     * Check if this is a PDF file.
     */
    fun isPdf(): Boolean = mimeType == "application/pdf"

    /**
     * Check if this is a video file.
     */
    fun isVideo(): Boolean = mimeType.startsWith("video/")

    /**
     * Check if this is an audio file.
     */
    fun isAudio(): Boolean = mimeType.startsWith("audio/")

    /**
     * Check if this is a text file (includes code files).
     */
    fun isText(): Boolean = mimeType.startsWith("text/") ||
        mimeType in listOf(
            "application/json",
            "application/xml",
            "application/javascript",
            "application/x-sh",
            "application/x-python",
            "application/x-ruby",
            "application/x-perl",
            "application/x-yaml",
            "application/toml",
            "application/x-httpd-php"
        )
}

enum class FileStatus {
    PENDING,      // Upload not started
    UPLOADING,    // Upload in progress
    COMPLETE,     // Upload complete
    FAILED;       // Upload failed

    companion object {
        fun fromString(value: String): FileStatus {
            return when (value.lowercase()) {
                "pending" -> PENDING
                "uploading" -> UPLOADING
                "complete" -> COMPLETE
                "failed" -> FAILED
                else -> PENDING
            }
        }
    }
}

/**
 * Encrypted file data as received from the server.
 */
data class EncryptedFile(
    val id: String,
    val folderId: String,
    val ownerId: String,
    val tenantId: String,
    val storagePath: String?,
    val blobSize: Long?,
    val blobHash: String?,
    val chunkCount: Int?,
    val status: FileStatus,
    val encryptedMetadata: ByteArray,
    val wrappedDek: ByteArray,
    val kemCiphertext: ByteArray,
    val signature: ByteArray,
    val createdAt: Instant,
    val updatedAt: Instant
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (javaClass != other?.javaClass) return false
        other as EncryptedFile
        return id == other.id
    }

    override fun hashCode(): Int = id.hashCode()
}

/**
 * File metadata (encrypted client-side).
 */
data class FileMetadata(
    val name: String,
    val mimeType: String,
    val size: Long,
    val originalPath: String? = null
)
