import FileProvider
import UniformTypeIdentifiers
import CryptoKit

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

    /// Provide the actual file content
    func fetchContents(for itemIdentifier: NSFileProviderItemIdentifier, version requestedVersion: NSFileProviderItemVersion?, request: NSFileProviderRequest, completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 100)

        Task {
            do {
                let fileItem = try await apiClient.getFile(itemIdentifier.rawValue)
                progress.completedUnitCount = 10

                let encryptedData = try await apiClient.downloadFile(itemIdentifier.rawValue)
                progress.completedUnitCount = 80

                // Attempt decryption using folder key hierarchy first, then PQC fallback
                let fileData: Data
                if let decrypted = try? self.decryptWithFolderKeyHierarchy(fileItem: fileItem, encryptedData: encryptedData) {
                    // Folder key hierarchy decryption succeeded
                    fileData = decrypted
                } else if var kazKey = FPKeychainReader.readKazKemPrivateKey(),
                          var mlKey = FPKeychainReader.readMlKemPrivateKey() {
                    // Fallback: PQC hybrid decryption (legacy envelope format)
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
                    // No keys available — serve raw data (graceful degradation)
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

                    let mimeType = itemTemplate.contentType?.preferredMIMEType ?? "application/octet-stream"

                    // Try folder key hierarchy encryption first
                    if let parentId,
                       let folderKey = self.readFolderKey(folderId: parentId) {
                        let result = try self.encryptWithFolderKey(data: fileData, folderKey: folderKey)
                        progress.completedUnitCount = 50

                        let uploaded = try await apiClient.uploadFile(
                            name: itemTemplate.filename,
                            data: result.encryptedData,
                            mimeType: mimeType,
                            folderId: parentId,
                            encryptedFileKey: result.wrappedFileKey,
                            nonce: result.nonce,
                            keyNonce: result.keyNonce,
                            algorithm: "aes-256-gcm"
                        )
                        progress.completedUnitCount = 90

                        let item = FileProviderItem.from(fpFile: uploaded, parentIdentifier: itemTemplate.parentItemIdentifier)
                        completionHandler(item, [], false, nil)
                    } else {
                        // Fallback: PQC hybrid encryption or plaintext
                        let uploadData = self.encryptIfPossible(fileData)
                        progress.completedUnitCount = 50

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

                    if let parentFolderId,
                       let folderKey = self.readFolderKey(folderId: parentFolderId) {
                        let result = try self.encryptWithFolderKey(data: fileData, folderKey: folderKey)
                        let uploaded = try await apiClient.uploadFile(
                            name: item.filename,
                            data: result.encryptedData,
                            mimeType: mimeType,
                            folderId: parentFolderId,
                            encryptedFileKey: result.wrappedFileKey,
                            nonce: result.nonce,
                            keyNonce: result.keyNonce,
                            algorithm: "aes-256-gcm"
                        )
                        resultItem = FileProviderItem.from(fpFile: uploaded, parentIdentifier: item.parentItemIdentifier)
                    } else {
                        let uploadData = self.encryptIfPossible(fileData)
                        let uploaded = try await apiClient.uploadFile(
                            name: item.filename,
                            data: uploadData,
                            mimeType: mimeType,
                            folderId: parentFolderId
                        )
                        resultItem = FileProviderItem.from(fpFile: uploaded, parentIdentifier: item.parentItemIdentifier)
                    }
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

    // MARK: - Folder Key Hierarchy Encryption

    /// Result of encrypting file data with the folder key hierarchy.
    private struct FolderKeyEncryptionResult {
        let encryptedData: Data     // encrypted file content (ciphertext + tag)
        let wrappedFileKey: String  // base64: wrapped file DEK (ciphertext + tag)
        let nonce: String           // base64: file data nonce
        let keyNonce: String        // base64: key wrapping nonce
    }

    /// Read a decrypted folder key from the shared keychain.
    /// The main app stores folder keys keyed by folder ID after unlocking them.
    private func readFolderKey(folderId: String) -> Data? {
        FPKeychainReader.readFolderKey(folderId: folderId)
    }

    /// Encrypt file data using the folder key hierarchy (AES-256-GCM).
    ///
    /// 1. Generate a random 256-bit file DEK.
    /// 2. Encrypt file data with the file DEK.
    /// 3. Wrap the file DEK with the folder KEK.
    private func encryptWithFolderKey(data: Data, folderKey: Data) throws -> FolderKeyEncryptionResult {
        // Generate file DEK
        var fileKey = Data(count: 32)
        fileKey.withUnsafeMutableBytes { ptr in
            _ = SecRandomCopyBytes(kSecRandomDefault, 32, ptr.baseAddress!)
        }
        defer {
            fileKey.withUnsafeMutableBytes { ptr in
                if let base = ptr.baseAddress { memset(base, 0, ptr.count) }
            }
        }

        // Encrypt file data with file DEK
        let fileSymKey = SymmetricKey(data: fileKey)
        let fileNonce = AES.GCM.Nonce()
        let fileSealedBox = try AES.GCM.seal(data, using: fileSymKey, nonce: fileNonce)
        let encryptedData = fileSealedBox.ciphertext + fileSealedBox.tag

        // Wrap file DEK with folder KEK
        let wrapSymKey = SymmetricKey(data: folderKey)
        let wrapNonce = AES.GCM.Nonce()
        let wrapSealedBox = try AES.GCM.seal(fileKey, using: wrapSymKey, nonce: wrapNonce)
        let wrappedKey = wrapSealedBox.ciphertext + wrapSealedBox.tag

        return FolderKeyEncryptionResult(
            encryptedData: Data(encryptedData),
            wrappedFileKey: Data(wrappedKey).base64EncodedString(),
            nonce: Data(fileNonce).base64EncodedString(),
            keyNonce: Data(wrapNonce).base64EncodedString()
        )
    }

    /// Decrypt file data using the folder key hierarchy.
    ///
    /// Requires the file to have encryption metadata (encrypted_file_key, nonce, key_nonce)
    /// and the folder key to be available in the shared keychain.
    private func decryptWithFolderKeyHierarchy(fileItem: FPFileItem, encryptedData: Data) throws -> Data {
        guard let encryptedFileKeyB64 = fileItem.encryptedFileKey,
              let nonceB64 = fileItem.nonce,
              let keyNonceB64 = fileItem.keyNonce,
              let folderId = fileItem.folderId,
              let wrappedFileKey = Data(base64Encoded: encryptedFileKeyB64),
              let fileNonceData = Data(base64Encoded: nonceB64),
              let keyNonceData = Data(base64Encoded: keyNonceB64),
              let folderKey = readFolderKey(folderId: folderId) else {
            throw NSFileProviderError(.cannotSynchronize)
        }

        // Unwrap file DEK
        let tagSize = 16
        guard wrappedFileKey.count >= tagSize else {
            throw NSFileProviderError(.cannotSynchronize)
        }

        let wrapSymKey = SymmetricKey(data: folderKey)
        guard let wrapNonce = try? AES.GCM.Nonce(data: keyNonceData) else {
            throw NSFileProviderError(.cannotSynchronize)
        }

        let wrapCiphertext = wrappedFileKey.prefix(wrappedFileKey.count - tagSize)
        let wrapTag = wrappedFileKey.suffix(tagSize)
        let wrapBox = try AES.GCM.SealedBox(nonce: wrapNonce, ciphertext: wrapCiphertext, tag: wrapTag)
        var fileKey = try AES.GCM.open(wrapBox, using: wrapSymKey)
        defer {
            fileKey.withUnsafeMutableBytes { ptr in
                if let base = ptr.baseAddress { memset(base, 0, ptr.count) }
            }
        }

        // Decrypt file data
        guard encryptedData.count >= tagSize else {
            throw NSFileProviderError(.cannotSynchronize)
        }

        let fileSymKey = SymmetricKey(data: fileKey)
        guard let fileNonce = try? AES.GCM.Nonce(data: fileNonceData) else {
            throw NSFileProviderError(.cannotSynchronize)
        }

        let fileCiphertext = encryptedData.prefix(encryptedData.count - tagSize)
        let fileTag = encryptedData.suffix(tagSize)
        let fileBox = try AES.GCM.SealedBox(nonce: fileNonce, ciphertext: fileCiphertext, tag: fileTag)
        return try AES.GCM.open(fileBox, using: fileSymKey)
    }
}
