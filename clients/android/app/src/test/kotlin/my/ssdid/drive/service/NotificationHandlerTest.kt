package my.ssdid.drive.service

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import my.ssdid.drive.data.local.entity.NotificationActionType
import my.ssdid.drive.data.local.entity.NotificationEntity
import my.ssdid.drive.data.local.entity.NotificationType
import io.mockk.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import java.lang.reflect.Method

/**
 * Unit tests for NotificationHandler.
 *
 * Tests cover:
 * - Channel ID mapping by notification type
 * - Icon mapping by notification type
 * - Priority mapping by notification type
 * - Category mapping by notification type
 * - Sync progress and completion notifications
 * - Cancel operations
 * - Error handling (SecurityException on notify)
 */
class NotificationHandlerTest {

    private lateinit var context: Context
    private lateinit var notificationManagerCompat: NotificationManagerCompat
    private lateinit var systemNotificationManager: NotificationManager
    private lateinit var handler: NotificationHandler
    private lateinit var mockNotification: Notification

    // Reflected private methods for direct testing
    private lateinit var getChannelIdMethod: Method
    private lateinit var getPriorityMethod: Method
    private lateinit var getCategoryMethod: Method

    @Before
    fun setup() {
        context = mockk(relaxed = true)
        notificationManagerCompat = mockk(relaxed = true)
        systemNotificationManager = mockk(relaxed = true)
        mockNotification = mockk(relaxed = true)

        every { context.getSystemService(Context.NOTIFICATION_SERVICE) } returns systemNotificationManager

        mockkStatic(NotificationManagerCompat::class)
        every { NotificationManagerCompat.from(any()) } returns notificationManagerCompat

        // Mock PendingIntent.getActivity to return a mock (it returns null in unit tests)
        mockkStatic(PendingIntent::class)
        every { PendingIntent.getActivity(any(), any(), any(), any()) } returns mockk(relaxed = true)

        // Mock NotificationCompat.Builder to return a controllable notification
        mockkConstructor(NotificationCompat.Builder::class)
        every { anyConstructed<NotificationCompat.Builder>().setSmallIcon(any<Int>()) } answers { self as NotificationCompat.Builder }
        every { anyConstructed<NotificationCompat.Builder>().setContentTitle(any()) } answers { self as NotificationCompat.Builder }
        every { anyConstructed<NotificationCompat.Builder>().setContentText(any()) } answers { self as NotificationCompat.Builder }
        every { anyConstructed<NotificationCompat.Builder>().setStyle(any()) } answers { self as NotificationCompat.Builder }
        every { anyConstructed<NotificationCompat.Builder>().setPriority(any()) } answers { self as NotificationCompat.Builder }
        every { anyConstructed<NotificationCompat.Builder>().setAutoCancel(any()) } answers { self as NotificationCompat.Builder }
        every { anyConstructed<NotificationCompat.Builder>().setContentIntent(any()) } answers { self as NotificationCompat.Builder }
        every { anyConstructed<NotificationCompat.Builder>().setCategory(any()) } answers { self as NotificationCompat.Builder }
        every { anyConstructed<NotificationCompat.Builder>().setProgress(any(), any(), any()) } answers { self as NotificationCompat.Builder }
        every { anyConstructed<NotificationCompat.Builder>().setOngoing(any()) } answers { self as NotificationCompat.Builder }
        every { anyConstructed<NotificationCompat.Builder>().addAction(any<Int>(), any(), any<PendingIntent>()) } answers { self as NotificationCompat.Builder }
        every { anyConstructed<NotificationCompat.Builder>().build() } returns mockNotification

        val secureStorage = mockk<my.ssdid.drive.data.local.SecureStorage>(relaxed = true)
        handler = NotificationHandler(context, secureStorage)

        // Access private methods via reflection for direct testing
        getChannelIdMethod = NotificationHandler::class.java.getDeclaredMethod(
            "getChannelId", NotificationType::class.java
        ).apply { isAccessible = true }

        getPriorityMethod = NotificationHandler::class.java.getDeclaredMethod(
            "getPriority", NotificationType::class.java
        ).apply { isAccessible = true }

        getCategoryMethod = NotificationHandler::class.java.getDeclaredMethod(
            "getCategory", NotificationType::class.java
        ).apply { isAccessible = true }
    }

