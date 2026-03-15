import Foundation
import LocalAuthentication
import CryptoKit
import Security
import UIKit

/// Implementation of AuthRepository.
/// Authentication is SSDID wallet-based (QR challenge-response).
/// Password is only used for client-side key encryption during invitation acceptance.
final class AuthRepositoryImpl: AuthRepository {

    // MARK: - Properties

    private let apiClient: APIClient
    private let keychainManager: KeychainManager
    private let keyManager: KeyManager

    // MARK: - Initialization

    init(
        apiClient: APIClient,
        keychainManager: KeychainManager,
        keyManager: KeyManager
    ) {
        self.apiClient = apiClient
        self.keychainManager = keychainManager
        self.keyManager = keyManager
    }

    // MARK: - Authentication

    func logout() async throws {
        // Call logout endpoint (optional - may fail if already logged out)
        try? await apiClient.requestNoContent(
            Constants.API.Endpoints.logout,
            method: .post
        )

        // Clear shared defaults for menu bar helper
        SharedDefaults.shared.clearAll()
        SharedDefaults.shared.notifyHelper()

        // Clear shared keychain (File Provider extension)
        keychainManager.clearSharedKeychain()

        // Unregister File Provider domain
        await MainActor.run {
            DependencyContainer.shared.fileProviderDomainManager.unregisterDomain()
        }

        // Clear Spotlight index and thumbnail cache (zero-knowledge cleanup)
        SpotlightIndexer.shared.clearAllIndexes()
        ThumbnailCache.shared.clearCache()

        // Clean up any drag-and-drop temp directories containing plaintext files
        let tmpDir = FileManager.default.temporaryDirectory
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: tmpDir.path) {
            for name in contents where name.hasPrefix("drop-") {
                try? FileManager.default.removeItem(at: tmpDir.appendingPathComponent(name))
            }
        }

