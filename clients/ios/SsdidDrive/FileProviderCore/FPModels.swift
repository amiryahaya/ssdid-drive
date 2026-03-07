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
    let encryptedFileKey: String?  // base64-encoded wrapped file DEK (ciphertext + tag)
    let nonce: String?             // base64-encoded AES-GCM nonce for the file data
    let keyNonce: String?          // base64-encoded AES-GCM nonce for the wrapped file key
    let algorithm: String?         // encryption algorithm, e.g. "aes-256-gcm"
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, size, nonce, algorithm
        case mimeType = "mime_type"
        case folderId = "folder_id"
        case ownerId = "owner_id"
        case encryptedFileKey = "encrypted_file_key"
        case keyNonce = "key_nonce"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct FPFolder: Codable {
    let id: String
    let name: String
    let parentId: String?
    let ownerId: String
    let encryptedFolderKey: String?  // base64-encoded encrypted folder KEK
    let kemAlgorithm: String?        // KEM algorithm used to encrypt the folder key
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name
        case parentId = "parent_id"
        case ownerId = "owner_id"
        case encryptedFolderKey = "encrypted_folder_key"
        case kemAlgorithm = "kem_algorithm"
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
