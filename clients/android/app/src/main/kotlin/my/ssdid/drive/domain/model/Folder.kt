package my.ssdid.drive.domain.model

import java.time.Instant

/**
 * Domain model representing a folder.
 */
data class Folder(
    val id: String,
    val parentId: String?,
    val ownerId: String,
    val tenantId: String,
    val isRoot: Boolean,
    val name: String,         // Decrypted name
    val createdAt: Instant,
    val updatedAt: Instant
) {
    /**
     * Check if this folder is owned by the given user.
     */
    fun isOwnedBy(userId: String): Boolean = ownerId == userId
}

/**
 * Encrypted folder data as received from the server.
 */
data class EncryptedFolder(
    val id: String,
    val parentId: String?,
    val ownerId: String,
    val tenantId: String,
    val isRoot: Boolean,
    val encryptedMetadata: ByteArray,
    val wrappedKek: ByteArray,
    val kemCiphertext: ByteArray,
    val signature: ByteArray,
    val createdAt: Instant,
    val updatedAt: Instant
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (javaClass != other?.javaClass) return false
        other as EncryptedFolder
        return id == other.id
    }

    override fun hashCode(): Int = id.hashCode()
}

/**
 * Folder metadata (encrypted client-side).
 */
data class FolderMetadata(
    val name: String,
    val color: String? = null,
    val icon: String? = null
)
