import Foundation
import CryptoKit
import CommonCrypto
import Argon2Swift

/// Errors for tiered KDF operations
enum TieredKdfError: Error, LocalizedError {
    case unknownProfile(UInt8)
    case invalidSalt
    case derivationFailed(String)

    var errorDescription: String? {
        switch self {
        case .unknownProfile(let byte):
            return "Unknown KDF profile byte: 0x\(String(byte, radix: 16))"
        case .invalidSalt:
            return "Invalid salt format"
        case .derivationFailed(let reason):
            return "KDF derivation failed: \(reason)"
        }
    }
}

/// Tiered Key Derivation Function supporting multiple profiles.
///
/// Profiles are selected based on device capabilities and encoded
/// in the wire salt format: `[profile_byte] || [16 salt bytes]`
enum TieredKdf {

    // MARK: - Argon2id Parameters

    private static let outputLength = 32

    // MARK: - Bcrypt-HKDF Parameters

    private static let bcryptCost: UInt32 = 13
    private static let bcryptHkdfSalt = Data("SsdidDrive-Bcrypt-KDF-v1".utf8)
    private static let bcryptHkdfInfo = Data("bcrypt-derived-key".utf8)

    // MARK: - Public API

    /// Derive a key using the tiered KDF system.
    ///
    /// Parses the profile byte from the first byte of `saltWithProfile`,
    /// then dispatches to the correct KDF.
    ///
    /// For backward compatibility: if the salt is not 17 bytes or the first
    /// byte is not a valid profile, falls back to legacy PBKDF2.
    static func deriveKey(password: String, saltWithProfile: Data) throws -> SymmetricKey {
        guard let passwordData = password.data(using: .utf8) else {
            throw TieredKdfError.derivationFailed("Invalid password encoding")
        }

        if KdfProfile.isTieredSalt(saltWithProfile) {
            let profile = try KdfProfile.fromByte(saltWithProfile[saltWithProfile.startIndex])
            let salt = saltWithProfile.subdata(in: 1..<KdfProfile.wireSaltSize)

            switch profile {
            case .argon2idStandard:
                return try deriveArgon2id(
                    password: passwordData, salt: salt,
                    memory: 65536, iterations: 3, parallelism: 4
                )
            case .argon2idLow:
                return try deriveArgon2id(
                    password: passwordData, salt: salt,
                    memory: 19456, iterations: 4, parallelism: 4
                )
            case .bcryptHkdf:
                return try deriveBcryptHkdf(password: passwordData, salt: salt)
            }
        }

        // Legacy fallback: PBKDF2-SHA256 with 100K iterations
        return try legacyPbkdf2(password: passwordData, salt: saltWithProfile)
    }

    /// Create a new salt with profile byte for key derivation.
    static func createSaltWithProfile(_ profile: KdfProfile) -> Data {
        KdfProfile.createSaltWithProfile(profile)
    }

    // MARK: - Argon2id Implementation (via Argon2Swift)

    private static func deriveArgon2id(
        password: Data,
        salt: Data,
        memory: Int,
        iterations: Int,
        parallelism: Int
    ) throws -> SymmetricKey {
        let s = Salt(bytes: salt)
        let result = try Argon2Swift.hashPasswordBytes(
            password: password,
            salt: s,
            iterations: iterations,
            memory: memory,
            parallelism: parallelism,
            length: outputLength,
            type: .id
        )

        let hashData = result.hashData()

        return SymmetricKey(data: hashData)
    }

    // MARK: - Bcrypt-HKDF Implementation

    /// Bcrypt cost=13 + HKDF-SHA-384 stretch to 32 bytes.
    ///
    /// 1. Bcrypt hash (cost=13) → 24-byte output
    /// 2. HKDF-SHA-384 stretch to 32 bytes
    private static func deriveBcryptHkdf(password: Data, salt: Data) throws -> SymmetricKey {
        guard salt.count == KdfProfile.saltSize else {
            throw TieredKdfError.invalidSalt
        }

        // Step 1: Bcrypt hash → 24 bytes
        let bcryptOutput = try BcryptKdf.hash(
            password: Array(password),
            salt: Array(salt),
            cost: bcryptCost
        )

        // Step 2: HKDF-SHA-384 stretch to 32 bytes using CryptoKit
        let derivedKey = HKDF<SHA384>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: bcryptOutput),
            salt: bcryptHkdfSalt,
            info: bcryptHkdfInfo,
            outputByteCount: outputLength
        )

        return derivedKey
    }

    // MARK: - Legacy PBKDF2 Fallback

    /// Legacy PBKDF2-SHA256 with 100K iterations (for salts without profile byte)
    private static func legacyPbkdf2(password: Data, salt: Data) throws -> SymmetricKey {
        var derivedKey = Data(count: Constants.Crypto.masterKeySize)

        let result = derivedKey.withUnsafeMutableBytes { derivedKeyPtr in
            salt.withUnsafeBytes { saltPtr in
                password.withUnsafeBytes { passwordPtr in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordPtr.baseAddress?.assumingMemoryBound(to: Int8.self),
                        password.count,
                        saltPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(Constants.Crypto.pbkdf2Iterations),
                        derivedKeyPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        Constants.Crypto.masterKeySize
                    )
                }
            }
        }

        guard result == kCCSuccess else {
            throw TieredKdfError.derivationFailed("PBKDF2 failed with status \(result)")
        }

        return SymmetricKey(data: derivedKey)
    }
}
