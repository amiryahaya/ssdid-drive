import Foundation

/// Represents a single activity log entry for file operations
struct FileActivity: Codable, Identifiable, Equatable {
    let id: String
    let actorId: String
    let actorName: String?
    let eventType: String
    let resourceType: String
    let resourceId: String
    let resourceName: String
    let details: [String: String]?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case actorId = "actor_id"
        case actorName = "actor_name"
        case eventType = "event_type"
        case resourceType = "resource_type"
        case resourceId = "resource_id"
        case resourceName = "resource_name"
        case details
        case createdAt = "created_at"
    }

    /// Human-readable label for the event type
    var eventLabel: String {
        switch eventType {
        case "file_uploaded": return "Uploaded"
        case "file_downloaded": return "Downloaded"
        case "file_deleted": return "Deleted"
        case "file_renamed": return "Renamed"
        case "file_moved": return "Moved"
        case "file_previewed": return "Previewed"
        case "file_shared": return "Shared"
        case "share_revoked": return "Share revoked"
        case "share_permission_changed": return "Permission changed"
        case "folder_created": return "Created folder"
        case "folder_deleted": return "Deleted folder"
        case "folder_renamed": return "Renamed folder"
        default: return eventType
        }
    }

    /// SF Symbol icon name for the event type
    var iconName: String {
        switch eventType {
        case "file_uploaded": return "arrow.up.doc"
        case "file_downloaded": return "arrow.down.doc"
        case "file_deleted", "folder_deleted": return "trash"
        case "file_renamed", "folder_renamed": return "pencil"
        case "file_moved": return "folder.badge.questionmark"
        case "file_previewed": return "eye"
        case "file_shared": return "person.badge.plus"
        case "share_revoked": return "person.badge.minus"
        case "share_permission_changed": return "person.badge.key"
        case "folder_created": return "folder.badge.plus"
        default: return "doc"
        }
    }

    /// Tint color name for the event icon
    var iconColorName: String {
        switch eventType {
        case "file_uploaded": return "systemBlue"
        case "file_downloaded": return "systemGreen"
        case "file_deleted", "folder_deleted": return "systemRed"
        case "file_renamed", "folder_renamed": return "systemOrange"
        case "file_moved": return "systemPurple"
        case "file_previewed": return "systemTeal"
        case "file_shared", "share_revoked", "share_permission_changed": return "systemIndigo"
        case "folder_created": return "systemYellow"
        default: return "systemGray"
        }
    }

    /// Relative time string (e.g. "2 hours ago")
    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }

    /// Filter category for segmented control
    var filterCategory: String {
        if eventType.hasPrefix("folder_") { return "folders" }
        switch eventType {
        case "file_uploaded": return "uploads"
        case "file_downloaded": return "downloads"
        case "file_shared", "share_revoked", "share_permission_changed": return "shares"
        case "file_deleted": return "deletes"
        default: return "all"
        }
    }
}

/// Paginated response for activity logs
struct ActivityResponse: Codable {
    let items: [FileActivity]
    let total: Int
    let page: Int
    let pageSize: Int

    enum CodingKeys: String, CodingKey {
        case items, total, page
        case pageSize = "page_size"
    }
}
