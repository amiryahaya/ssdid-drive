package my.ssdid.drive.domain.repository

import my.ssdid.drive.domain.model.Share
import my.ssdid.drive.domain.model.SharePermission
import my.ssdid.drive.domain.model.User
import my.ssdid.drive.util.Result
import kotlinx.coroutines.flow.Flow
import java.time.Instant

/**
 * Repository interface for share operations.
 */
interface ShareRepository {

    /**
     * Get shares received by the current user.
     */
    suspend fun getReceivedShares(): Result<List<Share>>

    /**
     * Observe shares received by the current user.
     */
    fun observeReceivedShares(): Flow<List<Share>>

    /**
     * Get shares created by the current user.
     */
    suspend fun getCreatedShares(): Result<List<Share>>

    /**
     * Observe shares created by the current user.
     */
    fun observeCreatedShares(): Flow<List<Share>>

    /**
     * Get a share by ID.
     */
    suspend fun getShare(shareId: String): Result<Share>

    /**
     * Share a file with another user.
     */
    suspend fun shareFile(
        fileId: String,
        grantee: User,
        permission: SharePermission,
        expiresAt: Instant? = null
    ): Result<Share>

    /**
     * Share a file with another user by ID (for background sync).
     */
    suspend fun shareFile(
        fileId: String,
        recipientId: String,
        permission: String
    ): Result<Share>

    /**
     * Share a folder with another user.
     */
    suspend fun shareFolder(
        folderId: String,
        grantee: User,
        permission: SharePermission,
        recursive: Boolean = true,
        expiresAt: Instant? = null
    ): Result<Share>

    /**
     * Share a folder with another user by ID (for background sync).
     */
    suspend fun shareFolder(
        folderId: String,
        recipientId: String,
        permission: String
    ): Result<Share>

    /**
     * Update a share's permission level.
     */
    suspend fun updatePermission(
        shareId: String,
        permission: SharePermission
    ): Result<Share>

    /**
     * Update a share's permission level by permission string (for background sync).
     */
    suspend fun updatePermission(
        shareId: String,
        permission: String
    ): Result<Share>

    /**
     * Set or remove a share's expiry.
     */
    suspend fun setExpiry(
        shareId: String,
        expiresAt: Instant?
    ): Result<Share>

    /**
     * Revoke a share.
     */
    suspend fun revokeShare(shareId: String): Result<Unit>

    /**
     * Search for users to share with.
     */
    suspend fun searchUsers(query: String): Result<List<User>>

    /**
     * Sync shares from the server.
     */
    suspend fun syncShares(): Result<Unit>
}