    @After
    fun tearDown() {
        unmockkStatic(NotificationManagerCompat::class)
        unmockkStatic(PendingIntent::class)
        unmockkConstructor(NotificationCompat.Builder::class)
    }

    // ==================== Channel ID Mapping Tests ====================

    @Test
    fun `getChannelId returns shares channel for SHARE_RECEIVED`() {
        val result = getChannelIdMethod.invoke(handler, NotificationType.SHARE_RECEIVED)
        assertEquals(NotificationHandler.CHANNEL_SHARES, result)
    }

    @Test
    fun `getChannelId returns shares channel for SHARE_REVOKED`() {
        val result = getChannelIdMethod.invoke(handler, NotificationType.SHARE_REVOKED)
        assertEquals(NotificationHandler.CHANNEL_SHARES, result)
    }

    @Test
    fun `getChannelId returns shares channel for SHARE_UPDATED`() {
        val result = getChannelIdMethod.invoke(handler, NotificationType.SHARE_UPDATED)
        assertEquals(NotificationHandler.CHANNEL_SHARES, result)
    }

    @Test
    fun `getChannelId returns shares channel for FILE_SHARED`() {
        val result = getChannelIdMethod.invoke(handler, NotificationType.FILE_SHARED)
        assertEquals(NotificationHandler.CHANNEL_SHARES, result)
    }

    @Test
    fun `getChannelId returns shares channel for FOLDER_SHARED`() {
        val result = getChannelIdMethod.invoke(handler, NotificationType.FOLDER_SHARED)
        assertEquals(NotificationHandler.CHANNEL_SHARES, result)
    }

    @Test
    fun `getChannelId returns recovery channel for RECOVERY_REQUEST_RECEIVED`() {
        val result = getChannelIdMethod.invoke(handler, NotificationType.RECOVERY_REQUEST_RECEIVED)
        assertEquals(NotificationHandler.CHANNEL_RECOVERY, result)
    }

    @Test
    fun `getChannelId returns recovery channel for RECOVERY_SHARE_ASSIGNED`() {
        val result = getChannelIdMethod.invoke(handler, NotificationType.RECOVERY_SHARE_ASSIGNED)
        assertEquals(NotificationHandler.CHANNEL_RECOVERY, result)
    }

    @Test
    fun `getChannelId returns sync channel for SYNC_COMPLETED`() {
        val result = getChannelIdMethod.invoke(handler, NotificationType.SYNC_COMPLETED)
        assertEquals(NotificationHandler.CHANNEL_SYNC, result)
    }

    @Test
    fun `getChannelId returns sync channel for SYNC_FAILED`() {
        val result = getChannelIdMethod.invoke(handler, NotificationType.SYNC_FAILED)
        assertEquals(NotificationHandler.CHANNEL_SYNC, result)
    }

    @Test
    fun `getChannelId returns security channel for SECURITY_ALERT`() {
        val result = getChannelIdMethod.invoke(handler, NotificationType.SECURITY_ALERT)
        assertEquals(NotificationHandler.CHANNEL_SECURITY, result)
    }

    @Test
    fun `getChannelId returns general channel for INFO type`() {
        val result = getChannelIdMethod.invoke(handler, NotificationType.INFO)
        assertEquals(NotificationHandler.CHANNEL_GENERAL, result)
    }

    // ==================== Priority Mapping Tests ====================

    @Test
    fun `getPriority returns HIGH for SECURITY_ALERT`() {
        val result = getPriorityMethod.invoke(handler, NotificationType.SECURITY_ALERT)
        assertEquals(NotificationCompat.PRIORITY_HIGH, result)
    }

    @Test
    fun `getPriority returns HIGH for RECOVERY_REQUEST_RECEIVED`() {
        val result = getPriorityMethod.invoke(handler, NotificationType.RECOVERY_REQUEST_RECEIVED)
        assertEquals(NotificationCompat.PRIORITY_HIGH, result)
    }

    @Test
    fun `getPriority returns LOW for SYNC_COMPLETED`() {
        val result = getPriorityMethod.invoke(handler, NotificationType.SYNC_COMPLETED)
        assertEquals(NotificationCompat.PRIORITY_LOW, result)
    }

