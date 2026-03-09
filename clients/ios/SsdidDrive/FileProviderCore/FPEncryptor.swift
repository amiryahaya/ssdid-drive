import Foundation
import CryptoKit
import KazKemNative

/// Standalone encryption engine for the File Provider extension.
/// Mirrors the hybrid PQC encryption from CryptoManager without UIKit or main app dependencies.
/// Uses KazKemNative for real KAZ-KEM encapsulation and HKDF placeholder for ML-KEM.
enum FPEncryptor {

    // MARK: - Types

    enum EncryptionError: Error {
        case kazKemNotInitialized
        case kazKemEncapsulationFailed
        case encryptionFailed
        case publicKeysNotAvailable
        case invalidFolderKey
        case keyDerivationFailed
    }

    /// Result of folder-key-based file encryption.
    struct FileEncryptionResult {
        let ciphertext: Data
        let nonce: Data
        let authTag: Data
    }

    // MARK: - File Key Constants

    /// HKDF info prefix for deriving per-file keys from folder keys.
    private static let fileKeyInfoPrefix = "SsdidDrive-FileKey-v1".data(using: .utf8)!

    /// Expected folder key size: 32 bytes (AES-256).
    private static let folderKeySize = 32

    // MARK: - Folder-Key-Based Encryption

    /// Encrypt file data using a folder key and file ID.
    ///
    /// Derives a per-file encryption key using HKDF-SHA256 from the folder key and file ID,
    /// then encrypts with AES-256-GCM.
    ///
    /// - Parameters:
    ///   - data: Plaintext file data.
    ///   - folderKey: 32-byte folder key (AES-256 KEK).
    ///   - fileId: Unique file identifier used as HKDF context.
    /// - Returns: Encryption result containing ciphertext, nonce, and auth tag.
    static func encrypt(data: Data, folderKey: Data, fileId: String) throws -> FileEncryptionResult {
        guard folderKey.count == folderKeySize else {
            throw EncryptionError.invalidFolderKey
        }

        // Derive per-file key: HKDF-SHA256(folderKey, info = prefix || fileId)
        var fileKey = try deriveFileKey(folderKey: folderKey, fileId: fileId)
        defer { FPDecryptor.fpSecureZero(&fileKey) }

        let symmetricKey = SymmetricKey(data: fileKey)
        let nonce = AES.GCM.Nonce()

        guard let sealedBox = try? AES.GCM.seal(data, using: symmetricKey, nonce: nonce),
              let combined = sealedBox.combined else {
            throw EncryptionError.encryptionFailed
        }

        // combined = nonce (12) + ciphertext + tag (16)
        let nonceData = Data(nonce)
        let tagSize = 16
        let encryptedContent = combined.dropFirst(nonceData.count).dropLast(tagSize)
        let authTag = combined.suffix(tagSize)

        return FileEncryptionResult(
            ciphertext: Data(encryptedContent),
            nonce: nonceData,
            authTag: Data(authTag)
        )
    }

