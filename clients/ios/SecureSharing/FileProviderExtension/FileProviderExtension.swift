import FileProvider
import UniformTypeIdentifiers

/// File Provider extension for SecureSharing.
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

    /// Provide the actual file content
    func fetchContents(for itemIdentifier: NSFileProviderItemIdentifier, version requestedVersion: NSFileProviderItemVersion?, request: NSFileProviderRequest, completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 100)

        Task {
            do {
                let fileItem = try await apiClient.getFile(itemIdentifier.rawValue)
                progress.completedUnitCount = 10

                let encryptedData = try await apiClient.downloadFile(itemIdentifier.rawValue)
                progress.completedUnitCount = 80

                // Attempt decryption — if keys unavailable or decryption fails, serve encrypted (graceful degradation)
                let fileData: Data
                if var kazKey = FPKeychainReader.readKazKemPrivateKey(),
                   var mlKey = FPKeychainReader.readMlKemPrivateKey() {
                    defer {
                        FPDecryptor.fpSecureZero(&kazKey)
                        FPDecryptor.fpSecureZero(&mlKey)
                    }
                    fileData = (try? FPDecryptor.decrypt(
                        encryptedData: encryptedData,
                        kazKemPrivateKey: kazKey,
                        mlKemPrivateKey: mlKey
                    )) ?? encryptedData
                } else {
                    fileData = encryptedData
                }

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

    /// Create a new item
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

                    // Encrypt data if public keys are available
                    let uploadData = self.encryptIfPossible(fileData)
                    progress.completedUnitCount = 50

                    let mimeType = itemTemplate.contentType?.preferredMIMEType ?? "application/octet-stream"
                    let uploaded = try await apiClient.uploadFile(
                        name: itemTemplate.filename,
                        data: uploadData,
                        mimeType: mimeType,
                        folderId: parentId
                    )
                    progress.completedUnitCount = 90

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
                    let uploadData = self.encryptIfPossible(fileData)
                    let mimeType = item.contentType?.preferredMIMEType ?? "application/octet-stream"
                    let uploaded = try await apiClient.uploadFile(
                        name: item.filename,
                        data: uploadData,
                        mimeType: mimeType,
                        folderId: resolveParentId(item.parentItemIdentifier)
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

    // MARK: - Encryption

    /// Encrypt data if public keys are available in the shared keychain.
    /// Falls back to plaintext if keys are not available (graceful degradation).
    private func encryptIfPossible(_ data: Data) -> Data {
        guard let kazKemPublicKey = FPKeychainReader.readKazKemPublicKey(),
              let mlKemPublicKey = FPKeychainReader.readMlKemPublicKey() else {
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
            return data
        }
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
