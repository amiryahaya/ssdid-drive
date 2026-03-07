import Foundation
import LocalAuthentication
import CryptoKit
import Security

/// Implementation of AuthRepository
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

    func login(email: String, password: String) async throws -> User {
        // Generate device signature
        let deviceSignature = try await createDeviceSignature()

        let request = LoginRequest(
            email: email,
            password: password,
            deviceSignature: deviceSignature
        )

        let response: LoginResponse = try await apiClient.request(
            Constants.API.Endpoints.login,
            method: .post,
            body: request,
            requiresAuth: false
        )

        // Store tokens
        keychainManager.accessToken = response.tokens.accessToken
        keychainManager.refreshToken = response.tokens.refreshToken
        keychainManager.userId = response.user.id

        // Write tokens to shared keychain for File Provider extension
        if let tokenData = response.tokens.accessToken.data(using: .utf8) {
            try? keychainManager.saveToSharedKeychain(tokenData, for: Constants.Keychain.accessToken)
        }
        if let refreshData = response.tokens.refreshToken.data(using: .utf8) {
            try? keychainManager.saveToSharedKeychain(refreshData, for: Constants.Keychain.refreshToken)
        }
        if let userIdData = response.user.id.data(using: .utf8) {
            try? keychainManager.saveToSharedKeychain(userIdData, for: Constants.Keychain.userId)
        }

        // Unlock keys with password
        try await unlockKeys(password: password)

        // Sync KEM keys to shared keychain for File Provider decryption
        syncKemKeysToExtension()

        // Update shared defaults for menu bar helper (H2: use .shared directly to avoid MainActor hop)
        let shared = SharedDefaults.shared
        shared.writeIsAuthenticated(true)
        shared.writeUserDisplayName(Self.maskedEmail(response.user.email))
        shared.notifyHelper()

        // Register File Provider domain for Finder integration
        await MainActor.run {
            DependencyContainer.shared.fileProviderDomainManager.registerDomain()
        }

        // Best-effort KDF profile upgrade
        await upgradeKdfProfileIfNeeded(
            password: password,
            serverEncryptedMasterKey: response.user.encryptedMasterKey,
            serverSalt: response.user.keyDerivationSalt
        )

        return response.user
    }

    func register(email: String, password: String) async throws -> User {
        // Generate key bundle
        let keyBundle = try keyManager.generateKeyBundle()

        let request = RegisterRequest(
            email: email,
            password: password,
            publicKeys: keyBundle.publicKeys
        )

        let response: RegisterResponse = try await apiClient.request(
            Constants.API.Endpoints.register,
            method: .post,
            body: request,
            requiresAuth: false
        )

        // Store tokens
        keychainManager.accessToken = response.tokens.accessToken
        keychainManager.refreshToken = response.tokens.refreshToken
        keychainManager.userId = response.user.id
        keychainManager.deviceId = response.device.id

        // Write tokens to shared keychain for File Provider extension
        if let tokenData = response.tokens.accessToken.data(using: .utf8) {
            try? keychainManager.saveToSharedKeychain(tokenData, for: Constants.Keychain.accessToken)
        }
        if let refreshData = response.tokens.refreshToken.data(using: .utf8) {
            try? keychainManager.saveToSharedKeychain(refreshData, for: Constants.Keychain.refreshToken)
        }
        if let userIdData = response.user.id.data(using: .utf8) {
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

        return response.user
    }

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

    func enableBiometricUnlock(password: String) async throws {
        // First verify password by unlocking keys
        try await unlockKeys(password: password)

        // Keys are now stored with biometric protection
        // (storeKeys already stores master key for biometric)
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

    func unlockKeys(password: String) async throws {
        _ = try keyManager.loadKeys(password: password)
        syncKemKeysToExtension()
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

    // MARK: - Password

    func changePassword(currentPassword: String, newPassword: String) async throws {
        // Verify current password
        guard try await verifyPassword(currentPassword) else {
            throw AuthError.invalidPassword
        }

        // Re-encrypt keys with new password
        guard let keyBundle = keyManager.currentKeyBundle else {
            throw AuthError.keysNotUnlocked
        }

        try keyManager.storeKeys(keyBundle, password: newPassword)

        // Notify server
        let request = ChangePasswordRequest(
            currentPassword: currentPassword,
            newPassword: newPassword
        )

        try await apiClient.requestNoContent(
            "/auth/password",
            method: .put,
            body: request
        )
    }

    func verifyPassword(_ password: String) async throws -> Bool {
        do {
            _ = try keyManager.loadKeys(password: password)
            return true
        } catch {
            return false
        }
    }

    // MARK: - KDF Profile Upgrade

    /// Silently upgrade the KDF profile if the device supports a stronger one.
    /// Re-encrypts the server's master key with a stronger password-derived key,
    /// updates the server, and re-encrypts the local key bundle.
    /// Best-effort: failures are logged and do not affect the login flow.
    private func upgradeKdfProfileIfNeeded(
        password: String,
        serverEncryptedMasterKey: String?,
        serverSalt: String?
    ) async {
        do {
            guard let saltB64 = serverSalt,
                  let encMasterKeyB64 = serverEncryptedMasterKey,
                  let currentSalt = Data(base64Encoded: saltB64),
                  let encryptedMasterKey = Data(base64Encoded: encMasterKeyB64)
            else { return }

            let deviceProfile = KdfProfile.selectForDevice()

            let needsUpgrade: Bool
            if KdfProfile.isTieredSalt(currentSalt) {
                let currentProfile = try KdfProfile.fromByte(currentSalt[currentSalt.startIndex])
                needsUpgrade = currentProfile.rawValue > deviceProfile.rawValue
            } else {
                needsUpgrade = true // Legacy salt always needs upgrade
            }

            guard needsUpgrade else { return }

            // Derive old key from password + old salt
            let oldKey = try TieredKdf.deriveKey(password: password, saltWithProfile: currentSalt)

            // Decrypt server's master key
            let sealedBox = try AES.GCM.SealedBox(combined: encryptedMasterKey)
            var rawMasterKey = try AES.GCM.open(sealedBox, using: oldKey)
            defer { rawMasterKey.secureZero() }

            // Generate new salt + derive new key with stronger profile
            let newSalt = KdfProfile.createSaltWithProfile(deviceProfile)
            let newKey = try TieredKdf.deriveKey(password: password, saltWithProfile: newSalt)

            // Re-encrypt master key with the stronger key
            guard let newEncryptedMasterKey = try AES.GCM.seal(rawMasterKey, using: newKey).combined else {
                return
            }

            // Update server via PUT /me/keys
            struct UpdateKeysRequest: Encodable {
                let encrypted_master_key: String
                let key_derivation_salt: String
            }
            let request = UpdateKeysRequest(
                encrypted_master_key: newEncryptedMasterKey.base64EncodedString(),
                key_derivation_salt: newSalt.base64EncodedString()
            )
            try await apiClient.requestNoContent("/me/keys", method: .put, body: request)

            // Re-encrypt local key bundle with new profile
            if let bundle = keyManager.currentKeyBundle {
                try keyManager.storeKeys(bundle, password: password)
            }

            print("[KdfUpgrade] Upgraded KDF profile to \(deviceProfile)")
        } catch {
            print("[KdfUpgrade] KDF profile upgrade failed (non-fatal): \(error)")
        }
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
            print("[KemSync] Failed to sync KEM keys to shared keychain: \(error)")
        }
    }

    // MARK: - Private Helpers

    /// Mask an email address to prevent full PII leakage in shared storage.
    /// "user@example.com" → "u***@e***.com"
    static func maskedEmail(_ email: String) -> String {
        let parts = email.split(separator: "@", maxSplits: 1)
        guard parts.count == 2 else { return "***" }
        let local = parts[0]
        let domain = parts[1]
        let maskedLocal = local.prefix(1) + "***"
        let domainParts = domain.split(separator: ".", maxSplits: 1)
        let maskedDomain: String
        if domainParts.count == 2 {
            maskedDomain = domainParts[0].prefix(1) + "***." + domainParts[1]
        } else {
            maskedDomain = String(domain.prefix(1)) + "***"
        }
        return "\(maskedLocal)@\(maskedDomain)"
    }

    private func createDeviceSignature() async throws -> String {
        // For initial login, we may not have device keys yet
        // Return empty string for first-time auth
        guard let keyBundle = keyManager.currentKeyBundle else {
            return ""
        }

        let timestamp = ISO8601DateFormatter().string(from: Date())
        guard let data = timestamp.data(using: .utf8) else {
            throw AuthError.signatureFailed
        }

        let signature = try keyBundle.deviceSigningKey.signature(for: data)
        return signature.rawRepresentation.base64EncodedString()
    }
}

// MARK: - Request Types

private struct LoginRequest: Codable {
    let email: String
    let password: String
    let deviceSignature: String

    enum CodingKeys: String, CodingKey {
        case email
        case password
        case deviceSignature = "device_signature"
    }
}

private struct RegisterRequest: Codable {
    let email: String
    let password: String
    let publicKeys: KeyManager.PublicKeys

    enum CodingKeys: String, CodingKey {
        case email
        case password
        case publicKeys = "public_keys"
    }
}

private struct RefreshRequest: Codable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

private struct ChangePasswordRequest: Codable {
    let currentPassword: String
    let newPassword: String

    enum CodingKeys: String, CodingKey {
        case currentPassword = "current_password"
        case newPassword = "new_password"
    }
}

// MARK: - Invitation Token Implementation

extension AuthRepositoryImpl {

    func getInvitationInfo(token: String) async throws -> TokenInvitation {
        let endpoint = Constants.API.Endpoints.inviteInfo.replacingOccurrences(of: "{token}", with: token)

        let response: InviteInfoResponse = try await apiClient.request(
            endpoint,
            method: .get,
            requiresAuth: false
        )

        return response.data
    }

    func acceptInvitation(token: String, displayName: String, password: String) async throws -> InviteUser {
        // Generate key bundle
        let keyBundle = try keyManager.generateKeyBundle()

        // Generate salt with tiered KDF profile
        let salt = TieredKdf.createSaltWithProfile(KdfProfile.selectForDevice())

        // Derive password key using tiered KDF
        let passwordKey = try TieredKdf.deriveKey(password: password, saltWithProfile: salt)

        // Encrypt master key with password-derived key
        let masterKey = generateMasterKey()
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

    // MARK: - Private Helpers for Invitation

    private func generateMasterKey() -> Data {
        var masterKey = Data(count: Constants.Crypto.masterKeySize)
        _ = masterKey.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, Constants.Crypto.masterKeySize, $0.baseAddress!) }
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
    case invalidCredentials
    case invalidPassword
    case biometricFailed
    case keysNotUnlocked
    case signatureFailed
    case registrationFailed
    case invitationExpired
    case invitationInvalid

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated"
        case .invalidCredentials:
            return "Invalid email or password"
        case .invalidPassword:
            return "Invalid password"
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
        }
    }
}
