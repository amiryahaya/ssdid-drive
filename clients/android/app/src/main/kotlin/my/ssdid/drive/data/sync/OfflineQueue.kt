package my.ssdid.drive.data.sync

import com.google.gson.Gson
import my.ssdid.drive.data.local.dao.PendingOperationDao
import my.ssdid.drive.data.local.entity.OperationStatus
import my.ssdid.drive.data.local.entity.OperationType
import my.ssdid.drive.data.local.entity.PendingOperationEntity
import my.ssdid.drive.data.local.entity.ResourceType
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import java.time.Instant
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Manages the offline operation queue.
 * Queues operations when offline and provides them for sync when connectivity is restored.
 */
@Singleton
class OfflineQueue @Inject constructor(
    private val pendingOperationDao: PendingOperationDao,
    private val gson: Gson
) {
    // ==================== Queue Operations ====================

    /**
     * Queue a file upload operation.
     */
    suspend fun queueFileUpload(
        localFilePath: String,
        folderId: String,
        fileName: String,
        mimeType: String,
        fileSize: Long
    ): String {
        val payload = FileUploadPayload(
            localFilePath = localFilePath,
            folderId = folderId,
            fileName = fileName,
            mimeType = mimeType,
            fileSize = fileSize
        )

        val operation = PendingOperationEntity(
            operationType = OperationType.UPLOAD_FILE,
            resourceType = ResourceType.FILE,
            resourceId = null,
            parentId = folderId,
            payload = gson.toJson(payload),
            priority = 10,
            localFilePath = localFilePath
        )

        pendingOperationDao.insert(operation)
        return operation.id
    }

    /**
     * Queue a file deletion operation.
     */
    suspend fun queueFileDelete(fileId: String): String {
        val payload = FileDeletePayload(fileId = fileId)

        val operation = PendingOperationEntity(
            operationType = OperationType.DELETE_FILE,
            resourceType = ResourceType.FILE,
            resourceId = fileId,
            parentId = null,
            payload = gson.toJson(payload),
            priority = 5
        )

        pendingOperationDao.insert(operation)
        return operation.id
    }

    /**
     * Queue a file move operation.
     */
    suspend fun queueFileMove(fileId: String, targetFolderId: String): String {
        val payload = FileMovePayload(fileId = fileId, targetFolderId = targetFolderId)

        val operation = PendingOperationEntity(
            operationType = OperationType.MOVE_FILE,
            resourceType = ResourceType.FILE,
            resourceId = fileId,
            parentId = targetFolderId,
            payload = gson.toJson(payload),
            priority = 5
        )

        pendingOperationDao.insert(operation)
        return operation.id
    }

    /**
     * Queue a folder creation operation.
     */
    suspend fun queueFolderCreate(
        name: String,
        parentFolderId: String
    ): String {
        val payload = FolderCreatePayload(name = name, parentFolderId = parentFolderId)

        val operation = PendingOperationEntity(
            operationType = OperationType.CREATE_FOLDER,
            resourceType = ResourceType.FOLDER,
            resourceId = null,
            parentId = parentFolderId,
            payload = gson.toJson(payload),
            priority = 8
        )

        pendingOperationDao.insert(operation)
        return operation.id
    }

    /**
     * Queue a folder deletion operation.
     */
    suspend fun queueFolderDelete(folderId: String): String {
        val payload = FolderDeletePayload(folderId = folderId)

        val operation = PendingOperationEntity(
            operationType = OperationType.DELETE_FOLDER,
            resourceType = ResourceType.FOLDER,
            resourceId = folderId,
            parentId = null,
            payload = gson.toJson(payload),
            priority = 5
        )

        pendingOperationDao.insert(operation)
        return operation.id
    }

    /**
     * Queue a share creation operation.
     */
    suspend fun queueShareFile(
        fileId: String,
        recipientId: String,
        permission: String
    ): String {
        val payload = ShareFilePayload(
            fileId = fileId,
            recipientId = recipientId,
            permission = permission
        )

        val operation = PendingOperationEntity(
            operationType = OperationType.SHARE_FILE,
            resourceType = ResourceType.SHARE,
            resourceId = null,
            parentId = fileId,
            payload = gson.toJson(payload),
            priority = 7
        )

        pendingOperationDao.insert(operation)
        return operation.id
    }

    /**
     * Queue a share folder operation.
     */
    suspend fun queueShareFolder(
        folderId: String,
        recipientId: String,
        permission: String
    ): String {
        val payload = ShareFolderPayload(
            folderId = folderId,
            recipientId = recipientId,
            permission = permission
        )

        val operation = PendingOperationEntity(
            operationType = OperationType.SHARE_FOLDER,
            resourceType = ResourceType.SHARE,
            resourceId = null,
            parentId = folderId,
            payload = gson.toJson(payload),
            priority = 7
        )

        pendingOperationDao.insert(operation)
        return operation.id
    }

    /**
     * Queue a share revocation operation.
     */
    suspend fun queueRevokeShare(shareId: String): String {
        val payload = RevokeSharePayload(shareId = shareId)

        val operation = PendingOperationEntity(
            operationType = OperationType.REVOKE_SHARE,
            resourceType = ResourceType.SHARE,
            resourceId = shareId,
            parentId = null,
            payload = gson.toJson(payload),
            priority = 6
        )

        pendingOperationDao.insert(operation)
        return operation.id
    }

    // ==================== Query Operations ====================

    /**
     * Get all pending operations ready to be processed.
     */
    suspend fun getPendingOperations(): List<PendingOperationEntity> {
        return pendingOperationDao.getPendingOperations()
    }

    /**
     * Get the next batch of operations to process.
     */
    suspend fun getNextBatch(batchSize: Int = 10): List<PendingOperationEntity> {
        return pendingOperationDao.getPendingOperationsLimit(batchSize)
    }

    /**
     * Get operations that failed but can be retried.
     */
    suspend fun getRetryableOperations(): List<PendingOperationEntity> {
        return pendingOperationDao.getRetryableOperations()
    }

    /**
     * Check if there are any pending operations for a resource.
     */
    suspend fun hasPendingOperations(resourceType: ResourceType, resourceId: String): Boolean {
        return pendingOperationDao.hasActiveOperationForResource(resourceType, resourceId)
    }

    /**
     * Observe active operations (pending, in-progress, failed).
     */
    fun observeActiveOperations(): Flow<List<PendingOperationEntity>> {
        return pendingOperationDao.observeActiveOperations()
    }

    /**
     * Observe pending upload operations.
     */
    fun observePendingUploads(): Flow<List<PendingOperationEntity>> {
        return pendingOperationDao.observePendingUploads()
    }

    /**
     * Observe the count of pending operations.
     */
    fun observePendingCount(): Flow<Int> {
        return pendingOperationDao.observePendingCount()
    }

    /**
     * Observe failed operations.
     */
    fun observeFailedOperations(): Flow<List<PendingOperationEntity>> {
        return pendingOperationDao.observeFailedOperations()
    }

    // ==================== Status Updates ====================

    /**
     * Mark an operation as in progress.
     */
    suspend fun markInProgress(operationId: String) {
        pendingOperationDao.markInProgress(operationId)
    }

    /**
     * Mark an operation as completed.
     */
    suspend fun markCompleted(operationId: String) {
        pendingOperationDao.markCompleted(operationId)
    }

    /**
     * Mark an operation as failed.
     */
    suspend fun markFailed(operationId: String, errorMessage: String?) {
        pendingOperationDao.markFailed(operationId, errorMessage)
    }

    /**
     * Update the progress of an operation (for uploads).
     */
    suspend fun updateProgress(operationId: String, progress: Int) {
        pendingOperationDao.updateProgress(operationId, progress)
    }

    /**
     * Cancel an operation.
     */
    suspend fun cancelOperation(operationId: String) {
        pendingOperationDao.markCancelled(operationId)
    }

    /**
     * Retry a failed operation.
     */
    suspend fun retryOperation(operationId: String) {
        pendingOperationDao.resetForRetry(operationId)
    }

    /**
     * Reset any in-progress operations to pending.
     * Called on app startup to handle interrupted operations.
     */
    suspend fun resetInterruptedOperations() {
        pendingOperationDao.resetInProgressToPending()
    }

    // ==================== Cleanup ====================

    /**
     * Delete completed operations older than the specified time.
     */
    suspend fun cleanupCompleted(olderThan: Instant = Instant.now().minusSeconds(86400)) {
        pendingOperationDao.deleteCompletedBefore(olderThan)
    }

    /**
     * Delete all cancelled operations.
     */
    suspend fun cleanupCancelled() {
        pendingOperationDao.deleteCancelled()
    }

    /**
     * Delete all operations for a resource.
     */
    suspend fun deleteOperationsForResource(resourceType: ResourceType, resourceId: String) {
        pendingOperationDao.deleteByResource(resourceType, resourceId)
    }

    // ==================== Payload Parsing ====================

    fun parsePayload(operation: PendingOperationEntity): OperationPayload {
        return when (operation.operationType) {
            OperationType.UPLOAD_FILE -> gson.fromJson(operation.payload, FileUploadPayload::class.java)
            OperationType.DELETE_FILE -> gson.fromJson(operation.payload, FileDeletePayload::class.java)
            OperationType.MOVE_FILE -> gson.fromJson(operation.payload, FileMovePayload::class.java)
            OperationType.RENAME_FILE -> gson.fromJson(operation.payload, FileRenamePayload::class.java)
            OperationType.CREATE_FOLDER -> gson.fromJson(operation.payload, FolderCreatePayload::class.java)
            OperationType.DELETE_FOLDER -> gson.fromJson(operation.payload, FolderDeletePayload::class.java)
            OperationType.RENAME_FOLDER -> gson.fromJson(operation.payload, FolderRenamePayload::class.java)
            OperationType.MOVE_FOLDER -> gson.fromJson(operation.payload, FolderMovePayload::class.java)
            OperationType.SHARE_FILE -> gson.fromJson(operation.payload, ShareFilePayload::class.java)
            OperationType.SHARE_FOLDER -> gson.fromJson(operation.payload, ShareFolderPayload::class.java)
            OperationType.REVOKE_SHARE -> gson.fromJson(operation.payload, RevokeSharePayload::class.java)
            OperationType.UPDATE_SHARE_PERMISSION -> gson.fromJson(operation.payload, UpdateSharePermissionPayload::class.java)
            OperationType.CREATE_RECOVERY_SHARE -> gson.fromJson(operation.payload, CreateRecoverySharePayload::class.java)
            OperationType.APPROVE_RECOVERY -> gson.fromJson(operation.payload, ApproveRecoveryPayload::class.java)
        }
    }
}

