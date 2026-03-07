import Foundation

/// Constants for the File Provider extension.
/// Mirrors values from the main app's Constants without importing UIKit or the app target.
enum FPConstants {

    #if DEBUG
    static let baseURL = "https://api-dev.securesharing.app/v1"
    #else
    static let baseURL = "https://api.securesharing.app/v1"
    #endif

    static let sharedKeychainService = "com.securesharing.ios"
    static var sharedKeychainAccessGroup: String {
        let teamId = Bundle.main.infoDictionary?["AppIdentifierPrefix"] as? String ?? ""
        return "\(teamId)com.securesharing.shared"
    }
    static let appGroupSuite = "group.com.securesharing"

    // Shared keychain keys (must match "shared_" prefix used by KeychainManager)
    static let accessTokenKey = "shared_access_token"
    static let refreshTokenKey = "shared_refresh_token"
    static let userIdKey = "shared_user_id"

    // KEM private keys for decryption (synced by main app)
    static let kazKemPrivateKey = "shared_kaz_kem_private_key"
    static let mlKemPrivateKey = "shared_ml_kem_private_key"

    // KEM public keys for encryption on upload (synced by main app)
    static let kazKemPublicKey = "shared_kaz_kem_public_key"
    static let mlKemPublicKey = "shared_ml_kem_public_key"

    static let httpTimeout: TimeInterval = 30

    enum Domain {
        static let identifier = "com.securesharing.user-files"
        static let displayName = "SecureSharing"
    }
}
