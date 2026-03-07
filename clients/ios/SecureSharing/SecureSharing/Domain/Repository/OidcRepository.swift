import Foundation

/// OIDC authorization result
struct OidcAuthorizeResult {
    let authorizationUrl: String
    let state: String
}

/// OIDC callback result
enum OidcCallbackResult {
    case authenticated(User)
    case newUser(keyMaterial: String, keySalt: String)
}

/// Repository for OIDC authentication operations
protocol OidcRepository: AnyObject {
    /// Get available OIDC providers for a tenant
    func getProviders(tenantSlug: String) async throws -> [AuthProvider]

    /// Begin OIDC authorization flow
    func beginAuthorize(providerId: String) async throws -> OidcAuthorizeResult

    /// Handle OIDC callback with authorization code
    func handleCallback(code: String, state: String) async throws -> OidcCallbackResult

    /// Complete registration for new OIDC user
    func completeRegistration(
        keyMaterial: String,
        keySalt: String,
        encryptedMasterKey: String,
        vaultEncryptedMasterKey: String,
        vaultMkNonce: String,
        encryptedPrivateKeys: String,
        publicKeys: [String: String]
    ) async throws -> User
}
