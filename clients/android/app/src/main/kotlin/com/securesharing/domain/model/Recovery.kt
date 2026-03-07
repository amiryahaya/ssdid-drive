package com.securesharing.domain.model

import java.time.Instant

/**
 * Recovery configuration for a user's account.
 *
 * Defines the Shamir secret sharing parameters:
 * - threshold: Minimum shares required to recover
 * - totalShares: Total shares distributed to trustees
 */
data class RecoveryConfig(
    val id: String,
    val userId: String,
    val threshold: Int,
    val totalShares: Int,
    val status: RecoveryConfigStatus,
    val createdAt: Instant,
    val updatedAt: Instant
) {
    /**
     * Check if recovery is fully configured (all shares distributed).
     */
    fun isConfigured(): Boolean = status == RecoveryConfigStatus.ACTIVE

    /**
     * Check if more shares can be added.
     */
    fun canAddShares(): Boolean = status == RecoveryConfigStatus.PENDING
}

enum class RecoveryConfigStatus {
    PENDING,    // Shares not yet distributed
    ACTIVE,     // All shares distributed, recovery available
    DISABLED;   // Recovery disabled

    companion object {
        fun fromString(value: String): RecoveryConfigStatus {
            return when (value.lowercase()) {
                "pending" -> PENDING
                "active" -> ACTIVE
                "disabled" -> DISABLED
                else -> PENDING
            }
        }
    }
}

/**
 * A recovery share held by a trustee.
 *
 * The share is encrypted for the trustee and can only be decrypted
 * by them to approve a recovery request.
 */
data class RecoveryShare(
    val id: String,
    val configId: String,
    val grantorId: String,
    val trusteeId: String,
    val shareIndex: Int,
    val status: RecoveryShareStatus,
    val grantor: User?,
    val trustee: User?,
    val createdAt: Instant,
    val updatedAt: Instant
) {
    /**
     * Check if this share can be used for recovery.
     */
    fun isActive(): Boolean = status == RecoveryShareStatus.ACCEPTED
}

enum class RecoveryShareStatus {
    PENDING,    // Trustee hasn't accepted yet
    ACCEPTED,   // Trustee accepted, share is active
    REJECTED,   // Trustee rejected
    REVOKED;    // Owner revoked

    companion object {
        fun fromString(value: String): RecoveryShareStatus {
            return when (value.lowercase()) {
                "pending" -> PENDING
                "accepted" -> ACCEPTED
                "rejected" -> REJECTED
                "revoked" -> REVOKED
                else -> PENDING
            }
        }
    }
}

/**
 * A recovery request initiated when a user needs to recover their account.
 *
 * The request goes through a flow:
 * 1. User initiates with new public keys
 * 2. Trustees approve and submit re-encrypted shares
 * 3. Once threshold met, user can complete recovery
 */
data class RecoveryRequest(
    val id: String,
    val userId: String,
    val status: RecoveryRequestStatus,
    val reason: String?,
    val user: User?,
    val progress: RecoveryProgress?,
    val createdAt: Instant,
    val updatedAt: Instant
) {
    /**
     * Check if this request is waiting for approvals.
     */
    fun isPending(): Boolean = status == RecoveryRequestStatus.PENDING

    /**
     * Check if this request has enough approvals to complete.
     */
    fun canComplete(): Boolean = status == RecoveryRequestStatus.APPROVED

    /**
     * Check if this request has been completed.
     */
    fun isCompleted(): Boolean = status == RecoveryRequestStatus.COMPLETED
}

enum class RecoveryRequestStatus {
    PENDING,    // Waiting for trustee approvals
    APPROVED,   // Threshold met, ready to complete
    COMPLETED,  // Recovery completed
    REJECTED,   // Request rejected/expired
    CANCELLED;  // User cancelled

    companion object {
        fun fromString(value: String): RecoveryRequestStatus {
            return when (value.lowercase()) {
                "pending" -> PENDING
                "approved" -> APPROVED
                "completed" -> COMPLETED
                "rejected" -> REJECTED
                "cancelled" -> CANCELLED
                else -> PENDING
            }
        }
    }
}

/**
 * Progress tracking for a recovery request.
 */
data class RecoveryProgress(
    val threshold: Int,
    val approvals: Int,
    val remaining: Int
) {
    /**
     * Check if threshold has been met.
     */
    fun thresholdMet(): Boolean = approvals >= threshold

    /**
     * Get completion percentage.
     */
    fun percentage(): Float = if (threshold > 0) {
        (approvals.toFloat() / threshold * 100).coerceAtMost(100f)
    } else {
        0f
    }
}

/**
 * An approval for a recovery request from a trustee.
 */
data class RecoveryApproval(
    val id: String,
    val requestId: String,
    val shareId: String,
    val approverId: String,
    val createdAt: Instant
)
