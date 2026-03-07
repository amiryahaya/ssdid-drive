package my.ssdid.drive.domain.model

/**
 * Domain model representing a tenant member.
 */
data class TenantMember(
    val id: String,
    val userId: String,
    val email: String?,
    val displayName: String?,
    val role: UserRole,
    val status: MemberStatus,
    val joinedAt: String?
)

/**
 * Member status in a tenant.
 */
enum class MemberStatus {
    ACTIVE,
    PENDING,
    SUSPENDED;

    companion object {
        fun fromString(value: String): MemberStatus {
            return when (value.lowercase()) {
                "active" -> ACTIVE
                "pending" -> PENDING
                "suspended" -> SUSPENDED
                else -> ACTIVE
            }
        }
    }
}

/**
 * Domain model representing a pending invitation for the current user.
 */
data class Invitation(
    val id: String,
    val tenantId: String,
    val tenantName: String?,
    val tenantSlug: String?,
    val role: UserRole,
    val invitedBy: Inviter?,
    val invitedAt: String?
)

/**
 * Information about who sent an invitation.
 */
data class Inviter(
    val id: String?,
    val email: String?,
    val displayName: String?
) {
    /**
     * Get display text for the inviter.
     */
    fun getDisplayText(): String {
        return displayName ?: email ?: "Unknown"
    }
}

/**
 * Result of accepting an invitation.
 */
data class InvitationAccepted(
    val id: String,
    val tenantId: String,
    val role: UserRole,
    val joinedAt: String?
)

// ==================== Token Invitation (Public - for new users) ====================

/**
 * Public invitation info retrieved by token.
 * Used for invitation-only registration flow.
 */
data class TokenInvitation(
    val id: String,
    val email: String,
    val role: UserRole,
    val tenantName: String,
    val inviterName: String?,
    val message: String?,
    val expiresAt: String,
    val valid: Boolean,
    val errorReason: TokenInvitationError?
)

/**
 * Possible error reasons for invalid invitations.
 */
enum class TokenInvitationError {
    EXPIRED,
    REVOKED,
    ALREADY_USED,
    NOT_FOUND;

    companion object {
        fun fromString(value: String?): TokenInvitationError? {
            return when (value?.lowercase()) {
                "expired" -> EXPIRED
                "revoked" -> REVOKED
                "already_used" -> ALREADY_USED
                "not_found" -> NOT_FOUND
                else -> null
            }
        }
    }
}