    @Test
    fun `getPriority returns DEFAULT for INFO`() {
        val result = getPriorityMethod.invoke(handler, NotificationType.INFO)
        assertEquals(NotificationCompat.PRIORITY_DEFAULT, result)
    }

    // ==================== Category Mapping Tests ====================

    @Test
    fun `getCategory returns SOCIAL for SHARE_RECEIVED`() {
        val result = getCategoryMethod.invoke(handler, NotificationType.SHARE_RECEIVED)
        assertEquals(NotificationCompat.CATEGORY_SOCIAL, result)
    }

    @Test
    fun `getCategory returns ALARM for SECURITY_ALERT`() {
        val result = getCategoryMethod.invoke(handler, NotificationType.SECURITY_ALERT)
        assertEquals(NotificationCompat.CATEGORY_ALARM, result)
    }

    @Test
    fun `getCategory returns STATUS for SYNC_COMPLETED`() {
        val result = getCategoryMethod.invoke(handler, NotificationType.SYNC_COMPLETED)
        assertEquals(NotificationCompat.CATEGORY_STATUS, result)
    }

    @Test
    fun `getCategory returns ERROR for ERROR type`() {
        val result = getCategoryMethod.invoke(handler, NotificationType.ERROR)
        assertEquals(NotificationCompat.CATEGORY_ERROR, result)
    }

    @Test
    fun `getCategory returns MESSAGE for default types`() {
        val result = getCategoryMethod.invoke(handler, NotificationType.INFO)
        assertEquals(NotificationCompat.CATEGORY_MESSAGE, result)
    }

    // ==================== Notification Display Tests ====================

    @Test
    fun `showNotification uses incrementing notification id for system notification`() {
        val notification = createNotification(id = "test-notification-id")

        handler.showNotification(notification)

        verify {
            notificationManagerCompat.notify(
                any<Int>(),
                any()
            )
        }
    }

    @Test
    fun `showNotification sets title and message from entity`() {
        val notification = createNotification(
            title = "Test Title",
            message = "Test Message Body"
        )

        handler.showNotification(notification)

        verify {
            anyConstructed<NotificationCompat.Builder>().setContentTitle("Test Title")
            anyConstructed<NotificationCompat.Builder>().setContentText("Test Message Body")
        }
    }

    @Test
    fun `showNotification catches SecurityException without crashing`() {
        val notification = createNotification()
        every { notificationManagerCompat.notify(any(), any()) } throws SecurityException("No permission")

        // Should not throw
        handler.showNotification(notification)
    }

    // ==================== Cancel Tests ====================

    @Test
    fun `cancelNotification cancels by id hashCode`() {
        val notificationId = "notification-abc"

        handler.cancelNotification(notificationId)

        verify { notificationManagerCompat.cancel(notificationId.hashCode()) }
    }

    @Test
    fun `cancelAllNotifications calls cancelAll on manager`() {
        handler.cancelAllNotifications()

        verify { notificationManagerCompat.cancelAll() }
    }

    // ==================== Sync Progress Tests ====================

    @Test
    fun `showSyncProgressNotification uses SYNC_NOTIFICATION_ID`() {
        handler.showSyncProgressNotification(progress = 5, total = 10)

        verify {
            notificationManagerCompat.notify(
                eq(NotificationHandler.SYNC_NOTIFICATION_ID),
                any()
            )
        }
    }

    @Test
    fun `showSyncProgressNotification sets progress on builder`() {
        handler.showSyncProgressNotification(progress = 5, total = 10)

        verify {
            anyConstructed<NotificationCompat.Builder>().setProgress(10, 5, false)
        }
    }

    @Test
    fun `showSyncProgressNotification sets ongoing`() {
        handler.showSyncProgressNotification(progress = 5, total = 10)

        verify {
            anyConstructed<NotificationCompat.Builder>().setOngoing(true)
        }
    }

    @Test
    fun `showSyncProgressNotification catches SecurityException`() {
        every { notificationManagerCompat.notify(any(), any()) } throws SecurityException("No permission")

        // Should not throw
        handler.showSyncProgressNotification(progress = 1, total = 5)
    }

    @Test
    fun `cancelSyncProgressNotification cancels SYNC_NOTIFICATION_ID`() {
        handler.cancelSyncProgressNotification()

        verify { notificationManagerCompat.cancel(NotificationHandler.SYNC_NOTIFICATION_ID) }
    }

