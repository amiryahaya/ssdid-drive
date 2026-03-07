package com.securesharing.data.sync

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import com.securesharing.data.local.entity.OperationStatus
import com.securesharing.data.local.entity.OperationType
import com.securesharing.data.local.entity.PendingOperationEntity
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Coordinates synchronization between local operations and remote server.
 * Manages the sync lifecycle and work scheduling.
 */
@Singleton
class SyncManager @Inject constructor(
    @ApplicationContext private val context: Context,
    private val offlineQueue: OfflineQueue,
    private val networkMonitor: NetworkMonitor
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val workManager = WorkManager.getInstance(context)

    private val _syncState = MutableStateFlow(SyncState.IDLE)
    val syncState: StateFlow<SyncState> = _syncState.asStateFlow()

    private val _lastSyncTime = MutableStateFlow<Long?>(null)
    val lastSyncTime: StateFlow<Long?> = _lastSyncTime.asStateFlow()

    init {
        // Reset interrupted operations on startup
        scope.launch {
            offlineQueue.resetInterruptedOperations()
        }

        // Monitor connectivity and trigger sync when connected
        scope.launch {
            networkMonitor.isConnected.collect { isConnected ->
                if (isConnected && _syncState.value == SyncState.IDLE) {
                    triggerSync()
                }
            }
        }
    }

    // ==================== Sync Control ====================

    /**
     * Trigger an immediate sync if conditions allow.
     */
    fun triggerSync() {
        if (!networkMonitor.isNetworkAvailable()) {
            _syncState.value = SyncState.WAITING_FOR_NETWORK
            return
        }

        val syncRequest = OneTimeWorkRequestBuilder<SyncWorker>()
            .setConstraints(
                Constraints.Builder()
                    .setRequiredNetworkType(NetworkType.CONNECTED)
                    .build()
            )
            .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
            .build()

        workManager.enqueueUniqueWork(
            SYNC_WORK_NAME,
            ExistingWorkPolicy.REPLACE,
            syncRequest
        )

        _syncState.value = SyncState.SYNCING
    }

    /**
     * Schedule periodic background sync.
     */
    fun schedulePeriodicSync() {
        val periodicSyncRequest = PeriodicWorkRequestBuilder<SyncWorker>(
            repeatInterval = 15,
            repeatIntervalTimeUnit = TimeUnit.MINUTES
        )
            .setConstraints(
                Constraints.Builder()
                    .setRequiredNetworkType(NetworkType.CONNECTED)
                    .build()
            )
            .setBackoffCriteria(
                BackoffPolicy.EXPONENTIAL,
                1,
                TimeUnit.MINUTES
            )
            .build()

        workManager.enqueueUniquePeriodicWork(
            PERIODIC_SYNC_WORK_NAME,
            ExistingPeriodicWorkPolicy.UPDATE,
            periodicSyncRequest
        )
    }

    /**
     * Cancel periodic sync.
     */
    fun cancelPeriodicSync() {
        workManager.cancelUniqueWork(PERIODIC_SYNC_WORK_NAME)
    }

    /**
     * Cancel all pending sync work.
     */
    fun cancelAllSync() {
        workManager.cancelAllWorkByTag(SYNC_TAG)
        _syncState.value = SyncState.IDLE
    }

    // ==================== Status Reporting ====================

    /**
     * Report sync started (called from SyncWorker).
     */
    internal fun reportSyncStarted() {
        _syncState.value = SyncState.SYNCING
    }

    /**
     * Report sync completed (called from SyncWorker).
     */
    internal fun reportSyncCompleted() {
        _syncState.value = SyncState.IDLE
        _lastSyncTime.value = System.currentTimeMillis()
    }

    /**
     * Report sync failed (called from SyncWorker).
     */
    internal fun reportSyncFailed(error: String?) {
        _syncState.value = SyncState.ERROR
    }

    // ==================== Status Queries ====================

    /**
     * Get the current number of pending operations.
     */
    fun observePendingCount(): Flow<Int> {
        return offlineQueue.observePendingCount()
    }

    /**
     * Get active operations (pending, in-progress, failed).
     */
    fun observeActiveOperations(): Flow<List<PendingOperationEntity>> {
        return offlineQueue.observeActiveOperations()
    }

    /**
     * Get pending upload operations.
     */
    fun observePendingUploads(): Flow<List<PendingOperationEntity>> {
        return offlineQueue.observePendingUploads()
    }

    /**
     * Get failed operations.
     */
    fun observeFailedOperations(): Flow<List<PendingOperationEntity>> {
        return offlineQueue.observeFailedOperations()
    }

    /**
     * Get combined sync status with pending count.
     */
    fun observeSyncStatus(): Flow<SyncStatus> {
        return combine(
            syncState,
            offlineQueue.observePendingCount(),
            networkMonitor.isConnected
        ) { state, pendingCount, isConnected ->
            SyncStatus(
                state = state,
                pendingCount = pendingCount,
                isOnline = isConnected
            )
        }
    }

    // ==================== Operation Management ====================

    /**
     * Retry a failed operation.
     */
    suspend fun retryOperation(operationId: String) {
        offlineQueue.retryOperation(operationId)
        triggerSync()
    }

    /**
     * Retry all failed operations.
     */
    suspend fun retryAllFailed() {
        val failedOperations = offlineQueue.getRetryableOperations()
        failedOperations.forEach { operation ->
            offlineQueue.retryOperation(operation.id)
        }
        triggerSync()
    }

    /**
     * Cancel a pending operation.
     */
    suspend fun cancelOperation(operationId: String) {
        offlineQueue.cancelOperation(operationId)
    }

    /**
     * Cleanup old completed and cancelled operations.
     */
    suspend fun cleanup() {
        offlineQueue.cleanupCompleted()
        offlineQueue.cleanupCancelled()
    }

    companion object {
        const val SYNC_WORK_NAME = "secure_sharing_sync"
        const val PERIODIC_SYNC_WORK_NAME = "secure_sharing_periodic_sync"
        const val SYNC_TAG = "sync"
    }
}

/**
 * Sync state.
 */
enum class SyncState {
    IDLE,
    SYNCING,
    WAITING_FOR_NETWORK,
    ERROR
}

/**
 * Combined sync status.
 */
data class SyncStatus(
    val state: SyncState,
    val pendingCount: Int,
    val isOnline: Boolean
) {
    val hasPendingOperations: Boolean get() = pendingCount > 0
    val isSyncing: Boolean get() = state == SyncState.SYNCING
    val needsSync: Boolean get() = hasPendingOperations && isOnline && state != SyncState.SYNCING
}
