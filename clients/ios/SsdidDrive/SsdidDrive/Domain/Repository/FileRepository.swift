import Foundation

/// Result of listing files, including cache status
struct ListFilesResult {
    let contents: FolderContents
    let isFromCache: Bool
}

/// Repository for file and folder operations
protocol FileRepository {

    // MARK: - Files

    /// List files in a folder (nil for root)
    func listFiles(folderId: String?) async throws -> ListFilesResult

    /// Get file details
    func getFile(fileId: String) async throws -> FileItem

    /// Upload a file
    func uploadFile(
        url: URL,
        folderId: String?,
        progress: @escaping (Double) -> Void
    ) async throws -> FileItem

    /// Upload multiple files
    func uploadFiles(
        urls: [URL],
        folderId: String?,
        progress: @escaping (Double) -> Void
    ) async throws -> [FileItem]

    /// Download a file
    func downloadFile(
        fileId: String,
        progress: @escaping (Double) -> Void
    ) async throws -> URL

    /// Delete a file
    func deleteFile(fileId: String) async throws

    /// Rename a file
    func renameFile(fileId: String, newName: String) async throws -> FileItem

    /// Move a file to another folder
    func moveFile(fileId: String, toFolderId: String?) async throws -> FileItem

    /// Copy a file
    func copyFile(fileId: String, toFolderId: String?) async throws -> FileItem

    // MARK: - Folders

    /// Create a new folder
    func createFolder(name: String, parentId: String?) async throws -> Folder

    /// Get folder details
    func getFolder(folderId: String) async throws -> Folder

    /// Delete a folder
    func deleteFolder(folderId: String) async throws

    /// Rename a folder
    func renameFolder(folderId: String, newName: String) async throws -> Folder

    /// Move a folder
    func moveFolder(folderId: String, toParentId: String?) async throws -> Folder

    // MARK: - Search

    /// Search for files and folders
    func search(query: String) async throws -> FolderContents

    // MARK: - Offline Cache

    /// Check if file is cached locally
    func isFileCached(fileId: String) -> Bool

    /// Get cached file URL if available
    func getCachedFile(fileId: String) -> URL?

    /// Clear file cache
    func clearCache() async throws

    /// Get cache size in bytes
    func getCacheSize() async -> Int64
}
