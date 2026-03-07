import Foundation
import UniformTypeIdentifiers

/// Represents a file or folder in the system
struct FileItem: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let mimeType: String
    let size: Int64
    let folderId: String?
    let ownerId: String
    let encryptedKey: Data?
    let createdAt: Date
    let updatedAt: Date
    let isFolder: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case mimeType = "mime_type"
        case size
        case folderId = "folder_id"
        case ownerId = "owner_id"
        case encryptedKey = "encrypted_key"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case isFolder = "is_folder"
    }

    init(id: String, name: String, mimeType: String, size: Int64, folderId: String?, ownerId: String, encryptedKey: Data?, createdAt: Date, updatedAt: Date, isFolder: Bool = false) {
        self.id = id
        self.name = name
        self.mimeType = mimeType
        self.size = size
        self.folderId = folderId
        self.ownerId = ownerId
        self.encryptedKey = encryptedKey
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isFolder = isFolder
    }

    /// Human-readable file size
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    /// File extension from name
    var fileExtension: String {
        (name as NSString).pathExtension.lowercased()
    }

    /// UTType for the file
    var utType: UTType? {
        UTType(mimeType: mimeType) ?? UTType(filenameExtension: fileExtension)
    }

    /// Icon name for the file type
    var iconName: String {
        if isImage { return "photo" }
        if isVideo { return "video" }
        if isAudio { return "music.note" }
        if isPDF { return "doc.text" }
        if isDocument { return "doc" }
        if isArchive { return "archivebox" }
        if isCode { return "chevron.left.forwardslash.chevron.right" }
        return "doc"
    }

    /// Check file type categories
    var isImage: Bool {
        mimeType.hasPrefix("image/")
    }

    var isVideo: Bool {
        mimeType.hasPrefix("video/")
    }

    var isAudio: Bool {
        mimeType.hasPrefix("audio/")
    }

    var isPDF: Bool {
        mimeType == "application/pdf"
    }

    var isDocument: Bool {
        let docTypes = ["application/msword", "application/vnd.openxmlformats-officedocument",
                        "application/vnd.ms-excel", "text/plain", "text/markdown"]
        return docTypes.contains { mimeType.hasPrefix($0) }
    }

    var isArchive: Bool {
        let archiveTypes = ["application/zip", "application/x-tar", "application/gzip",
                           "application/x-rar-compressed", "application/x-7z-compressed"]
        return archiveTypes.contains(mimeType)
    }

    var isCode: Bool {
        let codeExtensions = ["swift", "kt", "java", "py", "js", "ts", "go", "rs", "c", "cpp", "h", "json", "xml", "html", "css"]
        return codeExtensions.contains(fileExtension)
    }

    /// Can be previewed in-app
    var isPreviewable: Bool {
        isImage || isPDF || isVideo || isAudio || isCode || mimeType.hasPrefix("text/")
    }
}

/// Represents a folder in the system
struct Folder: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let parentId: String?
    let ownerId: String
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case parentId = "parent_id"
        case ownerId = "owner_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// Icon name for folder
    var iconName: String {
        "folder.fill"
    }
}

/// Combined type for file browser items
enum BrowserItem: Identifiable, Hashable {
    case file(FileItem)
    case folder(Folder)

    var id: String {
        switch self {
        case .file(let file): return "file_\(file.id)"
        case .folder(let folder): return "folder_\(folder.id)"
        }
    }

    var name: String {
        switch self {
        case .file(let file): return file.name
        case .folder(let folder): return folder.name
        }
    }

    var isFolder: Bool {
        if case .folder = self { return true }
        return false
    }

    var updatedAt: Date {
        switch self {
        case .file(let file): return file.updatedAt
        case .folder(let folder): return folder.updatedAt
        }
    }
}

/// Folder contents response
struct FolderContents: Codable {
    let folder: Folder?
    let files: [FileItem]
    let subfolders: [Folder]
    let breadcrumbs: [Folder]?

    /// Convert to browser items, sorted
    func toBrowserItems(sortBy: SortOption = .name, ascending: Bool = true) -> [BrowserItem] {
        var items: [BrowserItem] = subfolders.map { .folder($0) } + files.map { .file($0) }

        items.sort { a, b in
            // Folders always come first
            if a.isFolder && !b.isFolder { return true }
            if !a.isFolder && b.isFolder { return false }

            let result: Bool
            switch sortBy {
            case .name:
                result = a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .date:
                result = a.updatedAt < b.updatedAt
            case .size:
                if case .file(let fileA) = a, case .file(let fileB) = b {
                    result = fileA.size < fileB.size
                } else {
                    result = a.name < b.name
                }
            case .type:
                if case .file(let fileA) = a, case .file(let fileB) = b {
                    result = fileA.fileExtension < fileB.fileExtension
                } else {
                    result = a.name < b.name
                }
            }
            return ascending ? result : !result
        }

        return items
    }
}

/// Sort options for file browser
enum SortOption: String, CaseIterable {
    case name
    case date
    case size
    case type

    var displayName: String {
        switch self {
        case .name: return "Name"
        case .date: return "Date"
        case .size: return "Size"
        case .type: return "Type"
        }
    }

    var iconName: String {
        switch self {
        case .name: return "textformat.abc"
        case .date: return "calendar"
        case .size: return "arrow.up.arrow.down"
        case .type: return "doc"
        }
    }
}
