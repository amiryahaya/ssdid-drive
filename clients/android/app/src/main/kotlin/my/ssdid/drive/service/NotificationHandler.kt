package my.ssdid.drive.service

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import my.ssdid.drive.MainActivity
import my.ssdid.drive.R
import my.ssdid.drive.data.local.SecureStorage
import my.ssdid.drive.data.local.entity.NotificationActionType
import my.ssdid.drive.data.local.entity.NotificationEntity
import my.ssdid.drive.data.local.entity.NotificationType
import my.ssdid.drive.util.Logger
import dagger.hilt.android.qualifiers.ApplicationContext
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Handles displaying system notifications.
 */
@Singleton
class NotificationHandler @Inject constructor(
    @ApplicationContext private val context: Context,
    private val secureStorage: SecureStorage
) {
    private val notificationManager = NotificationManagerCompat.from(context)

    // D7: Thread-safe notification ID mapping to avoid hashCode() collisions.
    // Counter starts above any hardcoded notification IDs (e.g., SYNC_NOTIFICATION_ID = 1001).
    private val notificationIdCounter = AtomicInteger(NOTIFICATION_ID_START)
    private val notificationIdMap = ConcurrentHashMap<String, Int>()

    init {
        createNotificationChannels()
    }

    /**
     * D7: Get a stable, collision-free integer notification ID for a UUID string.
     */
    private fun getNotificationId(uuid: String): Int {
        return notificationIdMap.getOrPut(uuid) {
            notificationIdCounter.getAndIncrement()
        }
    }

    /**
     * Create all notification channels.
     * Required for Android 8.0 (API 26) and above.
     */
    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channels = listOf(
                NotificationChannel(
                    CHANNEL_SHARES,
                    "Shares",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Notifications about shared files and folders"
                },
                NotificationChannel(
                    CHANNEL_RECOVERY,
                    "Recovery",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Notifications about account recovery"
                },
                NotificationChannel(
                    CHANNEL_SYNC,
                    "Sync",
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "Notifications about sync status"
                },
                NotificationChannel(
                    CHANNEL_SECURITY,
                    "Security",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Security alerts and warnings"
                },
                NotificationChannel(
                    CHANNEL_GENERAL,
                    "General",
                    NotificationManager.IMPORTANCE_DEFAULT
                ).apply {
                    description = "General notifications"
                }
            )

            val systemNotificationManager =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            channels.forEach { systemNotificationManager.createNotificationChannel(it) }
        }
    }

    /**
     * Show a system notification.
     */
    fun showNotification(notification: NotificationEntity) {
        val channelId = getChannelId(notification.type)
        val notificationId = getNotificationId(notification.id)

        // Create intent for notification tap
        val intent = createIntent(notification)
        val pendingIntent = PendingIntent.getActivity(
            context,
            notificationId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Build notification
        val builder = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(getSmallIcon(notification.type))
            .setContentTitle(notification.title)
            .setContentText(notification.message)
            .setStyle(NotificationCompat.BigTextStyle().bigText(notification.message))
            .setPriority(getPriority(notification.type))
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .setCategory(getCategory(notification.type))

        // Add action buttons if applicable
        addActionButtons(builder, notification)

        // Show notification
        try {
            notificationManager.notify(notificationId, builder.build())
        } catch (e: SecurityException) {
            // D11: Log the SecurityException so it's visible in debug builds
            Logger.w(TAG, "Notification permission not granted, cannot show notification", e)
        }
    }

    /**
     * Cancel a notification.
     */
    fun cancelNotification(notificationId: String) {
        val id = notificationIdMap[notificationId] ?: notificationId.hashCode()
        notificationManager.cancel(id)
    }

    /**
     * Cancel all notifications.
     */
    fun cancelAllNotifications() {
        notificationManager.cancelAll()
    }

    /**
     * Show a sync progress notification.
     */
    fun showSyncProgressNotification(progress: Int, total: Int) {
        val notificationId = SYNC_NOTIFICATION_ID

        val builder = NotificationCompat.Builder(context, CHANNEL_SYNC)
            .setSmallIcon(R.drawable.ic_sync)
            .setContentTitle("Syncing")
            .setContentText("$progress of $total operations")
            .setProgress(total, progress, false)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)

        try {
            notificationManager.notify(notificationId, builder.build())
        } catch (e: SecurityException) {
            // D11: Log the SecurityException so it's visible in debug builds
            Logger.w(TAG, "Notification permission not granted, cannot show sync progress", e)
        }
    }

    /**
     * Cancel sync progress notification.
     */
    fun cancelSyncProgressNotification() {
        notificationManager.cancel(SYNC_NOTIFICATION_ID)
    }

    /**
     * Show a sync complete notification.
     */
    fun showSyncCompleteNotification(successCount: Int, failedCount: Int) {
        cancelSyncProgressNotification()

        if (failedCount > 0) {
            // D12: Use actual userId from SecureStorage instead of empty string
            val userId = secureStorage.getUserIdSync() ?: ""
            val notification = NotificationEntity(
                userId = userId,
                type = NotificationType.SYNC_FAILED,
                title = "Sync Complete",
                message = "$successCount synced, $failedCount failed"
            )
            showNotification(notification)
        }
    }

    // ==================== Helper Methods ====================

    private fun getChannelId(type: NotificationType): String {
        return when (type) {
            NotificationType.SHARE_RECEIVED,
            NotificationType.SHARE_REVOKED,
            NotificationType.SHARE_UPDATED,
            NotificationType.FILE_SHARED,
            NotificationType.FOLDER_SHARED -> CHANNEL_SHARES

            NotificationType.RECOVERY_REQUEST_RECEIVED,
            NotificationType.RECOVERY_REQUEST_APPROVED,
            NotificationType.RECOVERY_REQUEST_COMPLETED,
            NotificationType.RECOVERY_SHARE_ASSIGNED -> CHANNEL_RECOVERY

            NotificationType.SYNC_COMPLETED,
            NotificationType.SYNC_FAILED -> CHANNEL_SYNC

            NotificationType.SECURITY_ALERT -> CHANNEL_SECURITY

            else -> CHANNEL_GENERAL
        }
    }

    private fun getSmallIcon(type: NotificationType): Int {
        return when (type) {
            NotificationType.SHARE_RECEIVED,
            NotificationType.SHARE_UPDATED,
            NotificationType.FILE_SHARED,
            NotificationType.FOLDER_SHARED -> R.drawable.ic_share

            NotificationType.SHARE_REVOKED -> R.drawable.ic_share_off

            NotificationType.RECOVERY_REQUEST_RECEIVED,
            NotificationType.RECOVERY_REQUEST_APPROVED,
            NotificationType.RECOVERY_REQUEST_COMPLETED,
            NotificationType.RECOVERY_SHARE_ASSIGNED -> R.drawable.ic_key

            NotificationType.FILE_UPLOADED,
            NotificationType.FILE_DELETED -> R.drawable.ic_file

            NotificationType.FOLDER_CREATED -> R.drawable.ic_folder

            NotificationType.SYNC_COMPLETED,
            NotificationType.SYNC_FAILED -> R.drawable.ic_sync

            NotificationType.STORAGE_WARNING -> R.drawable.ic_storage

            NotificationType.SECURITY_ALERT -> R.drawable.ic_security

            NotificationType.WARNING -> R.drawable.ic_warning

            NotificationType.ERROR -> R.drawable.ic_error

            else -> R.drawable.ic_notification
        }
    }

    private fun getPriority(type: NotificationType): Int {
        return when (type) {
            NotificationType.SECURITY_ALERT,
            NotificationType.RECOVERY_REQUEST_RECEIVED -> NotificationCompat.PRIORITY_HIGH

            NotificationType.SYNC_COMPLETED,
            NotificationType.SYNC_FAILED -> NotificationCompat.PRIORITY_LOW

            else -> NotificationCompat.PRIORITY_DEFAULT
        }
    }

    private fun getCategory(type: NotificationType): String {
        return when (type) {
            NotificationType.SHARE_RECEIVED,
            NotificationType.RECOVERY_REQUEST_RECEIVED -> NotificationCompat.CATEGORY_SOCIAL

            NotificationType.SECURITY_ALERT -> NotificationCompat.CATEGORY_ALARM

            NotificationType.SYNC_COMPLETED,
            NotificationType.SYNC_FAILED -> NotificationCompat.CATEGORY_STATUS

            NotificationType.ERROR -> NotificationCompat.CATEGORY_ERROR

            else -> NotificationCompat.CATEGORY_MESSAGE
        }
    }

    private fun createIntent(notification: NotificationEntity): Intent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_NOTIFICATION_ID, notification.id)
            putExtra(EXTRA_NOTIFICATION_TYPE, notification.type.name)
            notification.actionType?.let { putExtra(EXTRA_ACTION_TYPE, it.name) }
            notification.actionId?.let { putExtra(EXTRA_ACTION_ID, it) }
        }
        return intent
    }

    private fun addActionButtons(
        builder: NotificationCompat.Builder,
        notification: NotificationEntity
    ) {
        val notificationId = getNotificationId(notification.id)

        when (notification.actionType) {
            NotificationActionType.OPEN_SHARE -> {
                val viewIntent = createActionIntent(notification, "view")
                val viewPendingIntent = PendingIntent.getActivity(
                    context,
                    notificationId + 1,
                    viewIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                builder.addAction(R.drawable.ic_open, "View", viewPendingIntent)
            }

            NotificationActionType.OPEN_RECOVERY_REQUEST -> {
                val reviewIntent = createActionIntent(notification, "review")
                val reviewPendingIntent = PendingIntent.getActivity(
                    context,
                    notificationId + 1,
                    reviewIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                builder.addAction(R.drawable.ic_review, "Review", reviewPendingIntent)
            }

            NotificationActionType.RETRY_SYNC -> {
                val retryIntent = createActionIntent(notification, "retry")
                val retryPendingIntent = PendingIntent.getActivity(
                    context,
                    notificationId + 1,
                    retryIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                builder.addAction(R.drawable.ic_retry, "Retry", retryPendingIntent)
            }

            else -> { /* No action buttons */ }
        }
    }

    private fun createActionIntent(notification: NotificationEntity, action: String): Intent {
        return Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_NOTIFICATION_ID, notification.id)
            putExtra(EXTRA_NOTIFICATION_TYPE, notification.type.name)
            putExtra(EXTRA_ACTION, action)
            notification.actionType?.let { putExtra(EXTRA_ACTION_TYPE, it.name) }
            notification.actionId?.let { putExtra(EXTRA_ACTION_ID, it) }
        }
    }

    companion object {
        private const val TAG = "NotificationHandler"

        // Notification channels
        const val CHANNEL_SHARES = "shares"
        const val CHANNEL_RECOVERY = "recovery"
        const val CHANNEL_SYNC = "sync"
        const val CHANNEL_SECURITY = "security"
        const val CHANNEL_GENERAL = "general"

        // Notification IDs
        const val SYNC_NOTIFICATION_ID = 1001

        // D7: Start dynamic notification IDs above all hardcoded IDs
        private const val NOTIFICATION_ID_START = 2000

        // Intent extras
        const val EXTRA_NOTIFICATION_ID = "notification_id"
        const val EXTRA_NOTIFICATION_TYPE = "notification_type"
        const val EXTRA_ACTION_TYPE = "action_type"
        const val EXTRA_ACTION_ID = "action_id"
        const val EXTRA_ACTION = "action"
    }
}
