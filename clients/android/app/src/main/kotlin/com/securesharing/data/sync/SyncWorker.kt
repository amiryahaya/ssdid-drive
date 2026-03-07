package com.securesharing.data.sync

import android.content.Context
import android.util.Log
import androidx.hilt.work.HiltWorker
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import com.securesharing.data.local.entity.OperationType
import com.securesharing.data.local.entity.PendingOperationEntity
import com.securesharing.domain.repository.FileRepository
import com.securesharing.domain.repository.FolderRepository
import com.securesharing.domain.repository.ShareRepository
import com.securesharing.util.Result
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Background worker that processes pending operations from the offline queue.
 * Uses WorkManager for reliable background execution.
 */
@HiltWorker
class SyncWorker @AssistedInject constructor(
    @Assisted context: Context,
    @Assisted workerParams: WorkerParameters,
    private val syncManager: SyncManager,
    private val offlineQueue: OfflineQueue,
    private val fileRepository: FileRepository,
    private val folderRepository: FolderRepository,
    private val shareRepository: ShareRepository
) : CoroutineWorker(context, workerParams) {

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        Log.d(TAG, "SyncWorker started")
        syncManager.reportSyncStarted()

        try {
            // Process operations in batches
            var processedCount = 0
            var failedCount = 0

            while (true) {
                val operations = offlineQueue.getNextBatch(BATCH_SIZE)
                if (operations.isEmpty()) break

                for (operation in operations) {
                    val result = processOperation(operation)
                    if (result) {
                        processedCount++
                    } else {
                        failedCount++
                    }
                }
            }

            Log.d(TAG, "SyncWorker completed: processed=$processedCount, failed=$failedCount")

            if (failedCount > 0) {
                syncManager.reportSyncFailed("$failedCount operations failed")
                Result.retry()
            } else {
                syncManager.reportSyncCompleted()
                Result.success()
            }
        } catch (e: Exception) {
            Log.e(TAG, "SyncWorker failed", e)
            syncManager.reportSyncFailed(e.message)
            Result.retry()
        }
    }

    private suspend fun processOperation(operation: PendingOperationEntity): Boolean {
        Log.d(TAG, "Processing operation: ${operation.id} - ${operation.operationType}")
        offlineQueue.markInProgress(operation.id)

        return try {
            val result = when (operation.operationType) {
                // File operations
                OperationType.UPLOAD_FILE -> processFileUpload(operation)
                OperationType.DELETE_FILE -> processFileDelete(operation)
                OperationType.MOVE_FILE -> processFileMove(operation)
                OperationType.RENAME_FILE -> processFileRename(operation)

                // Folder operations
                OperationType.CREATE_FOLDER -> processFolderCreate(operation)
                OperationType.DELETE_FOLDER -> processFolderDelete(operation)
                OperationType.RENAME_FOLDER -> processFolderRename(operation)
                OperationType.MOVE_FOLDER -> processFolderMove(operation)

                // Share operations
                OperationType.SHARE_FILE -> processShareFile(operation)
                OperationType.SHARE_FOLDER -> processShareFolder(operation)
                OperationType.REVOKE_SHARE -> processRevokeShare(operation)
                OperationType.UPDATE_SHARE_PERMISSION -> processUpdateSharePermission(operation)

                // Recovery operations
                OperationType.CREATE_RECOVERY_SHARE -> processCreateRecoveryShare(operation)
                OperationType.APPROVE_RECOVERY -> processApproveRecovery(operation)
            }

            if (result) {
                offlineQueue.markCompleted(operation.id)
                Log.d(TAG, "Operation completed: ${operation.id}")
            } else {
                offlineQueue.markFailed(operation.id, "Operation failed")
                Log.w(TAG, "Operation failed: ${operation.id}")
            }

            result
        } catch (e: Exception) {
            Log.e(TAG, "Operation error: ${operation.id}", e)
            offlineQueue.markFailed(operation.id, e.message)
            false
        }
    }

    // ==================== File Operations ====================

    private suspend fun processFileUpload(operation: PendingOperationEntity): Boolean {
        val payload = offlineQueue.parsePayload(operation) as FileUploadPayload

        // Report progress
        offlineQueue.updateProgress(operation.id, 0)

        val result = fileRepository.uploadFile(
            localPath = payload.localFilePath,
            folderId = payload.folderId,
            fileName = payload.fileName,
            mimeType = payload.mimeType,
            onProgress = { progress ->
                // Update progress in a coroutine-safe way using runBlocking
                // This is safe because the callback runs on background thread
                kotlinx.coroutines.runBlocking {
                    offlineQueue.updateProgress(operation.id, progress)
                }
            }
        )

        return result is com.securesharing.util.Result.Success
    }

    private suspend fun processFileDelete(operation: PendingOperationEntity): Boolean {
        val payload = offlineQueue.parsePayload(operation) as FileDeletePayload
        val result = fileRepository.deleteFile(payload.fileId)
        return result is com.securesharing.util.Result.Success
    }

    private suspend fun processFileMove(operation: PendingOperationEntity): Boolean {
        val payload = offlineQueue.parsePayload(operation) as FileMovePayload
        val result = fileRepository.moveFile(payload.fileId, payload.targetFolderId)
        return result is com.securesharing.util.Result.Success
    }

    private suspend fun processFileRename(operation: PendingOperationEntity): Boolean {
        val payload = offlineQueue.parsePayload(operation) as FileRenamePayload
        val result = fileRepository.renameFile(payload.fileId, payload.newName)
        return result is com.securesharing.util.Result.Success
    }

    // ==================== Folder Operations ====================

    private suspend fun processFolderCreate(operation: PendingOperationEntity): Boolean {
        val payload = offlineQueue.parsePayload(operation) as FolderCreatePayload
        val result = folderRepository.createFolder(payload.name, payload.parentFolderId)
        return result is com.securesharing.util.Result.Success
    }

    private suspend fun processFolderDelete(operation: PendingOperationEntity): Boolean {
        val payload = offlineQueue.parsePayload(operation) as FolderDeletePayload
        val result = folderRepository.deleteFolder(payload.folderId)
        return result is com.securesharing.util.Result.Success
    }

    private suspend fun processFolderRename(operation: PendingOperationEntity): Boolean {
        val payload = offlineQueue.parsePayload(operation) as FolderRenamePayload
        val result = folderRepository.renameFolder(payload.folderId, payload.newName)
        return result is com.securesharing.util.Result.Success
    }

    private suspend fun processFolderMove(operation: PendingOperationEntity): Boolean {
        val payload = offlineQueue.parsePayload(operation) as FolderMovePayload
        val result = folderRepository.moveFolder(payload.folderId, payload.targetParentId)
        return result is com.securesharing.util.Result.Success
    }

    // ==================== Share Operations ====================

    private suspend fun processShareFile(operation: PendingOperationEntity): Boolean {
        val payload = offlineQueue.parsePayload(operation) as ShareFilePayload
        val result = shareRepository.shareFile(
            fileId = payload.fileId,
            recipientId = payload.recipientId,
            permission = payload.permission
        )
        return result is com.securesharing.util.Result.Success
    }

    private suspend fun processShareFolder(operation: PendingOperationEntity): Boolean {
        val payload = offlineQueue.parsePayload(operation) as ShareFolderPayload
        val result = shareRepository.shareFolder(
            folderId = payload.folderId,
            recipientId = payload.recipientId,
            permission = payload.permission
        )
        return result is com.securesharing.util.Result.Success
    }

    private suspend fun processRevokeShare(operation: PendingOperationEntity): Boolean {
        val payload = offlineQueue.parsePayload(operation) as RevokeSharePayload
        val result = shareRepository.revokeShare(payload.shareId)
        return result is com.securesharing.util.Result.Success
    }

    private suspend fun processUpdateSharePermission(operation: PendingOperationEntity): Boolean {
        val payload = offlineQueue.parsePayload(operation) as UpdateSharePermissionPayload
        val result = shareRepository.updatePermission(payload.shareId, payload.permission)
        return result is com.securesharing.util.Result.Success
    }

    // ==================== Recovery Operations ====================

    private suspend fun processCreateRecoveryShare(operation: PendingOperationEntity): Boolean {
        // Recovery operations are complex and involve crypto
        // For now, return false to indicate manual processing needed
        Log.w(TAG, "Recovery share creation requires manual processing")
        return false
    }

    private suspend fun processApproveRecovery(operation: PendingOperationEntity): Boolean {
        // Recovery operations are complex and involve crypto
        Log.w(TAG, "Recovery approval requires manual processing")
        return false
    }

    companion object {
        private const val TAG = "SyncWorker"
        private const val BATCH_SIZE = 10
    }
}
