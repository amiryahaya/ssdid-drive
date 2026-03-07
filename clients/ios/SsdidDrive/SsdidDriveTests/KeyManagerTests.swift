import XCTest
@testable import SsdidDrive

/// Unit tests for KeyManager
final class KeyManagerTests: XCTestCase {

    var keyManager: KeyManager!
    var mockKeychainManager: MockKeychainManager!

    override func setUp() {
        super.setUp()
        mockKeychainManager = MockKeychainManager()
        keyManager = KeyManager(keychainManager: mockKeychainManager)
    }

    override func tearDown() {
        keyManager = nil
        mockKeychainManager = nil
        super.tearDown()
    }

    // MARK: - Key Generation Tests

    func testGenerateKeyBundle() throws {
        // When
        let bundle = try keyManager.generateKeyBundle()

        // Then - All keys should be generated
        XCTAssertFalse(bundle.kazKemPublicKey.isEmpty, "KAZ-KEM public key should not be empty")
        XCTAssertFalse(bundle.kazKemPrivateKey.isEmpty, "KAZ-KEM private key should not be empty")
        XCTAssertFalse(bundle.mlKemPublicKey.isEmpty, "ML-KEM public key should not be empty")
        XCTAssertFalse(bundle.mlKemPrivateKey.isEmpty, "ML-KEM private key should not be empty")
        XCTAssertFalse(bundle.kazSignPublicKey.isEmpty, "KAZ-SIGN public key should not be empty")
        XCTAssertFalse(bundle.kazSignPrivateKey.isEmpty, "KAZ-SIGN private key should not be empty")
        XCTAssertFalse(bundle.mlDsaPublicKey.isEmpty, "ML-DSA public key should not be empty")
        XCTAssertFalse(bundle.mlDsaPrivateKey.isEmpty, "ML-DSA private key should not be empty")

        // Device signing key should be valid P-256 key
        XCTAssertNotNil(bundle.deviceSigningKey, "Device signing key should be generated")
    }

    func testGenerateKeyBundleProducesUniqueKeys() throws {
        // When
        let bundle1 = try keyManager.generateKeyBundle()
        let bundle2 = try keyManager.generateKeyBundle()

        // Then - Different bundles should have different keys
        XCTAssertNotEqual(bundle1.kazKemPublicKey, bundle2.kazKemPublicKey, "Different bundles should have different KAZ-KEM keys")
        XCTAssertNotEqual(bundle1.mlKemPublicKey, bundle2.mlKemPublicKey, "Different bundles should have different ML-KEM keys")
        XCTAssertNotEqual(bundle1.kazSignPublicKey, bundle2.kazSignPublicKey, "Different bundles should have different KAZ-SIGN keys")
    }

    func testPublicKeysExtraction() throws {
        // Given
        let bundle = try keyManager.generateKeyBundle()

        // When
        let publicKeys = bundle.publicKeys

        // Then
        XCTAssertEqual(publicKeys.kazKemPublicKey, bundle.kazKemPublicKey)
        XCTAssertEqual(publicKeys.mlKemPublicKey, bundle.mlKemPublicKey)
        XCTAssertEqual(publicKeys.kazSignPublicKey, bundle.kazSignPublicKey)
        XCTAssertEqual(publicKeys.mlDsaPublicKey, bundle.mlDsaPublicKey)
    }

    // MARK: - Key Storage Tests

