import Foundation

/// Lightweight Codable structs mirroring backend API responses for the File Provider extension.
/// These are independent of the main app's model layer.

struct FPFileItem: Codable {
    let id: String
    let name: String
    let mimeType: String
    let size: Int64
    let folderId: String?
    let ownerId: String
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, size
        case mimeType = "mime_type"
        case folderId = "folder_id"
        case ownerId = "owner_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct FPFolder: Codable {
    let id: String
    let name: String
    let parentId: String?
    let ownerId: String
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name
        case parentId = "parent_id"
        case ownerId = "owner_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct FPFolderContents: Codable {
    let folder: FPFolder?
    let files: [FPFileItem]
    let subfolders: [FPFolder]
}

struct FPShare: Codable {
    let id: String
    let permission: String

    /// Map SsdidDrive permission string to a capability level.
    var permissionLevel: FPPermissionLevel {
        switch permission {
        case "read": return .read
        case "write": return .write
        case "admin": return .admin
        case "owner": return .owner
        default: return .read
        }
    }
}

enum FPPermissionLevel: Int, Comparable {
    case read = 0
    case write = 1
    case admin = 2
    case owner = 3

    static func < (lhs: FPPermissionLevel, rhs: FPPermissionLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
