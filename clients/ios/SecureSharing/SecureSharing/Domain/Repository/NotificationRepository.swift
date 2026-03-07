import Foundation
import Combine

/// Repository protocol for notification operations.
///
/// Provides local storage and read tracking for in-app notifications.
/// All operations are scoped to the current authenticated user.
protocol NotificationRepository {

    // MARK: - Read Status

    /// Mark a single notification as read
    /// - Parameter notificationId: ID of the notification to mark as read
    func markAsRead(notificationId: String) async throws

    /// Mark all notifications as read for the current user
    func markAllAsRead() async throws

    // MARK: - Queries

    /// Get current unread notification count
    /// - Returns: Number of unread notifications
    func getUnreadCount() async -> Int

    /// Get all notifications for the current user
    /// - Returns: Array of notifications sorted by creation date (newest first)
    func getNotifications() async throws -> [AppNotification]

    /// Get unread notifications for the current user
    /// - Returns: Array of unread notifications sorted by creation date (newest first)
    func getUnreadNotifications() async throws -> [AppNotification]

    // MARK: - Reactive Streams

    /// Observe unread count changes
    /// - Returns: Publisher that emits the current unread count whenever it changes
    func observeUnreadCount() -> AnyPublisher<Int, Never>

    /// Observe notification list changes
    /// - Returns: Publisher that emits the notification list whenever it changes
    func observeNotifications() -> AnyPublisher<[AppNotification], Never>

    // MARK: - Mutations

    /// Save a new notification (typically from push notification)
    /// - Parameter notification: The notification to save
    func saveNotification(_ notification: AppNotification) async throws

    /// Save multiple notifications at once
    /// - Parameter notifications: Array of notifications to save
    func saveNotifications(_ notifications: [AppNotification]) async throws

    /// Delete a notification
    /// - Parameter notificationId: ID of the notification to delete
    func deleteNotification(notificationId: String) async throws

    /// Delete all notifications for the current user
    func deleteAllNotifications() async throws

    /// Cleanup old read notifications
    /// - Parameter daysOld: Delete read notifications older than this many days (default: 30)
    func cleanupOldNotifications(daysOld: Int) async throws

    // MARK: - Badge Management

    /// Update the app icon badge count to match unread notifications
    func updateAppBadge() async
}

// MARK: - Default Implementations

extension NotificationRepository {

    /// Cleanup old read notifications with default 30 day threshold
    func cleanupOldNotifications() async throws {
        try await cleanupOldNotifications(daysOld: 30)
    }
}
