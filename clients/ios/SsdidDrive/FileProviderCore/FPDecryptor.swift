import Foundation
import CryptoKit
import KazKemNative

/// Standalone decryption engine for the File Provider extension.
/// Replicates the hybrid PQC decryption from CryptoManager without UIKit or main app dependencies.
/// Uses KazKemNative for real KAZ-KEM decapsulation and HKDF placeholder for ML-KEM.
enum FPDecryptor {

    // MARK: - Types

    /// Mirrors CryptoManager.EncryptedEnvelope for JSON decoding.
    struct FPEncryptedEnvelope: Codable {
        let kazKemCiphertext: Data
        let mlKemCiphertext: Data
        let nonce: Data
        let encryptedContent: Data
        let authTag: Data
        let kazSignSignature: Data?
        let mlDsaSignature: Data?
    }

    enum DecryptionError: Error {
        case invalidEnvelope
        case kazKemNotInitialized
        case kazKemDecapsulationFailed
        case decryptionFailed
        case invalidFolderKey
        case invalidNonce
        case keyDerivationFailed
        case keyUnwrapFailed
    }

    // MARK: - File Key Constants

    /// HKDF info prefix for deriving per-file keys from folder keys.
    /// Must match FPEncryptor.fileKeyInfoPrefix.
    private static let fileKeyInfoPrefix = "SsdidDrive-FileKey-v1".data(using: .utf8)!

    /// Expected folder key size: 32 bytes (AES-256).
    private static let folderKeySize = 32

    // MARK: - Folder-Key-Based Decryption

    /// Decrypt file data using a folder key and file ID.
    ///
    /// Derives the per-file decryption key using HKDF-SHA256 from the folder key and file ID,
    /// then decrypts with AES-256-GCM.
    ///
    /// - Parameters:
    ///   - ciphertext: Encrypted file content (without nonce or tag prefix).
    ///   - folderKey: 32-byte folder key (AES-256 KEK).
    ///   - fileId: Unique file identifier used as HKDF context.
    ///   - nonce: 12-byte AES-GCM nonce.
    ///   - authTag: 16-byte AES-GCM authentication tag.
    /// - Returns: Decrypted plaintext data.
    static func decrypt(
        ciphertext: Data,
        folderKey: Data,
        fileId: String,
        nonce: Data,
        authTag: Data
    ) throws -> Data {
        guard folderKey.count == folderKeySize else {
            throw DecryptionError.invalidFolderKey
        }
        guard nonce.count == 12 else {
            throw DecryptionError.invalidNonce
        }

        // Derive per-file key: HKDF-SHA256(folderKey, info = prefix || fileId)
        var fileKey = try deriveFileKey(folderKey: folderKey, fileId: fileId)
        defer { fpSecureZero(&fileKey) }

        let symmetricKey = SymmetricKey(data: fileKey)

        // Reassemble AES-GCM sealed box: nonce + ciphertext + tag
        let combined = nonce + ciphertext + authTag
        guard let sealedBox = try? AES.GCM.SealedBox(combined: combined) else {
            throw DecryptionError.decryptionFailed
        }

        do {
            return try AES.GCM.open(sealedBox, using: symmetricKey)
        } catch {
            throw DecryptionError.decryptionFailed
        }
    }

    /// Decrypt file data after download using the wrapped file key approach.
    ///
    /// 1. Unwrap the file DEK using the folder key + keyNonce.
    /// 2. Decrypt the file data using the DEK + fileNonce.
    ///
    /// - Parameters:
    ///   - encryptedData: Encrypted file content (ciphertext + tag, without nonce).
    ///   - encryptedFileKey: Wrapped file DEK (ciphertext + tag, without nonce).
    ///   - folderKey: 32-byte folder key (KEK).
    ///   - fileNonce: 12-byte nonce for the file data encryption.
    ///   - keyNonce: 12-byte nonce for the key wrapping.
    /// - Returns: Decrypted plaintext data.
    static func decryptDownload(
        encryptedData: Data,
        encryptedFileKey: Data,
        folderKey: Data,
        fileNonce: Data,
        keyNonce: Data
    ) throws -> Data {
        guard folderKey.count == folderKeySize else {
            throw DecryptionError.invalidFolderKey
        }
        guard fileNonce.count == 12, keyNonce.count == 12 else {
            throw DecryptionError.invalidNonce
        }

        // 1. Unwrap the file DEK
        let folderSymmetricKey = SymmetricKey(data: folderKey)
        let keyCombined = keyNonce + encryptedFileKey
        guard let keySealedBox = try? AES.GCM.SealedBox(combined: keyCombined) else {
            throw DecryptionError.keyUnwrapFailed
        }

        var fileDek: Data
        do {
            fileDek = try AES.GCM.open(keySealedBox, using: folderSymmetricKey)
        } catch {
            throw DecryptionError.keyUnwrapFailed
        }
        defer { fpSecureZero(&fileDek) }

        // 2. Decrypt the file data with the DEK
        let dekKey = SymmetricKey(data: fileDek)
        let fileCombined = fileNonce + encryptedData
        guard let fileSealedBox = try? AES.GCM.SealedBox(combined: fileCombined) else {
            throw DecryptionError.decryptionFailed
        }

        do {
            return try AES.GCM.open(fileSealedBox, using: dekKey)
        } catch {
            throw DecryptionError.decryptionFailed
        }
    }

    // MARK: - KEM Decapsulation for Folder Key Sharing

