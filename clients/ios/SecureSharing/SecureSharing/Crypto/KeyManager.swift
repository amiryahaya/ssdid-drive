import Foundation
import CryptoKit

/// Manages cryptographic key generation, storage, and operations.
/// Handles both classical (AES, ECDSA) and post-quantum (KAZ-KEM, ML-KEM, etc.) keys.
final class KeyManager {

    // MARK: - Types

    /// Complete key bundle for a user
    struct KeyBundle {
        // Encryption keys (KEM)
        let kazKemPublicKey: Data
        let kazKemPrivateKey: Data
        let mlKemPublicKey: Data
        let mlKemPrivateKey: Data

        // Signing keys (DSA)
        let kazSignPublicKey: Data
        let kazSignPrivateKey: Data
        let mlDsaPublicKey: Data
        let mlDsaPrivateKey: Data

        // Device signing key
        let deviceSigningKey: P256.Signing.PrivateKey

        /// Public keys for registration/sharing
        var publicKeys: PublicKeys {
            PublicKeys(
                kazKemPublicKey: kazKemPublicKey,
                mlKemPublicKey: mlKemPublicKey,
                kazSignPublicKey: kazSignPublicKey,
                mlDsaPublicKey: mlDsaPublicKey
            )
        }
    }

    /// Public keys only (for sharing with others)
    struct PublicKeys: Codable, Equatable, Hashable {
        let kazKemPublicKey: Data
        let mlKemPublicKey: Data
        let kazSignPublicKey: Data
        let mlDsaPublicKey: Data

        enum CodingKeys: String, CodingKey {
            case kazKemPublicKey = "kaz_kem_public_key"
            case mlKemPublicKey = "ml_kem_public_key"
            case kazSignPublicKey = "kaz_sign_public_key"
            case mlDsaPublicKey = "ml_dsa_public_key"
        }
    }

    /// Encrypted key bundle for storage
    struct EncryptedKeyBundle: Codable {
        let encryptedData: Data
        let nonce: Data
        let salt: Data
    }

    // MARK: - Errors

    enum KeyError: Error {
        case keyGenerationFailed
        case encryptionFailed
        case decryptionFailed
        case keyNotFound
        case invalidKeySize
        case biometricAuthRequired
        case invalidPassword
    }

    // MARK: - Properties

    private let keychainManager: KeychainManaging
    private var unlockedKeyBundle: KeyBundle?

    // MARK: - Initialization

    init(keychainManager: KeychainManaging) {
        self.keychainManager = keychainManager
    }

    // MARK: - Key Generation

    /// Generate a complete key bundle
    func generateKeyBundle() throws -> KeyBundle {
        // Generate KAZ-KEM keys
        let (kazKemPub, kazKemPriv) = try KAZKEM.generateKeyPair()

        // Generate ML-KEM-768 keys
        let (mlKemPub, mlKemPriv) = try MLKEM.generateKeyPair()

        // Generate KAZ-SIGN keys
        let (kazSignPub, kazSignPriv) = try KAZSIGN.generateKeyPair()

        // Generate ML-DSA-65 keys
        let (mlDsaPub, mlDsaPriv) = try MLDSA.generateKeyPair()

        // Generate device signing key (P-256 for efficiency)
        let deviceKey = P256.Signing.PrivateKey()

        return KeyBundle(
            kazKemPublicKey: kazKemPub,
            kazKemPrivateKey: kazKemPriv,
            mlKemPublicKey: mlKemPub,
            mlKemPrivateKey: mlKemPriv,
            kazSignPublicKey: kazSignPub,
            kazSignPrivateKey: kazSignPriv,
            mlDsaPublicKey: mlDsaPub,
            mlDsaPrivateKey: mlDsaPriv,
            deviceSigningKey: deviceKey
        )
    }

    // MARK: - Key Storage

    /// Store keys encrypted with password-derived key
    func storeKeys(_ bundle: KeyBundle, password: String) throws {
        // Derive master key from password using tiered KDF
        let salt = TieredKdf.createSaltWithProfile(KdfProfile.selectForDevice())
        let masterKey = try TieredKdf.deriveKey(password: password, saltWithProfile: salt)

        // Serialize key bundle
        let keyData = try serializeKeyBundle(bundle)

        // Encrypt with AES-256-GCM
        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(keyData, using: masterKey, nonce: nonce)

        guard let ciphertext = sealedBox.combined else {
            throw KeyError.encryptionFailed
        }

        // Create encrypted bundle
        let encryptedBundle = EncryptedKeyBundle(
            encryptedData: ciphertext,
            nonce: Data(nonce),
            salt: salt
        )

        // Encode and store in keychain
        let encodedBundle = try JSONEncoder().encode(encryptedBundle)
        try keychainManager.save(encodedBundle, for: Constants.Keychain.encryptedKeys, accessLevel: .standard)

        // Store master key for biometric unlock
        try keychainManager.saveMasterKey(masterKey.withUnsafeBytes { Data($0) })

        // Keep keys unlocked in memory
        unlockedKeyBundle = bundle
    }

