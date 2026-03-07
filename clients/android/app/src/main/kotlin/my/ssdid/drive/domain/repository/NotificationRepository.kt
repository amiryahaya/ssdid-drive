package my.ssdid.drive.domain.repository

import my.ssdid.drive.domain.model.Notification
import my.ssdid.drive.domain.model.NotificationType
import my.ssdid.drive.util.Result
import kotlinx.coroutines.flow.Flow

/**
 * Repository interface for notification operations.
 */
interface NotificationRepository {

    /**
     * Get all notifications for the current user.
     */
    suspend fun getNotifications(): Result<List<Notification>>

    /**
     * Observe all notifications.
     */
    fun observeNotifications(): Flow<List<Notification>>

    /**
     * Observe recent notifications with limit.
     */
    fun observeRecentNotifications(limit: Int = 50): Flow<List<Notification>>

    /**
     * Get unread notifications.
     */
    suspend fun getUnreadNotifications(): Result<List<Notification>>

    /**
     * Observe unread notifications.
     */
    fun observeUnreadNotifications(): Flow<List<Notification>>

    /**
     * Get unread notification count.
     */
    suspend fun getUnreadCount(): Int

    /**
     * Observe unread notification count.
     */
    fun observeUnreadCount(): Flow<Int>

    /**
     * Get notifications by type.
     */
    suspend fun getNotificationsByType(type: NotificationType): Result<List<Notification>>

    /**
     * Mark a notification as read.
     */
    suspend fun markAsRead(notificationId: String): Result<Unit>

    /**
     * Mark all notifications as read.
     */
    suspend fun markAllAsRead(): Result<Unit>

    /**
     * Delete a notification.
     */
    suspend fun deleteNotification(notificationId: String): Result<Unit>

    /**
     * Delete all notifications.
     */
    suspend fun deleteAllNotifications(): Result<Unit>

    /**
     * Cleanup old notifications.
     */
    suspend fun cleanupOldNotifications(daysOld: Int = 30): Result<Unit>

    /**
     * Create a local notification (for sync events, etc.).
     */
    suspend fun createLocalNotification(
        type: NotificationType,
        title: String,
        message: String,
        actionType: String? = null,
        actionId: String? = null
    ): Result<Notification>

    // Note: Push notification registration is handled by PushNotificationManager using OneSignal
}
