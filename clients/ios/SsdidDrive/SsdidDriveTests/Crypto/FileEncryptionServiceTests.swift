import XCTest
import CryptoKit
@testable import SsdidDrive

/// Unit tests for FileEncryptionService (AES-256-GCM file encryption).
final class FileEncryptionServiceTests: XCTestCase {

    private var sut: FileEncryptionService!

    override func setUp() {
        super.setUp()
        sut = FileEncryptionService.shared
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Key Generation

    func testGenerateKeyProduces32ByteKey() {
        // When
        let key = sut.generateKey()

        // Then
        XCTAssertEqual(key.count, 32, "Generated key should be 32 bytes (256 bits)")
    }

    func testGenerateKeyProducesUniqueKeys() {
        // When
        let key1 = sut.generateKey()
        let key2 = sut.generateKey()

        // Then
        XCTAssertNotEqual(key1, key2, "Two generated keys should not be equal")
    }

    func testGenerateFolderKeyProduces32ByteKey() {
        // When
        let key = sut.generateFolderKey()

        // Then
        XCTAssertEqual(key.count, 32, "Folder key should be 32 bytes")
    }

    func testGenerateFileKeyProduces32ByteKey() {
        // When
        let key = sut.generateFileKey()

        // Then
        XCTAssertEqual(key.count, 32, "File key should be 32 bytes")
    }

    // MARK: - Encrypt / Decrypt Roundtrip

    func testEncryptThenDecryptRoundtripReturnsOriginalData() throws {
        // Given
        let plaintext = "Hello, SsdidDrive! This is a secret file.".data(using: .utf8)!
        let key = sut.generateKey()

        // When
        let sealed = try sut.encryptFile(data: plaintext, key: key)
        let decrypted = try sut.decryptFile(ciphertext: sealed.ciphertext, key: key, nonce: sealed.nonce)

        // Then
        XCTAssertEqual(decrypted, plaintext, "Decrypted data should match original plaintext")
    }

    func testCiphertextDiffersFromPlaintext() throws {
        // Given
        let plaintext = "Sensitive document contents".data(using: .utf8)!
        let key = sut.generateKey()

        // When
        let sealed = try sut.encryptFile(data: plaintext, key: key)

        // Then
        // Ciphertext includes the 16-byte tag, so it will be longer; strip tag to compare
        let ciphertextOnly = sealed.ciphertext.prefix(sealed.ciphertext.count - 16)
        XCTAssertNotEqual(Data(ciphertextOnly), plaintext, "Ciphertext should differ from plaintext")
    }

    func testNonceIs12Bytes() throws {
        // Given
        let plaintext = Data([0x01, 0x02, 0x03])
        let key = sut.generateKey()

        // When
        let sealed = try sut.encryptFile(data: plaintext, key: key)

        // Then
        XCTAssertEqual(sealed.nonce.count, 12, "AES-GCM nonce should be 12 bytes")
    }

    // MARK: - Decrypt With Wrong Key

    func testDecryptWithWrongKeyThrows() throws {
        // Given
        let plaintext = "Secret data".data(using: .utf8)!
        let correctKey = sut.generateKey()
        let wrongKey = sut.generateKey()

        // When
        let sealed = try sut.encryptFile(data: plaintext, key: correctKey)

        // Then
        XCTAssertThrowsError(
            try sut.decryptFile(ciphertext: sealed.ciphertext, key: wrongKey, nonce: sealed.nonce),
            "Decryption with wrong key should throw"
        ) { error in
            XCTAssertTrue(
                error is FileEncryptionService.EncryptionError,
                "Error should be EncryptionError, got \(error)"
            )
            XCTAssertEqual(
                error as? FileEncryptionService.EncryptionError,
                .decryptionFailed,
                "Should throw decryptionFailed"
            )
        }
    }

    // MARK: - Tampered Ciphertext

    func testDecryptWithTamperedCiphertextThrows() throws {
        // Given
        let plaintext = "Important file contents".data(using: .utf8)!
        let key = sut.generateKey()
        let sealed = try sut.encryptFile(data: plaintext, key: key)

        // When - flip a byte in the ciphertext
        var tampered = sealed.ciphertext
        let flipIndex = tampered.count / 2
        tampered[tampered.startIndex.advanced(by: flipIndex)] ^= 0xFF

        // Then
        XCTAssertThrowsError(
            try sut.decryptFile(ciphertext: tampered, key: key, nonce: sealed.nonce),
            "Decryption of tampered ciphertext should throw"
        )
    }

    func testDecryptWithTamperedTagThrows() throws {
        // Given
        let plaintext = "Data with integrity".data(using: .utf8)!
        let key = sut.generateKey()
        let sealed = try sut.encryptFile(data: plaintext, key: key)

        // When - flip the last byte (part of the GCM tag)
        var tampered = sealed.ciphertext
        tampered[tampered.endIndex.advanced(by: -1)] ^= 0xFF

        // Then
        XCTAssertThrowsError(
            try sut.decryptFile(ciphertext: tampered, key: key, nonce: sealed.nonce),
            "Decryption with tampered tag should throw"
        )
    }

    // MARK: - Empty Data

    func testEncryptDecryptEmptyData() throws {
        // Given
        let plaintext = Data()
        let key = sut.generateKey()

        // When
        let sealed = try sut.encryptFile(data: plaintext, key: key)
        let decrypted = try sut.decryptFile(ciphertext: sealed.ciphertext, key: key, nonce: sealed.nonce)

        // Then
        XCTAssertEqual(decrypted, plaintext, "Empty data should roundtrip correctly")
        XCTAssertTrue(decrypted.isEmpty, "Decrypted empty data should be empty")
        // Ciphertext should still contain the 16-byte GCM tag even for empty plaintext
        XCTAssertEqual(sealed.ciphertext.count, 16, "Empty plaintext ciphertext should be tag-only (16 bytes)")
    }

    // MARK: - Large Data

    func testEncryptDecryptLargeData() throws {
        // Given - 1 MB of random data
        let size = 1_024 * 1_024
        var plaintext = Data(count: size)
        plaintext.withUnsafeMutableBytes { ptr in
            _ = SecRandomCopyBytes(kSecRandomDefault, size, ptr.baseAddress!)
        }
        let key = sut.generateKey()

        // When
        let sealed = try sut.encryptFile(data: plaintext, key: key)
        let decrypted = try sut.decryptFile(ciphertext: sealed.ciphertext, key: key, nonce: sealed.nonce)

        // Then
        XCTAssertEqual(decrypted, plaintext, "Large data should roundtrip correctly")
        XCTAssertEqual(sealed.ciphertext.count, size + 16, "Ciphertext should be plaintext size + 16 byte tag")
    }

    // MARK: - Invalid Key Size

    func testEncryptWithInvalidKeySizeThrows() {
        // Given
        let plaintext = "test".data(using: .utf8)!
        let shortKey = Data(count: 16) // 128-bit instead of 256-bit

        // Then
        XCTAssertThrowsError(
            try sut.encryptFile(data: plaintext, key: shortKey),
            "Encrypt with 16-byte key should throw"
        ) { error in
            XCTAssertEqual(
                error as? FileEncryptionService.EncryptionError,
                .invalidKeySize,
                "Should throw invalidKeySize"
            )
        }
    }

    func testDecryptWithInvalidKeySizeThrows() {
        // Given
        let ciphertext = Data(count: 32)
        let shortKey = Data(count: 24)
        let nonce = Data(count: 12)

        // Then
        XCTAssertThrowsError(
            try sut.decryptFile(ciphertext: ciphertext, key: shortKey, nonce: nonce),
            "Decrypt with 24-byte key should throw"
        ) { error in
            XCTAssertEqual(
                error as? FileEncryptionService.EncryptionError,
                .invalidKeySize,
                "Should throw invalidKeySize"
            )
        }
    }

    // MARK: - Invalid Ciphertext / Nonce

    func testDecryptWithTooShortCiphertextThrows() {
        // Given - ciphertext shorter than 16-byte GCM tag
        let ciphertext = Data(count: 10)
        let key = sut.generateKey()
        let nonce = Data(count: 12)

        // Then
        XCTAssertThrowsError(
            try sut.decryptFile(ciphertext: ciphertext, key: key, nonce: nonce),
            "Ciphertext shorter than tag should throw"
        ) { error in
            XCTAssertEqual(
                error as? FileEncryptionService.EncryptionError,
                .invalidCiphertext,
                "Should throw invalidCiphertext"
            )
        }
    }

    func testDecryptWithInvalidNonceThrows() {
        // Given - nonce of wrong length
        let ciphertext = Data(count: 32)
        let key = sut.generateKey()
        let badNonce = Data(count: 8) // should be 12

        // Then
        XCTAssertThrowsError(
            try sut.decryptFile(ciphertext: ciphertext, key: key, nonce: badNonce),
            "Invalid nonce length should throw"
        ) { error in
            XCTAssertEqual(
                error as? FileEncryptionService.EncryptionError,
                .invalidNonce,
                "Should throw invalidNonce"
            )
        }
    }

    // MARK: - Key Wrapping

    func testWrapUnwrapKeyRoundtrip() throws {
        // Given
        let fileKey = sut.generateFileKey()
        let folderKey = sut.generateFolderKey()

        // When
        let wrapped = try sut.wrapKey(fileKey, with: folderKey)
        let unwrapped = try sut.unwrapKey(wrapped.ciphertext, with: folderKey, nonce: wrapped.nonce)

        // Then
        XCTAssertEqual(unwrapped, fileKey, "Unwrapped key should match original file key")
    }

    // MARK: - Convenience: Encrypt / Decrypt With Wrapped Key

    func testEncryptFileWithNewKeyAndDecryptRoundtrip() throws {
        // Given
        let plaintext = "Document encrypted with folder key hierarchy".data(using: .utf8)!
        let folderKey = sut.generateFolderKey()

        // When - encrypt
        let result = try sut.encryptFileWithNewKey(data: plaintext, folderKey: folderKey)

        // When - decrypt
        let decrypted = try sut.decryptFileWithWrappedKey(
            ciphertext: result.encryptedData.ciphertext,
            fileNonce: result.encryptedData.nonce,
            wrappedFileKey: result.wrappedFileKey.ciphertext,
            keyNonce: result.wrappedFileKey.nonce,
            folderKey: folderKey
        )

        // Then
        XCTAssertEqual(decrypted, plaintext, "Full hierarchy roundtrip should return original data")
    }
}

// MARK: - Equatable conformance for assertion helpers

extension FileEncryptionService.EncryptionError: Equatable {
    public static func == (lhs: FileEncryptionService.EncryptionError, rhs: FileEncryptionService.EncryptionError) -> Bool {
        switch (lhs, rhs) {
        case (.encryptionFailed, .encryptionFailed),
             (.decryptionFailed, .decryptionFailed),
             (.invalidKeySize, .invalidKeySize),
             (.invalidNonce, .invalidNonce),
             (.invalidCiphertext, .invalidCiphertext):
            return true
        default:
            return false
        }
    }
}
