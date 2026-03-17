import XCTest
import Combine
@testable import SsdidDrive

/// Unit tests for NotificationListViewModel — loading, marking as read,
/// badge count updates, and section grouping.
@MainActor
final class NotificationViewModelTests: XCTestCase {

    // MARK: - Properties

    var viewModel: NotificationListViewModel!
    var mockRepository: MockNotificationRepository!
    var cancellables: Set<AnyCancellable>!

    // MARK: - Test Data

    private func makeNotification(
        id: String = UUID().uuidString,
        type: NotificationType = .info,
        title: String = "Test",
        message: String = "Test message",
        isRead: Bool = false,
        createdAt: Date = Date()
    ) -> AppNotification {
        AppNotification(
            id: id,
            type: type,
            title: title,
            message: message,
            isRead: isRead,
            createdAt: createdAt
        )
    }

    // MARK: - Setup

    override func setUp() {
        super.setUp()
        mockRepository = MockNotificationRepository()
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() {
        viewModel = nil
        mockRepository = nil
        cancellables = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func waitForRunLoop(seconds: TimeInterval = 0.5) {
        let expectation = expectation(description: "RunLoop wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: seconds + 1.0)
    }

    private func createViewModelWithNotifications(_ notifications: [AppNotification], unreadCount: Int? = nil) {
        mockRepository.stubbedNotifications = notifications
        mockRepository.stubbedUnreadCount = unreadCount ?? notifications.filter { $0.isUnread }.count
        viewModel = NotificationListViewModel(notificationRepository: mockRepository)
        // Emit initial state so the publishers deliver data
        mockRepository.emitCurrentState()
        waitForRunLoop(seconds: 0.3)
    }

    // MARK: - Load Notifications Tests

    func testLoadNotifications_emitsFromPublisher() {
        // Given
        let notifications = [
            makeNotification(id: "n1", title: "Share received", message: "User shared a file"),
            makeNotification(id: "n2", title: "File uploaded", message: "Upload complete"),
        ]

        // When
        createViewModelWithNotifications(notifications)

        // Then — sections should be populated (all are "today" since default createdAt is now)
        XCTAssertFalse(viewModel.isEmpty)
        XCTAssertEqual(viewModel.totalCount, 2)
    }

    func testLoadNotifications_emptyList_setsIsEmpty() {
        // When
        createViewModelWithNotifications([])

        // Then
        XCTAssertTrue(viewModel.isEmpty)
        XCTAssertTrue(viewModel.sections.isEmpty)
        XCTAssertEqual(viewModel.totalCount, 0)
    }

    func testLoadNotifications_groupsByDate_today() {
        // Given — notifications created now (today)
        let notifications = [
            makeNotification(id: "n1", title: "Today 1"),
            makeNotification(id: "n2", title: "Today 2"),
        ]

        // When
        createViewModelWithNotifications(notifications)

        // Then
        XCTAssertEqual(viewModel.sections.count, 1)
        XCTAssertEqual(viewModel.sections.first?.notifications.count, 2)
    }

    func testLoadNotifications_groupsByDate_todayAndYesterday() {
        // Given
        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!

        let notifications = [
            makeNotification(id: "n1", title: "Today", createdAt: today),
            makeNotification(id: "n2", title: "Yesterday", createdAt: yesterday),
        ]

        // When
        createViewModelWithNotifications(notifications)

        // Then
        XCTAssertEqual(viewModel.sections.count, 2)
    }

    func testLoadNotifications_groupsByDate_earlier() {
        // Given — notification from a week ago
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!

        let notifications = [
            makeNotification(id: "n1", title: "Old", createdAt: weekAgo),
        ]

        // When
        createViewModelWithNotifications(notifications)

        // Then — should be in "Earlier" section
        XCTAssertEqual(viewModel.sections.count, 1)
        XCTAssertTrue(viewModel.sections.first?.title.contains("Earlier") ?? false)
    }

    // MARK: - Mark as Read Tests

    func testMarkAsRead_unreadNotification_callsRepository() {
        // Given
        let notification = makeNotification(id: "n1", isRead: false)
        createViewModelWithNotifications([notification], unreadCount: 1)

        // When
        viewModel.markAsRead(notification)
        waitForRunLoop(seconds: 0.5)

        // Then
        XCTAssertEqual(mockRepository.markAsReadCallCount, 1)
        XCTAssertEqual(mockRepository.lastMarkedAsReadId, "n1")
    }

    func testMarkAsRead_alreadyReadNotification_doesNotCallRepository() {
        // Given
        let notification = makeNotification(id: "n1", isRead: true)
        createViewModelWithNotifications([notification], unreadCount: 0)

        // When
        viewModel.markAsRead(notification)
        waitForRunLoop(seconds: 0.3)

        // Then — guard clause should prevent the call
        XCTAssertEqual(mockRepository.markAsReadCallCount, 0)
    }

    func testMarkAllAsRead_callsRepository() {
        // Given
        let notifications = [
            makeNotification(id: "n1", isRead: false),
            makeNotification(id: "n2", isRead: false),
        ]
        createViewModelWithNotifications(notifications, unreadCount: 2)

        // When
        viewModel.markAllAsRead()
        waitForRunLoop(seconds: 0.5)

        // Then
        XCTAssertEqual(mockRepository.markAllAsReadCallCount, 1)
    }

    // MARK: - Badge Count Tests

    func testUnreadCount_reflectsPublisher() {
        // Given
        let notifications = [
            makeNotification(id: "n1", isRead: false),
            makeNotification(id: "n2", isRead: false),
            makeNotification(id: "n3", isRead: true),
        ]

        // When
        createViewModelWithNotifications(notifications, unreadCount: 2)

        // Then
        XCTAssertEqual(viewModel.unreadCount, 2)
        XCTAssertTrue(viewModel.hasUnread)
    }

    func testUnreadCount_zero_hasUnreadIsFalse() {
        // Given
        let notifications = [
            makeNotification(id: "n1", isRead: true),
        ]

        // When
        createViewModelWithNotifications(notifications, unreadCount: 0)

        // Then
        XCTAssertEqual(viewModel.unreadCount, 0)
        XCTAssertFalse(viewModel.hasUnread)
    }

    func testUnreadCount_updatesWhenNotificationMarkedAsRead() {
        // Given
        let notification = makeNotification(id: "n1", isRead: false)
        createViewModelWithNotifications([notification], unreadCount: 1)

        XCTAssertEqual(viewModel.unreadCount, 1)

        // When — mark as read triggers repository which updates publisher
        viewModel.markAsRead(notification)
        waitForRunLoop(seconds: 0.5)

        // Then — the mock repository updates the publisher
        XCTAssertEqual(viewModel.unreadCount, 0)
    }

    // MARK: - Delete Tests

    func testDeleteNotification_callsRepository() {
        // Given
        let notification = makeNotification(id: "n1")
        createViewModelWithNotifications([notification])

        // When
        viewModel.deleteNotification(notification)
        waitForRunLoop(seconds: 0.5)

        // Then
        XCTAssertEqual(mockRepository.deleteNotificationCallCount, 1)
        XCTAssertEqual(mockRepository.lastDeletedNotificationId, "n1")
    }

    func testDeleteAllNotifications_callsRepository() {
        // Given
        let notifications = [
            makeNotification(id: "n1"),
            makeNotification(id: "n2"),
        ]
        createViewModelWithNotifications(notifications)

        // When
        viewModel.deleteAllNotifications()
        waitForRunLoop(seconds: 0.5)

        // Then
        XCTAssertEqual(mockRepository.deleteAllNotificationsCallCount, 1)
    }

    // MARK: - Refresh Tests

    func testRefreshNotifications_setsIsRefreshing() {
        // Given
        createViewModelWithNotifications([])

        // When
        viewModel.refreshNotifications()

        // Then — isRefreshing should be set immediately
        XCTAssertTrue(viewModel.isRefreshing)
    }

    func testRefreshNotifications_callsGetNotifications() {
        // Given
        createViewModelWithNotifications([])

        // When
        viewModel.refreshNotifications()
        waitForRunLoop(seconds: 0.5)

        // Then
        XCTAssertEqual(mockRepository.getNotificationsCallCount, 1)
        XCTAssertFalse(viewModel.isRefreshing)
    }

    func testRefreshNotifications_failure_setsError() {
        // Given
        createViewModelWithNotifications([])
        mockRepository.shouldFailOnGetNotifications = true

        // When
        viewModel.refreshNotifications()
        waitForRunLoop(seconds: 0.5)

        // Then
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isRefreshing)
    }

    // MARK: - Select Notification Tests

    func testSelectNotification_marksAsReadAndNotifiesDelegate() {
        // Given
        let notification = makeNotification(id: "n1", isRead: false)
        createViewModelWithNotifications([notification], unreadCount: 1)

        final class MockDelegate: NotificationListViewModelCoordinatorDelegate {
            var selectedNotification: AppNotification?
            func notificationListDidSelectNotification(_ notification: AppNotification) {
                selectedNotification = notification
            }
        }

        let delegate = MockDelegate()
        viewModel.coordinatorDelegate = delegate

        // When
        viewModel.selectNotification(notification)
        waitForRunLoop(seconds: 0.5)

        // Then
        XCTAssertEqual(delegate.selectedNotification?.id, "n1")
        XCTAssertEqual(mockRepository.markAsReadCallCount, 1)
    }

    func testSelectNotification_alreadyRead_doesNotMarkAgain() {
        // Given
        let notification = makeNotification(id: "n1", isRead: true)
        createViewModelWithNotifications([notification], unreadCount: 0)

        // When
        viewModel.selectNotification(notification)
        waitForRunLoop(seconds: 0.3)

        // Then — should NOT call markAsRead since it's already read
        XCTAssertEqual(mockRepository.markAsReadCallCount, 0)
    }

    // MARK: - Computed Properties Tests

    func testTotalCount_sumsAcrossSections() {
        // Given
        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!

        let notifications = [
            makeNotification(id: "n1", createdAt: today),
            makeNotification(id: "n2", createdAt: today),
            makeNotification(id: "n3", createdAt: yesterday),
        ]

        // When
        createViewModelWithNotifications(notifications)

        // Then
        XCTAssertEqual(viewModel.totalCount, 3)
    }
}
