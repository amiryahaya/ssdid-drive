import Foundation
import CryptoKit

/// Implementation of WebAuthnRepository
final class WebAuthnRepositoryImpl: WebAuthnRepository {

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

    // MARK: - WebAuthnRepository

    func loginBegin(email: String?) async throws -> WebAuthnBeginResult {
        struct BeginRequest: Encodable {
            let email: String?
        }

        struct BeginResponse: Decodable {
            let options: AnyCodable
            let challenge_id: String
        }

        let request = BeginRequest(email: email)
        let response: BeginResponse = try await apiClient.request(
            Constants.API.Endpoints.webauthnLoginBegin,
            method: .post,
            body: request,
            requiresAuth: false
        )

        let optionsData = try JSONEncoder().encode(response.options)
        let optionsJson = String(data: optionsData, encoding: .utf8) ?? "{}"

        return WebAuthnBeginResult(
            optionsJson: optionsJson,
            challengeId: response.challenge_id
        )
    }

    func loginComplete(challengeId: String, assertionData: [String: Any]) async throws -> User {
        // iOS does NOT support PRF extension, so always uses vault-based key bundle
        let jsonData = try JSONSerialization.data(withJSONObject: assertionData)
        let assertionJson = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] ?? [:]

        struct CompleteRequest: Encodable {
            let challenge_id: String
            let assertion: AnyCodable
        }

        struct CompleteResponse: Decodable {
            let access_token: String
            let refresh_token: String
            let user: UserResponse
            let key_bundle: VaultKeyBundleResponse
        }

        struct UserResponse: Decodable {
            let id: String
            let email: String
            let display_name: String?
        }

        struct VaultKeyBundleResponse: Decodable {
            let source: String
            let vault_encrypted_master_key: String?
            let vault_mk_nonce: String?
            let key_material: String?
            let key_salt: String?
            let encrypted_private_keys: EncryptedPrivateKeysResponse
        }

        struct EncryptedPrivateKeysResponse: Decodable {
            let kaz_kem: String
            let ml_kem: String
            let kaz_sign: String
            let ml_dsa: String
        }

        let request = CompleteRequest(
            challenge_id: challengeId,
            assertion: AnyCodable(assertionJson)
        )

        let response: CompleteResponse = try await apiClient.request(
            Constants.API.Endpoints.webauthnLoginComplete,
            method: .post,
            body: request,
            requiresAuth: false
        )

        // Store tokens
        keychainManager.accessToken = response.access_token
        keychainManager.refreshToken = response.refresh_token
        keychainManager.userId = response.user.id

        // iOS always uses vault-based key unlock (no PRF support)
        let keyBundle = response.key_bundle
        guard let keyMaterial = keyBundle.key_material,
              let keySalt = keyBundle.key_salt,
              let vaultEncryptedMK = keyBundle.vault_encrypted_master_key,
              let vaultMkNonce = keyBundle.vault_mk_nonce,
              let keyMaterialData = Data(base64Encoded: keyMaterial),
              let keySaltData = Data(base64Encoded: keySalt),
              let encMKData = Data(base64Encoded: vaultEncryptedMK),
              let nonceData = Data(base64Encoded: vaultMkNonce) else {
            throw AuthError.invalidCredentials
        }

        // Derive vault key
        let vaultKey = HKDF<SHA384>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: keyMaterialData),
            salt: keySaltData,
            info: Data("ssdid-drive-vault-key".utf8),
            outputByteCount: 32
        )

        // Decrypt master key
        guard let gcmNonce = try? AES.GCM.Nonce(data: nonceData) else {
            throw AuthError.invalidCredentials
        }

        let sealedBox = try AES.GCM.SealedBox(nonce: gcmNonce, ciphertext: encMKData.dropLast(16), tag: encMKData.suffix(16))
        let masterKey = try AES.GCM.open(sealedBox, using: vaultKey)

        // Unlock keys
        try keyManager.unlockWithMasterKey(masterKey, encryptedPrivateKeys: keyBundle.encrypted_private_keys)

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

    func getCredentials() async throws -> [UserCredential] {
        struct CredentialsResponse: Decodable {
            let credentials: [UserCredential]
        }

        let response: CredentialsResponse = try await apiClient.request(
            Constants.API.Endpoints.authCredentials,
            method: .get
        )

        return response.credentials
    }

    func renameCredential(credentialId: String, name: String) async throws -> UserCredential {
        struct RenameRequest: Encodable {
            let name: String
        }

        let endpoint = "\(Constants.API.Endpoints.authCredentials)/\(credentialId)"
        let request = RenameRequest(name: name)

        let response: UserCredential = try await apiClient.request(
            endpoint,
            method: .put,
            body: request
        )

        return response
    }

    func deleteCredential(credentialId: String) async throws {
        let endpoint = "\(Constants.API.Endpoints.authCredentials)/\(credentialId)"
        try await apiClient.requestNoContent(endpoint, method: .delete)
    }
}

/// Type-erased Codable wrapper for dynamic JSON
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let dict = value as? [String: Any] {
            try container.encode(dict.mapValues { AnyCodable($0) })
        } else if let array = value as? [Any] {
            try container.encode(array.map { AnyCodable($0) })
        } else if let string = value as? String {
            try container.encode(string)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let bool = value as? Bool {
            try container.encode(bool)
        } else {
            try container.encodeNil()
        }
    }
}
