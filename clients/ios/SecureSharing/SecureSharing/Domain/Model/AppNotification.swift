import Foundation
import UIKit

/// Types of notifications matching Android implementation
enum NotificationType: String, Codable, CaseIterable {
    // Share notifications
    case shareReceived = "SHARE_RECEIVED"
    case shareRevoked = "SHARE_REVOKED"
    case shareUpdated = "SHARE_UPDATED"

    // Recovery notifications
    case recoveryRequestReceived = "RECOVERY_REQUEST_RECEIVED"
    case recoveryRequestApproved = "RECOVERY_REQUEST_APPROVED"
    case recoveryRequestCompleted = "RECOVERY_REQUEST_COMPLETED"
    case recoveryShareAssigned = "RECOVERY_SHARE_ASSIGNED"

    // File notifications
    case fileUploaded = "FILE_UPLOADED"
    case fileShared = "FILE_SHARED"
    case fileDeleted = "FILE_DELETED"

    // Folder notifications
    case folderShared = "FOLDER_SHARED"
    case folderCreated = "FOLDER_CREATED"

    // System notifications
    case syncCompleted = "SYNC_COMPLETED"
    case syncFailed = "SYNC_FAILED"
    case storageWarning = "STORAGE_WARNING"
    case securityAlert = "SECURITY_ALERT"

    // General
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"

    /// SF Symbol name for this notification type
    var icon: String {
        switch self {
        case .shareReceived, .shareUpdated:
            return "person.badge.plus"
        case .shareRevoked:
            return "person.badge.minus"
        case .recoveryRequestReceived, .recoveryRequestApproved,
             .recoveryRequestCompleted, .recoveryShareAssigned:
            return "key.fill"
        case .fileUploaded, .fileShared, .fileDeleted:
            return "doc.fill"
        case .folderShared, .folderCreated:
            return "folder.fill"
        case .syncCompleted, .syncFailed:
            return "arrow.triangle.2.circlepath"
        case .storageWarning:
            return "externaldrive.fill"
        case .securityAlert:
            return "exclamationmark.shield.fill"
        case .info:
            return "info.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.circle.fill"
        }
    }

    /// Tint color for this notification type
    var tintColor: UIColor {
        switch self {
        case .shareReceived, .shareUpdated, .info:
            return .systemBlue
        case .shareRevoked, .fileDeleted, .error, .securityAlert:
            return .systemRed
        case .recoveryRequestReceived, .recoveryRequestApproved,
             .recoveryRequestCompleted, .recoveryShareAssigned:
            return .systemOrange
        case .fileUploaded, .fileShared, .folderShared, .folderCreated, .syncCompleted:
            return .systemGreen
        case .syncFailed, .storageWarning, .warning:
            return .systemYellow
        }
    }

    /// Localized display name for this notification type category
    var categoryName: String {
        switch self {
        case .shareReceived, .shareRevoked, .shareUpdated:
            return NSLocalizedString("notification.category.shares", value: "Shares", comment: "Shares notification category")
        case .recoveryRequestReceived, .recoveryRequestApproved,
             .recoveryRequestCompleted, .recoveryShareAssigned:
            return NSLocalizedString("notification.category.recovery", value: "Recovery", comment: "Recovery notification category")
        case .fileUploaded, .fileShared, .fileDeleted:
            return NSLocalizedString("notification.category.files", value: "Files", comment: "Files notification category")
        case .folderShared, .folderCreated:
            return NSLocalizedString("notification.category.folders", value: "Folders", comment: "Folders notification category")
        case .syncCompleted, .syncFailed, .storageWarning, .securityAlert, .info, .warning, .error:
            return NSLocalizedString("notification.category.system", value: "System", comment: "System notification category")
        }
    }
}

/// Action to perform when notification is tapped
struct NotificationAction: Codable, Equatable {
    let type: ActionType
    let resourceId: String?

    enum ActionType: String, Codable {
        case openShare
        case openFile
        case openFolder
        case openRecovery
        case openSettings
        case none
    }

    init(type: ActionType, resourceId: String? = nil) {
        self.type = type
        self.resourceId = resourceId
    }
}

/// Domain notification model for in-app notifications
struct AppNotification: Identifiable, Equatable, Hashable {
    let id: String
    let type: NotificationType
    let title: String
    let message: String
    let isRead: Bool
    let action: NotificationAction?
    let createdAt: Date
    let readAt: Date?

    /// Convenience property for checking unread status
    var isUnread: Bool { !isRead }

    /// Creates a new notification
    init(
        id: String = UUID().uuidString,
        type: NotificationType,
        title: String,
        message: String,
        isRead: Bool = false,
        action: NotificationAction? = nil,
        createdAt: Date = Date(),
        readAt: Date? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.message = message
        self.isRead = isRead
        self.action = action
        self.createdAt = createdAt
        self.readAt = readAt
    }

    /// Creates a copy with updated read status
    func markingAsRead() -> AppNotification {
        AppNotification(
            id: id,
            type: type,
            title: title,
            message: message,
            isRead: true,
            action: action,
            createdAt: createdAt,
            readAt: Date()
        )
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: - Equatable

    static func == (lhs: AppNotification, rhs: AppNotification) -> Bool {
        lhs.id == rhs.id &&
        lhs.type == rhs.type &&
        lhs.title == rhs.title &&
        lhs.message == rhs.message &&
        lhs.isRead == rhs.isRead &&
        lhs.action == rhs.action &&
        lhs.createdAt == rhs.createdAt &&
        lhs.readAt == rhs.readAt
    }
}
