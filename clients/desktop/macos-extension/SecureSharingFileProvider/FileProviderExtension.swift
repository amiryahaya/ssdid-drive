import FileProvider
import os.log

/// Main File Provider extension class that integrates SecureSharing with Finder
class FileProviderExtension: NSObject, NSFileProviderReplicatedExtension {

    // MARK: - Properties

    let domain: NSFileProviderDomain
    let manager: NSFileProviderManager
    private let logger = Logger(subsystem: "com.securesharing.fileprovider", category: "Extension")
    private let apiClient: APIClient
    private let sharedDefaults: SharedDefaults
    private let keychainHelper: KeychainHelper

    // MARK: - Initialization

    required init(domain: NSFileProviderDomain) {
        self.domain = domain
        self.manager = NSFileProviderManager(for: domain)!
        self.apiClient = APIClient()
        self.sharedDefaults = SharedDefaults()
        self.keychainHelper = KeychainHelper()
        super.init()

        logger.info("FileProviderExtension initialized for domain: \(domain.identifier.rawValue)")
    }

    // MARK: - NSFileProviderReplicatedExtension

    func invalidate() {
        logger.info("Extension invalidated")
    }

    /// Fetch item metadata by identifier
    func item(for identifier: NSFileProviderItemIdentifier,
              request: NSFileProviderRequest,
              completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) -> Progress {

        let progress = Progress(totalUnitCount: 1)

        logger.debug("Fetching item: \(identifier.rawValue)")

        // Handle special identifiers
        if identifier == .rootContainer {
            let rootItem = FileProviderItem(
                id: "root",
                name: "SecureSharing",
                parentId: "",
                isFolder: true,
                size: 0,
                createdAt: Date(),
                modifiedAt: Date(),
                contentVersion: Data()
            )
            completionHandler(rootItem, nil)
            progress.completedUnitCount = 1
            return progress
        }

        if identifier == .workingSet {
            // Working set is handled by enumerator
            completionHandler(nil, NSFileProviderError(.noSuchItem))
            progress.completedUnitCount = 1
            return progress
        }

        // Fetch from cache or API
        Task {
            do {
                guard let authToken = keychainHelper.getAuthToken() else {
                    throw NSFileProviderError(.notAuthenticated)
                }

                let item = try await apiClient.fetchFileMetadata(
                    fileId: identifier.rawValue,
                    authToken: authToken
                )

                completionHandler(item, nil)
            } catch {
                logger.error("Failed to fetch item \(identifier.rawValue): \(error.localizedDescription)")
                completionHandler(nil, error)
            }
            progress.completedUnitCount = 1
        }

        return progress
    }

    /// Download file contents
    func fetchContents(for itemIdentifier: NSFileProviderItemIdentifier,
                       version requestedVersion: NSFileProviderItemVersion?,
                       request: NSFileProviderRequest,
                       completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void) -> Progress {

        let progress = Progress(totalUnitCount: 100)

        logger.info("Downloading contents for: \(itemIdentifier.rawValue)")

        Task {
            do {
                guard let authToken = keychainHelper.getAuthToken() else {
                    throw NSFileProviderError(.notAuthenticated)
                }

                // Get file metadata
                let item = try await apiClient.fetchFileMetadata(
                    fileId: itemIdentifier.rawValue,
                    authToken: authToken
                )

                // Download encrypted content
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(item.filename.pathExtension)

                try await apiClient.downloadFile(
                    fileId: itemIdentifier.rawValue,
                    to: tempURL,
                    authToken: authToken,
                    progress: { downloadProgress in
                        progress.completedUnitCount = Int64(downloadProgress * 100)
                    }
                )

                // Request decryption from main app via App Groups
                let decryptedURL = try await requestDecryption(encryptedURL: tempURL, fileId: itemIdentifier.rawValue)

                completionHandler(decryptedURL, item, nil)
            } catch {
                logger.error("Failed to download \(itemIdentifier.rawValue): \(error.localizedDescription)")
                completionHandler(nil, nil, error)
            }
            progress.completedUnitCount = 100
        }

        return progress
    }

