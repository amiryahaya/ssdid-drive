import Foundation
import CryptoKit

/// Orchestrates cryptographic operations including hybrid encryption and signatures.
/// Uses dual-algorithm approach for quantum resistance.
final class CryptoManager {

    // MARK: - Types

    /// Encrypted file envelope containing all necessary data for decryption
    struct EncryptedEnvelope: Codable {
        let kazKemCiphertext: Data
        let mlKemCiphertext: Data
        let nonce: Data
        let encryptedContent: Data
        let authTag: Data

        // Dual signatures for authenticity
        let kazSignSignature: Data?
        let mlDsaSignature: Data?
    }

    /// Result of hybrid encapsulation
    struct HybridEncapsulation {
        let kazKemCiphertext: Data
        let mlKemCiphertext: Data
        let combinedSharedSecret: Data
    }

    /// Dual signature result
    struct DualSignature: Codable {
        let kazSignSignature: Data
        let mlDsaSignature: Data
    }

    // MARK: - Errors

    enum CryptoError: Error {
        case encryptionFailed
        case decryptionFailed
        case keyNotAvailable
        case signatureFailed
        case verificationFailed
        case invalidEnvelope
    }

    // MARK: - Properties

    private let keyManager: KeyManager

    // MARK: - Initialization

    init(keyManager: KeyManager) {
        self.keyManager = keyManager
    }

    // MARK: - Hybrid Encryption

    /// Encrypt data using hybrid PQC encryption (KAZ-KEM + ML-KEM)
    /// - Parameters:
    ///   - data: Plaintext data to encrypt
    ///   - recipientPublicKeys: Recipient's public keys
    ///   - sign: Whether to sign the encrypted data
    /// - Returns: Encrypted envelope
    func encrypt(
        data: Data,
        recipientPublicKeys: KeyManager.PublicKeys,
        sign: Bool = true
    ) throws -> EncryptedEnvelope {
        // Perform hybrid encapsulation
        let encapsulation = try hybridEncapsulate(
            kazKemPublicKey: recipientPublicKeys.kazKemPublicKey,
            mlKemPublicKey: recipientPublicKeys.mlKemPublicKey
        )

        // Derive encryption key from combined shared secret
        let encryptionKey = SymmetricKey(data: encapsulation.combinedSharedSecret)

        // Generate random nonce
        let nonce = AES.GCM.Nonce()

        // Encrypt content with AES-256-GCM
        let sealedBox = try AES.GCM.seal(data, using: encryptionKey, nonce: nonce)

        guard let combined = sealedBox.combined else {
            throw CryptoError.encryptionFailed
        }

        // Extract ciphertext and tag
        let nonceData = Data(nonce)
        let tagSize = 16
        let encryptedContent = combined.dropFirst(nonceData.count).dropLast(tagSize)
        let authTag = combined.suffix(tagSize)

        // Optionally sign
        var kazSignSig: Data?
        var mlDsaSig: Data?

        if sign, let keyBundle = keyManager.currentKeyBundle {
            let signature = try signData(
                data: encryptedContent,
                kazSignPrivateKey: keyBundle.kazSignPrivateKey,
                mlDsaPrivateKey: keyBundle.mlDsaPrivateKey
            )
            kazSignSig = signature.kazSignSignature
            mlDsaSig = signature.mlDsaSignature
        }

        return EncryptedEnvelope(
            kazKemCiphertext: encapsulation.kazKemCiphertext,
            mlKemCiphertext: encapsulation.mlKemCiphertext,
            nonce: nonceData,
            encryptedContent: Data(encryptedContent),
            authTag: Data(authTag),
            kazSignSignature: kazSignSig,
            mlDsaSignature: mlDsaSig
        )
    }

