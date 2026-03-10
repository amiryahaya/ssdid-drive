package my.ssdid.drive.presentation.notifications

import app.cash.turbine.test
import my.ssdid.drive.domain.model.Notification
import my.ssdid.drive.domain.model.NotificationAction
import my.ssdid.drive.domain.model.NotificationActionType
import my.ssdid.drive.domain.model.NotificationType
import my.ssdid.drive.domain.repository.NotificationRepository
import my.ssdid.drive.util.AppException
import my.ssdid.drive.util.Result
import io.mockk.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import java.time.Instant

/**
 * Unit tests for NotificationViewModel.
 *
 * Tests cover:
 * - Loading notifications
 * - Marking as read / mark all as read
 * - Deleting notifications
 * - Unread count observation
 * - Filtering
 * - Navigation event handling
 * - Error handling
 */
@OptIn(ExperimentalCoroutinesApi::class)
class NotificationViewModelTest {

    private lateinit var notificationRepository: NotificationRepository
    private lateinit var viewModel: NotificationViewModel
    private val testDispatcher = StandardTestDispatcher()

    private val now = Instant.now()

    private val shareNotification = Notification(
        id = "notif-1",
        type = NotificationType.SHARE_RECEIVED,
        title = "New share",
        message = "Alice shared a file with you",
        isRead = false,
        action = NotificationAction(
            type = NotificationActionType.OPEN_SHARE,
            resourceId = "share-123"
        ),
        createdAt = now
    )

    private val recoveryNotification = Notification(
        id = "notif-2",
        type = NotificationType.RECOVERY_REQUEST_RECEIVED,
        title = "Recovery request",
        message = "Bob needs recovery help",
        isRead = false,
        action = NotificationAction(
            type = NotificationActionType.OPEN_RECOVERY_REQUEST,
            resourceId = "request-456"
        ),
        createdAt = now.minusSeconds(3600)
    )

    private val systemNotification = Notification(
        id = "notif-3",
        type = NotificationType.SYNC_COMPLETED,
        title = "Sync complete",
        message = "All files synced",
        isRead = true,
        action = null,
        createdAt = now.minusSeconds(7200)
    )

    private val readNotification = Notification(
        id = "notif-4",
        type = NotificationType.FILE_UPLOADED,
        title = "File uploaded",
        message = "document.pdf uploaded",
        isRead = true,
        action = NotificationAction(
            type = NotificationActionType.OPEN_FILE,
            resourceId = "file-789"
        ),
        createdAt = now.minusSeconds(10800)
    )

    private val allNotifications = listOf(
        shareNotification, recoveryNotification, systemNotification, readNotification
    )

    @Before
    fun setup() {
        Dispatchers.setMain(testDispatcher)
        notificationRepository = mockk(relaxed = true)

        // Default stubs
        coEvery { notificationRepository.getNotifications() } returns Result.success(allNotifications)
        every { notificationRepository.observeRecentNotifications(100) } returns flowOf(allNotifications)
        every { notificationRepository.observeUnreadCount() } returns flowOf(2)
    }

    private fun createViewModel(): NotificationViewModel {
        return NotificationViewModel(notificationRepository)
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    // ==================== Loading Tests ====================

    @Test
    fun `loadNotifications sets notifications on success`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals(4, state.notifications.size)
            assertFalse(state.isLoading)
            assertNull(state.error)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `loadNotifications sets error on failure`() = runTest {
        coEvery { notificationRepository.getNotifications() } returns Result.error(
            AppException.Network("Connection failed")
        )
        every { notificationRepository.observeRecentNotifications(100) } returns flowOf(emptyList())

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals("Connection failed", state.error)
            assertFalse(state.isLoading)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `loadNotifications can be called manually to refresh`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.loadNotifications()
        advanceUntilIdle()

        coVerify(atLeast = 2) { notificationRepository.getNotifications() }
    }

    // ==================== Unread Count Tests ====================

    @Test
    fun `unreadCount observes repository`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.unreadCount.test {
            // Initial value from stateIn may be 0; skip to the upstream-emitted value
            var count = awaitItem()
            if (count == 0) {
                count = awaitItem()
            }
            assertEquals(2, count)
            cancelAndIgnoreRemainingEvents()
        }
    }

    // ==================== Mark As Read Tests ====================

    @Test
    fun `markAsRead calls repository`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.markAsRead("notif-1")
        advanceUntilIdle()

