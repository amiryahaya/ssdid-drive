import Foundation
import Security

/// Helper class for accessing shared keychain items between the main app and extension
class KeychainHelper {

    // MARK: - Constants

    private let serviceName = "my.ssdid.drive.desktop"
    private let accessGroup = "$(TeamIdentifierPrefix)my.ssdid.drive"
    private let authTokenKey = "auth_token"
    private let refreshTokenKey = "refresh_token"

    // MARK: - Initialization

    init() {}

    // MARK: - Public Methods

    /// Get the current authentication token
    func getAuthToken() -> String? {
        return getString(forKey: authTokenKey)
    }

    /// Store the authentication token
    func setAuthToken(_ token: String) -> Bool {
        return setString(token, forKey: authTokenKey)
    }

    /// Get the refresh token
    func getRefreshToken() -> String? {
        return getString(forKey: refreshTokenKey)
    }

    /// Store the refresh token
    func setRefreshToken(_ token: String) -> Bool {
        return setString(token, forKey: refreshTokenKey)
    }

    /// Clear all authentication tokens
    func clearTokens() {
        deleteItem(forKey: authTokenKey)
        deleteItem(forKey: refreshTokenKey)
    }

    /// Check if user is authenticated
    var isAuthenticated: Bool {
        return getAuthToken() != nil
    }

    // MARK: - Private Methods

    private func getString(forKey key: String) -> String? {
        guard let data = getData(forKey: key) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func setString(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else {
            return false
        }
        return setData(data, forKey: key)
    }

    private func getData(forKey key: String) -> Data? {
        var query = baseQuery(forKey: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            return nil
        }

        return result as? Data
    }

    private func setData(_ data: Data, forKey key: String) -> Bool {
        // First try to update existing item
        var query = baseQuery(forKey: key)

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if status == errSecItemNotFound {
            // Item doesn't exist, add it
            query[kSecValueData as String] = data
            status = SecItemAdd(query as CFDictionary, nil)
        }

        return status == errSecSuccess
    }

    private func deleteItem(forKey key: String) {
        let query = baseQuery(forKey: key)
        SecItemDelete(query as CFDictionary)
    }

    private func baseQuery(forKey key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]

        // Use access group for sharing between app and extension
        #if !targetEnvironment(simulator)
        query[kSecAttrAccessGroup as String] = accessGroup
        #endif

        return query
    }
}
