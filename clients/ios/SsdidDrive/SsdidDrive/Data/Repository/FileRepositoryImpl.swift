import Foundation
import Security

/// Implementation of FileRepository
final class FileRepositoryImpl: FileRepository {

    private let apiClient: APIClient
    private let cryptoManager: CryptoManager
    private let encryptionService: FileEncryptionService
    private let cacheDirectory: URL
    private let metadataCacheDirectory: URL

    init(apiClient: APIClient, cryptoManager: CryptoManager, encryptionService: FileEncryptionService = .shared) {
        self.apiClient = apiClient
        self.cryptoManager = cryptoManager
        self.encryptionService = encryptionService

        let baseDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SsdidDrive", isDirectory: true)

        // Setup file cache directory
        self.cacheDirectory = baseDir.appendingPathComponent("files", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        // Setup metadata cache directory for offline listing
        self.metadataCacheDirectory = baseDir.appendingPathComponent("metadata", isDirectory: true)
        try? FileManager.default.createDirectory(at: metadataCacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Files

    func listFiles(folderId: String?) async throws -> ListFilesResult {
        let endpoint: String
        if let folderId = folderId {
            endpoint = "/folders/\(folderId)/contents"
        } else {
            endpoint = "/folders/root/contents"
        }

        do {
            let response: FolderContentsResponse = try await apiClient.request(endpoint)
            let contents = response.toFolderContents()
            saveFolderContentsCache(contents, folderId: folderId)
            return ListFilesResult(contents: contents, isFromCache: false)
        } catch {
            // Fall back to cached metadata on network failure
            if let cached = loadFolderContentsCache(folderId: folderId) {
                return ListFilesResult(contents: cached, isFromCache: true)
            }
            throw error
        }
    }

    func getFile(fileId: String) async throws -> FileItem {
        try await apiClient.request("/files/\(fileId)")
    }

    func uploadFile(
        url: URL,
        folderId: String?,
        progress: @escaping (Double) -> Void
    ) async throws -> FileItem {
        let endpoint: String
        if let folderId = folderId {
            endpoint = "/folders/\(folderId)/files"
        } else {
            endpoint = "/files"
        }

        let mimeType = mimeType(for: url)
        let fileName = url.lastPathComponent

        // Encrypt with folder key hierarchy if a folder key is available
        var additionalFields: [String: String]? = nil
        var fileURL = url

        if let folderId = folderId,
           let folderKey = loadFolderKey(folderId: folderId) {
            let fileData = try Data(contentsOf: url)
            let (encryptedFile, wrappedKey) = try encryptionService.encryptFileWithNewKey(
                data: fileData,
                folderKey: folderKey
            )

            // Write encrypted data to a temp file for upload
            let tempDir = FileManager.default.temporaryDirectory
            let tempFile = tempDir.appendingPathComponent(UUID().uuidString)
            try encryptedFile.ciphertext.write(to: tempFile)
            fileURL = tempFile

            additionalFields = [
                "encrypted_file_key": wrappedKey.ciphertext.base64EncodedString(),
                "nonce": encryptedFile.nonce.base64EncodedString(),
                "key_nonce": wrappedKey.nonce.base64EncodedString(),
                "algorithm": "aes-256-gcm"
            ]

            progress(0.3)
        }

        let data = try await apiClient.upload(
            endpoint,
            fileURL: fileURL,
            mimeType: mimeType,
            fileName: fileName,
            additionalFields: additionalFields,
            progress: { p in progress(0.3 + p * 0.7) }
        )

        // Clean up temp file if we created one
        if fileURL != url {
            try? FileManager.default.removeItem(at: fileURL)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(FileItem.self, from: data)
    }

    func uploadFiles(
        urls: [URL],
        folderId: String?,
        progress: @escaping (Double) -> Void
    ) async throws -> [FileItem] {
        var results: [FileItem] = []
        let totalFiles = Double(urls.count)

        for (index, url) in urls.enumerated() {
            let fileItem = try await uploadFile(url: url, folderId: folderId) { fileProgress in
                let overallProgress = (Double(index) + fileProgress) / totalFiles
                progress(overallProgress)
            }
            results.append(fileItem)
        }

        return results
    }

    func downloadFile(
        fileId: String,
        progress: @escaping (Double) -> Void
    ) async throws -> URL {
        // Check cache first
        if let cachedURL = getCachedFile(fileId: fileId) {
            progress(1.0)
            return cachedURL
        }

        // Fetch file metadata to get encryption info
        let fileItem: FileItem = try await apiClient.request("/files/\(fileId)")

        // Download encrypted data from server
        let encryptedData = try await apiClient.download(
            "/files/\(fileId)/download",
            progress: { p in progress(p * 0.8) }
        )

        // Attempt decryption with folder key hierarchy
        let fileData: Data
        if let encryptedFileKeyB64 = fileItem.encryptedFileKey,
           let nonceB64 = fileItem.nonce,
           let keyNonceB64 = fileItem.keyNonce,
           let folderId = fileItem.folderId,
           let wrappedFileKey = Data(base64Encoded: encryptedFileKeyB64),
           let fileNonce = Data(base64Encoded: nonceB64),
           let keyNonce = Data(base64Encoded: keyNonceB64),
           let folderKey = loadFolderKey(folderId: folderId) {
            fileData = (try? encryptionService.decryptFileWithWrappedKey(
                ciphertext: encryptedData,
                fileNonce: fileNonce,
                wrappedFileKey: wrappedFileKey,
                keyNonce: keyNonce,
                folderKey: folderKey
            )) ?? encryptedData
        } else {
            // No folder key hierarchy metadata — return raw data
            // (may be PQC-encrypted or plaintext, handled by caller)
            fileData = encryptedData
        }

        progress(0.9)

        // Cache the decrypted file
        let cacheURL = cacheDirectory.appendingPathComponent(fileId)
        try fileData.write(to: cacheURL)

        progress(1.0)
        return cacheURL
    }

    func deleteFile(fileId: String) async throws {
        try await apiClient.requestNoContent("/files/\(fileId)", method: .delete)

        // Remove from cache
        let cacheURL = cacheDirectory.appendingPathComponent(fileId)
        try? FileManager.default.removeItem(at: cacheURL)
    }

    func renameFile(fileId: String, newName: String) async throws -> FileItem {
        let body = RenameRequest(name: newName)
        return try await apiClient.request("/files/\(fileId)", method: .patch, body: body)
    }

    func moveFile(fileId: String, toFolderId: String?) async throws -> FileItem {
        let body = MoveRequest(folderId: toFolderId)
        return try await apiClient.request("/files/\(fileId)/move", method: .post, body: body)
    }

    func copyFile(fileId: String, toFolderId: String?) async throws -> FileItem {
        let body = MoveRequest(folderId: toFolderId)
        return try await apiClient.request("/files/\(fileId)/copy", method: .post, body: body)
    }

    // MARK: - Folders

    func createFolder(name: String, parentId: String?) async throws -> Folder {
        let body = CreateFolderRequest(name: name, parentId: parentId)
        let folder: Folder = try await apiClient.request("/folders", method: .post, body: body)

        // Generate a folder KEK and store it locally for use by the FileProvider extension.
        // The folder key is stored in the shared keychain so the FP extension can encrypt/decrypt.
        // In a full implementation, the folder key would be KEM-encrypted for the owner
        // and stored on the server. For now, we generate and cache locally.
        let folderKey = encryptionService.generateFolderKey()
        storeFolderKey(folderId: folder.id, key: folderKey)

        return folder
    }

    func getFolder(folderId: String) async throws -> Folder {
        try await apiClient.request("/folders/\(folderId)")
    }

    func deleteFolder(folderId: String) async throws {
        try await apiClient.requestNoContent("/folders/\(folderId)", method: .delete)
    }

    func renameFolder(folderId: String, newName: String) async throws -> Folder {
        let body = RenameRequest(name: newName)
        return try await apiClient.request("/folders/\(folderId)", method: .patch, body: body)
    }

    func moveFolder(folderId: String, toParentId: String?) async throws -> Folder {
        let body = MoveFolderRequest(parentId: toParentId)
        return try await apiClient.request("/folders/\(folderId)/move", method: .post, body: body)
    }

    // MARK: - Search

    func search(query: String) async throws -> FolderContents {
        // Zero-knowledge: server cannot search encrypted filenames.
        // Fetch all accessible files and return them for client-side filtering.
        let response: AccessibleFilesResponse = try await apiClient.request(
            "/files/accessible?status=complete&page_size=100"
        )
        let files = response.data ?? []
        return FolderContents(
            folder: nil,
            files: files,
            subfolders: [],
            breadcrumbs: nil
        )
    }

    // MARK: - Offline Cache

    func isFileCached(fileId: String) -> Bool {
        let cacheURL = cacheDirectory.appendingPathComponent(fileId)
        return FileManager.default.fileExists(atPath: cacheURL.path)
    }

    func getCachedFile(fileId: String) -> URL? {
        let cacheURL = cacheDirectory.appendingPathComponent(fileId)
        if FileManager.default.fileExists(atPath: cacheURL.path) {
            return cacheURL
        }
        return nil
    }

    func clearCache() async throws {
        for dir in [cacheDirectory, metadataCacheDirectory] {
            let contents = try FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil
            )
            for url in contents {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    func getCacheSize() async -> Int64 {
        var totalSize: Int64 = 0

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else {
            return 0
        }

        for url in contents {
            if let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey]),
               let fileSize = resourceValues.fileSize {
                totalSize += Int64(fileSize)
            }
        }

        return totalSize
    }

    // MARK: - Metadata Cache

    private func metadataCacheURL(folderId: String?) -> URL {
        let key = folderId ?? "root"
        return metadataCacheDirectory.appendingPathComponent("folder_\(key).json")
    }

    private func saveFolderContentsCache(_ contents: FolderContents, folderId: String?) {
        let url = metadataCacheURL(folderId: folderId)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(contents) else { return }
        try? data.write(to: url)
    }

    private func loadFolderContentsCache(folderId: String?) -> FolderContents? {
        let url = metadataCacheURL(folderId: folderId)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(FolderContents.self, from: data)
    }

    // MARK: - Folder Key Management

    /// Load a decrypted folder key from the local keychain.
    /// In a full implementation this would decapsulate the folder KEK from the server response.
    private func loadFolderKey(folderId: String) -> Data? {
        // Read from UserDefaults app group or keychain
        let key = "folder_key_\(folderId)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.Keychain.serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    /// Store a decrypted folder key in the local keychain.
    /// Also syncs to the shared keychain for the FileProvider extension.
    private func storeFolderKey(folderId: String, key: Data) {
        let account = "folder_key_\(folderId)"

        // Store in main keychain
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.Keychain.serviceName,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.Keychain.serviceName,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: key
        ]
        SecItemAdd(addQuery as CFDictionary, nil)

        // Sync to shared keychain for File Provider extension
        if let group = Constants.Keychain.accessGroup {
            let sharedAccount = "shared_folder_key_\(folderId)"
            let sharedDeleteQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: Constants.Keychain.serviceName,
                kSecAttrAccount as String: sharedAccount,
                kSecAttrAccessGroup as String: group
            ]
            SecItemDelete(sharedDeleteQuery as CFDictionary)

            let sharedAddQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: Constants.Keychain.serviceName,
                kSecAttrAccount as String: sharedAccount,
                kSecAttrAccessGroup as String: group,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                kSecValueData as String: key
            ]
            SecItemAdd(sharedAddQuery as CFDictionary, nil)
        }
    }

    // MARK: - Private Helpers

    private func mimeType(for url: URL) -> String {
        let pathExtension = url.pathExtension.lowercased()

        let mimeTypes: [String: String] = [
            "jpg": "image/jpeg",
            "jpeg": "image/jpeg",
            "png": "image/png",
            "gif": "image/gif",
            "pdf": "application/pdf",
            "doc": "application/msword",
            "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "xls": "application/vnd.ms-excel",
            "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "txt": "text/plain",
            "mp4": "video/mp4",
            "mov": "video/quicktime",
            "mp3": "audio/mpeg",
            "m4a": "audio/mp4",
            "zip": "application/zip"
        ]

        return mimeTypes[pathExtension] ?? "application/octet-stream"
    }
}

// MARK: - Request/Response Types

private struct FolderContentsResponse: Codable {
    let folder: Folder?
    let files: [FileItem]?
    let subfolders: [Folder]?
    let breadcrumbs: [Folder]?

    func toFolderContents() -> FolderContents {
        FolderContents(
            folder: folder,
            files: files ?? [],
            subfolders: subfolders ?? [],
            breadcrumbs: breadcrumbs
        )
    }
}

private struct AccessibleFilesResponse: Codable {
    let data: [FileItem]?
    let meta: PaginationMeta?
}

private struct PaginationMeta: Codable {
    let page: Int?
    let pageSize: Int?
    let totalItems: Int?
    let totalPages: Int?
    let hasNext: Bool?
    let hasPrev: Bool?

    enum CodingKeys: String, CodingKey {
        case page
        case pageSize = "page_size"
        case totalItems = "total_items"
        case totalPages = "total_pages"
        case hasNext = "has_next"
        case hasPrev = "has_prev"
    }
}

private struct RenameRequest: Codable {
    let name: String
}

private struct MoveRequest: Codable {
    let folderId: String?

    enum CodingKeys: String, CodingKey {
        case folderId = "folder_id"
    }
}

private struct MoveFolderRequest: Codable {
    let parentId: String?

    enum CodingKeys: String, CodingKey {
        case parentId = "parent_id"
    }
}

private struct CreateFolderRequest: Codable {
    let name: String
    let parentId: String?

    enum CodingKeys: String, CodingKey {
        case name
        case parentId = "parent_id"
    }
}
