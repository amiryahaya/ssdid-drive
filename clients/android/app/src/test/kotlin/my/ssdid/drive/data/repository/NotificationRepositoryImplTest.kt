package my.ssdid.drive.data.repository

import my.ssdid.drive.data.local.SecureStorage
import my.ssdid.drive.data.local.dao.NotificationDao
import my.ssdid.drive.data.local.entity.NotificationActionType
import my.ssdid.drive.data.local.entity.NotificationEntity
import my.ssdid.drive.data.local.entity.NotificationType as EntityNotificationType
import my.ssdid.drive.domain.model.NotificationActionType as DomainActionType
import my.ssdid.drive.domain.model.NotificationType
import my.ssdid.drive.service.NotificationHandler
import my.ssdid.drive.util.AppException
import my.ssdid.drive.util.Result
import app.cash.turbine.test
import io.mockk.*
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import java.time.Instant

/**
 * Unit tests for NotificationRepositoryImpl.
 *
 * Tests cover:
 * - getNotifications
 * - observeNotifications / observeRecentNotifications
 * - getUnreadNotifications / getUnreadCount
 * - markAsRead / markAllAsRead
 * - deleteNotification / deleteAllNotifications
 * - cleanupOldNotifications
 * - createLocalNotification
 * - Entity-to-domain mapping
 * - Error handling
 */
@OptIn(ExperimentalCoroutinesApi::class)
class NotificationRepositoryImplTest {

    private lateinit var notificationDao: NotificationDao
    private lateinit var secureStorage: SecureStorage
    private lateinit var notificationHandler: NotificationHandler
    private lateinit var repository: NotificationRepositoryImpl

    private val testUserId = "user-123"

    @Before
    fun setup() {
        notificationDao = mockk()
        secureStorage = mockk(relaxed = true)
        notificationHandler = mockk(relaxed = true)

        every { secureStorage.getUserIdSync() } returns testUserId

        repository = NotificationRepositoryImpl(
            notificationDao = notificationDao,
            secureStorage = secureStorage,
            notificationHandler = notificationHandler
        )
    }

    @After
    fun tearDown() {
        unmockkAll()
    }

    // ==================== getNotifications Tests ====================

    @Test
    fun `getNotifications returns mapped notifications on success`() = runTest {
        val entities = listOf(
            createTestEntity(id = "n1", title = "Share received"),
            createTestEntity(id = "n2", title = "File uploaded", type = EntityNotificationType.FILE_UPLOADED)
        )
        coEvery { notificationDao.getAll(testUserId) } returns entities

        val result = repository.getNotifications()

        assertTrue(result is Result.Success)
        val notifications = (result as Result.Success).data
        assertEquals(2, notifications.size)
        assertEquals("n1", notifications[0].id)
        assertEquals("Share received", notifications[0].title)
        assertEquals(NotificationType.FILE_UPLOADED, notifications[1].type)
    }

    @Test
    fun `getNotifications returns empty list when no notifications`() = runTest {
        coEvery { notificationDao.getAll(testUserId) } returns emptyList()

        val result = repository.getNotifications()

        assertTrue(result is Result.Success)
        assertEquals(0, (result as Result.Success).data.size)
    }

