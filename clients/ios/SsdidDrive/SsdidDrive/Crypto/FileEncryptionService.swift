import Foundation
import CryptoKit

/// Lightweight AES-256-GCM file encryption service for the folder key hierarchy.
///
/// Provides symmetric-only operations for encrypting/decrypting file data and
/// wrapping/unwrapping keys in the folder-key/file-key hierarchy:
///
///   Folder KEK (256-bit) --wraps--> File DEK (256-bit) --encrypts--> file data
///
/// KEM encapsulation of the folder KEK is handled separately by `CryptoManager`
/// during sharing and initial folder creation.
final class FileEncryptionService {

    // MARK: - Types

    enum EncryptionError: Error, LocalizedError {
        case encryptionFailed
        case decryptionFailed
        case invalidKeySize
        case invalidNonce
        case invalidCiphertext

        var errorDescription: String? {
            switch self {
            case .encryptionFailed: return "File encryption failed"
            case .decryptionFailed: return "File decryption failed"
            case .invalidKeySize: return "Invalid key size (expected 32 bytes)"
            case .invalidNonce: return "Invalid nonce data"
            case .invalidCiphertext: return "Invalid ciphertext (too short for AES-GCM tag)"
            }
        }
    }

    /// Result of an AES-256-GCM encryption operation.
    struct SealedData {
        /// Ciphertext concatenated with 16-byte GCM authentication tag.
        let ciphertext: Data
        /// 12-byte AES-GCM nonce.
        let nonce: Data
    }

    // MARK: - Singleton

    static let shared = FileEncryptionService()

    private init() {}

    // MARK: - Key Generation

    /// Generate a random 256-bit key suitable for use as a folder KEK or file DEK.
    func generateKey() -> Data {
        var key = Data(count: 32)
        key.withUnsafeMutableBytes { ptr in
            _ = SecRandomCopyBytes(kSecRandomDefault, 32, ptr.baseAddress!)
        }
        return key
    }

    /// Generate a random 256-bit folder key (convenience alias).
    func generateFolderKey() -> Data {
        generateKey()
    }

    /// Generate a random 256-bit file key (convenience alias).
    func generateFileKey() -> Data {
        generateKey()
    }

    // MARK: - File Encryption / Decryption

    /// Encrypt file data with AES-256-GCM.
    ///
    /// - Parameters:
    ///   - data: Plaintext file data.
    ///   - key: 256-bit encryption key (file DEK).
    /// - Returns: Sealed data containing ciphertext+tag and nonce.
    func encryptFile(data: Data, key: Data) throws -> SealedData {
        guard key.count == 32 else { throw EncryptionError.invalidKeySize }

        let symmetricKey = SymmetricKey(data: key)
        let nonce = AES.GCM.Nonce()

        let sealedBox: AES.GCM.SealedBox
        do {
            sealedBox = try AES.GCM.seal(data, using: symmetricKey, nonce: nonce)
        } catch {
            throw EncryptionError.encryptionFailed
        }

        // ciphertext + 16-byte tag (no nonce prefix)
        let ciphertext = sealedBox.ciphertext + sealedBox.tag
        return SealedData(ciphertext: Data(ciphertext), nonce: Data(nonce))
    }

    /// Decrypt file data with AES-256-GCM.
    ///
    /// - Parameters:
    ///   - ciphertext: Ciphertext concatenated with 16-byte GCM tag.
    ///   - key: 256-bit decryption key (file DEK).
    ///   - nonce: 12-byte AES-GCM nonce.
    /// - Returns: Decrypted plaintext data.
    func decryptFile(ciphertext: Data, key: Data, nonce: Data) throws -> Data {
        guard key.count == 32 else { throw EncryptionError.invalidKeySize }

        let tagSize = 16
        guard ciphertext.count >= tagSize else { throw EncryptionError.invalidCiphertext }

        let symmetricKey = SymmetricKey(data: key)

        guard let gcmNonce = try? AES.GCM.Nonce(data: nonce) else {
            throw EncryptionError.invalidNonce
        }

        let actualCiphertext = ciphertext.prefix(ciphertext.count - tagSize)
        let tag = ciphertext.suffix(tagSize)

        let sealedBox: AES.GCM.SealedBox
        do {
            sealedBox = try AES.GCM.SealedBox(nonce: gcmNonce, ciphertext: actualCiphertext, tag: tag)
        } catch {
            throw EncryptionError.invalidCiphertext
        }

        do {
            return try AES.GCM.open(sealedBox, using: symmetricKey)
        } catch {
            throw EncryptionError.decryptionFailed
        }
    }

    // MARK: - Key Wrapping (AES-256-GCM)

    /// Wrap (encrypt) a key with another key using AES-256-GCM.
    ///
    /// Used to wrap a file DEK with its folder KEK, or a sub-folder KEK with its parent KEK.
    ///
    /// - Parameters:
    ///   - keyToWrap: The key to wrap (file DEK or child KEK).
    ///   - wrappingKey: The wrapping key (folder KEK or parent KEK).
    /// - Returns: Sealed data containing the wrapped key and nonce.
    func wrapKey(_ keyToWrap: Data, with wrappingKey: Data) throws -> SealedData {
        try encryptFile(data: keyToWrap, key: wrappingKey)
    }

    /// Unwrap (decrypt) a key with another key using AES-256-GCM.
    ///
    /// - Parameters:
    ///   - wrappedKey: The wrapped key (ciphertext + tag).
    ///   - wrappingKey: The wrapping key (folder KEK or parent KEK).
    ///   - nonce: 12-byte nonce used during wrapping.
    /// - Returns: The unwrapped raw key.
    func unwrapKey(_ wrappedKey: Data, with wrappingKey: Data, nonce: Data) throws -> Data {
        try decryptFile(ciphertext: wrappedKey, key: wrappingKey, nonce: nonce)
    }

    // MARK: - Convenience: Encrypt File With New Key

    /// Generate a new file DEK, encrypt the file data, and return everything needed for upload.
    ///
    /// - Parameters:
    ///   - data: Plaintext file data.
    ///   - folderKey: The folder KEK to wrap the file DEK with.
    /// - Returns: Tuple of encrypted file data, wrapped file key, and nonces.
    func encryptFileWithNewKey(
        data: Data,
        folderKey: Data
    ) throws -> (encryptedData: SealedData, wrappedFileKey: SealedData) {
        // Generate a random file DEK
        let fileKey = generateFileKey()

        // Encrypt file data with the file DEK
        let encryptedData = try encryptFile(data: data, key: fileKey)

        // Wrap the file DEK with the folder KEK
        let wrappedKey = try wrapKey(fileKey, with: folderKey)

        return (encryptedData, wrappedKey)
    }

    /// Decrypt a file given the wrapped file key and folder key.
    ///
    /// - Parameters:
    ///   - ciphertext: Encrypted file data (ciphertext + tag).
    ///   - fileNonce: Nonce used to encrypt the file data.
    ///   - wrappedFileKey: The file DEK wrapped with the folder KEK.
    ///   - keyNonce: Nonce used to wrap the file DEK.
    ///   - folderKey: The folder KEK.
    /// - Returns: Decrypted plaintext data.
    func decryptFileWithWrappedKey(
        ciphertext: Data,
        fileNonce: Data,
        wrappedFileKey: Data,
        keyNonce: Data,
        folderKey: Data
    ) throws -> Data {
        // Unwrap the file DEK
        let fileKey = try unwrapKey(wrappedFileKey, with: folderKey, nonce: keyNonce)

        // Decrypt the file data
        return try decryptFile(ciphertext: ciphertext, key: fileKey, nonce: fileNonce)
    }
}