    /// Decrypt an encrypted envelope using current user's private keys
    /// - Parameter envelope: The encrypted envelope
    /// - Returns: Decrypted plaintext data
    func decrypt(envelope: EncryptedEnvelope) throws -> Data {
        guard let keyBundle = keyManager.currentKeyBundle else {
            throw CryptoError.keyNotAvailable
        }

        // Perform hybrid decapsulation
        let sharedSecret = try hybridDecapsulate(
            kazKemCiphertext: envelope.kazKemCiphertext,
            mlKemCiphertext: envelope.mlKemCiphertext,
            kazKemPrivateKey: keyBundle.kazKemPrivateKey,
            mlKemPrivateKey: keyBundle.mlKemPrivateKey
        )

        // Derive decryption key
        let decryptionKey = SymmetricKey(data: sharedSecret)

        // Reconstruct sealed box
        guard let nonce = try? AES.GCM.Nonce(data: envelope.nonce) else {
            throw CryptoError.invalidEnvelope
        }

        let combinedData = envelope.nonce + envelope.encryptedContent + envelope.authTag
        guard let sealedBox = try? AES.GCM.SealedBox(combined: combinedData) else {
            throw CryptoError.invalidEnvelope
        }

        // Decrypt
        do {
            return try AES.GCM.open(sealedBox, using: decryptionKey)
        } catch {
            throw CryptoError.decryptionFailed
        }
    }

    // MARK: - Hybrid Encapsulation

    /// Perform hybrid key encapsulation using both KAZ-KEM and ML-KEM
    private func hybridEncapsulate(
        kazKemPublicKey: Data,
        mlKemPublicKey: Data
    ) throws -> HybridEncapsulation {
        // Encapsulate with KAZ-KEM
        let (kazCiphertext, kazSecret) = try KAZKEM.encapsulate(publicKey: kazKemPublicKey)

        // Encapsulate with ML-KEM
        let (mlCiphertext, mlSecret) = try MLKEM.encapsulate(publicKey: mlKemPublicKey)

        // Combine secrets: SHA3-256(kazSecret || mlSecret)
        let combinedInput = kazSecret + mlSecret
        let combinedSecret = SHA256.hash(data: combinedInput)

        return HybridEncapsulation(
            kazKemCiphertext: kazCiphertext,
            mlKemCiphertext: mlCiphertext,
            combinedSharedSecret: Data(combinedSecret)
        )
    }

    /// Perform hybrid key decapsulation
    private func hybridDecapsulate(
        kazKemCiphertext: Data,
        mlKemCiphertext: Data,
        kazKemPrivateKey: Data,
        mlKemPrivateKey: Data
    ) throws -> Data {
        // Decapsulate with KAZ-KEM
        var kazSecret = try KAZKEM.decapsulate(
            ciphertext: kazKemCiphertext,
            privateKey: kazKemPrivateKey
        )
        defer { kazSecret.secureZero() }

        // Decapsulate with ML-KEM
        var mlSecret = try MLKEM.decapsulate(
            ciphertext: mlKemCiphertext,
            privateKey: mlKemPrivateKey
        )
        defer { mlSecret.secureZero() }

        // Combine secrets
        var combinedInput = kazSecret + mlSecret
        defer { combinedInput.secureZero() }

        let combinedSecret = SHA256.hash(data: combinedInput)

        return Data(combinedSecret)
    }

    // MARK: - Dual Signatures

    /// Sign data with both KAZ-SIGN and ML-DSA
    func signData(
        data: Data,
        kazSignPrivateKey: Data,
        mlDsaPrivateKey: Data
    ) throws -> DualSignature {
        // Sign with KAZ-SIGN
        let kazSig = try KAZSIGN.sign(message: data, privateKey: kazSignPrivateKey)

        // Sign with ML-DSA
        let mlSig = try MLDSA.sign(message: data, privateKey: mlDsaPrivateKey)

        return DualSignature(
            kazSignSignature: kazSig,
            mlDsaSignature: mlSig
        )
    }

    /// Verify dual signature
    func verifySignature(
        signature: DualSignature,
        data: Data,
        kazSignPublicKey: Data,
        mlDsaPublicKey: Data
    ) throws -> Bool {
        // Both signatures must be valid
        let kazValid = try KAZSIGN.verify(
            signature: signature.kazSignSignature,
            message: data,
            publicKey: kazSignPublicKey
        )

        let mlValid = try MLDSA.verify(
            signature: signature.mlDsaSignature,
            message: data,
            publicKey: mlDsaPublicKey
        )

        return kazValid && mlValid
    }