    /// Create a new file or folder
    func createItem(basedOn itemTemplate: NSFileProviderItem,
                    fields: NSFileProviderItemFields,
                    contents url: URL?,
                    options: NSFileProviderCreateItemOptions,
                    request: NSFileProviderRequest,
                    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {

        let progress = Progress(totalUnitCount: 100)

        logger.info("Creating item: \(itemTemplate.filename)")

        Task {
            do {
                guard let authToken = keychainHelper.getAuthToken() else {
                    throw NSFileProviderError(.notAuthenticated)
                }

                let parentId = itemTemplate.parentItemIdentifier == .rootContainer
                    ? "root"
                    : itemTemplate.parentItemIdentifier.rawValue

                if itemTemplate.contentType == .folder {
                    // Create folder
                    let item = try await apiClient.createFolder(
                        name: itemTemplate.filename,
                        parentId: parentId,
                        authToken: authToken
                    )
                    completionHandler(item, [], false, nil)
                } else if let contentURL = url {
                    // Request encryption from main app
                    let encryptedURL = try await requestEncryption(plainURL: contentURL)

                    // Upload encrypted file
                    let item = try await apiClient.uploadFile(
                        name: itemTemplate.filename,
                        parentId: parentId,
                        contentURL: encryptedURL,
                        authToken: authToken,
                        progress: { uploadProgress in
                            progress.completedUnitCount = Int64(uploadProgress * 100)
                        }
                    )
                    completionHandler(item, [], false, nil)
                } else {
                    throw NSFileProviderError(.noSuchItem)
                }
            } catch {
                logger.error("Failed to create item: \(error.localizedDescription)")
                completionHandler(nil, [], false, error)
            }
            progress.completedUnitCount = 100
        }

        return progress
    }

    /// Modify an existing item
    func modifyItem(_ item: NSFileProviderItem,
                    baseVersion version: NSFileProviderItemVersion,
                    changedFields: NSFileProviderItemFields,
                    contents newContents: URL?,
                    options: NSFileProviderModifyItemOptions,
                    request: NSFileProviderRequest,
                    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {

        let progress = Progress(totalUnitCount: 100)

        logger.info("Modifying item: \(item.itemIdentifier.rawValue)")

        Task {
            do {
                guard let authToken = keychainHelper.getAuthToken() else {
                    throw NSFileProviderError(.notAuthenticated)
                }

                var updatedItem: FileProviderItem?

                // Handle rename
                if changedFields.contains(.filename) {
                    updatedItem = try await apiClient.renameFile(
                        fileId: item.itemIdentifier.rawValue,
                        newName: item.filename,
                        authToken: authToken
                    )
                }

                // Handle move
                if changedFields.contains(.parentItemIdentifier) {
                    let newParentId = item.parentItemIdentifier == .rootContainer
                        ? "root"
                        : item.parentItemIdentifier.rawValue

                    updatedItem = try await apiClient.moveFile(
                        fileId: item.itemIdentifier.rawValue,
                        newParentId: newParentId,
                        authToken: authToken
                    )
                }

                // Handle content update
                if changedFields.contains(.contents), let contentURL = newContents {
                    // Request encryption from main app
                    let encryptedURL = try await requestEncryption(plainURL: contentURL)

                    updatedItem = try await apiClient.updateFileContent(
                        fileId: item.itemIdentifier.rawValue,
                        contentURL: encryptedURL,
                        authToken: authToken,
                        progress: { uploadProgress in
                            progress.completedUnitCount = Int64(uploadProgress * 100)
                        }
                    )
                }

                completionHandler(updatedItem ?? item as? FileProviderItem, [], false, nil)
            } catch {
                logger.error("Failed to modify item: \(error.localizedDescription)")
                completionHandler(nil, [], false, error)
            }
            progress.completedUnitCount = 100
        }

        return progress
    }

    /// Delete an item
    func deleteItem(identifier: NSFileProviderItemIdentifier,
                    baseVersion version: NSFileProviderItemVersion,
                    options: NSFileProviderDeleteItemOptions,
                    request: NSFileProviderRequest,
                    completionHandler: @escaping (Error?) -> Void) -> Progress {

        let progress = Progress(totalUnitCount: 1)

        logger.info("Deleting item: \(identifier.rawValue)")

        Task {
            do {
                guard let authToken = keychainHelper.getAuthToken() else {
                    throw NSFileProviderError(.notAuthenticated)
                }

                try await apiClient.deleteFile(
                    fileId: identifier.rawValue,
                    authToken: authToken
                )

                completionHandler(nil)
            } catch {
                logger.error("Failed to delete item: \(error.localizedDescription)")
                completionHandler(error)
            }
            progress.completedUnitCount = 1
        }

        return progress
    }

    /// Create enumerator for directory listing
    func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier,
                    request: NSFileProviderRequest) throws -> NSFileProviderEnumerator {

        logger.debug("Creating enumerator for: \(containerItemIdentifier.rawValue)")

        return FileProviderEnumerator(
            containerItemIdentifier: containerItemIdentifier,
            apiClient: apiClient,
            keychainHelper: keychainHelper
        )
    }

    // MARK: - Crypto Integration (Delegates to Main App)

    /// Request decryption from main app via App Groups IPC
    private func requestDecryption(encryptedURL: URL, fileId: String) async throws -> URL {
        // Write request to shared container
        let requestId = UUID().uuidString
        let request = CryptoRequest(
            id: requestId,
            type: .decrypt,
            inputPath: encryptedURL.path,
            fileId: fileId
        )

        try sharedDefaults.writeCryptoRequest(request)

        // Signal main app (if running) via distributed notification
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("com.securesharing.cryptoRequest"),
            object: nil,
            userInfo: ["requestId": requestId],
            deliverImmediately: true
        )

        // Wait for response (with timeout)
        let response = try await waitForCryptoResponse(requestId: requestId, timeout: 30)

        guard let outputPath = response.outputPath else {
            throw NSFileProviderError(.serverUnreachable)
        }

        return URL(fileURLWithPath: outputPath)
    }

