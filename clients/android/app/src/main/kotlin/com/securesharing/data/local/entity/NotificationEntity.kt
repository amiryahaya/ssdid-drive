package com.securesharing.data.local.entity

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import java.time.Instant
import java.util.UUID

/**
 * Room entity for storing notifications locally.
 */
@Entity(
    tableName = "notifications",
    indices = [
        Index(value = ["userId"]),
        Index(value = ["type"]),
        Index(value = ["isRead"]),
        Index(value = ["createdAt"])
    ]
)
data class NotificationEntity(
    @PrimaryKey
    val id: String = UUID.randomUUID().toString(),
    val userId: String,
    val type: NotificationType,
    val title: String,
    val message: String,
    val data: String? = null, // JSON payload for action data
    val isRead: Boolean = false,
    val actionType: NotificationActionType? = null,
    val actionId: String? = null, // ID of the resource to navigate to
    val createdAt: Instant = Instant.now()
)

/**
 * Types of notifications.
 */
enum class NotificationType {
    // Share notifications
    SHARE_RECEIVED,
    SHARE_REVOKED,
    SHARE_UPDATED,

    // Recovery notifications
    RECOVERY_REQUEST_RECEIVED,
    RECOVERY_REQUEST_APPROVED,
    RECOVERY_REQUEST_COMPLETED,
    RECOVERY_SHARE_ASSIGNED,

    // File notifications
    FILE_UPLOADED,
    FILE_SHARED,
    FILE_DELETED,

    // Folder notifications
    FOLDER_SHARED,
    FOLDER_CREATED,

    // System notifications
    SYNC_COMPLETED,
    SYNC_FAILED,
    STORAGE_WARNING,
    SECURITY_ALERT,

    // General
    INFO,
    WARNING,
    ERROR;

    companion object {
        fun fromString(value: String): NotificationType {
            return try {
                valueOf(value.uppercase())
            } catch (e: Exception) {
                INFO
            }
        }
    }
}

/**
 * Types of actions that can be taken from a notification.
 */
enum class NotificationActionType {
    OPEN_SHARE,
    OPEN_FILE,
    OPEN_FOLDER,
    OPEN_RECOVERY_REQUEST,
    OPEN_SETTINGS,
    RETRY_SYNC,
    NONE;

    companion object {
        fun fromString(value: String): NotificationActionType {
            return try {
                valueOf(value.uppercase())
            } catch (e: Exception) {
                NONE
            }
        }
    }
}
