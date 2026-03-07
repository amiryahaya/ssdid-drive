import Foundation
import CryptoKit

/// Implementation of OidcRepository
final class OidcRepositoryImpl: OidcRepository {

    // MARK: - Properties

    private let apiClient: APIClient
    private let keychainManager: KeychainManager
    private let keyManager: KeyManager

    // MARK: - Initialization

    init(apiClient: APIClient, keychainManager: KeychainManager, keyManager: KeyManager) {
        self.apiClient = apiClient
        self.keychainManager = keychainManager
        self.keyManager = keyManager
    }

    // MARK: - OidcRepository

    func getProviders(tenantSlug: String) async throws -> [AuthProvider] {
        struct ProvidersResponse: Codable {
            let providers: [AuthProvider]
        }

        let response: ProvidersResponse = try await apiClient.request(
            Constants.API.Endpoints.authProviders + "?tenant_slug=\(tenantSlug)",
            method: .get,
            requiresAuth: false
        )

        return response.providers
    }

    func beginAuthorize(providerId: String) async throws -> OidcAuthorizeResult {
        struct AuthorizeRequest: Encodable {
            let provider_id: String
        }

        struct AuthorizeResponse: Decodable {
            let authorization_url: String
            let state: String
        }

        let request = AuthorizeRequest(provider_id: providerId)
        let response: AuthorizeResponse = try await apiClient.request(
            Constants.API.Endpoints.oidcAuthorize,
            method: .post,
            body: request,
            requiresAuth: false
        )

        return OidcAuthorizeResult(
            authorizationUrl: response.authorization_url,
            state: response.state
        )
    }

    func handleCallback(code: String, state: String) async throws -> OidcCallbackResult {
        struct CallbackRequest: Encodable {
            let code: String
            let state: String
        }

        struct CallbackResponse: Decodable {
            let status: String
            let access_token: String?
            let refresh_token: String?
            let user: UserResponse?
            let key_bundle: VaultKeyBundleResponse?
            let key_material: String?
            let key_salt: String?
        }

        struct UserResponse: Decodable {
            let id: String
            let email: String
            let display_name: String?
        }

        struct VaultKeyBundleResponse: Decodable {
            let source: String
            let vault_encrypted_master_key: String
            let vault_mk_nonce: String
            let encrypted_private_keys: EncryptedPrivateKeysResponse
        }

        struct EncryptedPrivateKeysResponse: Decodable {
            let kaz_kem: String
            let ml_kem: String
            let kaz_sign: String
            let ml_dsa: String
        }

        let request = CallbackRequest(code: code, state: state)
        let response: CallbackResponse = try await apiClient.request(
            Constants.API.Endpoints.oidcCallback,
            method: .post,
            body: request,
            requiresAuth: false
        )

        if response.status == "authenticated" {
            guard let accessToken = response.access_token,
                  let refreshToken = response.refresh_token,
                  let userResponse = response.user,
                  let keyBundle = response.key_bundle,
                  let keyMaterial = response.key_material,
                  let keySalt = response.key_salt else {
                throw AuthError.invalidCredentials
            }

            // Store tokens
            keychainManager.accessToken = accessToken
            keychainManager.refreshToken = refreshToken
            keychainManager.userId = userResponse.id

            // Derive vault key from key_material + key_salt
            guard let keyMaterialData = Data(base64Encoded: keyMaterial),
                  let keySaltData = Data(base64Encoded: keySalt) else {
                throw AuthError.invalidCredentials
            }

            let vaultKey = deriveVaultKey(keyMaterial: keyMaterialData, keySalt: keySaltData)

            // Decrypt master key using vault key
            guard let vaultEncryptedMK = Data(base64Encoded: keyBundle.vault_encrypted_master_key),
                  let vaultMkNonce = Data(base64Encoded: keyBundle.vault_mk_nonce) else {
                throw AuthError.invalidCredentials
            }

            let masterKey = try decryptWithVaultKey(
                encryptedData: vaultEncryptedMK,
                nonce: vaultMkNonce,
                vaultKey: vaultKey
            )

            // Unlock keys with master key
            try keyManager.unlockWithMasterKey(masterKey, encryptedPrivateKeys: keyBundle.encrypted_private_keys)

            let user = User(
                id: userResponse.id,
                email: userResponse.email,
                displayName: userResponse.display_name,
                tenantId: nil,
                createdAt: Date(),
                updatedAt: Date(),
                encryptedMasterKey: nil,
                keyDerivationSalt: nil
            )

            return .authenticated(user)
        } else {
            // New user - return key material for registration
            guard let keyMaterial = response.key_material,
                  let keySalt = response.key_salt else {
                throw AuthError.registrationFailed
            }

            return .newUser(keyMaterial: keyMaterial, keySalt: keySalt)
        }
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
        struct RegisterRequest: Encodable {
            let key_material: String
            let key_salt: String
            let encrypted_master_key: String
            let vault_encrypted_master_key: String
            let vault_mk_nonce: String
            let encrypted_private_keys: String
            let public_keys: [String: String]
        }

        struct RegisterResponse: Decodable {
            let access_token: String
            let refresh_token: String
            let user: UserResponse
        }

        struct UserResponse: Decodable {
            let id: String
            let email: String
            let display_name: String?
        }

        let request = RegisterRequest(
            key_material: keyMaterial,
            key_salt: keySalt,
            encrypted_master_key: encryptedMasterKey,
            vault_encrypted_master_key: vaultEncryptedMasterKey,
            vault_mk_nonce: vaultMkNonce,
            encrypted_private_keys: encryptedPrivateKeys,
            public_keys: publicKeys
        )

        let response: RegisterResponse = try await apiClient.request(
            Constants.API.Endpoints.oidcRegister,
            method: .post,
            body: request,
            requiresAuth: false
        )

        keychainManager.accessToken = response.access_token
        keychainManager.refreshToken = response.refresh_token
        keychainManager.userId = response.user.id

        return User(
            id: response.user.id,
            email: response.user.email,
            displayName: response.user.display_name,
            tenantId: nil,
            createdAt: Date(),
            updatedAt: Date(),
            encryptedMasterKey: nil,
            keyDerivationSalt: nil
        )
    }

    // MARK: - Private Helpers

    /// Derive vault key from OIDC key_material and key_salt using HKDF-SHA384
    private func deriveVaultKey(keyMaterial: Data, keySalt: Data) -> SymmetricKey {
        HKDF<SHA384>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: keyMaterial),
            salt: keySalt,
            info: Data("ssdid-drive-vault-key".utf8),
            outputByteCount: 32
        )
    }

    /// Decrypt data using AES-GCM with a separately provided nonce
    private func decryptWithVaultKey(encryptedData: Data, nonce: Data, vaultKey: SymmetricKey) throws -> Data {
        guard let gcmNonce = try? AES.GCM.Nonce(data: nonce) else {
            throw AuthError.invalidCredentials
        }

        let sealedBox = try AES.GCM.SealedBox(nonce: gcmNonce, ciphertext: encryptedData.dropLast(16), tag: encryptedData.suffix(16))
        return try AES.GCM.open(sealedBox, using: vaultKey)
    }
}
