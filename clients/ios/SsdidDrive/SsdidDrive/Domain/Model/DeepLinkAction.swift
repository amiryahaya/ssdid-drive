import Foundation

/// Represents an action to be taken based on a deep link or share intent.
/// Mirrors the Android DeepLinkAction sealed class for consistency.
enum DeepLinkAction: Equatable, Codable {
    /// Open a shared file or folder by share ID
    case openShare(shareId: String)

    /// Open a specific file by file ID
    case openFile(fileId: String)

    /// Open a specific folder by folder ID
    case openFolder(folderId: String)

    /// Accept an invitation using a token
    case acceptInvitation(token: String)

    /// Upload files from Share Extension
    case importFiles(manifest: ImportManifest)

    /// SSDID wallet auth callback with session token
    case authCallback(sessionToken: String)

    /// SSDID wallet invite callback with session token
    case walletInviteCallback(sessionToken: String)

    /// SSDID wallet invite callback with error
    case walletInviteError(message: String)

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case type, shareId, fileId, folderId, token, manifest, sessionToken, message
    }

    private enum ActionType: String, Codable {
        case openShare, openFile, openFolder, acceptInvitation, importFiles, authCallback
        case walletInviteCallback, walletInviteError
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ActionType.self, forKey: .type)

        switch type {
        case .openShare:
            let shareId = try container.decode(String.self, forKey: .shareId)
            self = .openShare(shareId: shareId)
        case .openFile:
            let fileId = try container.decode(String.self, forKey: .fileId)
            self = .openFile(fileId: fileId)
        case .openFolder:
            let folderId = try container.decode(String.self, forKey: .folderId)
            self = .openFolder(folderId: folderId)
        case .acceptInvitation:
            let token = try container.decode(String.self, forKey: .token)
            self = .acceptInvitation(token: token)
        case .importFiles:
            let manifest = try container.decode(ImportManifest.self, forKey: .manifest)
            self = .importFiles(manifest: manifest)
        case .authCallback:
            let sessionToken = try container.decode(String.self, forKey: .sessionToken)
            self = .authCallback(sessionToken: sessionToken)
        case .walletInviteCallback:
            let sessionToken = try container.decode(String.self, forKey: .sessionToken)
            self = .walletInviteCallback(sessionToken: sessionToken)
        case .walletInviteError:
            let message = try container.decode(String.self, forKey: .message)
            self = .walletInviteError(message: message)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .openShare(let shareId):
            try container.encode(ActionType.openShare, forKey: .type)
            try container.encode(shareId, forKey: .shareId)
        case .openFile(let fileId):
            try container.encode(ActionType.openFile, forKey: .type)
            try container.encode(fileId, forKey: .fileId)
        case .openFolder(let folderId):
            try container.encode(ActionType.openFolder, forKey: .type)
            try container.encode(folderId, forKey: .folderId)
        case .acceptInvitation(let token):
            try container.encode(ActionType.acceptInvitation, forKey: .type)
            try container.encode(token, forKey: .token)
        case .importFiles(let manifest):
            try container.encode(ActionType.importFiles, forKey: .type)
            try container.encode(manifest, forKey: .manifest)
        case .authCallback(let sessionToken):
            try container.encode(ActionType.authCallback, forKey: .type)
            try container.encode(sessionToken, forKey: .sessionToken)
        case .walletInviteCallback(let sessionToken):
            try container.encode(ActionType.walletInviteCallback, forKey: .type)
            try container.encode(sessionToken, forKey: .sessionToken)
        case .walletInviteError(let message):
            try container.encode(ActionType.walletInviteError, forKey: .type)
            try container.encode(message, forKey: .message)
        }
    }
}

// MARK: - Import Manifest

/// Manifest describing files to import from Share Extension.
///
/// The manifest is created by the Share Extension and stored in the App Group
/// container. It contains metadata about files that were shared to the app
/// and need to be uploaded.
///
/// - Note: Import manifests should not be persisted for deferred processing
///         because the underlying files in the App Group container may expire
///         or be cleaned up by the system.
struct ImportManifest: Equatable, Codable {
    /// List of files to import
    let files: [ImportFileInfo]

    /// Information about a single file to import
    struct ImportFileInfo: Equatable, Codable {
        /// Original file name (e.g., "photo.jpg")
        let name: String

        /// Absolute path to the file in the App Group shared container
        let path: String

        /// File size in bytes
        let size: Int64
    }
}