    /// Encrypt file data and wrap the per-file key with the folder key.
    ///
    /// This is the full upload flow: generates a random file DEK, encrypts the file data,
    /// then wraps the DEK with AES-256-GCM using the folder key.
    ///
    /// - Parameters:
    ///   - data: Plaintext file data.
    ///   - folderKey: 32-byte folder key (KEK).
    ///   - fileId: Unique file identifier for HKDF context.
    /// - Returns: Tuple of (encryptedFileData, encryptedFileKey, fileNonce, keyNonce).
    static func encryptForUpload(
        data: Data,
        folderKey: Data,
        fileId: String
    ) throws -> (encryptedData: Data, encryptedFileKey: Data, fileNonce: Data, keyNonce: Data) {
        guard folderKey.count == folderKeySize else {
            throw EncryptionError.invalidFolderKey
        }

        // 1. Generate a random per-file DEK (32 bytes)
        var fileDek = Data(count: 32)
        fileDek.withUnsafeMutableBytes { ptr in
            _ = SecRandomCopyBytes(kSecRandomDefault, 32, ptr.baseAddress!)
        }
        defer { FPDecryptor.fpSecureZero(&fileDek) }

        // 2. Encrypt file data with the DEK
        let dekKey = SymmetricKey(data: fileDek)
        let fileNonce = AES.GCM.Nonce()
        guard let fileSealedBox = try? AES.GCM.seal(data, using: dekKey, nonce: fileNonce),
              let fileCombined = fileSealedBox.combined else {
            throw EncryptionError.encryptionFailed
        }

        // 3. Wrap the DEK with the folder key
        let folderSymmetricKey = SymmetricKey(data: folderKey)
        let keyNonce = AES.GCM.Nonce()
        guard let keySealedBox = try? AES.GCM.seal(fileDek, using: folderSymmetricKey, nonce: keyNonce),
              let keyCombined = keySealedBox.combined else {
            throw EncryptionError.encryptionFailed
        }

        // fileCombined = nonce (12) + ciphertext + tag (16) — strip the nonce prefix
        let fileEncrypted = fileCombined.dropFirst(Data(fileNonce).count)

        // keyCombined includes nonce + wrapped key + tag — strip the nonce prefix
        let wrappedKey = keyCombined.dropFirst(Data(keyNonce).count)

        return (
            encryptedData: Data(fileEncrypted),
            encryptedFileKey: Data(wrappedKey),
            fileNonce: Data(fileNonce),
            keyNonce: Data(keyNonce)
        )
    }

    // MARK: - KEM Encapsulation for Folder Key Sharing

    /// Encapsulate a folder key for a recipient using hybrid KEM.
    ///
    /// Encrypts the folder key using the recipient's KAZ-KEM and ML-KEM public keys,
    /// producing a ciphertext that only the recipient can decapsulate.
    ///
    /// - Parameters:
    ///   - folderKey: 32-byte folder key to share.
    ///   - kazKemPublicKey: Recipient's KAZ-KEM public key.
    ///   - mlKemPublicKey: Recipient's ML-KEM public key.
    /// - Returns: JSON-encoded encrypted envelope containing the wrapped folder key.
    static func encapsulateFolderKey(
        folderKey: Data,
        kazKemPublicKey: Data,
        mlKemPublicKey: Data
    ) throws -> Data {
        return try encrypt(data: folderKey, kazKemPublicKey: kazKemPublicKey, mlKemPublicKey: mlKemPublicKey)
    }

    // MARK: - ML-KEM Placeholder Constants

    /// Domain separator matching MlKem.domainSeparator in MLKEM.swift
    private static let mlKemPlaceholderSalt = "SsdidDrive-MLKEM-Placeholder-v1".data(using: .utf8)!

    // MARK: - Encryption

