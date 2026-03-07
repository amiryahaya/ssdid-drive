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
}