    @Test
    fun `getNotifications returns error on exception`() = runTest {
        coEvery { notificationDao.getAll(testUserId) } throws RuntimeException("DB error")

        val result = repository.getNotifications()

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Unknown)
        assertTrue(error.message.contains("Failed to get notifications"))
    }

    // ==================== observeNotifications Tests ====================

    @Test
    fun `observeNotifications emits mapped notifications`() = runTest {
        val entities = listOf(createTestEntity(id = "n1", title = "Test"))
        every { notificationDao.observeAll(testUserId) } returns flowOf(entities)

        repository.observeNotifications().test {
            val notifications = awaitItem()
            assertEquals(1, notifications.size)
            assertEquals("n1", notifications[0].id)
            assertEquals("Test", notifications[0].title)
            awaitComplete()
        }
    }

    @Test
    fun `observeNotifications emits empty list when no notifications`() = runTest {
        every { notificationDao.observeAll(testUserId) } returns flowOf(emptyList())

        repository.observeNotifications().test {
            val notifications = awaitItem()
            assertTrue(notifications.isEmpty())
            awaitComplete()
        }
    }

    // ==================== observeRecentNotifications Tests ====================

    @Test
    fun `observeRecentNotifications passes limit to dao`() = runTest {
        val entities = listOf(createTestEntity())
        every { notificationDao.observeRecent(testUserId, 10) } returns flowOf(entities)

        repository.observeRecentNotifications(10).test {
            val notifications = awaitItem()
            assertEquals(1, notifications.size)
            awaitComplete()
        }

        verify { notificationDao.observeRecent(testUserId, 10) }
    }

    // ==================== getUnreadNotifications Tests ====================

    @Test
    fun `getUnreadNotifications returns unread notifications`() = runTest {
        val entities = listOf(
            createTestEntity(id = "n1", isRead = false),
            createTestEntity(id = "n2", isRead = false)
        )
        coEvery { notificationDao.getUnread(testUserId) } returns entities

        val result = repository.getUnreadNotifications()

        assertTrue(result is Result.Success)
        val notifications = (result as Result.Success).data
        assertEquals(2, notifications.size)
        assertTrue(notifications.all { !it.isRead })
    }

    @Test
    fun `getUnreadNotifications returns error on exception`() = runTest {
        coEvery { notificationDao.getUnread(testUserId) } throws RuntimeException("DB error")

        val result = repository.getUnreadNotifications()

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Unknown)
    }

    // ==================== getUnreadCount Tests ====================

    @Test
    fun `getUnreadCount returns count from dao`() = runTest {
        coEvery { notificationDao.getUnreadCount(testUserId) } returns 5

        val count = repository.getUnreadCount()

        assertEquals(5, count)
    }

    @Test
    fun `getUnreadCount returns 0 on exception`() = runTest {
        coEvery { notificationDao.getUnreadCount(testUserId) } throws RuntimeException("DB error")

        val count = repository.getUnreadCount()

        assertEquals(0, count)
    }

    // ==================== observeUnreadCount Tests ====================

    @Test
    fun `observeUnreadCount emits count from dao`() = runTest {
        every { notificationDao.observeUnreadCount(testUserId) } returns flowOf(3)

        repository.observeUnreadCount().test {
            assertEquals(3, awaitItem())
            awaitComplete()
        }
    }

    // ==================== observeUnreadNotifications Tests ====================

    @Test
    fun `observeUnreadNotifications emits unread notifications`() = runTest {
        val entities = listOf(createTestEntity(isRead = false))
        every { notificationDao.observeUnread(testUserId) } returns flowOf(entities)

        repository.observeUnreadNotifications().test {
            val notifications = awaitItem()
            assertEquals(1, notifications.size)
            assertFalse(notifications[0].isRead)
            awaitComplete()
        }
    }

    // ==================== markAsRead Tests ====================

    @Test
    fun `markAsRead calls dao and returns success`() = runTest {
        coEvery { notificationDao.markAsRead("n1") } just Runs

        val result = repository.markAsRead("n1")

        assertTrue(result is Result.Success)
        coVerify { notificationDao.markAsRead("n1") }
    }

    @Test
    fun `markAsRead returns error on exception`() = runTest {
        coEvery { notificationDao.markAsRead("n1") } throws RuntimeException("DB error")

        val result = repository.markAsRead("n1")

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Unknown)
        assertTrue(error.message.contains("Failed to mark notification as read"))
    }

    // ==================== markAllAsRead Tests ====================

    @Test
    fun `markAllAsRead calls dao with userId and returns success`() = runTest {
        coEvery { notificationDao.markAllAsRead(testUserId) } just Runs

        val result = repository.markAllAsRead()

        assertTrue(result is Result.Success)
        coVerify { notificationDao.markAllAsRead(testUserId) }
    }

    @Test
    fun `markAllAsRead returns error on exception`() = runTest {
        coEvery { notificationDao.markAllAsRead(testUserId) } throws RuntimeException("DB error")

        val result = repository.markAllAsRead()

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Unknown)
    }

    // ==================== deleteNotification Tests ====================

    @Test
    fun `deleteNotification deletes from dao and cancels system notification`() = runTest {
        coEvery { notificationDao.deleteById("n1") } just Runs

        val result = repository.deleteNotification("n1")

        assertTrue(result is Result.Success)
        coVerify { notificationDao.deleteById("n1") }
        verify { notificationHandler.cancelNotification("n1") }
    }

    @Test
    fun `deleteNotification returns error on exception`() = runTest {
        coEvery { notificationDao.deleteById("n1") } throws RuntimeException("DB error")

        val result = repository.deleteNotification("n1")

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Unknown)
        assertTrue(error.message.contains("Failed to delete notification"))
    }

    // ==================== deleteAllNotifications Tests ====================

    @Test
    fun `deleteAllNotifications deletes from dao and cancels all system notifications`() = runTest {
        coEvery { notificationDao.deleteAll(testUserId) } just Runs

        val result = repository.deleteAllNotifications()

        assertTrue(result is Result.Success)
        coVerify { notificationDao.deleteAll(testUserId) }
        verify { notificationHandler.cancelAllNotifications() }
    }

    @Test
    fun `deleteAllNotifications returns error on exception`() = runTest {
        coEvery { notificationDao.deleteAll(testUserId) } throws RuntimeException("DB error")

        val result = repository.deleteAllNotifications()

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Unknown)
    }

    // ==================== cleanupOldNotifications Tests ====================

    @Test
    fun `cleanupOldNotifications calls dao with correct cutoff`() = runTest {
        coEvery { notificationDao.deleteOldReadNotifications(testUserId, any()) } just Runs

        val result = repository.cleanupOldNotifications(30)

        assertTrue(result is Result.Success)
        coVerify {
            notificationDao.deleteOldReadNotifications(testUserId, match { cutoff ->
                // Cutoff should be approximately 30 days ago
                val expectedSeconds = 30L * 24 * 60 * 60
                val nowEpoch = Instant.now().epochSecond
                val cutoffEpoch = cutoff.epochSecond
                val diff = nowEpoch - cutoffEpoch
                diff in (expectedSeconds - 5)..(expectedSeconds + 5)
            })
        }
    }

    @Test
    fun `cleanupOldNotifications returns error on exception`() = runTest {
        coEvery {
            notificationDao.deleteOldReadNotifications(testUserId, any())
        } throws RuntimeException("DB error")

        val result = repository.cleanupOldNotifications(7)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Unknown)
    }

    // ==================== createLocalNotification Tests ====================

    @Test
    fun `createLocalNotification inserts entity and shows system notification`() = runTest {
        coEvery { notificationDao.insert(any()) } just Runs

        val result = repository.createLocalNotification(
            type = NotificationType.SHARE_RECEIVED,
            title = "New share",
            message = "User shared a file with you",
            actionType = "OPEN_SHARE",
            actionId = "share-123"
        )

        assertTrue(result is Result.Success)
        val notification = (result as Result.Success).data
        assertEquals("New share", notification.title)
        assertEquals("User shared a file with you", notification.message)
        assertEquals(NotificationType.SHARE_RECEIVED, notification.type)
        assertNotNull(notification.action)
        assertEquals(DomainActionType.OPEN_SHARE, notification.action!!.type)
        assertEquals("share-123", notification.action!!.resourceId)

        coVerify { notificationDao.insert(any()) }
        verify { notificationHandler.showNotification(any()) }
    }

    @Test
    fun `createLocalNotification with no action type creates notification without action`() = runTest {
        coEvery { notificationDao.insert(any()) } just Runs

        val result = repository.createLocalNotification(
            type = NotificationType.INFO,
            title = "Info",
            message = "Some info message"
        )

        assertTrue(result is Result.Success)
        val notification = (result as Result.Success).data
        assertNull(notification.action)
    }

    @Test
    fun `createLocalNotification returns error on exception`() = runTest {
        coEvery { notificationDao.insert(any()) } throws RuntimeException("DB error")

        val result = repository.createLocalNotification(
            type = NotificationType.ERROR,
            title = "Error",
            message = "Something went wrong"
        )

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Unknown)
        assertTrue(error.message.contains("Failed to create notification"))
    }

    // ==================== Entity-to-Domain Mapping Tests ====================

    @Test
    fun `toDomain maps all fields correctly`() = runTest {
        val now = Instant.parse("2024-06-15T10:30:00Z")
        val entity = NotificationEntity(
            id = "n-map-test",
            userId = testUserId,
            type = EntityNotificationType.RECOVERY_REQUEST_RECEIVED,
            title = "Recovery Request",
            message = "Someone requested recovery",
            isRead = true,
            actionType = NotificationActionType.OPEN_RECOVERY_REQUEST,
            actionId = "req-456",
            createdAt = now
        )
        coEvery { notificationDao.getAll(testUserId) } returns listOf(entity)

        val result = repository.getNotifications()

        assertTrue(result is Result.Success)
        val notification = (result as Result.Success).data[0]
        assertEquals("n-map-test", notification.id)
        assertEquals(NotificationType.RECOVERY_REQUEST_RECEIVED, notification.type)
        assertEquals("Recovery Request", notification.title)
        assertEquals("Someone requested recovery", notification.message)
        assertTrue(notification.isRead)
        assertFalse(notification.isUnread)
        assertNotNull(notification.action)
        assertEquals(DomainActionType.OPEN_RECOVERY_REQUEST, notification.action!!.type)
        assertEquals("req-456", notification.action!!.resourceId)
        assertEquals(now, notification.createdAt)
    }

    @Test
    fun `toDomain maps entity without action correctly`() = runTest {
        val entity = createTestEntity(actionType = null, actionId = null)
        coEvery { notificationDao.getAll(testUserId) } returns listOf(entity)

        val result = repository.getNotifications()

        assertTrue(result is Result.Success)
        val notification = (result as Result.Success).data[0]
        assertNull(notification.action)
    }

    // ==================== getNotificationsByType Tests ====================

    @Test
    fun `getNotificationsByType returns filtered notifications`() = runTest {
        val entities = listOf(
            createTestEntity(type = EntityNotificationType.SHARE_RECEIVED)
        )
        coEvery {
            notificationDao.getByType(testUserId, EntityNotificationType.SHARE_RECEIVED)
        } returns entities

        val result = repository.getNotificationsByType(NotificationType.SHARE_RECEIVED)

        assertTrue(result is Result.Success)
        val notifications = (result as Result.Success).data
        assertEquals(1, notifications.size)
        assertEquals(NotificationType.SHARE_RECEIVED, notifications[0].type)
    }

    @Test
    fun `getNotificationsByType returns error on exception`() = runTest {
        coEvery {
            notificationDao.getByType(testUserId, any())
        } throws RuntimeException("DB error")

        val result = repository.getNotificationsByType(NotificationType.SECURITY_ALERT)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Unknown)
    }

    // ==================== userId fallback Tests ====================

    @Test
    fun `userId falls back to empty string when not set`() = runTest {
        every { secureStorage.getUserIdSync() } returns null
        coEvery { notificationDao.getAll("") } returns emptyList()

        val result = repository.getNotifications()

        assertTrue(result is Result.Success)
        coVerify { notificationDao.getAll("") }
    }

    // ==================== Helper Functions ====================

    private fun createTestEntity(
        id: String = "test-notification-id",
        title: String = "Test Notification",
        message: String = "Test message",
        type: EntityNotificationType = EntityNotificationType.SHARE_RECEIVED,
        isRead: Boolean = false,
        actionType: NotificationActionType? = NotificationActionType.OPEN_SHARE,
        actionId: String? = "resource-123",
        createdAt: Instant = Instant.now()
    ) = NotificationEntity(
        id = id,
        userId = testUserId,
        type = type,
        title = title,
        message = message,
        isRead = isRead,
        actionType = actionType,
        actionId = actionId,
        createdAt = createdAt
    )
}
