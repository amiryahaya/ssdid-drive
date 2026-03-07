import Foundation

// MARK: - Removed: OIDC authentication replaced by SSDID wallet authentication

/// Stub: OIDC authentication has been replaced by SSDID wallet QR-based authentication.
/// Protocol and types are kept to satisfy existing DI container references.
final class OidcRepositoryImpl: OidcRepository {

    init(apiClient: APIClient, keychainManager: KeychainManager, keyManager: KeyManager) {}

    func getProviders(tenantSlug: String) async throws -> [AuthProvider] {
        return []
    }

    func beginAuthorize(providerId: String) async throws -> OidcAuthorizeResult {
        throw AuthError.notAuthenticated
    }

    func handleCallback(code: String, state: String) async throws -> OidcCallbackResult {
        throw AuthError.notAuthenticated
    }

    func completeRegistration(
        keyMaterial: String,
        keySalt: String,
        encryptedMasterKey: String,
        vaultEncryptedMasterKey: String,
        vaultMkNonce: String,
        encryptedPrivateKeys: String,
        publicKeys: [String: String]
    ) async throws -> User {
        throw AuthError.notAuthenticated
    }
}