        // Clear local data
        keychainManager.clearAll()
        keyManager.lockKeys()
    }

    func refreshToken() async throws {
        guard let refreshToken = keychainManager.refreshToken else {
            // H1: Clear shared defaults on auth failure so helper shows correct state
            SharedDefaults.shared.writeIsAuthenticated(false)
            SharedDefaults.shared.writeSyncStatus(.offline)
            SharedDefaults.shared.notifyHelper()
            throw AuthError.notAuthenticated
        }

        let request = RefreshRequest(refreshToken: refreshToken)

        do {
            let response: AuthTokens = try await apiClient.request(
                Constants.API.Endpoints.refreshToken,
                method: .post,
                body: request,
                requiresAuth: false
            )

            keychainManager.accessToken = response.accessToken
            keychainManager.refreshToken = response.refreshToken

            // Sync refreshed tokens to shared keychain for File Provider extension
            if let tokenData = response.accessToken.data(using: .utf8) {
                try? keychainManager.saveToSharedKeychain(tokenData, for: Constants.Keychain.accessToken)
            }
            if let refreshData = response.refreshToken.data(using: .utf8) {
                try? keychainManager.saveToSharedKeychain(refreshData, for: Constants.Keychain.refreshToken)
            }
        } catch {
            // H1: Session expired — update shared defaults so helper reflects reality
            SharedDefaults.shared.writeIsAuthenticated(false)
            SharedDefaults.shared.writeSyncStatus(.error)
            SharedDefaults.shared.notifyHelper()
            throw error
        }
    }

    func getCurrentUser() async throws -> User {
        let response: MeResponse = try await apiClient.request(
            Constants.API.Endpoints.me,
            method: .get
        )
        return response.user
    }

    // MARK: - Authentication State

    func isAuthenticated() async -> Bool {
        keychainManager.accessToken != nil
    }

    var currentUserId: String? {
        keychainManager.userId
    }

    // MARK: - Biometric Authentication

    func isBiometricAvailable() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    func isBiometricUnlockEnabled() async -> Bool {
        keychainManager.hasMasterKey
    }

    func disableBiometricUnlock() async throws {
        try keychainManager.delete(key: Constants.Keychain.masterKey)
    }

    func authenticateWithBiometric() async throws -> Bool {
        let context = LAContext()
        context.localizedReason = "Unlock SsdidDrive"
        context.localizedFallbackTitle = "Use Password"

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Unlock your secure files"
            )

            if success {
                // Load keys using biometric-protected master key
                _ = try keyManager.loadKeysWithBiometric()
                // Sync KEM keys to shared keychain for File Provider decryption
                syncKemKeysToExtension()
                return true
            }
            return false
        } catch {
            throw AuthError.biometricFailed
        }
    }

    // MARK: - Key Management

    func areKeysUnlocked() async -> Bool {
        keyManager.areKeysUnlocked
    }

    func lockKeys() async {
        keyManager.lockKeys()
        keychainManager.clearSharedKemKeys()
    }

    // MARK: - Device Management

    func enrollDevice(name: String) async throws -> Device {
        guard let keyBundle = keyManager.currentKeyBundle else {
            throw AuthError.keysNotUnlocked
        }

        let request = DeviceEnrollRequest(
            name: name,
            platform: "ios",
            publicKey: keyBundle.deviceSigningKey.publicKey.rawRepresentation
        )

        let response: DeviceEnrollResponse = try await apiClient.request(
            Constants.API.Endpoints.enrollDevice,
            method: .post,
            body: request
        )

        keychainManager.deviceId = response.device.id
        return response.device
    }

    func getDevices() async throws -> [Device] {
        struct DevicesResponse: Codable {
            let devices: [Device]
        }

        let response: DevicesResponse = try await apiClient.request(
            Constants.API.Endpoints.devices,
            method: .get
        )

        return response.devices
    }

    func revokeDevice(deviceId: String) async throws {
        let endpoint = Constants.API.Endpoints.revokeDevice.replacingOccurrences(of: "{id}", with: deviceId)

        try await apiClient.requestNoContent(
            endpoint,
            method: .post
        )
    }

    var currentDeviceId: String? {
        keychainManager.deviceId
    }

    // MARK: - KEM Key Sync

    /// Sync KEM keys to the shared keychain so the File Provider extension can decrypt and encrypt files.
    private func syncKemKeysToExtension() {
        guard let bundle = keyManager.currentKeyBundle else { return }
        do {
            try keychainManager.syncKemKeysToSharedKeychain(
                kazKemPrivateKey: bundle.kazKemPrivateKey,
                mlKemPrivateKey: bundle.mlKemPrivateKey
            )
            try keychainManager.syncKemPublicKeysToSharedKeychain(
                kazKemPublicKey: bundle.kazKemPublicKey,
                mlKemPublicKey: bundle.mlKemPublicKey
            )
        } catch {
            #if DEBUG
            print("[KemSync] Failed to sync KEM keys to shared keychain: \(error)")
            #endif
        }
    }
}

// MARK: - Request Types

private struct RefreshRequest: Codable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

// MARK: - Invitation Token Implementation

extension AuthRepositoryImpl {

    func getInvitationInfo(token: String) async throws -> TokenInvitation {
        let endpoint = Constants.API.Endpoints.inviteInfo.replacingOccurrences(of: "{token}", with: token)

        let response: TokenInvitation = try await apiClient.request(
            endpoint,
            method: .get,
            requiresAuth: false
        )

        return response
    }

