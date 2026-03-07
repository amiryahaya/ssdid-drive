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