    // MARK: - Device Signatures

    /// Sign data with device key (P-256 ECDSA)
    func signWithDeviceKey(data: Data) throws -> Data {
        guard let keyBundle = keyManager.currentKeyBundle else {
            throw CryptoError.keyNotAvailable
        }

        let signature = try keyBundle.deviceSigningKey.signature(for: data)
        return signature.rawRepresentation
    }

    /// Create device signature header for API requests
    func createDeviceSignature(
        method: String,
        path: String,
        timestamp: String,
        body: Data?
    ) throws -> String {
        // Create signing payload: method|path|timestamp|bodyHash
        var payload = "\(method)|\(path)|\(timestamp)"

        if let body = body, !body.isEmpty {
            let bodyHash = SHA256.hash(data: body)
            payload += "|" + bodyHash.map { String(format: "%02x", $0) }.joined()
        }

        guard let payloadData = payload.data(using: .utf8) else {
            throw CryptoError.signatureFailed
        }

        let signature = try signWithDeviceKey(data: payloadData)
        return signature.base64EncodedString()
    }

    // MARK: - File Encryption Helpers

    /// Encrypt a file and return encrypted data
    func encryptFile(
        at url: URL,
        recipientPublicKeys: KeyManager.PublicKeys
    ) throws -> Data {
        let fileData = try Data(contentsOf: url)
        let envelope = try encrypt(data: fileData, recipientPublicKeys: recipientPublicKeys)
        return try JSONEncoder().encode(envelope)
    }

    /// Encrypt file data for the current user (self-encryption for storage)
    /// - Parameter data: The plaintext file data to encrypt
    /// - Returns: Encrypted data envelope serialized as Data
    func encryptFile(_ data: Data) async throws -> Data {
        guard let keyBundle = keyManager.currentKeyBundle else {
            throw CryptoError.keyNotAvailable
        }

        // Encrypt using current user's public keys
        let envelope = try encrypt(
            data: data,
            recipientPublicKeys: keyBundle.publicKeys,
            sign: true
        )

        return try JSONEncoder().encode(envelope)
    }

    /// Decrypt file data
    func decryptFile(encryptedData: Data) throws -> Data {
        let envelope = try JSONDecoder().decode(EncryptedEnvelope.self, from: encryptedData)
        return try decrypt(envelope: envelope)
    }

    // MARK: - Key Wrapping for Sharing

    /// Result of wrapping a key for a recipient, containing all fields
    /// needed by the backend share API.
    struct KeyWrappingResult {
        let wrappedKey: Data        // The key (DEK or KEK) encrypted for the recipient
        let kemCiphertext: Data     // KEM ciphertext for the recipient to decapsulate
        let signature: Data         // Grantor's signature over the wrapped key
    }

