import Foundation
import CryptoKit
import Combine

/// Delegate for OIDC register view model coordinator events
protocol OidcRegisterViewModelCoordinatorDelegate: AnyObject {
    func oidcRegisterViewModelDidComplete()
}

/// View model for OIDC registration screen.
/// Generates a key bundle and encrypts it with the vault key derived from OIDC key material.
final class OidcRegisterViewModel: BaseViewModel {

    // MARK: - Properties

    private let oidcRepository: OidcRepository
    private let keyManager: KeyManager
    private let keyMaterial: String
    private let keySalt: String
    weak var coordinatorDelegate: OidcRegisterViewModelCoordinatorDelegate?

    // MARK: - Initialization

    init(
        oidcRepository: OidcRepository,
        keyManager: KeyManager,
        keyMaterial: String,
        keySalt: String
    ) {
        self.oidcRepository = oidcRepository
        self.keyManager = keyManager
        self.keyMaterial = keyMaterial
        self.keySalt = keySalt
        super.init()
    }

    // MARK: - Actions

    /// Complete OIDC registration by generating keys and encrypting with vault key
    func completeRegistration(password: String) {
        isLoading = true
        clearError()

        Task {
            do {
                // Generate PQC key bundle
                let keyBundle = try keyManager.generateKeyBundle()

                // Generate master key (random 32 bytes)
                var masterKey = SymmetricKey(size: .bits256)

                // Encrypt master key with password (for local backup)
                let (encSalt, encKey) = try deriveEncryptionKey(password: password)
                let encryptedMasterKey = try encryptMasterKey(masterKey, with: encKey)

                // Derive vault key from OIDC key material
                guard let keyMaterialData = Data(base64Encoded: keyMaterial),
                      let keySaltData = Data(base64Encoded: keySalt) else {
                    throw AuthError.registrationFailed
                }

                let vaultKey = HKDF<SHA384>.deriveKey(
                    inputKeyMaterial: SymmetricKey(data: keyMaterialData),
                    salt: keySaltData,
                    info: Data("securesharing-vault-key".utf8),
                    outputByteCount: 32
                )

                // Encrypt master key with vault key
                let vaultNonce = AES.GCM.Nonce()
                let masterKeyData = masterKey.withUnsafeBytes { Data($0) }
                let vaultSealedBox = try AES.GCM.seal(masterKeyData, using: vaultKey, nonce: vaultNonce)
                guard let vaultCombined = vaultSealedBox.combined else {
                    throw AuthError.registrationFailed
                }
                let vaultEncryptedMasterKey = vaultCombined.base64EncodedString()
                let vaultMkNonce = Data(vaultNonce).base64EncodedString()

                // Encrypt private keys with master key
                let encryptedPrivateKeys = try encryptPrivateKeys(keyBundle, masterKey: masterKey)

                // Build public keys map
                let publicKeys: [String: String] = [
                    "kaz_kem": keyBundle.kazKemPublicKey.base64EncodedString(),
                    "ml_kem": keyBundle.mlKemPublicKey.base64EncodedString(),
                    "kaz_sign": keyBundle.kazSignPublicKey.base64EncodedString(),
                    "ml_dsa": keyBundle.mlDsaPublicKey.base64EncodedString()
                ]

                // Call API to complete registration
                let user = try await oidcRepository.completeRegistration(
                    keyMaterial: keyMaterial,
                    keySalt: keySalt,
                    encryptedMasterKey: encryptedMasterKey,
                    vaultEncryptedMasterKey: vaultEncryptedMasterKey,
                    vaultMkNonce: vaultMkNonce,
                    encryptedPrivateKeys: encryptedPrivateKeys,
                    publicKeys: publicKeys
                )

                // Store keys locally
                try keyManager.storeKeys(keyBundle, password: password)

                await MainActor.run {
                    isLoading = false
                    coordinatorDelegate?.oidcRegisterViewModelDidComplete()
                }
            } catch {
                await MainActor.run {
                    handleError(error)
                }
            }
        }
    }

    // MARK: - Private Helpers

    private func deriveEncryptionKey(password: String) throws -> (String, SymmetricKey) {
        let salt = TieredKdf.createSaltWithProfile(KdfProfile.selectForDevice())
        let key = try TieredKdf.deriveKey(password: password, saltWithProfile: salt)
        return (salt.base64EncodedString(), key)
    }

    private func encryptMasterKey(_ masterKey: SymmetricKey, with encKey: SymmetricKey) throws -> String {
        let masterKeyData = masterKey.withUnsafeBytes { Data($0) }
        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(masterKeyData, using: encKey, nonce: nonce)
        guard let combined = sealedBox.combined else {
            throw AuthError.registrationFailed
        }
        return combined.base64EncodedString()
    }

    private func encryptPrivateKeys(_ bundle: KeyBundle, masterKey: SymmetricKey) throws -> String {
        let keys: [String: Data] = [
            "kaz_kem": bundle.kazKemPrivateKey,
            "ml_kem": bundle.mlKemPrivateKey,
            "kaz_sign": bundle.kazSignPrivateKey,
            "ml_dsa": bundle.mlDsaPrivateKey
        ]

        var encrypted: [String: String] = [:]
        for (name, keyData) in keys {
            let nonce = AES.GCM.Nonce()
            let sealedBox = try AES.GCM.seal(keyData, using: masterKey, nonce: nonce)
            guard let combined = sealedBox.combined else {
                throw AuthError.registrationFailed
            }
            encrypted[name] = combined.base64EncodedString()
        }

        let jsonData = try JSONSerialization.data(withJSONObject: encrypted)
        return String(data: jsonData, encoding: .utf8) ?? "{}"
    }
}