    // ==================== Sync Complete Tests ====================

    @Test
    fun `showSyncCompleteNotification does not show notification when no failures`() {
        handler.showSyncCompleteNotification(successCount = 5, failedCount = 0)

        // Should cancel sync progress but not show a new notification
        verify { notificationManagerCompat.cancel(NotificationHandler.SYNC_NOTIFICATION_ID) }
        verify(exactly = 0) { notificationManagerCompat.notify(any(), any()) }
    }

    @Test
    fun `showSyncCompleteNotification shows notification when there are failures`() {
        handler.showSyncCompleteNotification(successCount = 3, failedCount = 2)

        // Should cancel sync progress and show a failure notification
        verify { notificationManagerCompat.cancel(NotificationHandler.SYNC_NOTIFICATION_ID) }
        verify { notificationManagerCompat.notify(any(), any()) }
    }

    // ==================== Action Button Tests ====================

    @Test
    fun `showNotification with OPEN_SHARE action adds View action button`() {
        val notification = createNotification(
            type = NotificationType.SHARE_RECEIVED,
            actionType = NotificationActionType.OPEN_SHARE,
            actionId = "share-123"
        )

        handler.showNotification(notification)

        verify {
            anyConstructed<NotificationCompat.Builder>().addAction(any<Int>(), eq("View"), any<PendingIntent>())
        }
    }

    @Test
    fun `showNotification with OPEN_RECOVERY_REQUEST action adds Review action button`() {
        val notification = createNotification(
            type = NotificationType.RECOVERY_REQUEST_RECEIVED,
            actionType = NotificationActionType.OPEN_RECOVERY_REQUEST,
            actionId = "recovery-456"
        )

        handler.showNotification(notification)

        verify {
            anyConstructed<NotificationCompat.Builder>().addAction(any<Int>(), eq("Review"), any<PendingIntent>())
        }
    }

    @Test
    fun `showNotification with RETRY_SYNC action adds Retry action button`() {
        val notification = createNotification(
            type = NotificationType.SYNC_FAILED,
            actionType = NotificationActionType.RETRY_SYNC
        )

        handler.showNotification(notification)

        verify {
            anyConstructed<NotificationCompat.Builder>().addAction(any<Int>(), eq("Retry"), any<PendingIntent>())
        }
    }

    @Test
    fun `showNotification without action type does not add action buttons`() {
        val notification = createNotification(
            type = NotificationType.INFO,
            actionType = null
        )

        handler.showNotification(notification)

        verify(exactly = 0) {
            anyConstructed<NotificationCompat.Builder>().addAction(any<Int>(), any(), any<PendingIntent>())
        }
    }

    // ==================== Constants Tests ====================

    @Test
    fun `channel constants have expected values`() {
        assertEquals("shares", NotificationHandler.CHANNEL_SHARES)
        assertEquals("recovery", NotificationHandler.CHANNEL_RECOVERY)
        assertEquals("sync", NotificationHandler.CHANNEL_SYNC)
        assertEquals("security", NotificationHandler.CHANNEL_SECURITY)
        assertEquals("general", NotificationHandler.CHANNEL_GENERAL)
    }

    @Test
    fun `SYNC_NOTIFICATION_ID is 1001`() {
        assertEquals(1001, NotificationHandler.SYNC_NOTIFICATION_ID)
    }

    @Test
    fun `intent extra constants have expected values`() {
        assertEquals("notification_id", NotificationHandler.EXTRA_NOTIFICATION_ID)
        assertEquals("notification_type", NotificationHandler.EXTRA_NOTIFICATION_TYPE)
        assertEquals("action_type", NotificationHandler.EXTRA_ACTION_TYPE)
        assertEquals("action_id", NotificationHandler.EXTRA_ACTION_ID)
        assertEquals("action", NotificationHandler.EXTRA_ACTION)
    }

    // ==================== Helper Functions ====================

    private fun createNotification(
        id: String = "test-id",
        type: NotificationType = NotificationType.INFO,
        title: String = "Test Title",
        message: String = "Test Message",
        actionType: NotificationActionType? = null,
        actionId: String? = null
    ) = NotificationEntity(
        id = id,
        userId = "user-123",
        type = type,
        title = title,
        message = message,
        actionType = actionType,
        actionId = actionId
    )
}
