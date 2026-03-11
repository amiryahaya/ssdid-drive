import Foundation
import CoreData
import Combine
import UserNotifications

/// Implementation of NotificationRepository using Core Data for local storage.
final class NotificationRepositoryImpl: NotificationRepository {

    // MARK: - Properties

    private let coreDataStack: CoreDataStack
    private let authRepository: AuthRepository

    private let notificationsSubject = CurrentValueSubject<[AppNotification], Never>([])
    private let unreadCountSubject = CurrentValueSubject<Int, Never>(0)

    // MARK: - Initialization

    init(coreDataStack: CoreDataStack = .shared, authRepository: AuthRepository) {
        self.coreDataStack = coreDataStack
        self.authRepository = authRepository

        // Initial load
        Task {
            await refreshNotifications()
        }
    }

    // MARK: - Read Status

    func markAsRead(notificationId: String) async throws {
        // SECURITY: Verify notification belongs to current user before modifying
        guard let userId = await getCurrentUserId() else {
            #if DEBUG
            print("NotificationRepository: Cannot mark as read - no current user")
            #endif
            return
        }

        let context = coreDataStack.writeContext
        try await context.perform {
            let request: NSFetchRequest<NotificationEntity> = NotificationEntity.fetchRequest()
            // Include userId in predicate to ensure user can only modify their own notifications
            request.predicate = NSPredicate(format: "id == %@ AND userId == %@", notificationId, userId)

            if let entity = try context.fetch(request).first {
                entity.isRead = true
                entity.readAt = Date()
                try context.save()
            }
        }
        await refreshNotifications()
        await updateAppBadge()
    }

    func markAllAsRead() async throws {
        guard let userId = await getCurrentUserId() else {
            #if DEBUG
            print("NotificationRepository: Cannot mark all as read - no current user")
            #endif
            return
        }

        let context = coreDataStack.writeContext
        try await context.perform {
            let request: NSFetchRequest<NotificationEntity> = NotificationEntity.fetchRequest()
            request.predicate = NSPredicate(format: "userId == %@ AND isRead == NO", userId)

            let entities = try context.fetch(request)
            let now = Date()
            for entity in entities {
                entity.isRead = true
                entity.readAt = now
            }
            try context.save()
        }
        await refreshNotifications()
        await updateAppBadge()
    }

    // MARK: - Queries

    func getUnreadCount() async -> Int {
        guard let userId = await getCurrentUserId() else { return 0 }

        let context = coreDataStack.viewContext
        return await MainActor.run {
            let request: NSFetchRequest<NotificationEntity> = NotificationEntity.fetchRequest()
            request.predicate = NSPredicate(format: "userId == %@ AND isRead == NO", userId)
            return (try? context.count(for: request)) ?? 0
        }
    }

    func getNotifications() async throws -> [AppNotification] {
        guard let userId = await getCurrentUserId() else { return [] }

        let context = coreDataStack.viewContext
        return try await MainActor.run {
            let request: NSFetchRequest<NotificationEntity> = NotificationEntity.fetchRequest()
            request.predicate = NSPredicate(format: "userId == %@", userId)
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

            let entities = try context.fetch(request)
            return entities.map { $0.toDomain() }
        }
    }

    func getUnreadNotifications() async throws -> [AppNotification] {
        guard let userId = await getCurrentUserId() else { return [] }

        let context = coreDataStack.viewContext
        return try await MainActor.run {
            let request: NSFetchRequest<NotificationEntity> = NotificationEntity.fetchRequest()
            request.predicate = NSPredicate(format: "userId == %@ AND isRead == NO", userId)
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

            let entities = try context.fetch(request)
            return entities.map { $0.toDomain() }
        }
    }

    // MARK: - Reactive Streams

    func observeUnreadCount() -> AnyPublisher<Int, Never> {
        unreadCountSubject.eraseToAnyPublisher()
    }

    func observeNotifications() -> AnyPublisher<[AppNotification], Never> {
        notificationsSubject.eraseToAnyPublisher()
    }

    // MARK: - Mutations

    func saveNotification(_ notification: AppNotification) async throws {
        guard let userId = await getCurrentUserId() else {
            #if DEBUG
            print("NotificationRepository: Cannot save notification - no current user")
            #endif
            return
        }

        let context = coreDataStack.writeContext
        try await context.perform {
            // Check if notification already exists
            let fetchRequest: NSFetchRequest<NotificationEntity> = NotificationEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", notification.id)

            if let existingEntity = try context.fetch(fetchRequest).first {
                // Update existing
                existingEntity.update(from: notification, userId: userId)
            } else {
                // Create new
                let entity = NotificationEntity(context: context)
                entity.update(from: notification, userId: userId)
            }

            try context.save()
        }
        await refreshNotifications()
        await updateAppBadge()
    }