// ==================== Payload Data Classes ====================

sealed interface OperationPayload

data class FileUploadPayload(
    val localFilePath: String,
    val folderId: String,
    val fileName: String,
    val mimeType: String,
    val fileSize: Long
) : OperationPayload

data class FileDeletePayload(
    val fileId: String
) : OperationPayload

data class FileMovePayload(
    val fileId: String,
    val targetFolderId: String
) : OperationPayload

data class FileRenamePayload(
    val fileId: String,
    val newName: String
) : OperationPayload

data class FolderCreatePayload(
    val name: String,
    val parentFolderId: String
) : OperationPayload

data class FolderDeletePayload(
    val folderId: String
) : OperationPayload

data class FolderRenamePayload(
    val folderId: String,
    val newName: String
) : OperationPayload

data class FolderMovePayload(
    val folderId: String,
    val targetParentId: String
) : OperationPayload

data class ShareFilePayload(
    val fileId: String,
    val recipientId: String,
    val permission: String
) : OperationPayload

data class ShareFolderPayload(
    val folderId: String,
    val recipientId: String,
    val permission: String
) : OperationPayload

data class RevokeSharePayload(
    val shareId: String
) : OperationPayload

data class UpdateSharePermissionPayload(
    val shareId: String,
    val permission: String
) : OperationPayload

data class CreateRecoverySharePayload(
    val trusteeId: String,
    val shareIndex: Int
) : OperationPayload

data class ApproveRecoveryPayload(
    val requestId: String,
    val shareId: String
) : OperationPayload
