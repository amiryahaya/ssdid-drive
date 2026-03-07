import Foundation
import Security

/// Read-only keychain client for the File Provider extension.
/// Reads auth tokens written by the main app via the shared keychain access group.
/// No writes, no biometric — extension only reads `afterFirstUnlock` items.
enum FPKeychainReader {

    /// Read the access token from the shared keychain.
    static func readAccessToken() -> String? {
        readString(account: FPConstants.accessTokenKey)
    }

    /// Read the refresh token from the shared keychain.
    static func readRefreshToken() -> String? {
        readString(account: FPConstants.refreshTokenKey)
    }

    /// Read the current user ID from the shared keychain.
    static func readUserId() -> String? {
        readString(account: FPConstants.userIdKey)
    }

    /// Read the KAZ-KEM private key from the shared keychain.
    static func readKazKemPrivateKey() -> Data? {
        readData(account: FPConstants.kazKemPrivateKey)
    }

    /// Read the ML-KEM private key from the shared keychain.
    static func readMlKemPrivateKey() -> Data? {
        readData(account: FPConstants.mlKemPrivateKey)
    }

    /// Read the KAZ-KEM public key from the shared keychain.
    static func readKazKemPublicKey() -> Data? {
        readData(account: FPConstants.kazKemPublicKey)
    }

    /// Read the ML-KEM public key from the shared keychain.
    static func readMlKemPublicKey() -> Data? {
        readData(account: FPConstants.mlKemPublicKey)
    }

    // MARK: - Private

    private static func readString(account: String) -> String? {
        guard let data = readData(account: account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func readData(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: FPConstants.sharedKeychainService,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: FPConstants.sharedKeychainAccessGroup,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else { return nil }
        return result as? Data
    }
}