    func saveNotifications(_ notifications: [AppNotification]) async throws {
        guard let userId = await getCurrentUserId() else {
            #if DEBUG
            print("NotificationRepository: Cannot save notifications - no current user")
            #endif
            return
        }
        guard !notifications.isEmpty else { return }

        let context = coreDataStack.writeContext
        try await context.perform {
            // Fetch all potentially existing notifications in a single query for efficiency
            // D11: Filter out empty IDs to prevent dictionary crash
            let ids = notifications.map { $0.id }.filter { !$0.isEmpty }
            let fetchRequest: NSFetchRequest<NotificationEntity> = NotificationEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id IN %@", ids)

            let existingEntities = try context.fetch(fetchRequest)
            // D11: Filter out entities with empty IDs before creating dictionary
            let existingById = Dictionary(
                uniqueKeysWithValues: existingEntities.compactMap { entity -> (String, NotificationEntity)? in
                    guard !entity.id.isEmpty else { return nil }
                    return (entity.id, entity)
                }
            )

            for notification in notifications {
                if let existingEntity = existingById[notification.id] {
                    existingEntity.update(from: notification, userId: userId)
                } else {
                    let entity = NotificationEntity(context: context)
                    entity.update(from: notification, userId: userId)
                }
            }
            try context.save()
        }
        await refreshNotifications()
        await updateAppBadge()
    }

    func deleteNotification(notificationId: String) async throws {
        // SECURITY: Verify notification belongs to current user before deleting
        guard let userId = await getCurrentUserId() else {
            #if DEBUG
            print("NotificationRepository: Cannot delete notification - no current user")
            #endif
            return
        }

        let context = coreDataStack.writeContext
        try await context.perform {
            let request: NSFetchRequest<NotificationEntity> = NotificationEntity.fetchRequest()
            // Include userId in predicate to ensure user can only delete their own notifications
            request.predicate = NSPredicate(format: "id == %@ AND userId == %@", notificationId, userId)

            if let entity = try context.fetch(request).first {
                context.delete(entity)
                try context.save()
            }
        }
        await refreshNotifications()
        await updateAppBadge()
    }

    func deleteAllNotifications() async throws {
        guard let userId = await getCurrentUserId() else {
            #if DEBUG
            print("NotificationRepository: Cannot delete all notifications - no current user")
            #endif
            return
        }

        let context = coreDataStack.writeContext
        try await context.perform {
            let request: NSFetchRequest<NotificationEntity> = NotificationEntity.fetchRequest()
            request.predicate = NSPredicate(format: "userId == %@", userId)

            let entities = try context.fetch(request)
            for entity in entities {
                context.delete(entity)
            }
            try context.save()
        }
        await refreshNotifications()
        await updateAppBadge()
    }

    func cleanupOldNotifications(daysOld: Int) async throws {
        guard let userId = await getCurrentUserId() else {
            #if DEBUG
            print("NotificationRepository: Cannot cleanup notifications - no current user")
            #endif
            return
        }

        let cutoffDate = Calendar.current.date(byAdding: .day, value: -daysOld, to: Date()) ?? Date()

        let context = coreDataStack.writeContext
        try await context.perform {
            let request: NSFetchRequest<NotificationEntity> = NotificationEntity.fetchRequest()
            request.predicate = NSPredicate(
                format: "userId == %@ AND isRead == YES AND createdAt < %@",
                userId, cutoffDate as NSDate
            )

            let entities = try context.fetch(request)
            for entity in entities {
                context.delete(entity)
            }

            if !entities.isEmpty {
                try context.save()
                #if DEBUG
                print("NotificationRepository: Cleaned up \(entities.count) old notifications")
                #endif
            }
        }
        await refreshNotifications()
    }

    // MARK: - Badge Management

    func updateAppBadge() async {
        let count = await getUnreadCount()
        await MainActor.run {
            UNUserNotificationCenter.current().setBadgeCount(count) { error in
                #if DEBUG
                if let error = error {
                    print("NotificationRepository: Failed to set badge count: \(error)")
                }
                #endif
            }
        }
    }

    // MARK: - Private Helpers

    private func getCurrentUserId() async -> String? {
        return authRepository.currentUserId
    }

    private func refreshNotifications() async {
        do {
            let notifications = try await getNotifications()
            let unreadCount = await getUnreadCount()

            await MainActor.run {
                notificationsSubject.send(notifications)
                unreadCountSubject.send(unreadCount)
            }
        } catch {
            #if DEBUG
            print("NotificationRepository: Failed to refresh notifications - \(error)")
            #endif
        }
    }
}
