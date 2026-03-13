import Foundation

/// Parses deep link URLs into typed DeepLinkAction
final class DeepLinkParser {

    // MARK: - Constants

    /// App Group identifier for Share Extension communication
    static let appGroupIdentifier = "group.my.ssdid.drive"

    /// Shared files directory name within App Group container
    private static let sharedFilesDirectory = "SharedFiles"

    /// Manifest file name
    private static let manifestFileName = "manifest.json"

    /// Allowed hosts for Universal Links (HTTPS deep links)
    private static let allowedUniversalLinkHosts: Set<String> = [
        "drive.ssdid.my",
        "ssdid.my"
    ]

    // MARK: - Validation Constants

    /// Maximum allowed file name length (common filesystem limit)
    private static let maxFileNameLength = 255

    /// Maximum allowed resource ID length
    private static let maxResourceIdLength = 128

    /// Minimum allowed invitation token length
    private static let minTokenLength = 8

    /// Maximum allowed invitation token length
    private static let maxTokenLength = 256

    /// Patterns that indicate path traversal attempts
    private static let pathTraversalPatterns = ["../", "..\\", "%2e%2e", "%252e"]

    /// Patterns that indicate script injection attempts
    private static let injectionPatterns = ["<script", "javascript:", "data:", "vbscript:"]

    // MARK: - Parsing

    /// Parse a URL into a DeepLinkAction
    /// - Parameter url: The URL to parse (custom scheme or Universal Link)
    /// - Returns: A DeepLinkAction if the URL is valid, nil otherwise
    static func parse(_ url: URL) -> DeepLinkAction? {
        let host: String?
        let pathComponents: [String]

        if url.scheme == "ssdid-drive" {
            // Custom scheme: ssdid-drive://share/123
            host = url.host
            pathComponents = url.pathComponents.filter { $0 != "/" }
        } else if url.scheme == "https" {
            // Universal Link: https://drive.ssdid.my/share/123
            // SECURITY: Validate the host is in our allowed list
            guard let urlHost = url.host, allowedUniversalLinkHosts.contains(urlHost) else {
                return nil
            }
            pathComponents = url.pathComponents.filter { $0 != "/" }
            host = pathComponents.first
        } else {
            return nil
        }

        switch host {
        case "auth":
            // Handle SSDID wallet auth callback: ssdid-drive://auth/callback?session_token=...
            // D7: Strict path matching — only accept exactly "callback" as the single path component
            if pathComponents.count == 1, pathComponents.first == "callback" {
                if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let token = components.queryItems?.first(where: { $0.name == "session_token" })?.value,
                   !token.isEmpty {
                    return .authCallback(sessionToken: token)
                }
            }
            return nil

        case "share":
            let shareId = extractResourceId(from: url, pathComponents: pathComponents)
            if let shareId = shareId, isValidResourceId(shareId) {
                return .openShare(shareId: shareId)
            }

        case "file":
            let fileId = extractResourceId(from: url, pathComponents: pathComponents)
            if let fileId = fileId, isValidResourceId(fileId) {
                return .openFile(fileId: fileId)
            }

        case "folder":
            let folderId = extractResourceId(from: url, pathComponents: pathComponents)
            if let folderId = folderId, isValidResourceId(folderId) {
                return .openFolder(folderId: folderId)
            }

        case "invite":
            // Check for wallet invite callback first (custom scheme only)
            if url.scheme == "ssdid-drive", pathComponents.first == "callback" {
                if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                    let status = components.queryItems?.first(where: { $0.name == "status" })?.value ?? ""
                    let sessionToken = components.queryItems?.first(where: { $0.name == "session_token" })?.value
                    if status == "success", let token = sessionToken, !token.isEmpty {
                        return .walletInviteCallback(sessionToken: token)
                    } else {
                        let message = components.queryItems?.first(where: { $0.name == "message" })?.value ?? "Invitation failed"
                        return .walletInviteError(message: message)
                    }
                }
                return nil
            }
            // Existing invitation token handling
            let token = extractResourceId(from: url, pathComponents: pathComponents)
            if let token = token, isValidInvitationToken(token) {
                return .acceptInvitation(token: token)
            }

        case "import":
            // Read manifest from App Group container
            if let manifest = loadImportManifest() {
                return .importFiles(manifest: manifest)
            }

        default:
            break
        }

