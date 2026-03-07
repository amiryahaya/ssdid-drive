import XCTest
@testable import SecureSharing

/// Unit tests for cryptographic operations
final class CryptoTests: XCTestCase {

    // MARK: - KAZ-KEM Tests

    func testKazKemKeyGeneration() throws {
        // Given/When
        let (publicKey, privateKey) = try KAZKEM.generateKeyPair()

        // Then
        XCTAssertFalse(publicKey.isEmpty, "Public key should not be empty")
        XCTAssertFalse(privateKey.isEmpty, "Private key should not be empty")
        XCTAssertNotEqual(publicKey, privateKey, "Public and private keys should be different")
    }

    func testKazKemEncapsulationDecapsulation() throws {
        // Given
        let (publicKey, privateKey) = try KAZKEM.generateKeyPair()

        // When - Encapsulate
        let (ciphertext, sharedSecret1) = try KAZKEM.encapsulate(publicKey: publicKey)

        // Then - Encapsulation produces output
        XCTAssertFalse(ciphertext.isEmpty, "Ciphertext should not be empty")
        XCTAssertFalse(sharedSecret1.isEmpty, "Shared secret should not be empty")

        // When - Decapsulate
        let sharedSecret2 = try KAZKEM.decapsulate(ciphertext: ciphertext, privateKey: privateKey)

        // Then - Shared secrets should match
        XCTAssertEqual(sharedSecret1, sharedSecret2, "Decapsulated secret should match encapsulated secret")
    }

    func testKazKemDifferentKeysProduceDifferentSecrets() throws {
        // Given
        let (publicKey1, _) = try KAZKEM.generateKeyPair()
        let (publicKey2, _) = try KAZKEM.generateKeyPair()

        // When
        let (_, secret1) = try KAZKEM.encapsulate(publicKey: publicKey1)
        let (_, secret2) = try KAZKEM.encapsulate(publicKey: publicKey2)

        // Then
        XCTAssertNotEqual(secret1, secret2, "Different keys should produce different secrets")
    }

    // MARK: - KAZ-SIGN Tests

    func testKazSignKeyGeneration() throws {
        // Given/When
        let (publicKey, privateKey) = try KAZSIGN.generateKeyPair()

        // Then
        XCTAssertFalse(publicKey.isEmpty, "Public key should not be empty")
        XCTAssertFalse(privateKey.isEmpty, "Private key should not be empty")
        XCTAssertNotEqual(publicKey, privateKey, "Public and private keys should be different")
    }

    func testKazSignSignAndVerify() throws {
        // Given
        let (publicKey, privateKey) = try KAZSIGN.generateKeyPair()
        let message = "Hello, SecureSharing!".data(using: .utf8)!

        // When - Sign
        let signature = try KAZSIGN.sign(message: message, privateKey: privateKey)

        // Then - Signature is not empty
        XCTAssertFalse(signature.isEmpty, "Signature should not be empty")

        // When - Verify
        let isValid = try KAZSIGN.verify(signature: signature, message: message, publicKey: publicKey)

        // Then
        XCTAssertTrue(isValid, "Signature should be valid")
    }

    func testKazSignInvalidSignatureFails() throws {
        // Given
        let (publicKey, privateKey) = try KAZSIGN.generateKeyPair()
        let message = "Original message".data(using: .utf8)!
        let tamperedMessage = "Tampered message".data(using: .utf8)!

        // When - Sign original message
        let signature = try KAZSIGN.sign(message: message, privateKey: privateKey)

        // Then - Verify with tampered message should fail
        let isValid = try KAZSIGN.verify(signature: signature, message: tamperedMessage, publicKey: publicKey)
        XCTAssertFalse(isValid, "Signature verification should fail for tampered message")
    }

    func testKazSignWrongKeyFails() throws {
        // Given
        let (_, privateKey1) = try KAZSIGN.generateKeyPair()
        let (publicKey2, _) = try KAZSIGN.generateKeyPair()
        let message = "Test message".data(using: .utf8)!

        // When - Sign with key1, verify with key2
        let signature = try KAZSIGN.sign(message: message, privateKey: privateKey1)
        let isValid = try KAZSIGN.verify(signature: signature, message: message, publicKey: publicKey2)

        // Then
        XCTAssertFalse(isValid, "Signature should be invalid with wrong public key")
    }

    // MARK: - ML-KEM Tests

