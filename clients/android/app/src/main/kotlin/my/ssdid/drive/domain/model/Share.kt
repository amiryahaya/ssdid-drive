package my.ssdid.drive.domain.model

import java.time.Instant

/**
 * Domain model representing a share grant.
 */
data class Share(
    val id: String,
    val grantorId: String,
    val granteeId: String,
    val resourceType: ResourceType,
    val resourceId: String,
    val permission: SharePermission,
    val recursive: Boolean,
    val expiresAt: Instant?,
    val revokedAt: Instant?,
    val grantor: User?,
    val grantee: User?,
    val createdAt: Instant,
    val updatedAt: Instant
) {
    /**
     * Check if this share is still valid (not expired or revoked).
     */
    fun isValid(): Boolean {
        if (revokedAt != null) return false
        if (expiresAt != null && Instant.now().isAfter(expiresAt)) return false
        return true
    }

    /**
     * Check if this share was created by the given user.
     */
    fun isGrantedBy(userId: String): Boolean = grantorId == userId

    /**
     * Check if this share was received by the given user.
     */
    fun isGrantedTo(userId: String): Boolean = granteeId == userId
}

enum class ResourceType {
    FILE,
    FOLDER;

    companion object {
        fun fromString(value: String): ResourceType {
            return when (value.lowercase()) {
                "file" -> FILE
                "folder" -> FOLDER
                else -> FILE
            }
        }
    }

    override fun toString(): String {
        return name.lowercase()
    }
}

enum class SharePermission {
    READ,
    WRITE,
    ADMIN;

    companion object {
        fun fromString(value: String): SharePermission {
            return when (value.lowercase()) {
                "read" -> READ
                "write" -> WRITE
                "admin" -> ADMIN
                else -> READ
            }
        }
    }

    override fun toString(): String {
        return name.lowercase()
    }

    fun displayName(): String {
        return when (this) {
            READ -> "Read Only"
            WRITE -> "Read & Write"
            ADMIN -> "Admin"
        }
    }
}
