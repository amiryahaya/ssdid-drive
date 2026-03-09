import Foundation
import Security

/// Read-only keychain client for the File Provider extension.
/// Reads auth tokens written by the main app via the shared keychain access group.
/// No writes, no biometric — extension only reads `afterFirstUnlock` items.
enum FPKeychainReader {

    // MARK: - Types

    /// Complete KEM key pair for hybrid PQC operations.
    struct KemKeyPair {
        let kazKemPublicKey: Data
        let kazKemPrivateKey: Data
        let mlKemPublicKey: Data
        let mlKemPrivateKey: Data
    }

    enum KeychainError: Error {
        case kemKeysNotAvailable
        case folderKeyNotAvailable
    }

    // MARK: - Token Access

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

    // MARK: - KEM Key Access

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

    /// Read the complete hybrid KEM key pair from the shared keychain.
    ///
    /// Returns all four keys (KAZ-KEM + ML-KEM, public + private) needed for
    /// hybrid PQC encryption and decryption. Throws if any key is missing.
    ///
    /// - Returns: A `KemKeyPair` containing all four KEM keys.
    /// - Throws: `KeychainError.kemKeysNotAvailable` if any key is missing.
    static func getKemKeyPair() throws -> KemKeyPair {
        guard let kazPub = readKazKemPublicKey(),
              let kazPriv = readKazKemPrivateKey(),
              let mlPub = readMlKemPublicKey(),
              let mlPriv = readMlKemPrivateKey() else {
            throw KeychainError.kemKeysNotAvailable
        }
        return KemKeyPair(
            kazKemPublicKey: kazPub,
            kazKemPrivateKey: kazPriv,
            mlKemPublicKey: mlPub,
            mlKemPrivateKey: mlPriv
        )
    }

    // MARK: - Folder Key Access

    /// Read a decrypted folder key from the shared keychain.
    /// The main app stores folder keys keyed by folder ID after unlocking them.
    static func readFolderKey(folderId: String) -> Data? {
        readData(account: "shared_folder_key_\(folderId)")
    }

    /// Read a folder key, throwing if not available.
    ///
    /// - Parameter folderId: The folder identifier.
    /// - Returns: 32-byte folder key.
    /// - Throws: `KeychainError.folderKeyNotAvailable` if the key is not in the keychain.
    static func requireFolderKey(folderId: String) throws -> Data {
        guard let key = readFolderKey(folderId: folderId) else {
            throw KeychainError.folderKeyNotAvailable
        }
        return key
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