    /// Wrap a key (DEK or KEK) for a recipient.
    /// Decrypts the key using the owner's private keys, then re-encrypts it
    /// for the recipient using their public keys. Signs the wrapped key
    /// for authenticity.
    ///
    /// - Parameters:
    ///   - encryptedKey: The key encrypted for the owner (from FileItem.encryptedKey or folder KEK)
    ///   - recipientPublicKeys: The recipient's public keys
    /// - Returns: A KeyWrappingResult with wrappedKey, kemCiphertext, and signature
    func wrapKeyForRecipient(
        encryptedKey: Data,
        recipientPublicKeys: KeyManager.PublicKeys
    ) throws -> KeyWrappingResult {
        guard let keyBundle = keyManager.currentKeyBundle else {
            throw CryptoError.keyNotAvailable
        }

        // Step 1: Decode the encrypted key envelope
        let envelope = try JSONDecoder().decode(EncryptedEnvelope.self, from: encryptedKey)

        // Step 2: Decrypt to get the raw key using owner's private keys
        let rawKey = try hybridDecapsulate(
            kazKemCiphertext: envelope.kazKemCiphertext,
            mlKemCiphertext: envelope.mlKemCiphertext,
            kazKemPrivateKey: keyBundle.kazKemPrivateKey,
            mlKemPrivateKey: keyBundle.mlKemPrivateKey
        )

        // Step 3: Encapsulate for the recipient using their public keys
        let encapsulation = try hybridEncapsulate(
            kazKemPublicKey: recipientPublicKeys.kazKemPublicKey,
            mlKemPublicKey: recipientPublicKeys.mlKemPublicKey
        )

        // Step 4: Encrypt the raw key with the recipient's shared secret
        let encryptionKey = SymmetricKey(data: encapsulation.combinedSharedSecret)
        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(rawKey, using: encryptionKey, nonce: nonce)

        guard let combined = sealedBox.combined else {
            throw CryptoError.encryptionFailed
        }

        let wrappedKey = combined

        // Step 5: Combine KEM ciphertexts for the backend
        // Backend stores a single kem_ciphertext field; we concatenate both
        let kemCiphertext = encapsulation.kazKemCiphertext + encapsulation.mlKemCiphertext

        // Step 6: Sign the wrapped key for authenticity
        let dualSignature = try signData(
            data: Data(wrappedKey),
            kazSignPrivateKey: keyBundle.kazSignPrivateKey,
            mlDsaPrivateKey: keyBundle.mlDsaPrivateKey
        )
        // Combine dual signatures into a single signature field
        let signatureData = dualSignature.kazSignSignature + dualSignature.mlDsaSignature

        return KeyWrappingResult(
            wrappedKey: Data(wrappedKey),
            kemCiphertext: kemCiphertext,
            signature: signatureData
        )
    }

    /// Re-encrypt an encrypted file key for a new recipient (legacy convenience method).
    /// - Parameters:
    ///   - encryptedKey: The file key encrypted for the owner (from FileItem.encryptedKey)
    ///   - recipientPublicKeys: The recipient's public keys
    /// - Returns: The file key re-encrypted for the recipient as an encoded envelope
    func reencryptKeyForRecipient(
        encryptedKey: Data,
        recipientPublicKeys: KeyManager.PublicKeys
    ) throws -> Data {
        guard let keyBundle = keyManager.currentKeyBundle else {
            throw CryptoError.keyNotAvailable
        }

        // Step 1: Decode the encrypted key envelope
        let envelope = try JSONDecoder().decode(EncryptedEnvelope.self, from: encryptedKey)

        // Step 2: Decrypt to get the file key using owner's private keys
        let fileKey = try hybridDecapsulate(
            kazKemCiphertext: envelope.kazKemCiphertext,
            mlKemCiphertext: envelope.mlKemCiphertext,
            kazKemPrivateKey: keyBundle.kazKemPrivateKey,
            mlKemPrivateKey: keyBundle.mlKemPrivateKey
        )

        // Step 3: Re-encrypt the file key for the recipient
        let encapsulation = try hybridEncapsulate(
            kazKemPublicKey: recipientPublicKeys.kazKemPublicKey,
            mlKemPublicKey: recipientPublicKeys.mlKemPublicKey
        )

        // Step 4: Encrypt the file key with the new shared secret
        let encryptionKey = SymmetricKey(data: encapsulation.combinedSharedSecret)
        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(fileKey, using: encryptionKey, nonce: nonce)

        guard let combined = sealedBox.combined else {
            throw CryptoError.encryptionFailed
        }

        // Extract components
        let nonceData = Data(nonce)
        let tagSize = 16
        let encryptedContent = combined.dropFirst(nonceData.count).dropLast(tagSize)
        let authTag = combined.suffix(tagSize)

        // Step 5: Create new envelope for recipient
        let recipientEnvelope = EncryptedEnvelope(
            kazKemCiphertext: encapsulation.kazKemCiphertext,
            mlKemCiphertext: encapsulation.mlKemCiphertext,
            nonce: nonceData,
            encryptedContent: Data(encryptedContent),
            authTag: Data(authTag),
            kazSignSignature: nil,
            mlDsaSignature: nil
        )

        return try JSONEncoder().encode(recipientEnvelope)
    }
}
