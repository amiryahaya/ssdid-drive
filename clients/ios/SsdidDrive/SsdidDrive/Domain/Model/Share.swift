import Foundation

/// Represents a share grant (file or folder shared with a user).
/// Maps to the backend Share entity and ListReceivedShares/ListCreatedShares projections.
struct Share: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let resourceType: ResourceType
    let resourceId: String
    let sharedById: String
    let sharedByName: String?
    let sharedWithId: String
    let sharedWithName: String?
    let permission: Permission
    let encryptedKey: String?    // base64-encoded encrypted DEK/KEK
    let kemAlgorithm: String?
    let expiresAt: Date?
    let revokedAt: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case resourceType = "resource_type"
        case resourceId = "resource_id"
        case sharedById = "shared_by_id"
        case sharedByName = "shared_by_name"
        case sharedWithId = "shared_with_id"
        case sharedWithName = "shared_with_name"
        case permission
        case encryptedKey = "encrypted_key"
        case kemAlgorithm = "kem_algorithm"
        case expiresAt = "expires_at"
        case revokedAt = "revoked_at"
        case createdAt = "created_at"
    }

    /// Whether this is a folder share
    var isFolder: Bool { resourceType == .folder }

    /// Is the share still active (not revoked, not expired)
    var isActive: Bool { revokedAt == nil }

    /// Resource type (file or folder)
    enum ResourceType: String, Codable {
        case file
        case folder
    }

    /// Permission level matching backend :read, :write, :admin
    enum Permission: String, Codable, CaseIterable {
        case read
        case write
        case admin

        var displayName: String {
            switch self {
            case .read: return "View only"
            case .write: return "Can edit"
            case .admin: return "Full access"
            }
        }

        var iconName: String {
            switch self {
            case .read: return "eye"
            case .write: return "pencil"
            case .admin: return "person.badge.key"
            }
        }
    }
}

/// Share invitation (pending share request)
struct ShareInvitation: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let shareId: String
    let resourceType: Share.ResourceType
    let resourceName: String
    let permission: Share.Permission
    let senderEmail: String
    let senderName: String?
    let expiresAt: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case shareId = "share_id"
        case resourceType = "resource_type"
        case resourceName = "resource_name"
        case permission
        case senderEmail = "sender_email"
        case senderName = "sender_name"
        case expiresAt = "expires_at"
        case createdAt = "created_at"
    }
}

/// Request to share a file
struct ShareFileRequest: Codable {
    let fileId: String
    let granteeId: String
    let wrappedKey: String      // base64-encoded
    let kemCiphertext: String   // base64-encoded
    let signature: String       // base64-encoded
    let permission: Share.Permission
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case fileId = "file_id"
        case granteeId = "grantee_id"
        case wrappedKey = "wrapped_key"
        case kemCiphertext = "kem_ciphertext"
        case signature
        case permission
        case expiresAt = "expires_at"
    }
}

/// Request to share a folder
struct ShareFolderRequest: Codable {
    let folderId: String
    let granteeId: String
    let wrappedKey: String      // base64-encoded
    let kemCiphertext: String   // base64-encoded
    let signature: String       // base64-encoded
    let permission: Share.Permission
    let recursive: Bool
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case folderId = "folder_id"
        case granteeId = "grantee_id"
        case wrappedKey = "wrapped_key"
        case kemCiphertext = "kem_ciphertext"
        case signature
        case permission
        case recursive
        case expiresAt = "expires_at"
    }
}

/// Wrapper for backend responses that use the { "data": ... } format
struct ShareDataResponse: Codable {
    let data: Share
}

/// Wrapper for backend list responses that use the { "data": [...] } format
struct ShareListDataResponse: Codable {
    let data: [Share]
}

/// Wrapper for backend paginated responses that use the { "items": [...] } format
struct SharePagedResponse: Codable {
    let items: [Share]
    let total: Int
    let page: Int
    let pageSize: Int

    enum CodingKeys: String, CodingKey {
        case items, total, page
        case pageSize = "page_size"
    }
}

/// Response containing invitations
struct InvitationsResponse: Codable {
    let invitations: [ShareInvitation]
}