    /// Encrypt file data using hybrid PQC encryption (KAZ-KEM + ML-KEM placeholder).
    ///
    /// Flow:
    /// 1. KAZ-KEM encapsulate with recipient's public key -> kazSecret + kazCiphertext
    /// 2. ML-KEM placeholder encapsulate -> mlSecret + mlCiphertext
    /// 3. SHA256(kazSecret + mlSecret) -> combined encryption key
    /// 4. AES-256-GCM encrypt the data
    /// 5. JSON-encode the envelope
    ///
    /// - Parameters:
    ///   - data: Plaintext data to encrypt
    ///   - kazKemPublicKey: Recipient's KAZ-KEM public key
    ///   - mlKemPublicKey: Recipient's ML-KEM public key
    /// - Returns: JSON-encoded encrypted envelope
    static func encrypt(
        data: Data,
        kazKemPublicKey: Data,
        mlKemPublicKey: Data
    ) throws -> Data {
        // 1. KAZ-KEM encapsulation (real PQC via KazKemNative)
        let kazKem = try KazKem.initialize(level: .level128)

        var kazResult: KazKemEncapsulationResult
        do {
            kazResult = try kazKem.encapsulate(publicKey: kazKemPublicKey)
        } catch {
            throw EncryptionError.kazKemEncapsulationFailed
        }
        var kazSecret = kazResult.sharedSecret
        defer { FPDecryptor.fpSecureZero(&kazSecret) }

        // 2. ML-KEM placeholder encapsulation (HKDF-based, matches MLKEM.swift fallback)
        let (mlCiphertext, mlSecretRaw) = mlKemEncapsulatePlaceholder(publicKey: mlKemPublicKey)
        var mlSecret = mlSecretRaw
        defer { FPDecryptor.fpSecureZero(&mlSecret) }

        // 3. Combine secrets: SHA256(kazSecret || mlSecret)
        var combinedInput = kazSecret + mlSecret
        defer { FPDecryptor.fpSecureZero(&combinedInput) }
        let combinedHash = SHA256.hash(data: combinedInput)
        var combinedSecret = Data(combinedHash)
        defer { FPDecryptor.fpSecureZero(&combinedSecret) }

        // 4. AES-256-GCM encryption
        let encryptionKey = SymmetricKey(data: combinedSecret)
        let nonce = AES.GCM.Nonce()

        let sealedBox = try AES.GCM.seal(data, using: encryptionKey, nonce: nonce)
        guard let combined = sealedBox.combined else {
            throw EncryptionError.encryptionFailed
        }

        // Extract components: combined = nonce (12) + ciphertext + tag (16)
        let nonceData = Data(nonce)
        let tagSize = 16
        let encryptedContent = combined.dropFirst(nonceData.count).dropLast(tagSize)
        let authTag = combined.suffix(tagSize)

        // 5. Build envelope (matches FPDecryptor.FPEncryptedEnvelope)
        let envelope = FPDecryptor.FPEncryptedEnvelope(
            kazKemCiphertext: kazResult.ciphertext,
            mlKemCiphertext: mlCiphertext,
            nonce: nonceData,
            encryptedContent: Data(encryptedContent),
            authTag: Data(authTag),
            kazSignSignature: nil,
            mlDsaSignature: nil
        )

        return try JSONEncoder().encode(envelope)
    }

    // MARK: - Private Helpers

    /// ML-KEM placeholder encapsulation using HKDF-SHA256.
    /// Replicates the exact logic from MlKem.encapsulatePlaceholder() in MLKEM.swift.
    private static func mlKemEncapsulatePlaceholder(publicKey: Data) -> (ciphertext: Data, sharedSecret: Data) {
        // Generate 32 bytes of randomness
        var randomness = Data(count: 32)
        randomness.withUnsafeMutableBytes { ptr in
            _ = SecRandomCopyBytes(kSecRandomDefault, 32, ptr.baseAddress!)
        }

        let combinedInput = randomness + publicKey

        // Derive ciphertext (ML-KEM-768 ciphertext size = 1088)
        let ciphertext = deriveKeyMaterial(from: combinedInput, info: "mlkem-ciphertext", length: 1088)

        // Derive shared secret (32 bytes)
        let sharedSecret = deriveKeyMaterial(from: combinedInput, info: "mlkem-shared-secret", length: 32)

        return (ciphertext, sharedSecret)
    }

    /// Derive key material using HKDF-SHA256 with the placeholder salt.
    private static func deriveKeyMaterial(from input: Data, info: String, length: Int) -> Data {
        let inputKey = SymmetricKey(data: input)
        let derivedKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKey,
            salt: mlKemPlaceholderSalt,
            info: info.data(using: .utf8)!,
            outputByteCount: length
        )
        return derivedKey.withUnsafeBytes { Data($0) }
    }

    // MARK: - File Key Derivation

    /// Derive a per-file encryption key from a folder key and file ID using HKDF-SHA256.
    ///
    /// - Parameters:
    ///   - folderKey: 32-byte folder key (input key material).
    ///   - fileId: Unique file identifier (used as part of HKDF info).
    /// - Returns: 32-byte derived file key.
    private static func deriveFileKey(folderKey: Data, fileId: String) throws -> Data {
        guard let fileIdData = fileId.data(using: .utf8) else {
            throw EncryptionError.keyDerivationFailed
        }
        let inputKey = SymmetricKey(data: folderKey)
        let infoData = fileKeyInfoPrefix + fileIdData
        let derivedKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKey,
            salt: Data(),
            info: infoData,
            outputByteCount: 32
        )
        return derivedKey.withUnsafeBytes { Data($0) }
    }
}