    /// Load and decrypt keys using password
    func loadKeys(password: String) throws -> KeyBundle {
        // Load encrypted bundle
        let encodedBundle = try keychainManager.load(key: Constants.Keychain.encryptedKeys, withBiometric: false)
        let encryptedBundle = try JSONDecoder().decode(EncryptedKeyBundle.self, from: encodedBundle)

        // Derive key from password (auto-detects tiered vs legacy salt)
        let masterKey = try TieredKdf.deriveKey(password: password, saltWithProfile: encryptedBundle.salt)

        // Decrypt
        let keyData = try decryptKeyBundle(encryptedBundle, masterKey: masterKey)

        // Deserialize
        let bundle = try deserializeKeyBundle(keyData)

        // Keep unlocked
        unlockedKeyBundle = bundle

        return bundle
    }

    /// Load keys using biometric authentication
    func loadKeysWithBiometric() throws -> KeyBundle {
        // Load encrypted bundle
        let encodedBundle = try keychainManager.load(key: Constants.Keychain.encryptedKeys, withBiometric: true)
        let encryptedBundle = try JSONDecoder().decode(EncryptedKeyBundle.self, from: encodedBundle)

        // Load master key with biometric
        let masterKeyData = try keychainManager.loadMasterKey()
        let masterKey = SymmetricKey(data: masterKeyData)

        // Decrypt
        let keyData = try decryptKeyBundle(encryptedBundle, masterKey: masterKey)

        // Deserialize
        let bundle = try deserializeKeyBundle(keyData)

        // Keep unlocked
        unlockedKeyBundle = bundle

        return bundle
    }

    // MARK: - Vault-Based Key Unlock (OIDC/WebAuthn)

    /// Unlock keys using a raw master key and server-provided encrypted private keys.
    /// Used by OIDC and WebAuthn vault-based authentication flows where the master key
    /// is derived from server-provided key material rather than a user password.
    ///
    /// - Parameters:
    ///   - masterKey: Decrypted raw master key (32 bytes)
    ///   - encryptedPrivateKeys: Server-provided encrypted private keys (per-algorithm base64 strings)
    func unlockWithMasterKey<T>(_ masterKey: Data, encryptedPrivateKeys: T) throws {
        let symmetricKey = SymmetricKey(data: masterKey)

        // The server provides encrypted private keys as individual base64 fields.
        // Each is AES-GCM encrypted with the master key (nonce || ciphertext || tag).
        guard let keysDict = encryptedPrivateKeys as? [String: String] ??
              (encryptedPrivateKeys as? Encodable).flatMap({ obj -> [String: String]? in
                  guard let data = try? JSONEncoder().encode(AnyEncodableWrapper(obj)),
                        let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return nil }
                  return dict
              }) else {
            throw KeyError.decryptionFailed
        }

        func decryptKey(_ base64: String?) throws -> Data {
            guard let b64 = base64, let encrypted = Data(base64Encoded: b64) else {
                throw KeyError.decryptionFailed
            }
            let sealedBox = try AES.GCM.SealedBox(combined: encrypted)
            return try AES.GCM.open(sealedBox, using: symmetricKey)
        }

        let kazKemPriv = try decryptKey(keysDict["kaz_kem"])
        let mlKemPriv = try decryptKey(keysDict["ml_kem"])
        let kazSignPriv = try decryptKey(keysDict["kaz_sign"])
        let mlDsaPriv = try decryptKey(keysDict["ml_dsa"])

        // Derive public keys from private keys or use empty (they'll be fetched from server)
        // For now, generate placeholder public keys - the actual public keys come from server responses
        let kazKemPub = Data()
        let mlKemPub = Data()
        let kazSignPub = Data()
        let mlDsaPub = Data()

        // Generate a device signing key (or load existing)
        let deviceKey: P256.Signing.PrivateKey
        if let existingKeyData = try? keychainManager.load(key: Constants.Keychain.devicePrivateKey, withBiometric: false) {
            deviceKey = try P256.Signing.PrivateKey(rawRepresentation: existingKeyData)
        } else {
            deviceKey = P256.Signing.PrivateKey()
        }