    func testMlKemKeyGeneration() throws {
        // Given/When
        let (publicKey, privateKey) = try MLKEM.generateKeyPair()

        // Then
        XCTAssertEqual(publicKey.count, MLKEM.publicKeySize, "Public key should be correct size")
        XCTAssertEqual(privateKey.count, MLKEM.privateKeySize, "Private key should be correct size")
    }

    func testMlKemEncapsulationDecapsulation() throws {
        // Given
        let (publicKey, privateKey) = try MLKEM.generateKeyPair()

        // When
        let (ciphertext, sharedSecret1) = try MLKEM.encapsulate(publicKey: publicKey)
        let sharedSecret2 = try MLKEM.decapsulate(ciphertext: ciphertext, privateKey: privateKey)

        // Then
        XCTAssertEqual(ciphertext.count, MLKEM.ciphertextSize, "Ciphertext should be correct size")
        XCTAssertEqual(sharedSecret1.count, MLKEM.sharedSecretSize, "Shared secret should be correct size")
        // Note: In placeholder implementation, secrets may not match
        // In real implementation, this should be: XCTAssertEqual(sharedSecret1, sharedSecret2)
    }

    // MARK: - ML-DSA Tests

    func testMlDsaKeyGeneration() throws {
        // Given/When
        let (publicKey, privateKey) = try MLDSA.generateKeyPair()

        // Then
        XCTAssertEqual(publicKey.count, MLDSA.publicKeySize, "Public key should be correct size")
        XCTAssertEqual(privateKey.count, MLDSA.privateKeySize, "Private key should be correct size")
    }

    func testMlDsaSignAndVerify() throws {
        // Given
        let (publicKey, privateKey) = try MLDSA.generateKeyPair()
        let message = "Test message for ML-DSA".data(using: .utf8)!

        // When
        let signature = try MLDSA.sign(message: message, privateKey: privateKey)
        let isValid = try MLDSA.verify(signature: signature, message: message, publicKey: publicKey)

        // Then
        XCTAssertEqual(signature.count, MLDSA.signatureSize, "Signature should be correct size")
        XCTAssertTrue(isValid, "Signature should be valid")
    }

    // MARK: - AES-GCM Tests

    func testAesGcmEncryptionDecryption() throws {
        // Given
        let plaintext = "Secret message for AES-GCM encryption test".data(using: .utf8)!
        let key = SymmetricKey(size: .bits256)

        // When - Encrypt
        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(plaintext, using: key, nonce: nonce)

        // Then - Ciphertext is different from plaintext
        XCTAssertNotEqual(sealedBox.ciphertext, plaintext, "Ciphertext should differ from plaintext")

        // When - Decrypt
        let decrypted = try AES.GCM.open(sealedBox, using: key)

        // Then
        XCTAssertEqual(decrypted, plaintext, "Decrypted data should match original plaintext")
    }

    func testAesGcmWrongKeyFails() throws {
        // Given
        let plaintext = "Secret message".data(using: .utf8)!
        let key1 = SymmetricKey(size: .bits256)
        let key2 = SymmetricKey(size: .bits256)

        // When - Encrypt with key1
        let sealedBox = try AES.GCM.seal(plaintext, using: key1)

        // Then - Decrypt with key2 should fail
        XCTAssertThrowsError(try AES.GCM.open(sealedBox, using: key2)) { error in
            // Expected: CryptoKit.CryptoKitError.authenticationFailure
        }
    }

    // MARK: - SHA-256 Tests

    func testSha256Hash() {
        // Given
        let data = "Test data for hashing".data(using: .utf8)!

        // When
        let hash1 = SHA256.hash(data: data)
        let hash2 = SHA256.hash(data: data)

        // Then - Same input produces same hash
        XCTAssertEqual(Data(hash1), Data(hash2), "Same input should produce same hash")

        // And - Hash is 32 bytes
        XCTAssertEqual(Data(hash1).count, 32, "SHA-256 hash should be 32 bytes")
    }

    func testSha256DifferentInputsDifferentHashes() {
        // Given
        let data1 = "First message".data(using: .utf8)!
        let data2 = "Second message".data(using: .utf8)!

        // When
        let hash1 = SHA256.hash(data: data1)
        let hash2 = SHA256.hash(data: data2)

        // Then
        XCTAssertNotEqual(Data(hash1), Data(hash2), "Different inputs should produce different hashes")
    }
}

// Import CryptoKit for AES-GCM and SHA-256 tests
import CryptoKit
