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
        case "file.uploaded": return "Uploaded"
        case "file.downloaded": return "Downloaded"
        case "file.deleted": return "Deleted"
        case "file.renamed": return "Renamed"
        case "file.moved": return "Moved"
        case "file.copied": return "Copied"
        case "file.shared": return "Shared"
        case "file.unshared": return "Unshared"
        case "folder.created": return "Created folder"
        case "folder.deleted": return "Deleted folder"
        case "folder.renamed": return "Renamed folder"
        case "folder.moved": return "Moved folder"
        default: return eventType
        }
    }

    /// SF Symbol icon name for the event type
    var iconName: String {
        switch eventType {
        case "file.uploaded": return "arrow.up.doc"
        case "file.downloaded": return "arrow.down.doc"
        case "file.deleted", "folder.deleted": return "trash"
        case "file.renamed", "folder.renamed": return "pencil"
        case "file.moved", "folder.moved": return "folder.badge.questionmark"
        case "file.copied": return "doc.on.doc"
        case "file.shared": return "person.badge.plus"
        case "file.unshared": return "person.badge.minus"
        case "folder.created": return "folder.badge.plus"
        default: return "doc"
        }
    }

    /// Tint color name for the event icon
    var iconColorName: String {
        switch eventType {
        case "file.uploaded": return "systemBlue"
        case "file.downloaded": return "systemGreen"
        case "file.deleted", "folder.deleted": return "systemRed"
        case "file.renamed", "folder.renamed": return "systemOrange"
        case "file.moved", "folder.moved": return "systemPurple"
        case "file.copied": return "systemTeal"
        case "file.shared", "file.unshared": return "systemIndigo"
        case "folder.created": return "systemYellow"
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
        if eventType.hasPrefix("folder.") { return "folders" }
        switch eventType {
        case "file.uploaded": return "uploads"
        case "file.downloaded": return "downloads"
        case "file.shared", "file.unshared": return "shares"
        case "file.deleted": return "deletes"
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
