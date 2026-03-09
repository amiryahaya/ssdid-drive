import FileProvider
import UniformTypeIdentifiers

/// File Provider extension for SsdidDrive.
/// Makes encrypted files appear natively in Finder/Files.app with on-demand download and upload.
class FileProviderExtension: NSObject, NSFileProviderReplicatedExtension {

    // MARK: - Properties

    let domain: NSFileProviderDomain
    private let apiClient: FPAPIClient
    private let tempStorage: FPTemporaryStorage

    // MARK: - Initialization

    required init(domain: NSFileProviderDomain) {
        self.domain = domain
        self.apiClient = FPAPIClient()
        self.tempStorage = FPTemporaryStorage()
        super.init()
    }

    // MARK: - NSFileProviderReplicatedExtension

    func invalidate() {
        tempStorage.removeAll()
    }

    /// Return the item for the given identifier
    func item(for identifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest, completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)

        if identifier == .rootContainer {
            let rootItem = FileProviderItem.rootContainer()
            completionHandler(rootItem, nil)
            progress.completedUnitCount = 1
            return progress
        }

        Task {
            do {
                let item = try await fetchItem(identifier: identifier)
                completionHandler(item, nil)
            } catch {
                completionHandler(nil, mapError(error))
            }
            progress.completedUnitCount = 1
        }

