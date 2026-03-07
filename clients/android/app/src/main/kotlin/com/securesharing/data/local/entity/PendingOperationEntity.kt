package com.securesharing.data.local.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import java.time.Instant
import java.util.UUID

/**
 * Entity representing a pending operation that needs to be synced.
 * Operations are queued when offline and executed when connectivity is restored.
 */
@Entity(
    tableName = "pending_operations",
    indices = [
        Index("status"),
        Index("operation_type"),
        Index("created_at"),
        Index("priority")
    ]
)
data class PendingOperationEntity(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String = UUID.randomUUID().toString(),

    @ColumnInfo(name = "operation_type")
    val operationType: OperationType,

    @ColumnInfo(name = "resource_type")
    val resourceType: ResourceType,

    @ColumnInfo(name = "resource_id")
    val resourceId: String?,

    @ColumnInfo(name = "parent_id")
    val parentId: String?,

    @ColumnInfo(name = "payload")
    val payload: String,

    @ColumnInfo(name = "status")
    val status: OperationStatus = OperationStatus.PENDING,

    @ColumnInfo(name = "priority")
    val priority: Int = 0,

    @ColumnInfo(name = "retry_count")
    val retryCount: Int = 0,

    @ColumnInfo(name = "max_retries")
    val maxRetries: Int = 3,

    @ColumnInfo(name = "error_message")
    val errorMessage: String? = null,

    @ColumnInfo(name = "created_at")
    val createdAt: Instant = Instant.now(),

    @ColumnInfo(name = "updated_at")
    val updatedAt: Instant = Instant.now(),

    @ColumnInfo(name = "executed_at")
    val executedAt: Instant? = null,

    @ColumnInfo(name = "local_file_path")
    val localFilePath: String? = null,

    @ColumnInfo(name = "progress")
    val progress: Int = 0
)

/**
 * Types of operations that can be queued.
 */
enum class OperationType {
    // File operations
    UPLOAD_FILE,
    DELETE_FILE,
    MOVE_FILE,
    RENAME_FILE,

    // Folder operations
    CREATE_FOLDER,
    DELETE_FOLDER,
    RENAME_FOLDER,
    MOVE_FOLDER,

    // Share operations
    SHARE_FILE,
    SHARE_FOLDER,
    REVOKE_SHARE,
    UPDATE_SHARE_PERMISSION,

    // Recovery operations
    CREATE_RECOVERY_SHARE,
    APPROVE_RECOVERY
}

/**
 * Resource types for operations.
 */
enum class ResourceType {
    FILE,
    FOLDER,
    SHARE,
    RECOVERY
}

/**
 * Status of a pending operation.
 */
enum class OperationStatus {
    PENDING,
    IN_PROGRESS,
    COMPLETED,
    FAILED,
    CANCELLED
}
