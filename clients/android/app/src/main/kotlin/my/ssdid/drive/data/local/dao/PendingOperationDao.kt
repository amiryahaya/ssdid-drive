package my.ssdid.drive.data.local.dao

import androidx.room.*
import my.ssdid.drive.data.local.entity.OperationStatus
import my.ssdid.drive.data.local.entity.OperationType
import my.ssdid.drive.data.local.entity.PendingOperationEntity
import my.ssdid.drive.data.local.entity.ResourceType
import kotlinx.coroutines.flow.Flow
import java.time.Instant

@Dao
interface PendingOperationDao {

    // ==================== Insert Operations ====================

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(operation: PendingOperationEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(operations: List<PendingOperationEntity>)

    // ==================== Query Operations ====================

    @Query("SELECT * FROM pending_operations WHERE id = :id")
    suspend fun getById(id: String): PendingOperationEntity?

    @Query("SELECT * FROM pending_operations WHERE status = :status ORDER BY priority DESC, created_at ASC")
    suspend fun getByStatus(status: OperationStatus): List<PendingOperationEntity>

    @Query("SELECT * FROM pending_operations WHERE status = 'PENDING' ORDER BY priority DESC, created_at ASC")
    suspend fun getPendingOperations(): List<PendingOperationEntity>

    @Query("SELECT * FROM pending_operations WHERE status = 'PENDING' ORDER BY priority DESC, created_at ASC LIMIT :limit")
    suspend fun getPendingOperationsLimit(limit: Int): List<PendingOperationEntity>

    @Query("SELECT * FROM pending_operations WHERE status IN ('PENDING', 'FAILED') AND retry_count < max_retries ORDER BY priority DESC, created_at ASC")
    suspend fun getRetryableOperations(): List<PendingOperationEntity>

    @Query("SELECT * FROM pending_operations WHERE operation_type = :type AND status = 'PENDING'")
    suspend fun getPendingByType(type: OperationType): List<PendingOperationEntity>

    @Query("SELECT * FROM pending_operations WHERE resource_type = :type AND resource_id = :resourceId")
    suspend fun getByResource(type: ResourceType, resourceId: String): List<PendingOperationEntity>

    @Query("SELECT * FROM pending_operations WHERE status = 'IN_PROGRESS'")
    suspend fun getInProgressOperations(): List<PendingOperationEntity>

    // ==================== Flow Queries (Reactive) ====================

    @Query("SELECT * FROM pending_operations WHERE status IN ('PENDING', 'IN_PROGRESS', 'FAILED') ORDER BY priority DESC, created_at ASC")
    fun observeActiveOperations(): Flow<List<PendingOperationEntity>>

    @Query("SELECT COUNT(*) FROM pending_operations WHERE status = 'PENDING'")
    fun observePendingCount(): Flow<Int>

    @Query("SELECT * FROM pending_operations WHERE operation_type = 'UPLOAD_FILE' AND status IN ('PENDING', 'IN_PROGRESS')")
    fun observePendingUploads(): Flow<List<PendingOperationEntity>>

    @Query("SELECT * FROM pending_operations WHERE status = 'FAILED'")
    fun observeFailedOperations(): Flow<List<PendingOperationEntity>>

    // ==================== Update Operations ====================

    @Update
    suspend fun update(operation: PendingOperationEntity)

    @Query("UPDATE pending_operations SET status = :status, updated_at = :updatedAt WHERE id = :id")
    suspend fun updateStatus(id: String, status: OperationStatus, updatedAt: Instant = Instant.now())

    @Query("UPDATE pending_operations SET status = 'IN_PROGRESS', updated_at = :updatedAt WHERE id = :id")
    suspend fun markInProgress(id: String, updatedAt: Instant = Instant.now())

    @Query("UPDATE pending_operations SET status = 'COMPLETED', executed_at = :executedAt, updated_at = :updatedAt WHERE id = :id")
    suspend fun markCompleted(id: String, executedAt: Instant = Instant.now(), updatedAt: Instant = Instant.now())

    @Query("UPDATE pending_operations SET status = 'FAILED', error_message = :errorMessage, retry_count = retry_count + 1, updated_at = :updatedAt WHERE id = :id")
    suspend fun markFailed(id: String, errorMessage: String?, updatedAt: Instant = Instant.now())

    @Query("UPDATE pending_operations SET status = 'CANCELLED', updated_at = :updatedAt WHERE id = :id")
    suspend fun markCancelled(id: String, updatedAt: Instant = Instant.now())

    @Query("UPDATE pending_operations SET progress = :progress, updated_at = :updatedAt WHERE id = :id")
    suspend fun updateProgress(id: String, progress: Int, updatedAt: Instant = Instant.now())

    @Query("UPDATE pending_operations SET status = 'PENDING', retry_count = 0, error_message = NULL, updated_at = :updatedAt WHERE id = :id")
    suspend fun resetForRetry(id: String, updatedAt: Instant = Instant.now())

    @Query("UPDATE pending_operations SET status = 'PENDING' WHERE status = 'IN_PROGRESS'")
    suspend fun resetInProgressToPending()

    // ==================== Delete Operations ====================

    @Delete
    suspend fun delete(operation: PendingOperationEntity)

    @Query("DELETE FROM pending_operations WHERE id = :id")
    suspend fun deleteById(id: String)

    @Query("DELETE FROM pending_operations WHERE status = 'COMPLETED'")
    suspend fun deleteCompleted()

    @Query("DELETE FROM pending_operations WHERE status = 'COMPLETED' AND executed_at < :before")
    suspend fun deleteCompletedBefore(before: Instant)

    @Query("DELETE FROM pending_operations WHERE status = 'CANCELLED'")
    suspend fun deleteCancelled()

    @Query("DELETE FROM pending_operations WHERE resource_type = :type AND resource_id = :resourceId")
    suspend fun deleteByResource(type: ResourceType, resourceId: String)

    @Query("DELETE FROM pending_operations")
    suspend fun deleteAll()

    // ==================== Aggregate Queries ====================

    @Query("SELECT COUNT(*) FROM pending_operations WHERE status = :status")
    suspend fun countByStatus(status: OperationStatus): Int

    @Query("SELECT COUNT(*) FROM pending_operations WHERE status IN ('PENDING', 'IN_PROGRESS')")
    suspend fun countActive(): Int

    @Query("SELECT EXISTS(SELECT 1 FROM pending_operations WHERE resource_type = :type AND resource_id = :resourceId AND status IN ('PENDING', 'IN_PROGRESS'))")
    suspend fun hasActiveOperationForResource(type: ResourceType, resourceId: String): Boolean
}