        return nil
    }

    // MARK: - Import Manifest

    /// Load import manifest from App Group container
    /// - Returns: ImportManifest if valid manifest exists, nil otherwise
    /// SECURITY: Validates all file paths are within the shared container
    static func loadImportManifest() -> ImportManifest? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            return nil
        }

        let sharedDir = containerURL.appendingPathComponent(sharedFilesDirectory, isDirectory: true)
        let manifestURL = sharedDir.appendingPathComponent(manifestFileName)

        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: manifestURL)
            let fileList = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []

            let files = fileList.compactMap { dict -> ImportManifest.ImportFileInfo? in
                guard let name = dict["name"] as? String,
                      let path = dict["path"] as? String,
                      let size = dict["size"] as? Int64 else {
                    return nil
                }

                // SECURITY: Validate file name
                // - Must not be empty
                // - Must not exceed filesystem limit
                // - Must not contain path separators or null bytes
                guard !name.isEmpty,
                      name.count <= maxFileNameLength,
                      !name.contains("/"),
                      !name.contains("\\"),
                      !name.contains("\0") else {
                    #if DEBUG
                    print("DeepLinkParser: Rejected invalid file name: \(name)")
                    #endif
                    return nil
                }

                // SECURITY: Validate path is within the shared container
                // Resolve symlinks to prevent path traversal attacks
                let normalizedPath = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
                let sharedDirPath = sharedDir.resolvingSymlinksInPath().path + "/"
                guard normalizedPath.hasPrefix(sharedDirPath) else {
                    #if DEBUG
                    print("DeepLinkParser: Rejected path outside shared container: \(path)")
                    #endif
                    return nil // Reject paths outside shared container
                }

                return ImportManifest.ImportFileInfo(name: name, path: path, size: size)
            }

            return files.isEmpty ? nil : ImportManifest(files: files)
        } catch {
            #if DEBUG
            print("DeepLinkParser: Failed to load manifest: \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    /// Clean up import files after processing
    static func cleanupImportFiles() {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            return
        }

        let sharedDir = containerURL.appendingPathComponent(sharedFilesDirectory, isDirectory: true)
        do {
            try FileManager.default.removeItem(at: sharedDir)
        } catch {
            #if DEBUG
            print("DeepLinkParser: Failed to cleanup import files: \(error.localizedDescription)")
            #endif
        }
    }

    /// Get the shared files directory URL
    /// - Returns: URL to shared files directory, nil if App Group not configured
    static func sharedFilesDirectoryURL() -> URL? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            return nil
        }
        return containerURL.appendingPathComponent(sharedFilesDirectory, isDirectory: true)
    }

    // MARK: - Private Helpers

    private static func extractResourceId(from url: URL, pathComponents: [String]) -> String? {
        let id: String?
        if url.scheme == "ssdid-drive" {
            id = pathComponents.first
        } else {
            // For Universal Links, first component is the type, second is the ID
            id = pathComponents.dropFirst().first
        }
        // Filter out empty strings
        return id?.isEmpty == true ? nil : id
    }

    // MARK: - Validation

    /// Validate resource ID format (UUID or alphanumeric identifier)
    /// - Parameter id: The resource ID to validate
    /// - Returns: true if the ID is valid
    static func isValidResourceId(_ id: String) -> Bool {
        // Must be non-empty and within length limit
        guard !id.isEmpty, id.count <= maxResourceIdLength else { return false }

        // Allow UUIDs and alphanumeric identifiers with hyphens/underscores
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return id.unicodeScalars.allSatisfy { allowedCharacters.contains($0) }
    }

    /// Validate invitation token format
    /// - Parameter token: The invitation token to validate
    /// - Returns: true if the token format is valid
    static func isValidInvitationToken(_ token: String) -> Bool {
        // Token validation rules:
        // 1. Non-empty and within length bounds
        // 2. Only alphanumeric characters, hyphens, underscores, and dots
        // 3. No path traversal attempts
        // 4. No HTML/script injection attempts

        guard !token.isEmpty,
              token.count >= minTokenLength,
              token.count <= maxTokenLength else {
            return false
        }

        // Check for path traversal attempts
        let lowercasedToken = token.lowercased()
        for pattern in pathTraversalPatterns {
            if lowercasedToken.contains(pattern) {
                return false
            }
        }

        // Check for script injection attempts
        for pattern in injectionPatterns {
            if lowercasedToken.contains(pattern) {
                return false
            }
        }

        // Allow only safe characters (alphanumeric, hyphens, underscores, dots)
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return token.unicodeScalars.allSatisfy { allowedCharacters.contains($0) }
    }
}