    /// Decapsulate a folder key encrypted with hybrid KEM.
    ///
    /// Uses the user's KAZ-KEM and ML-KEM private keys to recover the folder key.
    ///
    /// - Parameters:
    ///   - encryptedFolderKey: JSON-encoded encrypted envelope containing the wrapped folder key.
    ///   - kazKemPrivateKey: User's KAZ-KEM private key.
    ///   - mlKemPrivateKey: User's ML-KEM private key.
    /// - Returns: 32-byte decrypted folder key.
    static func decapsulateFolderKey(
        encryptedFolderKey: Data,
        kazKemPrivateKey: Data,
        mlKemPrivateKey: Data
    ) throws -> Data {
        return try decrypt(
            encryptedData: encryptedFolderKey,
            kazKemPrivateKey: kazKemPrivateKey,
            mlKemPrivateKey: mlKemPrivateKey
        )
    }

    // MARK: - ML-KEM Placeholder Constants

    /// Domain separator matching MlKem.domainSeparator in MLKEM.swift
    private static let mlKemPlaceholderSalt = "SsdidDrive-MLKEM-Placeholder-v1".data(using: .utf8)!

    // MARK: - Decryption

    /// Decrypt encrypted file data using the user's KEM private keys.
    ///
    /// Flow:
    /// 1. JSON-decode the encrypted envelope
    /// 2. KAZ-KEM decapsulate to get kazSecret
    /// 3. ML-KEM placeholder HKDF to get mlSecret
    /// 4. SHA256(kazSecret + mlSecret) -> combined secret
    /// 5. AES-GCM open with combined secret
    ///
    /// - Parameters:
    ///   - encryptedData: JSON-encoded EncryptedEnvelope
    ///   - kazKemPrivateKey: User's KAZ-KEM private key
    ///   - mlKemPrivateKey: User's ML-KEM private key
    /// - Returns: Decrypted plaintext data
    static func decrypt(
        encryptedData: Data,
        kazKemPrivateKey: Data,
        mlKemPrivateKey: Data
    ) throws -> Data {
        // 1. Decode envelope
        let envelope: FPEncryptedEnvelope
        do {
            envelope = try JSONDecoder().decode(FPEncryptedEnvelope.self, from: encryptedData)
        } catch {
            throw DecryptionError.invalidEnvelope
        }

        // 2. KAZ-KEM decapsulation (real PQC via KazKemNative)
        // Always call initialize() — it returns the existing instance if already initialized,
        // avoiding a TOCTOU race between isInitialized check and current access.
        let kazKem = try KazKem.initialize(level: .level128)

        var kazSecret: Data
        do {
            kazSecret = try kazKem.decapsulate(
                ciphertext: envelope.kazKemCiphertext,
                privateKey: kazKemPrivateKey
            )
        } catch {
            throw DecryptionError.kazKemDecapsulationFailed
        }
        defer { fpSecureZero(&kazSecret) }

        // 3. ML-KEM placeholder decapsulation (HKDF-SHA256, matches MLKEM.swift fallback)
        var mlSecret = mlKemDecapsulatePlaceholder(
            ciphertext: envelope.mlKemCiphertext,
            secretKey: mlKemPrivateKey
        )
        defer { fpSecureZero(&mlSecret) }

        // 4. Combine secrets: SHA256(kazSecret || mlSecret)
        var combinedInput = kazSecret + mlSecret
        defer { fpSecureZero(&combinedInput) }
        let combinedHash = SHA256.hash(data: combinedInput)
        var combinedSecret = Data(combinedHash)
        defer { fpSecureZero(&combinedSecret) }

        // 5. AES-256-GCM decryption
        let sealedData = envelope.nonce + envelope.encryptedContent + envelope.authTag
        guard let sealedBox = try? AES.GCM.SealedBox(combined: sealedData) else {
            throw DecryptionError.decryptionFailed
        }

        let decryptionKey = SymmetricKey(data: combinedSecret)
        do {
            return try AES.GCM.open(sealedBox, using: decryptionKey)
        } catch {
            throw DecryptionError.decryptionFailed
        }
    }

    // MARK: - Private Helpers

    /// ML-KEM placeholder decapsulation using HKDF-SHA256.
    /// Replicates the exact logic from MlKem.decapsulatePlaceholder() in MLKEM.swift.
    private static func mlKemDecapsulatePlaceholder(ciphertext: Data, secretKey: Data) -> Data {
        let combinedInput = ciphertext + secretKey
        let inputKey = SymmetricKey(data: combinedInput)
        let derivedKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKey,
            salt: mlKemPlaceholderSalt,
            info: "mlkem-shared-secret".data(using: .utf8)!,
            outputByteCount: 32
        )
        return derivedKey.withUnsafeBytes { Data($0) }
    }

    // MARK: - File Key Derivation

    /// Derive a per-file encryption key from a folder key and file ID using HKDF-SHA256.
    /// Must produce identical output to FPEncryptor.deriveFileKey for the same inputs.
    ///
    /// - Parameters:
    ///   - folderKey: 32-byte folder key (input key material).
    ///   - fileId: Unique file identifier (used as part of HKDF info).
    /// - Returns: 32-byte derived file key.
    private static func deriveFileKey(folderKey: Data, fileId: String) throws -> Data {
        guard let fileIdData = fileId.data(using: .utf8) else {
            throw DecryptionError.keyDerivationFailed
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

    /// Securely zero a Data buffer.
    @inline(__always)
    static func fpSecureZero(_ data: inout Data) {
        data.withUnsafeMutableBytes { ptr in
            if let baseAddress = ptr.baseAddress {
                memset(baseAddress, 0, ptr.count)
                OSMemoryBarrier()
            }
        }
        data = Data()
    }
}
