import Foundation
import Security
import LocalAuthentication

/// Protocol for keychain operations - enables testing with mocks
protocol KeychainManaging {
    func save(_ data: Data, for key: String, accessLevel: KeychainManager.AccessLevel) throws
    func load(key: String, withBiometric: Bool) throws -> Data
    func delete(key: String) throws
    func exists(key: String) -> Bool

    var hasEncryptedKeys: Bool { get }
    func saveMasterKey(_ data: Data) throws
    func loadMasterKey() throws -> Data
}

/// Manages secure storage using iOS Keychain.
/// All sensitive data (tokens, keys) should be stored here.
final class KeychainManager: KeychainManaging {

    // MARK: - Types

    enum KeychainError: Error {
        case duplicateItem
        case itemNotFound
        case unexpectedData
        case unhandledError(status: OSStatus)
        case biometricAuthFailed
        case accessDenied
    }

    enum AccessLevel {
        case standard
        case biometric
        case afterFirstUnlock

        var accessibility: CFString {
            switch self {
            case .standard:
                return kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            case .biometric:
                return kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            case .afterFirstUnlock:
                return kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            }
        }

        var requiresBiometric: Bool {
            self == .biometric
        }
    }

    // MARK: - Properties

    private let service: String

    // MARK: - Initialization

    init(service: String = Constants.Keychain.serviceName) {
        self.service = service
    }

    // MARK: - Core Operations