        return progress
    }

    /// Fetch contents of a directory
    func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest) throws -> NSFileProviderEnumerator {
        return FileProviderEnumerator(
            enumeratedItemIdentifier: containerItemIdentifier,
            apiClient: apiClient
        )
    }

    /// Provide the actual file content.
    ///
    /// Decryption strategy (in priority order):
    /// 1. Folder-key hierarchy via `FPDecryptor.decryptDownload` — used when the file has
    ///    encryption metadata (encrypted_file_key, nonce, key_nonce) and the folder key
    ///    is available in the shared keychain.
    /// 2. PQC hybrid envelope via `FPDecryptor.decrypt` — legacy format using KAZ-KEM + ML-KEM.
    /// 3. Graceful fallback — serve the raw downloaded bytes if no keys are available or
    ///    decryption fails.
    func fetchContents(for itemIdentifier: NSFileProviderItemIdentifier, version requestedVersion: NSFileProviderItemVersion?, request: NSFileProviderRequest, completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 100)

        Task {
            do {
                let fileItem = try await apiClient.getFile(itemIdentifier.rawValue)
                progress.completedUnitCount = 10

                let downloadedData = try await apiClient.downloadFile(itemIdentifier.rawValue)
                progress.completedUnitCount = 80

                let fileData = self.decryptDownloadedFile(fileItem: fileItem, downloadedData: downloadedData)

                let tempURL = tempStorage.temporaryURL(for: itemIdentifier.rawValue, filename: fileItem.name)
                try fileData.write(to: tempURL)
                progress.completedUnitCount = 90

                let item = FileProviderItem.from(fpFile: fileItem, parentIdentifier: parentIdentifier(for: fileItem))
                completionHandler(tempURL, item, nil)
                progress.completedUnitCount = 100
            } catch {
                completionHandler(nil, nil, mapError(error))
            }
        }

        return progress
    }

    /// Create a new item (file or folder).
    ///
    /// For files, the upload flow is:
    /// 1. Read the plaintext from the provided URL.
    /// 2. Obtain the folder key via `FPKeychainReader.requireFolderKey`.
    /// 3. Encrypt with `FPEncryptor.encryptForUpload` (AES-256-GCM, random DEK wrapped by folder KEK).
    /// 4. Upload ciphertext + encryption metadata to the server.
    /// 5. Graceful fallback: if folder key is unavailable or encryption fails, try PQC hybrid
    ///    encryption, or upload plaintext as a last resort.
    func createItem(basedOn itemTemplate: NSFileProviderItem, fields: NSFileProviderItemFields, contents url: URL?, options: NSFileProviderCreateItemOptions = [], request: NSFileProviderRequest, completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 100)

        Task {
            do {
                let parentId = resolveParentId(itemTemplate.parentItemIdentifier)

                if itemTemplate.contentType == .folder {
                    let folder = try await apiClient.createFolder(name: itemTemplate.filename, parentId: parentId)
                    let item = FileProviderItem.from(fpFolder: folder, parentIdentifier: itemTemplate.parentItemIdentifier)
                    completionHandler(item, [], false, nil)
                } else {
                    guard let url else {
                        completionHandler(nil, [], false, NSFileProviderError(.noSuchItem))
                        return
                    }
                    let fileData = try Data(contentsOf: url)
                    progress.completedUnitCount = 20

                    let mimeType = itemTemplate.contentType?.preferredMIMEType ?? "application/octet-stream"
                    // Use a temporary file ID for encryption context (server will assign the real one)
                    let tempFileId = UUID().uuidString

                    let uploaded = try await self.encryptAndUpload(
                        fileData: fileData,
                        fileName: itemTemplate.filename,
                        mimeType: mimeType,
                        folderId: parentId,
                        fileId: tempFileId,
                        progress: progress
                    )

                    let item = FileProviderItem.from(fpFile: uploaded, parentIdentifier: itemTemplate.parentItemIdentifier)
                    completionHandler(item, [], false, nil)
                }
                progress.completedUnitCount = 100
            } catch {
                completionHandler(nil, [], false, mapError(error))
            }
        }

        return progress
    }

    /// Modify an existing item
    func modifyItem(_ item: NSFileProviderItem, baseVersion version: NSFileProviderItemVersion, changedFields: NSFileProviderItemFields, contents newContents: URL?, options: NSFileProviderModifyItemOptions = [], request: NSFileProviderRequest, completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 100)

        Task {
            do {
                let itemId = item.itemIdentifier.rawValue
                var resultItem: FileProviderItem?

                // Handle rename
                if changedFields.contains(.filename) {
                    if item.contentType == .folder {
                        let folder = try await apiClient.renameFolder(itemId, newName: item.filename)
                        resultItem = FileProviderItem.from(fpFolder: folder, parentIdentifier: item.parentItemIdentifier)
                    } else {
                        let file = try await apiClient.renameFile(itemId, newName: item.filename)
                        resultItem = FileProviderItem.from(fpFile: file, parentIdentifier: item.parentItemIdentifier)
                    }
                }

                // Handle content update
                if changedFields.contains(.contents), let contentsURL = newContents {
                    let fileData = try Data(contentsOf: contentsURL)
                    let mimeType = item.contentType?.preferredMIMEType ?? "application/octet-stream"
                    let parentFolderId = resolveParentId(item.parentItemIdentifier)

                    let uploaded = try await self.encryptAndUpload(
                        fileData: fileData,
                        fileName: item.filename,
                        mimeType: mimeType,
                        folderId: parentFolderId,
                        fileId: itemId,
                        progress: progress
                    )
                    resultItem = FileProviderItem.from(fpFile: uploaded, parentIdentifier: item.parentItemIdentifier)
                }

                if let resultItem {
                    completionHandler(resultItem, [], false, nil)
                } else {
                    // No recognized changes — return the item as-is
                    let file = try await apiClient.getFile(itemId)
                    let fpItem = FileProviderItem.from(fpFile: file, parentIdentifier: item.parentItemIdentifier)
                    completionHandler(fpItem, [], false, nil)
                }
                progress.completedUnitCount = 100
            } catch {
                completionHandler(nil, [], false, mapError(error))
            }
        }

        return progress
    }

    /// Delete an item
    func deleteItem(identifier: NSFileProviderItemIdentifier, baseVersion version: NSFileProviderItemVersion, options: NSFileProviderDeleteItemOptions = [], request: NSFileProviderRequest, completionHandler: @escaping (Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)

        Task {
            do {
                // Try file deletion first; only fall back to folder on 404
                do {
                    try await apiClient.deleteFile(identifier.rawValue)
                } catch let error as NSFileProviderError where error.code == .noSuchItem {
                    try await apiClient.deleteFolder(identifier.rawValue)
                }
                completionHandler(nil)
            } catch {
                completionHandler(mapError(error))
            }
            progress.completedUnitCount = 1
        }

        return progress
    }

    // MARK: - Encryption (Upload)

    /// Encrypt file data and upload to the server.
    ///
    /// Strategy:
    /// 1. Try folder-key encryption via `FPEncryptor.encryptForUpload` — requires the folder key
    ///    to be in the shared keychain.
    /// 2. Fallback: PQC hybrid encryption via `FPEncryptor.encrypt` using KEM public keys.
    /// 3. Last resort: upload plaintext with a warning log.
    private func encryptAndUpload(
        fileData: Data,
        fileName: String,
        mimeType: String,
        folderId: String?,
        fileId: String,
        progress: Progress
    ) async throws -> FPFileItem {
        // Strategy 1: Folder-key hierarchy encryption via FPEncryptor
        if let folderId {
            do {
                var folderKey = try FPKeychainReader.requireFolderKey(folderId: folderId)
                defer { FPDecryptor.fpSecureZero(&folderKey) }

                let result = try FPEncryptor.encryptForUpload(
                    data: fileData,
                    folderKey: folderKey,
                    fileId: fileId
                )
                progress.completedUnitCount = 50

                let uploaded = try await apiClient.uploadFile(
                    name: fileName,
                    data: result.encryptedData,
                    mimeType: mimeType,
                    folderId: folderId,
                    encryptedFileKey: result.encryptedFileKey.base64EncodedString(),
                    nonce: result.fileNonce.base64EncodedString(),
                    keyNonce: result.keyNonce.base64EncodedString(),
                    algorithm: "aes-256-gcm"
                )
                progress.completedUnitCount = 90
                return uploaded
            } catch is FPKeychainReader.KeychainError {
                // Folder key not available — fall through to PQC or plaintext
                NSLog("[FileProvider] Folder key not available for folder %@, falling back", folderId)
            } catch {
                // Encryption failed — fall through with warning
                NSLog("[FileProvider] FPEncryptor.encryptForUpload failed: %@, falling back", "\(error)")
            }
        }

        // Strategy 2: PQC hybrid encryption
        let uploadData = encryptIfPossible(fileData)
        progress.completedUnitCount = 50

        let uploaded = try await apiClient.uploadFile(
            name: fileName,
            data: uploadData,
            mimeType: mimeType,
            folderId: folderId
        )
        progress.completedUnitCount = 90
        return uploaded
    }

    /// Encrypt data if public keys are available in the shared keychain.
    /// Falls back to plaintext if keys are not available (graceful degradation).
    private func encryptIfPossible(_ data: Data) -> Data {
        guard let kazKemPublicKey = FPKeychainReader.readKazKemPublicKey(),
              let mlKemPublicKey = FPKeychainReader.readMlKemPublicKey() else {
            NSLog("[FileProvider] KEM public keys not available, uploading unencrypted")
            return data
        }

        do {
            return try FPEncryptor.encrypt(
                data: data,
                kazKemPublicKey: kazKemPublicKey,
                mlKemPublicKey: mlKemPublicKey
            )
        } catch {
            // Graceful degradation: upload plaintext if encryption fails
            NSLog("[FileProvider] PQC hybrid encryption failed: %@, uploading unencrypted", "\(error)")
            return data
        }
    }

    // MARK: - Decryption (Download)

    /// Decrypt downloaded file data using the appropriate strategy.
    ///
    /// Strategy:
    /// 1. If the file has encryption metadata (encrypted_file_key, nonce, key_nonce), use
    ///    `FPDecryptor.decryptDownload` with the folder key from the shared keychain.
    /// 2. Fallback: PQC hybrid decryption via `FPDecryptor.decrypt` using KEM private keys.
    /// 3. Last resort: return the raw data as-is (graceful degradation).
    private func decryptDownloadedFile(fileItem: FPFileItem, downloadedData: Data) -> Data {
        // Strategy 1: Folder-key hierarchy decryption via FPDecryptor
        if let encryptedFileKeyB64 = fileItem.encryptedFileKey,
           let nonceB64 = fileItem.nonce,
           let keyNonceB64 = fileItem.keyNonce,
           let folderId = fileItem.folderId,
           let encryptedFileKey = Data(base64Encoded: encryptedFileKeyB64),
           let fileNonce = Data(base64Encoded: nonceB64),
           let keyNonce = Data(base64Encoded: keyNonceB64) {
            do {
                var folderKey = try FPKeychainReader.requireFolderKey(folderId: folderId)
                defer { FPDecryptor.fpSecureZero(&folderKey) }

                let plaintext = try FPDecryptor.decryptDownload(
                    encryptedData: downloadedData,
                    encryptedFileKey: encryptedFileKey,
                    folderKey: folderKey,
                    fileNonce: fileNonce,
                    keyNonce: keyNonce
                )
                return plaintext
            } catch {
                NSLog("[FileProvider] FPDecryptor.decryptDownload failed for file %@: %@", fileItem.id, "\(error)")
                // Fall through to PQC or raw data
            }
        }

        // Strategy 2: PQC hybrid decryption (legacy envelope format)
        if var kazKey = FPKeychainReader.readKazKemPrivateKey(),
           var mlKey = FPKeychainReader.readMlKemPrivateKey() {
            defer {
                FPDecryptor.fpSecureZero(&kazKey)
                FPDecryptor.fpSecureZero(&mlKey)
            }
            if let decrypted = try? FPDecryptor.decrypt(
                encryptedData: downloadedData,
                kazKemPrivateKey: kazKey,
                mlKemPrivateKey: mlKey
            ) {
                return decrypted
            }
            NSLog("[FileProvider] PQC hybrid decryption failed for file %@, serving raw data", fileItem.id)
        } else {
            NSLog("[FileProvider] No decryption keys available for file %@, serving raw data", fileItem.id)
        }

        // Strategy 3: Graceful fallback — return raw data
        return downloadedData
    }

    // MARK: - Private Helpers

    private func fetchItem(identifier: NSFileProviderItemIdentifier) async throws -> FileProviderItem {
        // Try fetching as a file first
        do {
            let file = try await apiClient.getFile(identifier.rawValue)
            return FileProviderItem.from(fpFile: file, parentIdentifier: parentIdentifier(for: file))
        } catch {
            // Fall back to folder
            let folder = try await apiClient.getFolder(identifier.rawValue)
            let parentId: NSFileProviderItemIdentifier = folder.parentId.map { NSFileProviderItemIdentifier($0) } ?? .rootContainer
            return FileProviderItem.from(fpFolder: folder, parentIdentifier: parentId)
        }
    }

    private func parentIdentifier(for file: FPFileItem) -> NSFileProviderItemIdentifier {
        if let folderId = file.folderId {
            return NSFileProviderItemIdentifier(folderId)
        }
        return .rootContainer
    }

    private func resolveParentId(_ identifier: NSFileProviderItemIdentifier) -> String? {
        if identifier == .rootContainer {
            return nil
        }
        return identifier.rawValue
    }

    private func mapError(_ error: Error) -> Error {
        if let fpError = error as? NSFileProviderError {
            return fpError
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return NSFileProviderError(.serverUnreachable)
            case .timedOut:
                return NSFileProviderError(.serverUnreachable)
            default:
                return NSFileProviderError(.serverUnreachable)
            }
        }
        return error
    }
}
