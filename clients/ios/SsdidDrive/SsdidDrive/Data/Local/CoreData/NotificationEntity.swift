import Foundation
import CoreData

/// Core Data entity for storing notifications locally.
///
/// This class is used with a programmatically defined Core Data model.
/// The entity description is created in CoreDataStack.
@objc(NotificationEntity)
public class NotificationEntity: NSManagedObject {

    // MARK: - Properties

    @NSManaged public var id: String
    @NSManaged public var userId: String
    @NSManaged public var type: String
    @NSManaged public var title: String
    @NSManaged public var message: String
    @NSManaged public var isRead: Bool
    @NSManaged public var actionType: String?
    @NSManaged public var actionResourceId: String?
    @NSManaged public var createdAt: Date
    @NSManaged public var readAt: Date?

    // MARK: - Fetch Request

    @nonobjc public class func fetchRequest() -> NSFetchRequest<NotificationEntity> {
        return NSFetchRequest<NotificationEntity>(entityName: "NotificationEntity")
    }
}

// MARK: - Domain Mapping

extension NotificationEntity {

    /// Converts Core Data entity to domain model
    func toDomain() -> AppNotification {
        var action: NotificationAction? = nil
        if let actionTypeString = self.actionType,
           let actionType = NotificationAction.ActionType(rawValue: actionTypeString) {
            action = NotificationAction(type: actionType, resourceId: self.actionResourceId)
        }

        return AppNotification(
            id: self.id,
            type: NotificationType(rawValue: self.type) ?? .info,
            title: self.title,
            message: self.message,
            isRead: self.isRead,
            action: action,
            createdAt: self.createdAt,
            readAt: self.readAt
        )
    }

    /// Updates entity from domain model
    /// - Parameters:
    ///   - notification: The domain notification model
    ///   - userId: The user ID this notification belongs to
    func update(from notification: AppNotification, userId: String) {
        self.id = notification.id
        self.userId = userId
        self.type = notification.type.rawValue
        self.title = notification.title
        self.message = notification.message
        self.isRead = notification.isRead
        self.actionType = notification.action?.type.rawValue
        self.actionResourceId = notification.action?.resourceId
        self.createdAt = notification.createdAt
        self.readAt = notification.readAt
    }
}