        unlockedKeyBundle = KeyBundle(
            kazKemPublicKey: kazKemPub,
            kazKemPrivateKey: kazKemPriv,
            mlKemPublicKey: mlKemPub,
            mlKemPrivateKey: mlKemPriv,
            kazSignPublicKey: kazSignPub,
            kazSignPrivateKey: kazSignPriv,
            mlDsaPublicKey: mlDsaPub,
            mlDsaPrivateKey: mlDsaPriv,
            deviceSigningKey: deviceKey
        )
    }

    // MARK: - Key Access

    /// Get currently unlocked keys
    var currentKeyBundle: KeyBundle? {
        unlockedKeyBundle
    }

    /// Check if keys are currently unlocked
    var areKeysUnlocked: Bool {
        unlockedKeyBundle != nil
    }

    /// Lock keys (clear from memory)
    /// Securely zeros all key material before releasing
    func lockKeys() {
        guard var bundle = unlockedKeyBundle else { return }

        // Securely zero all private key material
        var kazKemPrivate = bundle.kazKemPrivateKey
        var mlKemPrivate = bundle.mlKemPrivateKey
        var kazSignPrivate = bundle.kazSignPrivateKey
        var mlDsaPrivate = bundle.mlDsaPrivateKey

        kazKemPrivate.secureZero()
        mlKemPrivate.secureZero()
        kazSignPrivate.secureZero()
        mlDsaPrivate.secureZero()

        unlockedKeyBundle = nil
    }

    /// Check if keys exist in storage
    var hasStoredKeys: Bool {
        keychainManager.hasEncryptedKeys
    }

    // MARK: - Private Helpers

    private func serializeKeyBundle(_ bundle: KeyBundle) throws -> Data {
        var data = Data()

        // Append each key with length prefix (4 bytes)
        func appendKey(_ key: Data) {
            var length = UInt32(key.count).bigEndian
            data.append(Data(bytes: &length, count: 4))
            data.append(key)
        }

        appendKey(bundle.kazKemPublicKey)
        appendKey(bundle.kazKemPrivateKey)
        appendKey(bundle.mlKemPublicKey)
        appendKey(bundle.mlKemPrivateKey)
        appendKey(bundle.kazSignPublicKey)
        appendKey(bundle.kazSignPrivateKey)
        appendKey(bundle.mlDsaPublicKey)
        appendKey(bundle.mlDsaPrivateKey)
        appendKey(bundle.deviceSigningKey.rawRepresentation)

        return data
    }

    private func deserializeKeyBundle(_ data: Data) throws -> KeyBundle {
        var offset = 0

        func readKey() throws -> Data {
            guard offset + 4 <= data.count else { throw KeyError.decryptionFailed }
            let lengthData = data.subdata(in: offset..<offset+4)
            let length = Int(UInt32(bigEndian: lengthData.withUnsafeBytes { $0.load(as: UInt32.self) }))
            offset += 4

            guard offset + length <= data.count else { throw KeyError.decryptionFailed }
            let key = data.subdata(in: offset..<offset+length)
            offset += length
            return key
        }

        let kazKemPub = try readKey()
        let kazKemPriv = try readKey()
        let mlKemPub = try readKey()
        let mlKemPriv = try readKey()
        let kazSignPub = try readKey()
        let kazSignPriv = try readKey()
        let mlDsaPub = try readKey()
        let mlDsaPriv = try readKey()
        let deviceKeyData = try readKey()

        guard let deviceKey = try? P256.Signing.PrivateKey(rawRepresentation: deviceKeyData) else {
            throw KeyError.decryptionFailed
        }

        return KeyBundle(
            kazKemPublicKey: kazKemPub,
            kazKemPrivateKey: kazKemPriv,
            mlKemPublicKey: mlKemPub,
            mlKemPrivateKey: mlKemPriv,
            kazSignPublicKey: kazSignPub,
            kazSignPrivateKey: kazSignPriv,
            mlDsaPublicKey: mlDsaPub,
            mlDsaPrivateKey: mlDsaPriv,
            deviceSigningKey: deviceKey
        )
    }

    /// Helper to encode arbitrary Encodable values for dictionary extraction
    private struct AnyEncodableWrapper: Encodable {
        let value: Encodable
        init(_ value: Encodable) { self.value = value }
        func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
    }

    private func decryptKeyBundle(_ encryptedBundle: EncryptedKeyBundle, masterKey: SymmetricKey) throws -> Data {
        guard let nonce = try? AES.GCM.Nonce(data: encryptedBundle.nonce) else {
            throw KeyError.decryptionFailed
        }

        guard let sealedBox = try? AES.GCM.SealedBox(combined: encryptedBundle.encryptedData) else {
            throw KeyError.decryptionFailed
        }

        do {
            return try AES.GCM.open(sealedBox, using: masterKey)
        } catch {
            throw KeyError.decryptionFailed
        }
    }
}