    func testStoreAndLoadKeysWithPassword() throws {
        // Given
        let originalBundle = try keyManager.generateKeyBundle()
        let password = "TestPassword123!"

        // When - Store
        try keyManager.storeKeys(originalBundle, password: password)

        // Then - Keys should be stored
        XCTAssertTrue(mockKeychainManager.hasEncryptedKeys, "Encrypted keys should be stored")

        // When - Load with correct password
        let loadedBundle = try keyManager.loadKeys(password: password)

        // Then - Loaded keys should match original
        XCTAssertEqual(loadedBundle.kazKemPublicKey, originalBundle.kazKemPublicKey)
        XCTAssertEqual(loadedBundle.kazKemPrivateKey, originalBundle.kazKemPrivateKey)
        XCTAssertEqual(loadedBundle.mlKemPublicKey, originalBundle.mlKemPublicKey)
        XCTAssertEqual(loadedBundle.mlKemPrivateKey, originalBundle.mlKemPrivateKey)
        XCTAssertEqual(loadedBundle.kazSignPublicKey, originalBundle.kazSignPublicKey)
        XCTAssertEqual(loadedBundle.kazSignPrivateKey, originalBundle.kazSignPrivateKey)
        XCTAssertEqual(loadedBundle.mlDsaPublicKey, originalBundle.mlDsaPublicKey)
        XCTAssertEqual(loadedBundle.mlDsaPrivateKey, originalBundle.mlDsaPrivateKey)
    }

    func testLoadKeysWithWrongPasswordFails() throws {
        // Given
        let bundle = try keyManager.generateKeyBundle()
        let correctPassword = "CorrectPassword123!"
        let wrongPassword = "WrongPassword456!"

        // When - Store with correct password
        try keyManager.storeKeys(bundle, password: correctPassword)

        // Then - Load with wrong password should fail
        XCTAssertThrowsError(try keyManager.loadKeys(password: wrongPassword)) { error in
            XCTAssertTrue(error is KeyManager.KeyError, "Should throw KeyError")
        }
    }

    // MARK: - Key Access Tests

    func testCurrentKeyBundleInitiallyNil() {
        // Then
        XCTAssertNil(keyManager.currentKeyBundle, "Current key bundle should be nil initially")
        XCTAssertFalse(keyManager.areKeysUnlocked, "Keys should not be unlocked initially")
    }

    func testKeysUnlockedAfterLoad() throws {
        // Given
        let bundle = try keyManager.generateKeyBundle()
        let password = "TestPassword123!"
        try keyManager.storeKeys(bundle, password: password)

        // When
        _ = try keyManager.loadKeys(password: password)

        // Then
        XCTAssertNotNil(keyManager.currentKeyBundle, "Current key bundle should be available")
        XCTAssertTrue(keyManager.areKeysUnlocked, "Keys should be unlocked")
    }

    func testLockKeys() throws {
        // Given
        let bundle = try keyManager.generateKeyBundle()
        let password = "TestPassword123!"
        try keyManager.storeKeys(bundle, password: password)
        _ = try keyManager.loadKeys(password: password)

        // When
        keyManager.lockKeys()

        // Then
        XCTAssertNil(keyManager.currentKeyBundle, "Current key bundle should be nil after locking")
        XCTAssertFalse(keyManager.areKeysUnlocked, "Keys should be locked")
    }

    func testHasStoredKeys() throws {
        // Initially
        XCTAssertFalse(keyManager.hasStoredKeys, "Should not have stored keys initially")

        // After storing
        let bundle = try keyManager.generateKeyBundle()
        try keyManager.storeKeys(bundle, password: "password")

        XCTAssertTrue(keyManager.hasStoredKeys, "Should have stored keys after storing")
    }
}

// MARK: - Mock KeychainManager

final class MockKeychainManager: KeychainManaging {
    private var storage: [String: Data] = [:]
    private var masterKeyData: Data?

    var hasEncryptedKeys: Bool {
        storage[Constants.Keychain.encryptedKeys] != nil
    }

    func save(_ data: Data, for key: String, accessLevel: KeychainManager.AccessLevel = .standard) throws {
        storage[key] = data
    }

    func load(key: String, withBiometric: Bool = false) throws -> Data {
        guard let data = storage[key] else {
            throw MockKeychainError.itemNotFound
        }
        return data
    }

    func delete(key: String) throws {
        storage.removeValue(forKey: key)
    }

    func exists(key: String) -> Bool {
        storage[key] != nil
    }

    func saveMasterKey(_ key: Data) throws {
        masterKeyData = key
    }

    func loadMasterKey() throws -> Data {
        guard let key = masterKeyData else {
            throw MockKeychainError.itemNotFound
        }
        return key
    }

    enum MockKeychainError: Error {
        case itemNotFound
    }
}
