import FileProvider
import UniformTypeIdentifiers

/// Represents a file or folder in the File Provider
class FileProviderItem: NSObject, NSFileProviderItem {

    // MARK: - Properties

    let id: String
    let name: String
    let parentId: String
    let isFolder: Bool
    let size: Int64
    let createdAt: Date
    let modifiedAt: Date
    let contentVersion: Data
    let downloadedAt: Date?
    private let _downloaded: Bool
    private let _trashed: Bool

    // MARK: - Initialization

    init(
        id: String,
        name: String,
        parentId: String,
        isFolder: Bool,
        size: Int64,
        createdAt: Date,
        modifiedAt: Date,
        contentVersion: Data,
        downloadedAt: Date? = nil,
        downloaded: Bool = false,
        trashed: Bool = false
    ) {
        self.id = id
        self.name = name
        self.parentId = parentId
        self.isFolder = isFolder
        self.size = size
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.contentVersion = contentVersion
        self.downloadedAt = downloadedAt
        self._downloaded = downloaded
        self._trashed = trashed
        super.init()
    }

    // MARK: - NSFileProviderItem Required Properties

    var itemIdentifier: NSFileProviderItemIdentifier {
        if id == "root" {
            return .rootContainer
        }
        return NSFileProviderItemIdentifier(id)
    }

    var parentItemIdentifier: NSFileProviderItemIdentifier {
        if parentId.isEmpty || parentId == "root" {
            return .rootContainer
        }
        return NSFileProviderItemIdentifier(parentId)
    }

    var capabilities: NSFileProviderItemCapabilities {
        if _trashed {
            return [.allowsReading]
        }

        if isFolder {
            return [
                .allowsReading,
                .allowsAddingSubItems,
                .allowsContentEnumerating,
                .allowsDeleting,
                .allowsRenaming
            ]
        } else {
            return [
                .allowsReading,
                .allowsWriting,
                .allowsDeleting,
                .allowsRenaming
            ]
        }
    }

    var filename: String {
        name
    }

    // MARK: - NSFileProviderItem Optional Properties

    var contentType: UTType {
        if isFolder {
            return .folder
        }

        // Determine type from extension
        let ext = (name as NSString).pathExtension.lowercased()

        if ext.isEmpty {
            return .data
        }

        return UTType(filenameExtension: ext) ?? .data
    }

    var documentSize: NSNumber? {
        if isFolder {
            return nil
        }
        return NSNumber(value: size)
    }

    var creationDate: Date? {
        createdAt
    }

    var contentModificationDate: Date? {
        modifiedAt
    }

    var lastUsedDate: Date? {
        downloadedAt
    }

    var itemVersion: NSFileProviderItemVersion {
        NSFileProviderItemVersion(
            contentVersion: contentVersion,
            metadataVersion: contentVersion
        )
    }

    var isUploading: Bool {
        false
    }

    var isUploaded: Bool {
        true
    }

    var uploadingError: Error? {
        nil
    }

    var downloadingError: Error? {
        nil
    }

    // MARK: - Factory Methods

    /// Create from API response
    static func from(apiResponse: [String: Any]) -> FileProviderItem? {
        guard let id = apiResponse["id"] as? String,
              let name = apiResponse["name"] as? String else {
            return nil
        }

        let parentId = apiResponse["parent_id"] as? String ?? "root"
        let isFolder = apiResponse["is_folder"] as? Bool ?? false
        let size = apiResponse["size"] as? Int64 ?? 0

        let createdAt: Date
        if let createdStr = apiResponse["created_at"] as? String {
            createdAt = ISO8601DateFormatter().date(from: createdStr) ?? Date()
        } else {
            createdAt = Date()
        }

        let modifiedAt: Date
        if let modifiedStr = apiResponse["updated_at"] as? String {
            modifiedAt = ISO8601DateFormatter().date(from: modifiedStr) ?? Date()
        } else {
            modifiedAt = Date()
        }

        // Generate content version from modification date
        var versionData = Data()
        withUnsafeBytes(of: modifiedAt.timeIntervalSince1970) { bytes in
            versionData.append(contentsOf: bytes)
        }

        let isTrashed = apiResponse["trashed"] as? Bool ?? false

        return FileProviderItem(
            id: id,
            name: name,
            parentId: parentId,
            isFolder: isFolder,
            size: size,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            contentVersion: versionData,
            downloadedAt: nil,
            downloaded: false,
            trashed: isTrashed
        )
    }

    /// Create from cached data
    static func from(cachedData: Data) -> FileProviderItem? {
        guard let dict = try? JSONSerialization.jsonObject(with: cachedData) as? [String: Any] else {
            return nil
        }
        return from(apiResponse: dict)
    }

    /// Serialize to cache data
    func toCacheData() -> Data? {
        let dict: [String: Any] = [
            "id": id,
            "name": name,
            "parent_id": parentId,
            "is_folder": isFolder,
            "size": size,
            "created_at": ISO8601DateFormatter().string(from: createdAt),
            "updated_at": ISO8601DateFormatter().string(from: modifiedAt),
            "trashed": _trashed
        ]
        return try? JSONSerialization.data(withJSONObject: dict)
    }
}

// MARK: - Comparable

extension FileProviderItem: Comparable {
    static func < (lhs: FileProviderItem, rhs: FileProviderItem) -> Bool {
        // Folders first, then alphabetical
        if lhs.isFolder != rhs.isFolder {
            return lhs.isFolder
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    static func == (lhs: FileProviderItem, rhs: FileProviderItem) -> Bool {
        lhs.id == rhs.id
    }
}
