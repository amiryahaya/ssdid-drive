import Foundation
import Combine
@testable import SsdidDrive

/// Mock implementation of NotificationRepository for testing
final class MockNotificationRepository: NotificationRepository {

    // MARK: - Stub Data

    var stubbedNotifications: [AppNotification] = []
    var stubbedUnreadCount: Int = 0

    // MARK: - Publishers

    private let notificationsSubject = CurrentValueSubject<[AppNotification], Never>([])
    private let unreadCountSubject = CurrentValueSubject<Int, Never>(0)

    // MARK: - Behavior Control

    var shouldFailOnMarkAsRead = false
    var shouldFailOnMarkAllAsRead = false
    var shouldFailOnGetNotifications = false
    var shouldFailOnSave = false
    var shouldFailOnDelete = false
    var shouldFailOnDeleteAll = false
    var shouldFailOnCleanup = false

    var failureError: Error = MockError.testError("Mock error")

    // MARK: - Call Tracking

    var markAsReadCallCount = 0
    var markAllAsReadCallCount = 0
    var getNotificationsCallCount = 0
    var getUnreadNotificationsCallCount = 0
    var getUnreadCountCallCount = 0
    var saveNotificationCallCount = 0
    var saveNotificationsCallCount = 0
    var deleteNotificationCallCount = 0
    var deleteAllNotificationsCallCount = 0
    var cleanupCallCount = 0
    var updateAppBadgeCallCount = 0

    var lastMarkedAsReadId: String?
    var lastDeletedNotificationId: String?
    var lastSavedNotification: AppNotification?
    var lastCleanupDaysOld: Int?

    // MARK: - Setup

    /// Emit current stubbed state through publishers
    func emitCurrentState() {
        notificationsSubject.send(stubbedNotifications)
        unreadCountSubject.send(stubbedUnreadCount)
    }

    // MARK: - NotificationRepository Protocol

    func markAsRead(notificationId: String) async throws {
        markAsReadCallCount += 1
        lastMarkedAsReadId = notificationId

        if shouldFailOnMarkAsRead {
            throw failureError
        }

        // Update stubbed data
        if let index = stubbedNotifications.firstIndex(where: { $0.id == notificationId }) {
            let notification = stubbedNotifications[index]
            stubbedNotifications[index] = notification.markingAsRead()
            stubbedUnreadCount = stubbedNotifications.filter { $0.isUnread }.count
            emitCurrentState()
        }
    }

    func markAllAsRead() async throws {
        markAllAsReadCallCount += 1

        if shouldFailOnMarkAllAsRead {
            throw failureError
        }

        stubbedNotifications = stubbedNotifications.map { $0.markingAsRead() }
        stubbedUnreadCount = 0
        emitCurrentState()
    }

    func getUnreadCount() async -> Int {
        getUnreadCountCallCount += 1
        return stubbedUnreadCount
    }

    func getNotifications() async throws -> [AppNotification] {
        getNotificationsCallCount += 1

        if shouldFailOnGetNotifications {
            throw failureError
        }

        return stubbedNotifications
    }

    func getUnreadNotifications() async throws -> [AppNotification] {
        getUnreadNotificationsCallCount += 1
        return stubbedNotifications.filter { $0.isUnread }
    }

    func observeUnreadCount() -> AnyPublisher<Int, Never> {
        unreadCountSubject.eraseToAnyPublisher()
    }

    func observeNotifications() -> AnyPublisher<[AppNotification], Never> {
        notificationsSubject.eraseToAnyPublisher()
    }

    func saveNotification(_ notification: AppNotification) async throws {
        saveNotificationCallCount += 1
        lastSavedNotification = notification

        if shouldFailOnSave {
            throw failureError
        }

        stubbedNotifications.append(notification)
        if notification.isUnread {
            stubbedUnreadCount += 1
        }
        emitCurrentState()
    }

    func saveNotifications(_ notifications: [AppNotification]) async throws {
        saveNotificationsCallCount += 1

        if shouldFailOnSave {
            throw failureError
        }

        stubbedNotifications.append(contentsOf: notifications)
        stubbedUnreadCount = stubbedNotifications.filter { $0.isUnread }.count
        emitCurrentState()
    }

    func deleteNotification(notificationId: String) async throws {
        deleteNotificationCallCount += 1
        lastDeletedNotificationId = notificationId

        if shouldFailOnDelete {
            throw failureError
        }

        stubbedNotifications.removeAll { $0.id == notificationId }
        stubbedUnreadCount = stubbedNotifications.filter { $0.isUnread }.count
        emitCurrentState()
    }

    func deleteAllNotifications() async throws {
        deleteAllNotificationsCallCount += 1

        if shouldFailOnDeleteAll {
            throw failureError
        }

        stubbedNotifications.removeAll()
        stubbedUnreadCount = 0
        emitCurrentState()
    }

    func cleanupOldNotifications(daysOld: Int) async throws {
        cleanupCallCount += 1
        lastCleanupDaysOld = daysOld

        if shouldFailOnCleanup {
            throw failureError
        }
    }

    func updateAppBadge() async {
        updateAppBadgeCallCount += 1
    }

    // MARK: - Reset

    func reset() {
        stubbedNotifications = []
        stubbedUnreadCount = 0
        shouldFailOnMarkAsRead = false
        shouldFailOnMarkAllAsRead = false
        shouldFailOnGetNotifications = false
        shouldFailOnSave = false
        shouldFailOnDelete = false
        shouldFailOnDeleteAll = false
        shouldFailOnCleanup = false

        markAsReadCallCount = 0
        markAllAsReadCallCount = 0
        getNotificationsCallCount = 0
        getUnreadNotificationsCallCount = 0
        getUnreadCountCallCount = 0
        saveNotificationCallCount = 0
        saveNotificationsCallCount = 0
        deleteNotificationCallCount = 0
        deleteAllNotificationsCallCount = 0
        cleanupCallCount = 0
        updateAppBadgeCallCount = 0

        lastMarkedAsReadId = nil
        lastDeletedNotificationId = nil
        lastSavedNotification = nil
        lastCleanupDaysOld = nil

        emitCurrentState()
    }
}