    /// Request encryption from main app via App Groups IPC
    private func requestEncryption(plainURL: URL) async throws -> URL {
        let requestId = UUID().uuidString
        let request = CryptoRequest(
            id: requestId,
            type: .encrypt,
            inputPath: plainURL.path,
            fileId: nil
        )

        try sharedDefaults.writeCryptoRequest(request)

        // Signal main app
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("com.securesharing.cryptoRequest"),
            object: nil,
            userInfo: ["requestId": requestId],
            deliverImmediately: true
        )

        let response = try await waitForCryptoResponse(requestId: requestId, timeout: 60)

        guard let outputPath = response.outputPath else {
            throw NSFileProviderError(.serverUnreachable)
        }

        return URL(fileURLWithPath: outputPath)
    }

    /// Wait for crypto response from main app
    private func waitForCryptoResponse(requestId: String, timeout: TimeInterval) async throws -> CryptoResponse {
        let startTime = Date()

        while Date().timeIntervalSince(startTime) < timeout {
            if let response = sharedDefaults.readCryptoResponse(requestId: requestId) {
                // Clean up
                sharedDefaults.clearCryptoRequest(requestId: requestId)
                sharedDefaults.clearCryptoResponse(requestId: requestId)

                if let error = response.error {
                    throw NSError(domain: "com.securesharing.crypto", code: -1, userInfo: [NSLocalizedDescriptionKey: error])
                }

                return response
            }

            // Poll every 100ms
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        throw NSFileProviderError(.serverUnreachable)
    }
}

// MARK: - Crypto IPC Models

enum CryptoRequestType: String, Codable {
    case encrypt
    case decrypt
}

struct CryptoRequest: Codable {
    let id: String
    let type: CryptoRequestType
    let inputPath: String
    let fileId: String?
}

struct CryptoResponse: Codable {
    let requestId: String
    let outputPath: String?
    let error: String?
}

// MARK: - String Extension

extension String {
    var pathExtension: String {
        (self as NSString).pathExtension
    }
}
