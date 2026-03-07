import Foundation
@testable import SecureSharing

/// Mock implementation of FileRepository for testing view models
final class MockFileRepository: FileRepository {

    // MARK: - Stub Results

    var listFilesResult: Result<ListFilesResult, Error> = .success(
        ListFilesResult(
            contents: FolderContents(folder: nil, files: [], subfolders: [], breadcrumbs: nil),
            isFromCache: false
        )
    )
    var getFileResult: Result<FileItem, Error> = .failure(MockError.notImplemented)
    var uploadFileResult: Result<FileItem, Error> = .failure(MockError.notImplemented)
    var uploadFilesResult: Result<[FileItem], Error> = .failure(MockError.notImplemented)
    var downloadFileResult: Result<URL, Error> = .failure(MockError.notImplemented)
    var deleteFileResult: Result<Void, Error> = .success(())
    var renameFileResult: Result<FileItem, Error> = .failure(MockError.notImplemented)
    var moveFileResult: Result<FileItem, Error> = .failure(MockError.notImplemented)
    var copyFileResult: Result<FileItem, Error> = .failure(MockError.notImplemented)
    var createFolderResult: Result<Folder, Error> = .failure(MockError.notImplemented)
    var getFolderResult: Result<Folder, Error> = .failure(MockError.notImplemented)
    var deleteFolderResult: Result<Void, Error> = .success(())
    var renameFolderResult: Result<Folder, Error> = .failure(MockError.notImplemented)
    var moveFolderResult: Result<Folder, Error> = .failure(MockError.notImplemented)
    var searchResult: Result<FolderContents, Error> = .success(
        FolderContents(folder: nil, files: [], subfolders: [], breadcrumbs: nil)
    )

    // MARK: - Call Tracking

    var listFilesCallCount = 0
    var getFileCallCount = 0
    var uploadFileCallCount = 0
    var uploadFilesCallCount = 0
    var downloadFileCallCount = 0
    var deleteFileCallCount = 0
    var renameFileCallCount = 0
    var moveFileCallCount = 0
    var copyFileCallCount = 0
    var createFolderCallCount = 0
    var getFolderCallCount = 0
    var deleteFolderCallCount = 0
    var renameFolderCallCount = 0
    var moveFolderCallCount = 0
    var searchCallCount = 0

    // MARK: - Last Call Parameters

    var lastListFilesFolderId: String?
    var lastGetFileId: String?
    var lastDeleteFileId: String?
    var lastSearchQuery: String?
    var lastCreateFolderName: String?
    var lastCreateFolderParentId: String?

    // MARK: - FileRepository Protocol

    func listFiles(folderId: String?) async throws -> ListFilesResult {
        listFilesCallCount += 1
        lastListFilesFolderId = folderId
        return try listFilesResult.get()
    }

    func getFile(fileId: String) async throws -> FileItem {
        getFileCallCount += 1
        lastGetFileId = fileId
        return try getFileResult.get()
    }

    func uploadFile(url: URL, folderId: String?, progress: @escaping (Double) -> Void) async throws -> FileItem {
        uploadFileCallCount += 1
        return try uploadFileResult.get()
    }

    func uploadFiles(urls: [URL], folderId: String?, progress: @escaping (Double) -> Void) async throws -> [FileItem] {
        uploadFilesCallCount += 1
        return try uploadFilesResult.get()
    }

    func downloadFile(fileId: String, progress: @escaping (Double) -> Void) async throws -> URL {
        downloadFileCallCount += 1
        return try downloadFileResult.get()
    }

    func deleteFile(fileId: String) async throws {
        deleteFileCallCount += 1
        lastDeleteFileId = fileId
        try deleteFileResult.get()
    }

    func renameFile(fileId: String, newName: String) async throws -> FileItem {
        renameFileCallCount += 1
        return try renameFileResult.get()
    }

    func moveFile(fileId: String, toFolderId: String?) async throws -> FileItem {
        moveFileCallCount += 1
        return try moveFileResult.get()
    }

    func copyFile(fileId: String, toFolderId: String?) async throws -> FileItem {
        copyFileCallCount += 1
        return try copyFileResult.get()
    }

    func createFolder(name: String, parentId: String?) async throws -> Folder {
        createFolderCallCount += 1
        lastCreateFolderName = name
        lastCreateFolderParentId = parentId
        return try createFolderResult.get()
    }

    func getFolder(folderId: String) async throws -> Folder {
        getFolderCallCount += 1
        return try getFolderResult.get()
    }

    func deleteFolder(folderId: String) async throws {
        deleteFolderCallCount += 1
        try deleteFolderResult.get()
    }

    func renameFolder(folderId: String, newName: String) async throws -> Folder {
        renameFolderCallCount += 1
        return try renameFolderResult.get()
    }

    func moveFolder(folderId: String, toParentId: String?) async throws -> Folder {
        moveFolderCallCount += 1
        return try moveFolderResult.get()
    }

    func search(query: String) async throws -> FolderContents {
        searchCallCount += 1
        lastSearchQuery = query
        return try searchResult.get()
    }

    func isFileCached(fileId: String) -> Bool {
        return false
    }

    func getCachedFile(fileId: String) -> URL? {
        return nil
    }

    func clearCache() async throws {
        // No-op for tests
    }

    func getCacheSize() async -> Int64 {
        return 0
    }

    // MARK: - Reset

    func reset() {
        listFilesCallCount = 0
        getFileCallCount = 0
        uploadFileCallCount = 0
        uploadFilesCallCount = 0
        downloadFileCallCount = 0
        deleteFileCallCount = 0
        renameFileCallCount = 0
        moveFileCallCount = 0
        copyFileCallCount = 0
        createFolderCallCount = 0
        getFolderCallCount = 0
        deleteFolderCallCount = 0
        renameFolderCallCount = 0
        moveFolderCallCount = 0
        searchCallCount = 0

        lastListFilesFolderId = nil
        lastGetFileId = nil
        lastDeleteFileId = nil
        lastSearchQuery = nil
        lastCreateFolderName = nil
        lastCreateFolderParentId = nil
    }
}
