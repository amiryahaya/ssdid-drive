package my.ssdid.drive.domain.model

/**
 * Domain model representing a user with multi-tenant support.
 */
data class User(
    val id: String,
    val email: String,
    val displayName: String? = null,
    val status: String? = null,
    val recoverySetupComplete: Boolean? = null,
    // Multi-tenant fields
    val tenants: List<Tenant>? = null,
    val currentTenantId: String? = null,
    // Legacy single-tenant fields (for backwards compatibility)
    val tenantId: String? = null,
    val role: UserRole? = null,
    // Crypto fields
    val publicKeys: PublicKeys? = null,
    // Usage fields
    val storageQuota: Long? = null,
    val storageUsed: Long? = null
) {
    /**
     * Get the effective tenant ID (current or legacy).
     */
    fun getEffectiveTenantId(): String? = currentTenantId ?: tenantId

    /**
     * Get the effective role for the current tenant.
     */
    fun getEffectiveRole(): UserRole {
        return if (currentTenantId != null && tenants != null) {
            tenants.find { it.id == currentTenantId }?.role ?: UserRole.USER
        } else {
            role ?: UserRole.USER
        }
    }

    /**
     * Check if user belongs to multiple tenants.
     */
    fun isMultiTenant(): Boolean = (tenants?.size ?: 0) > 1

    /**
     * Get the current tenant.
     */
    fun getCurrentTenant(): Tenant? {
        val effectiveTenantId = getEffectiveTenantId() ?: return null
        return tenants?.find { it.id == effectiveTenantId }
    }
}

enum class UserRole {
    USER,
    ADMIN,
    OWNER;

    companion object {
        fun fromString(value: String): UserRole {
            return when (value.lowercase()) {
                "admin" -> ADMIN
                "owner" -> OWNER
                else -> USER
            }
        }
    }
}

/**
 * Public keys for a user (for sharing/verification).
 */
data class PublicKeys(
    val kem: ByteArray,      // KAZ-KEM public key
    val sign: ByteArray,     // KAZ-SIGN public key
    val mlKem: ByteArray?,   // ML-KEM-768 public key
    val mlDsa: ByteArray?    // ML-DSA-65 public key
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (javaClass != other?.javaClass) return false
        other as PublicKeys
        return kem.contentEquals(other.kem) &&
               sign.contentEquals(other.sign) &&
               mlKem?.contentEquals(other.mlKem ?: byteArrayOf()) == true &&
               mlDsa?.contentEquals(other.mlDsa ?: byteArrayOf()) == true
    }

    override fun hashCode(): Int {
        var result = kem.contentHashCode()
        result = 31 * result + sign.contentHashCode()
        return result
    }
}