    /// Save data to keychain
    func save(_ data: Data, for key: String, accessLevel: AccessLevel = .standard) throws {
        // Delete existing item first
        try? delete(key: key)

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        if let group = Constants.Keychain.accessGroup {
            query[kSecAttrAccessGroup as String] = group
        }

        if accessLevel.requiresBiometric {
            let access = SecAccessControlCreateWithFlags(
                nil,
                accessLevel.accessibility,
                .biometryCurrentSet,
                nil
            )
            query[kSecAttrAccessControl as String] = access
        } else {
            query[kSecAttrAccessible as String] = accessLevel.accessibility
        }

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            if status == errSecDuplicateItem {
                throw KeychainError.duplicateItem
            }
            throw KeychainError.unhandledError(status: status)
        }
    }

    /// Load data from keychain
    func load(key: String, withBiometric: Bool = false) throws -> Data {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        if let group = Constants.Keychain.accessGroup {
            query[kSecAttrAccessGroup as String] = group
        }

        if withBiometric {
            let context = LAContext()
            context.localizedReason = "Access secure data"
            query[kSecUseAuthenticationContext as String] = context
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            }
            if status == errSecUserCanceled || status == errSecAuthFailed {
                throw KeychainError.biometricAuthFailed
            }
            throw KeychainError.unhandledError(status: status)
        }

        guard let data = result as? Data else {
            throw KeychainError.unexpectedData
        }

        return data
    }

    /// Delete item from keychain
    func delete(key: String) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        if let group = Constants.Keychain.accessGroup {
            query[kSecAttrAccessGroup as String] = group
        }

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledError(status: status)
        }
    }

    /// Check if key exists
    func exists(key: String) -> Bool {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: false
        ]

        if let group = Constants.Keychain.accessGroup {
            query[kSecAttrAccessGroup as String] = group
        }

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Clear all items for this service
    func clearAll() {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]

        if let group = Constants.Keychain.accessGroup {
            query[kSecAttrAccessGroup as String] = group
        }

        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Shared Keychain (for extensions)

    /// Save data to the shared keychain access group with afterFirstUnlock accessibility.
    /// Used to share auth tokens with the File Provider extension.
    func saveToSharedKeychain(_ data: Data, for key: String) throws {
        guard let group = Constants.Keychain.accessGroup else { return }

        // Delete existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "shared_\(key)",
            kSecAttrAccessGroup as String: group
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "shared_\(key)",
            kSecAttrAccessGroup as String: group,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.unhandledError(status: status)
        }
    }

    /// Load data from the shared keychain access group.
    /// Used by extensions to read auth tokens written by the main app.
    func loadFromSharedKeychain(key: String) -> Data? {
        guard let group = Constants.Keychain.accessGroup else { return nil }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "shared_\(key)",
            kSecAttrAccessGroup as String: group,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    /// Sync KEM private keys to the shared keychain for the File Provider extension.
    /// Called after keys are unlocked (login, register, biometric unlock).
    func syncKemKeysToSharedKeychain(kazKemPrivateKey: Data, mlKemPrivateKey: Data) throws {
        try saveToSharedKeychain(kazKemPrivateKey, for: "kaz_kem_private_key")
        try saveToSharedKeychain(mlKemPrivateKey, for: "ml_kem_private_key")
    }

    /// Sync KEM public keys to the shared keychain for File Provider encryption on upload.
    func syncKemPublicKeysToSharedKeychain(kazKemPublicKey: Data, mlKemPublicKey: Data) throws {
        try saveToSharedKeychain(kazKemPublicKey, for: "kaz_kem_public_key")
        try saveToSharedKeychain(mlKemPublicKey, for: "ml_kem_public_key")
    }

    /// Sync a decrypted folder key to the shared keychain for the File Provider extension.
    /// Called after the folder key is unlocked (decapsulated) in the main app.
    func syncFolderKeyToSharedKeychain(folderId: String, folderKey: Data) throws {
        try saveToSharedKeychain(folderKey, for: "folder_key_\(folderId)")
    }

    /// Remove a folder key from the shared keychain.
    func clearSharedFolderKey(folderId: String) {
        guard let group = Constants.Keychain.accessGroup else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "shared_folder_key_\(folderId)",
            kSecAttrAccessGroup as String: group
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Clear KEM keys from the shared keychain.
    /// Called on lock and logout to prevent the extension from decrypting/encrypting.
    func clearSharedKemKeys() {
        guard let group = Constants.Keychain.accessGroup else { return }

        let keys = [
            "shared_kaz_kem_private_key",
            "shared_ml_kem_private_key",
            "shared_kaz_kem_public_key",
            "shared_ml_kem_public_key"
        ]

        for key in keys {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key,
                kSecAttrAccessGroup as String: group
            ]
            SecItemDelete(query as CFDictionary)
        }
    }

    /// Clear all shared keychain items
    func clearSharedKeychain() {
        guard let group = Constants.Keychain.accessGroup else { return }

        let keys = [
            "shared_\(Constants.Keychain.accessToken)",
            "shared_\(Constants.Keychain.refreshToken)",
            "shared_\(Constants.Keychain.userId)",
            "shared_kaz_kem_private_key",
            "shared_ml_kem_private_key",
            "shared_kaz_kem_public_key",
            "shared_ml_kem_public_key"
        ]

        for key in keys {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key,
                kSecAttrAccessGroup as String: group
            ]
            SecItemDelete(query as CFDictionary)
        }
    }

    // MARK: - Convenience Methods

    /// Save string to keychain
    func saveString(_ string: String, for key: String, accessLevel: AccessLevel = .standard) throws {
        guard let data = string.data(using: .utf8) else {
            throw KeychainError.unexpectedData
        }
        try save(data, for: key, accessLevel: accessLevel)
    }

    /// Load string from keychain
    func loadString(key: String, withBiometric: Bool = false) throws -> String {
        let data = try load(key: key, withBiometric: withBiometric)
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.unexpectedData
        }
        return string
    }

    // MARK: - Token Management

    var accessToken: String? {
        get {
            try? loadString(key: Constants.Keychain.accessToken)
        }
        set {
            if let token = newValue {
                try? saveString(token, for: Constants.Keychain.accessToken)
            } else {
                try? delete(key: Constants.Keychain.accessToken)
            }
        }
    }

    var refreshToken: String? {
        get {
            try? loadString(key: Constants.Keychain.refreshToken)
        }
        set {
            if let token = newValue {
                try? saveString(token, for: Constants.Keychain.refreshToken)
            } else {
                try? delete(key: Constants.Keychain.refreshToken)
            }
        }
    }

    var deviceId: String? {
        get {
            try? loadString(key: Constants.Keychain.deviceId)
        }
        set {
            if let id = newValue {
                try? saveString(id, for: Constants.Keychain.deviceId, accessLevel: .afterFirstUnlock)
            } else {
                try? delete(key: Constants.Keychain.deviceId)
            }
        }
    }

    var userId: String? {
        get {
            try? loadString(key: Constants.Keychain.userId)
        }
        set {
            if let id = newValue {
                try? saveString(id, for: Constants.Keychain.userId)
            } else {
                try? delete(key: Constants.Keychain.userId)
            }
        }
    }

    // MARK: - Tenant Management

    var tenantId: String? {
        get {
            try? loadString(key: Constants.Keychain.tenantId)
        }
        set {
            if let id = newValue {
                try? saveString(id, for: Constants.Keychain.tenantId)
            } else {
                try? delete(key: Constants.Keychain.tenantId)
            }
        }
    }

    var currentRole: String? {
        get {
            try? loadString(key: Constants.Keychain.currentRole)
        }
        set {
            if let role = newValue {
                try? saveString(role, for: Constants.Keychain.currentRole)
            } else {
                try? delete(key: Constants.Keychain.currentRole)
            }
        }
    }

    /// Save user's tenants as JSON
    func saveUserTenants(_ tenants: [Tenant]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(tenants)
        try save(data, for: Constants.Keychain.userTenants)
    }

    /// Load user's tenants from JSON
    func loadUserTenants() throws -> [Tenant] {
        let data = try load(key: Constants.Keychain.userTenants)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Tenant].self, from: data)
    }

    /// Atomically save tokens with tenant context (used during tenant switch)
    /// Uses a transaction marker to detect and recover from incomplete writes
    func saveTokensWithTenantContext(
        accessToken: String,
        refreshToken: String,
        tenantId: String,
        role: String
    ) throws {
        // Generate a unique transaction ID
        let transactionId = UUID().uuidString

        // Step 1: Mark transaction as in-progress
        try saveString(transactionId, for: Constants.Keychain.tenantTransactionId)

        // Step 2: Save all values
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tenantId = tenantId
        self.currentRole = role

        // Step 3: Save the completed transaction marker with matching ID
        try saveString(transactionId, for: Constants.Keychain.tenantTransactionComplete)
    }

    /// Validate tenant context consistency on app launch
    /// Returns true if state is consistent, false if recovery was needed
    @discardableResult
    func validateTenantContextConsistency() -> Bool {
        // Check if there's a pending transaction
        let startedId = try? loadString(key: Constants.Keychain.tenantTransactionId)
        let completedId = try? loadString(key: Constants.Keychain.tenantTransactionComplete)

        // If transaction IDs don't match, we have an inconsistent state
        if startedId != completedId {
            // Clear all tenant-related data to force re-authentication
            clearTenantData()
            // Also clear tokens since they may be for wrong tenant
            accessToken = nil
            refreshToken = nil
            // Clear transaction markers
            try? delete(key: Constants.Keychain.tenantTransactionId)
            try? delete(key: Constants.Keychain.tenantTransactionComplete)
            return false
        }

        return true
    }

    /// Clear tenant-specific data (used when switching tenants or logout)
    func clearTenantData() {
        tenantId = nil
        currentRole = nil
        try? delete(key: Constants.Keychain.userTenants)
        try? delete(key: Constants.Keychain.tenantTransactionId)
        try? delete(key: Constants.Keychain.tenantTransactionComplete)
    }

    // MARK: - Key Management

    /// Save encrypted keys (requires biometric to retrieve)
    func saveEncryptedKeys(_ data: Data) throws {
        try save(data, for: Constants.Keychain.encryptedKeys, accessLevel: .biometric)
    }

    /// Load encrypted keys with biometric authentication
    func loadEncryptedKeys() throws -> Data {
        try load(key: Constants.Keychain.encryptedKeys, withBiometric: true)
    }

    /// Save master key (derived from password, encrypted with biometric)
    func saveMasterKey(_ data: Data) throws {
        try save(data, for: Constants.Keychain.masterKey, accessLevel: .biometric)
    }

    /// Load master key with biometric authentication
    func loadMasterKey() throws -> Data {
        try load(key: Constants.Keychain.masterKey, withBiometric: true)
    }

    /// Check if master key is stored
    var hasMasterKey: Bool {
        exists(key: Constants.Keychain.masterKey)
    }

    /// Check if encrypted keys are stored
    var hasEncryptedKeys: Bool {
        exists(key: Constants.Keychain.encryptedKeys)
    }
}