    func acceptInvitation(token: String, displayName: String, password: String) async throws -> InviteUser {
        // Generate key bundle
        let keyBundle = try keyManager.generateKeyBundle()

        // Generate salt with tiered KDF profile
        let salt = TieredKdf.createSaltWithProfile(KdfProfile.selectForDevice())

        // Derive password key using tiered KDF
        let passwordKey = try TieredKdf.deriveKey(password: password, saltWithProfile: salt)

        // Encrypt master key with password-derived key
        let masterKey = try generateMasterKey()
        let encryptedMasterKey = try encryptWithKey(data: masterKey, key: passwordKey)

        // Serialize and encrypt private keys with master key
        let privateKeysData = try serializePrivateKeys(keyBundle)
        let encryptedPrivateKeys = try encryptWithKey(data: privateKeysData, key: SymmetricKey(data: masterKey))

        // Securely zero sensitive data
        var mutablePrivateKeysData = privateKeysData
        mutablePrivateKeysData.secureZero()

        // Prepare public keys for API
        let publicKeys = AcceptInvitePublicKeys(
            kem: keyBundle.kazKemPublicKey.base64EncodedString(),
            sign: keyBundle.kazSignPublicKey.base64EncodedString(),
            mlKem: keyBundle.mlKemPublicKey.isEmpty ? nil : keyBundle.mlKemPublicKey.base64EncodedString(),
            mlDsa: keyBundle.mlDsaPublicKey.isEmpty ? nil : keyBundle.mlDsaPublicKey.base64EncodedString()
        )

        let request = AcceptInviteRequest(
            displayName: displayName,
            password: password,
            publicKeys: publicKeys,
            encryptedMasterKey: encryptedMasterKey.base64EncodedString(),
            encryptedPrivateKeys: encryptedPrivateKeys.base64EncodedString(),
            keyDerivationSalt: salt.base64EncodedString()
        )

        let endpoint = Constants.API.Endpoints.acceptInvite.replacingOccurrences(of: "{token}", with: token)

        let response: AcceptInviteResponse = try await apiClient.request(
            endpoint,
            method: .post,
            body: request,
            requiresAuth: false
        )

        // Store tokens
        keychainManager.accessToken = response.data.accessToken
        keychainManager.refreshToken = response.data.refreshToken
        keychainManager.userId = response.data.user.id

        // Write tokens to shared keychain for File Provider extension
        if let tokenData = response.data.accessToken.data(using: .utf8) {
            try? keychainManager.saveToSharedKeychain(tokenData, for: Constants.Keychain.accessToken)
        }
        if let refreshData = response.data.refreshToken.data(using: .utf8) {
            try? keychainManager.saveToSharedKeychain(refreshData, for: Constants.Keychain.refreshToken)
        }
        if let userIdData = response.data.user.id.data(using: .utf8) {
            try? keychainManager.saveToSharedKeychain(userIdData, for: Constants.Keychain.userId)
        }

        // Register File Provider domain
        await MainActor.run {
            DependencyContainer.shared.fileProviderDomainManager.registerDomain()
        }

        // Store encrypted keys
        try keyManager.storeKeys(keyBundle, password: password)

        // Sync KEM keys to shared keychain for File Provider decryption
        syncKemKeysToExtension()

        return response.data.user
    }

    // MARK: - Wallet-Based Invitation

    func launchWalletInvite(token: String) async throws {
        let serverUrl = Constants.API.baseURL
        let callbackUrl = "ssdid-drive://invite/callback"

        var components = URLComponents()
        components.scheme = "ssdid"
        components.host = "invite"
        components.queryItems = [
            URLQueryItem(name: "server_url", value: serverUrl),
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "callback_url", value: callbackUrl)
        ]

        guard let url = components.url else {
            throw AuthError.invalidURL
        }

        guard await MainActor.run(body: { UIApplication.shared.canOpenURL(url) }) else {
            throw AuthError.walletNotInstalled
        }

