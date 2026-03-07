package com.securesharing.domain.repository

import com.securesharing.domain.model.RecoveryApproval
import com.securesharing.domain.model.RecoveryConfig
import com.securesharing.domain.model.RecoveryRequest
import com.securesharing.domain.model.RecoveryShare
import com.securesharing.domain.model.User
import com.securesharing.util.Result

/**
 * Repository interface for recovery operations.
 *
 * Recovery flow:
 * 1. Setup: User configures recovery with k-of-n threshold
 * 2. Distribution: User selects trustees and distributes encrypted shares
 * 3. Request: User initiates recovery with new keys
 * 4. Approval: Trustees approve by re-encrypting shares for new keys
 * 5. Complete: User reconstructs master key and updates credentials
 */
interface RecoveryRepository {

    // ==================== Configuration ====================

    /**
     * Get the current user's recovery configuration.
     */
    suspend fun getRecoveryConfig(): Result<RecoveryConfig?>

    /**
     * Set up recovery with Shamir secret sharing.
     *
     * @param threshold Minimum shares required (k)
     * @param totalShares Total shares to create (n)
     * @return The created recovery config
     */
    suspend fun setupRecovery(
        threshold: Int,
        totalShares: Int
    ): Result<RecoveryConfig>

    /**
     * Disable recovery (revokes all shares).
     */
    suspend fun disableRecovery(): Result<Unit>

    // ==================== Share Management ====================

    /**
     * Create and distribute a recovery share to a trustee.
     *
     * The share is encrypted for the trustee using their public keys.
     *
     * @param trustee The user to receive the share
     * @param shareIndex The share index (1-indexed)
     * @return The created share
     */
    suspend fun createShare(
        trustee: User,
        shareIndex: Int
    ): Result<RecoveryShare>

    /**
     * Get all shares created by the current user.
     */
    suspend fun getCreatedShares(): Result<List<RecoveryShare>>

    /**
     * Get all shares where the current user is a trustee.
     */
    suspend fun getTrusteeShares(): Result<List<RecoveryShare>>

    /**
     * Accept a recovery share as a trustee.
     */
    suspend fun acceptShare(shareId: String): Result<RecoveryShare>

    /**
     * Reject a recovery share as a trustee.
     */
    suspend fun rejectShare(shareId: String): Result<Unit>

    /**
     * Revoke a share (as the grantor).
     */
    suspend fun revokeShare(shareId: String): Result<Unit>

    // ==================== Recovery Requests ====================

    /**
     * Initiate a recovery request.
     *
     * This generates new key pairs and submits a recovery request.
     * Trustees will be notified to approve.
     *
     * @param password New password for the recovered account
     * @param reason Optional reason for recovery
     * @return The created recovery request
     */
    suspend fun initiateRecovery(
        password: String,
        reason: String? = null
    ): Result<RecoveryRequest>

    /**
     * Get the current user's active recovery requests.
     */
    suspend fun getMyRecoveryRequests(): Result<List<RecoveryRequest>>

    /**
     * Get pending recovery requests where the current user is a trustee.
     */
    suspend fun getPendingApprovalRequests(): Result<List<RecoveryRequest>>

    /**
     * Get details of a recovery request including progress.
     */
    suspend fun getRecoveryRequest(requestId: String): Result<RecoveryRequest>

    /**
     * Approve a recovery request as a trustee.
     *
     * This decrypts the user's share and re-encrypts it for the
     * recovering user's new public keys.
     *
     * @param requestId The recovery request ID
     * @param shareId The trustee's share ID
     * @return The approval record
     */
    suspend fun approveRecoveryRequest(
        requestId: String,
        shareId: String
    ): Result<RecoveryApproval>

    /**
     * Complete a recovery request.
     *
     * Called after threshold approvals have been collected.
     * This reconstructs the master key and updates the user's credentials.
     *
     * @param requestId The recovery request ID
     * @param password The new password
     * @return Success if recovery completed
     */
    suspend fun completeRecovery(
        requestId: String,
        password: String
    ): Result<Unit>

    /**
     * Cancel a pending recovery request.
     */
    suspend fun cancelRecoveryRequest(requestId: String): Result<Unit>
}