        coVerify { notificationRepository.markAsRead("notif-1") }
    }

    @Test
    fun `markAllAsRead calls repository`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.markAllAsRead()
        advanceUntilIdle()

        coVerify { notificationRepository.markAllAsRead() }
    }

    // ==================== Delete Tests ====================

    @Test
    fun `deleteNotification calls repository`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.deleteNotification("notif-1")
        advanceUntilIdle()

        coVerify { notificationRepository.deleteNotification("notif-1") }
    }

    @Test
    fun `deleteAllNotifications calls repository`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.deleteAllNotifications()
        advanceUntilIdle()

        coVerify { notificationRepository.deleteAllNotifications() }
    }

    // ==================== Filter Tests ====================

    @Test
    fun `setFilter UNREAD filters to unread notifications only`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.setFilter(NotificationFilter.UNREAD)
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals(NotificationFilter.UNREAD, state.selectedFilter)
            assertTrue(state.notifications.all { it.isUnread })
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `setFilter SHARES filters to share notifications`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.setFilter(NotificationFilter.SHARES)
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals(NotificationFilter.SHARES, state.selectedFilter)
            // SHARE_RECEIVED and FILE_UPLOADED should match
            assertTrue(state.notifications.all {
                it.type.name.contains("SHARE") || it.type.name.contains("FILE") || it.type.name.contains("FOLDER")
            })
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `setFilter RECOVERY filters to recovery notifications`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.setFilter(NotificationFilter.RECOVERY)
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals(NotificationFilter.RECOVERY, state.selectedFilter)
            assertTrue(state.notifications.all { it.type.name.contains("RECOVERY") })
            assertEquals(1, state.notifications.size)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `setFilter SYSTEM filters to system notifications`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.setFilter(NotificationFilter.SYSTEM)
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals(NotificationFilter.SYSTEM, state.selectedFilter)
            assertTrue(state.notifications.all {
                it.type.name.contains("SYNC") || it.type.name.contains("STORAGE") ||
                it.type.name.contains("SECURITY") || it.type.name == "INFO" ||
                it.type.name == "WARNING" || it.type.name == "ERROR"
            })
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `setFilter ALL shows all notifications`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.setFilter(NotificationFilter.UNREAD)
        advanceUntilIdle()

        viewModel.setFilter(NotificationFilter.ALL)
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals(NotificationFilter.ALL, state.selectedFilter)
            assertEquals(4, state.notifications.size)
            cancelAndIgnoreRemainingEvents()
        }
    }

    // ==================== Navigation Event Tests ====================

    @Test
    fun `handleNotificationClick marks as read and sets OPEN_SHARE event`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.handleNotificationClick(shareNotification)
        advanceUntilIdle()

        coVerify { notificationRepository.markAsRead("notif-1") }

        viewModel.uiState.test {
            val state = awaitItem()
            assertTrue(state.navigationEvent is NavigationEvent.OpenShare)
            assertEquals("share-123", (state.navigationEvent as NavigationEvent.OpenShare).shareId)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `handleNotificationClick sets OPEN_RECOVERY_REQUEST event`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.handleNotificationClick(recoveryNotification)
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertTrue(state.navigationEvent is NavigationEvent.OpenRecoveryRequest)
            assertEquals(
                "request-456",
                (state.navigationEvent as NavigationEvent.OpenRecoveryRequest).requestId
            )
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `handleNotificationClick sets OPEN_FILE event`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.handleNotificationClick(readNotification)
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertTrue(state.navigationEvent is NavigationEvent.OpenFile)
            assertEquals("file-789", (state.navigationEvent as NavigationEvent.OpenFile).fileId)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `handleNotificationClick with OPEN_SETTINGS action`() = runTest {
        val settingsNotification = Notification(
            id = "notif-5",
            type = NotificationType.SECURITY_ALERT,
            title = "Security update",
            message = "Check settings",
            isRead = false,
            action = NotificationAction(
                type = NotificationActionType.OPEN_SETTINGS,
                resourceId = null
            ),
            createdAt = now
        )

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.handleNotificationClick(settingsNotification)
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertTrue(state.navigationEvent is NavigationEvent.OpenSettings)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `handleNotificationClick with no action does not set navigation event`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.handleNotificationClick(systemNotification)
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertNull(state.navigationEvent)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `clearNavigationEvent clears event`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.handleNotificationClick(shareNotification)
        advanceUntilIdle()

        viewModel.clearNavigationEvent()

        viewModel.uiState.test {
            val state = awaitItem()
            assertNull(state.navigationEvent)
            cancelAndIgnoreRemainingEvents()
        }
    }

    // ==================== Error Handling Tests ====================

    @Test
    fun `setFilter with failed getNotifications returns empty list`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        // Make getNotifications fail for the setFilter call
        coEvery { notificationRepository.getNotifications() } returns Result.error(
            AppException.Unknown("Failed")
        )

        viewModel.setFilter(NotificationFilter.UNREAD)
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals(NotificationFilter.UNREAD, state.selectedFilter)
            assertTrue(state.notifications.isEmpty())
            cancelAndIgnoreRemainingEvents()
        }
    }
}