        await MainActor.run {
            UIApplication.shared.open(url)
        }
    }

    func saveSessionFromWallet(sessionToken: String) async throws {
        // Temporarily set token to allow getCurrentUser() to work
        keychainManager.accessToken = sessionToken

        do {
            let user = try await getCurrentUser()
            // Success — write all state atomically
            keychainManager.userId = user.id

            if let tokenData = sessionToken.data(using: .utf8) {
                try? keychainManager.saveToSharedKeychain(tokenData, for: Constants.Keychain.accessToken)
            }
            if let userIdData = user.id.data(using: .utf8) {
                try? keychainManager.saveToSharedKeychain(userIdData, for: Constants.Keychain.userId)
            }

            SharedDefaults.shared.writeIsAuthenticated(true)
            SharedDefaults.shared.notifyHelper()
        } catch {
            // Rollback: clear the access token since we couldn't validate it
            keychainManager.accessToken = nil
            throw error
        }
    }

    // MARK: - Multi-Auth Invitation Acceptance

    func acceptInvitationAsExistingUser(token: String) async throws {
        let endpoint = "/api/invitations/token/\(token)/accept"
        let _: AcceptCodeInvitationResponse = try await apiClient.request(
            endpoint,
            method: .post,
            body: nil,
            queryItems: nil,
            requiresAuth: true
        )
    }

    func acceptInvitationWithOidc(token: String, provider: String, idToken: String) async throws {
        struct OidcInviteRequest: Encodable {
            let provider: String
            let idToken: String
            let invitationToken: String

            enum CodingKeys: String, CodingKey {
                case provider
                case idToken = "id_token"
                case invitationToken = "invitation_token"
            }
        }

        let request = OidcInviteRequest(
            provider: provider,
            idToken: idToken,
            invitationToken: token
        )

        struct OidcInviteResponse: Decodable {
            let accessToken: String
            let refreshToken: String
            let user: InviteUser

            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case refreshToken = "refresh_token"
                case user
            }
        }

        let response: OidcInviteResponse = try await apiClient.request(
            "/api/auth/oidc/verify",
            method: .post,
            body: request,
            requiresAuth: false
        )

        // Store tokens
        keychainManager.accessToken = response.accessToken
        keychainManager.refreshToken = response.refreshToken
        keychainManager.userId = response.user.id

        // Write tokens to shared keychain for File Provider extension
        if let tokenData = response.accessToken.data(using: .utf8) {
            try? keychainManager.saveToSharedKeychain(tokenData, for: Constants.Keychain.accessToken)
        }
        if let refreshData = response.refreshToken.data(using: .utf8) {
            try? keychainManager.saveToSharedKeychain(refreshData, for: Constants.Keychain.refreshToken)
        }
        if let userIdData = response.user.id.data(using: .utf8) {
            try? keychainManager.saveToSharedKeychain(userIdData, for: Constants.Keychain.userId)
        }

        SharedDefaults.shared.writeIsAuthenticated(true)
        SharedDefaults.shared.notifyHelper()
    }

    // MARK: - Private Helpers for Invitation

    private func generateMasterKey() throws -> Data {
        var masterKey = Data(count: Constants.Crypto.masterKeySize)
        let status = masterKey.withUnsafeMutableBytes { ptr -> OSStatus in
            guard let base = ptr.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, Constants.Crypto.masterKeySize, base)
        }
        guard status == errSecSuccess else {
            throw AuthError.registrationFailed
        }
        return masterKey
    }

    private func encryptWithKey(data: Data, key: SymmetricKey) throws -> Data {
        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(data, using: key, nonce: nonce)
        guard let combined = sealedBox.combined else {
            throw AuthError.registrationFailed
        }
        return combined
    }

    private func serializePrivateKeys(_ bundle: KeyManager.KeyBundle) throws -> Data {
        var data = Data()

        // Append each private key with length prefix (4 bytes)
        func appendKey(_ key: Data) {
            var length = UInt32(key.count).bigEndian
            data.append(Data(bytes: &length, count: 4))
            data.append(key)
        }

        appendKey(bundle.kazKemPrivateKey)
        appendKey(bundle.mlKemPrivateKey)
        appendKey(bundle.kazSignPrivateKey)
        appendKey(bundle.mlDsaPrivateKey)
        appendKey(bundle.deviceSigningKey.rawRepresentation)

        return data
    }
}

// MARK: - Errors

enum AuthError: Error, LocalizedError {
    case notAuthenticated
    case biometricFailed
    case keysNotUnlocked
    case signatureFailed
    case registrationFailed
    case invitationExpired
    case invitationInvalid
    case invalidURL
    case walletNotInstalled

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated"
        case .biometricFailed:
            return "Biometric authentication failed"
        case .keysNotUnlocked:
            return "Keys not unlocked"
        case .signatureFailed:
            return "Failed to create device signature"
        case .registrationFailed:
            return "Registration failed"
        case .invitationExpired:
            return "Invitation has expired"
        case .invitationInvalid:
            return "Invalid invitation"
        case .invalidURL:
            return "Invalid URL"
        case .walletNotInstalled:
            return "SSDID Wallet is not installed"
        }
    }
}
