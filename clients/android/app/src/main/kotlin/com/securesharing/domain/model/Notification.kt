package com.securesharing.domain.model

import java.time.Instant

/**
 * Domain model for notifications.
 */
data class Notification(
    val id: String,
    val type: NotificationType,
    val title: String,
    val message: String,
    val isRead: Boolean,
    val action: NotificationAction?,
    val createdAt: Instant
) {
    val isUnread: Boolean get() = !isRead

    fun getRelativeTime(): String {
        val now = Instant.now()
        val seconds = now.epochSecond - createdAt.epochSecond

        return when {
            seconds < 60 -> "Just now"
            seconds < 3600 -> "${seconds / 60}m ago"
            seconds < 86400 -> "${seconds / 3600}h ago"
            seconds < 604800 -> "${seconds / 86400}d ago"
            else -> "${seconds / 604800}w ago"
        }
    }
}

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

    fun getIcon(): NotificationIcon {
        return when (this) {
            SHARE_RECEIVED, SHARE_UPDATED -> NotificationIcon.SHARE
            SHARE_REVOKED -> NotificationIcon.SHARE_OFF
            RECOVERY_REQUEST_RECEIVED, RECOVERY_REQUEST_APPROVED,
            RECOVERY_REQUEST_COMPLETED, RECOVERY_SHARE_ASSIGNED -> NotificationIcon.KEY
            FILE_UPLOADED, FILE_SHARED -> NotificationIcon.FILE
            FILE_DELETED -> NotificationIcon.DELETE
            FOLDER_SHARED, FOLDER_CREATED -> NotificationIcon.FOLDER
            SYNC_COMPLETED -> NotificationIcon.SYNC
            SYNC_FAILED -> NotificationIcon.SYNC_ERROR
            STORAGE_WARNING -> NotificationIcon.STORAGE
            SECURITY_ALERT -> NotificationIcon.SECURITY
            INFO -> NotificationIcon.INFO
            WARNING -> NotificationIcon.WARNING
            ERROR -> NotificationIcon.ERROR
        }
    }
}

/**
 * Icon types for notifications.
 */
enum class NotificationIcon {
    SHARE,
    SHARE_OFF,
    KEY,
    FILE,
    DELETE,
    FOLDER,
    SYNC,
    SYNC_ERROR,
    STORAGE,
    SECURITY,
    INFO,
    WARNING,
    ERROR
}

/**
 * Action that can be taken from a notification.
 */
data class NotificationAction(
    val type: NotificationActionType,
    val resourceId: String?
)

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
