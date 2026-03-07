import Foundation
@testable import SecureSharing

/// Mock implementation of KeychainManaging for invitation tests
/// Named differently to avoid conflict with MockKeychainManager in KeyManagerTests.swift
final class InvitationMockKeychainManager: KeychainManaging {

    // MARK: - Storage

    var storage: [String: Data] = [:]

    // MARK: - Behavior Control

    var shouldFailOnSave = false
    var shouldFailOnLoad = false
    var shouldFailOnDelete = false
    var shouldFailOnBiometric = false

    var saveError: Error = KeychainManager.KeychainError.unhandledError(status: -1)
    var loadError: Error = KeychainManager.KeychainError.itemNotFound
    var deleteError: Error = KeychainManager.KeychainError.unhandledError(status: -1)
    var biometricError: Error = KeychainManager.KeychainError.biometricAuthFailed

    // MARK: - Call Tracking

    var saveCallCount = 0
    var loadCallCount = 0
    var deleteCallCount = 0
    var existsCallCount = 0
    var saveMasterKeyCallCount = 0
    var loadMasterKeyCallCount = 0

    var lastSavedKey: String?
    var lastSavedData: Data?
    var lastSavedAccessLevel: KeychainManager.AccessLevel?
    var lastLoadedKey: String?
    var lastDeletedKey: String?

    // MARK: - KeychainManaging Protocol

    func save(_ data: Data, for key: String, accessLevel: KeychainManager.AccessLevel) throws {
        saveCallCount += 1
        lastSavedKey = key
        lastSavedData = data
        lastSavedAccessLevel = accessLevel

        if shouldFailOnSave {
            throw saveError
        }

        storage[key] = data
    }

    func load(key: String, withBiometric: Bool) throws -> Data {
        loadCallCount += 1
        lastLoadedKey = key

        if shouldFailOnLoad {
            throw loadError
        }

        if withBiometric && shouldFailOnBiometric {
            throw biometricError
        }

        guard let data = storage[key] else {
            throw KeychainManager.KeychainError.itemNotFound
        }

        return data
    }

    func delete(key: String) throws {
        deleteCallCount += 1
        lastDeletedKey = key

        if shouldFailOnDelete {
            throw deleteError
        }

        storage.removeValue(forKey: key)
    }

    func exists(key: String) -> Bool {
        existsCallCount += 1
        return storage[key] != nil
    }

    var hasEncryptedKeys: Bool {
        storage[Constants.Keychain.encryptedKeys] != nil
    }

    func saveMasterKey(_ data: Data) throws {
        saveMasterKeyCallCount += 1

        if shouldFailOnSave {
            throw saveError
        }

        storage[Constants.Keychain.masterKey] = data
    }

    func loadMasterKey() throws -> Data {
        loadMasterKeyCallCount += 1

        if shouldFailOnBiometric {
            throw biometricError
        }

        guard let data = storage[Constants.Keychain.masterKey] else {
            throw KeychainManager.KeychainError.itemNotFound
        }

        return data
    }

    // MARK: - Convenience Methods

    func setString(_ string: String, for key: String) {
        storage[key] = string.data(using: .utf8)
    }

    func getString(for key: String) -> String? {
        guard let data = storage[key] else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Reset

    func reset() {
        storage.removeAll()
        shouldFailOnSave = false
        shouldFailOnLoad = false
        shouldFailOnDelete = false
        shouldFailOnBiometric = false
        saveCallCount = 0
        loadCallCount = 0
        deleteCallCount = 0
        existsCallCount = 0
        saveMasterKeyCallCount = 0
        loadMasterKeyCallCount = 0
        lastSavedKey = nil
        lastSavedData = nil
        lastSavedAccessLevel = nil
        lastLoadedKey = nil
        lastDeletedKey = nil
    }
}
