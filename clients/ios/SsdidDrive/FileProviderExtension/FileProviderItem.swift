import FileProvider
import UniformTypeIdentifiers

/// Represents a file or folder item in the File Provider
class FileProviderItem: NSObject, NSFileProviderItem {

    // MARK: - Required Properties

    let itemIdentifier: NSFileProviderItemIdentifier
    let parentItemIdentifier: NSFileProviderItemIdentifier
    let filename: String
    let contentType: UTType

    // MARK: - Optional Properties

    let documentSize: NSNumber?
    let creationDate: Date?
    let contentModificationDate: Date?
    private let _isDownloaded: Bool
    private let _isUploaded: Bool
    private let _isShared: Bool
    private let _ownerName: String?
    private let _permissionLevel: FPPermissionLevel

    // MARK: - Initialization

    init(
        identifier: NSFileProviderItemIdentifier,
        parentIdentifier: NSFileProviderItemIdentifier,
        filename: String,
        contentType: UTType,
        documentSize: NSNumber?,
        creationDate: Date?,
        contentModificationDate: Date?,
        isDownloaded: Bool = false,
        isUploaded: Bool = true,
        isShared: Bool = false,
        ownerName: String? = nil,
        permissionLevel: FPPermissionLevel = .owner
    ) {
        self.itemIdentifier = identifier
        self.parentItemIdentifier = parentIdentifier
        self.filename = filename
        self.contentType = contentType
        self.documentSize = documentSize
        self.creationDate = creationDate
        self.contentModificationDate = contentModificationDate
        self._isDownloaded = isDownloaded
        self._isUploaded = isUploaded
        self._isShared = isShared
        self._ownerName = ownerName
        self._permissionLevel = permissionLevel
        super.init()
    }

    // MARK: - NSFileProviderItem Protocol

    var capabilities: NSFileProviderItemCapabilities {
        switch _permissionLevel {
        case .read:
            return [.allowsReading]
        case .write:
            if contentType == .folder {
                return [.allowsReading, .allowsWriting, .allowsRenaming, .allowsAddingSubItems]
            }
            return [.allowsReading, .allowsWriting, .allowsRenaming]
        case .admin, .owner:
            if contentType == .folder {
                return [.allowsReading, .allowsWriting, .allowsRenaming, .allowsDeleting, .allowsAddingSubItems]
            }
            return [.allowsReading, .allowsWriting, .allowsRenaming, .allowsDeleting]
        }
    }

    var itemVersion: NSFileProviderItemVersion {
        let contentData = contentModificationDate.map {
            String($0.timeIntervalSince1970).data(using: .utf8) ?? Data()
        } ?? Data()
        return NSFileProviderItemVersion(contentVersion: contentData, metadataVersion: contentData)
    }

    var isDownloaded: Bool {
        return _isDownloaded
    }

    var isUploaded: Bool {
        return _isUploaded
    }

    var isDownloading: Bool {
        return false
    }

    var isUploading: Bool {
        return false
    }

    var downloadingError: Error? {
        return nil
    }

    var uploadingError: Error? {
        return nil
    }

    var isShared: Bool {
        return _isShared
    }

    var ownerNameComponents: PersonNameComponents? {
        guard let name = _ownerName else { return nil }
        var components = PersonNameComponents()
        components.givenName = name
        return components
    }

    // MARK: - Factory Methods

    /// Create a root container item
    static func rootContainer() -> FileProviderItem {
        return FileProviderItem(
            identifier: .rootContainer,
            parentIdentifier: .rootContainer,
            filename: "SsdidDrive",
            contentType: .folder,
            documentSize: nil,
            creationDate: nil,
            contentModificationDate: nil,
            isDownloaded: true,
            isUploaded: true,
            permissionLevel: .owner
        )
    }

    /// Create a FileProviderItem from an FPFileItem (File Provider API model)
    static func from(fpFile: FPFileItem, parentIdentifier: NSFileProviderItemIdentifier, permissionLevel: FPPermissionLevel = .owner) -> FileProviderItem {
        let type = UTType(mimeType: fpFile.mimeType) ?? .data

        return FileProviderItem(
            identifier: NSFileProviderItemIdentifier(fpFile.id),
            parentIdentifier: parentIdentifier,
            filename: fpFile.name,
            contentType: type,
            documentSize: NSNumber(value: fpFile.size),
            creationDate: fpFile.createdAt,
            contentModificationDate: fpFile.updatedAt,
            isDownloaded: false,
            isUploaded: true,
            permissionLevel: permissionLevel
        )
    }

    /// Create a FileProviderItem from an FPFolder (File Provider API model)
    static func from(fpFolder: FPFolder, parentIdentifier: NSFileProviderItemIdentifier, permissionLevel: FPPermissionLevel = .owner) -> FileProviderItem {
        return FileProviderItem(
            identifier: NSFileProviderItemIdentifier(fpFolder.id),
            parentIdentifier: parentIdentifier,
            filename: fpFolder.name,
            contentType: .folder,
            documentSize: nil,
            creationDate: fpFolder.createdAt,
            contentModificationDate: fpFolder.updatedAt,
            isDownloaded: true,
            isUploaded: true,
            permissionLevel: permissionLevel
        )
    }

    /// Create a FileProviderItem from the main app's FileItemData model
    static func from(file: FileItemData, parentIdentifier: NSFileProviderItemIdentifier) -> FileProviderItem {
        let type = UTType(mimeType: file.mimeType) ?? .data

        return FileProviderItem(
            identifier: NSFileProviderItemIdentifier(file.id),
            parentIdentifier: parentIdentifier,
            filename: file.name,
            contentType: type,
            documentSize: NSNumber(value: file.size),
            creationDate: file.createdAt,
            contentModificationDate: file.updatedAt,
            isDownloaded: false,
            isUploaded: true,
            isShared: file.isShared,
            ownerName: file.ownerName
        )
    }

    /// Create a FileProviderItem for a folder (legacy)
    static func folder(id: String, name: String, parentIdentifier: NSFileProviderItemIdentifier, createdAt: Date?) -> FileProviderItem {
        return FileProviderItem(
            identifier: NSFileProviderItemIdentifier(id),
            parentIdentifier: parentIdentifier,
            filename: name,
            contentType: .folder,
            documentSize: nil,
            creationDate: createdAt,
            contentModificationDate: createdAt,
            isDownloaded: true,
            isUploaded: true
        )
    }
}

// MARK: - Supporting Types

/// Simplified file data for File Provider (used by main app's factory method)
struct FileItemData {
    let id: String
    let name: String
    let mimeType: String
    let size: Int64
    let createdAt: Date?
    let updatedAt: Date?
    let isShared: Bool
    let ownerName: String?
}
