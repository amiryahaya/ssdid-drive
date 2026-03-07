import Foundation

/// Tiered KDF profile for password-based key derivation.
///
/// Wire format: `[profile_byte] || [salt_bytes (16 bytes)]`
/// Profile is selected based on device RAM to balance security and usability.
enum KdfProfile: UInt8 {
    /// argon2id-standard: 64 MiB, t=3, p=4 — Desktop and modern mobile (4+ GB RAM)
    case argon2idStandard = 0x01
    /// argon2id-low: 19 MiB, t=4, p=4 — Older mobile (2-4 GB RAM)
    case argon2idLow      = 0x02
    /// bcrypt-hkdf: bcrypt cost=13 + HKDF-SHA-384 — Extremely constrained (< 2 GB RAM)
    case bcryptHkdf       = 0x03

    /// Salt size (random bytes, excluding profile byte)
    static let saltSize = 16

    /// Total wire salt size: 1 profile byte + 16 salt bytes
    static let wireSaltSize = 17

    /// Select optimal KDF profile based on device available RAM
    static func selectForDevice() -> KdfProfile {
        let totalRAM = ProcessInfo.processInfo.physicalMemory
        let totalGB = Double(totalRAM) / (1_024.0 * 1_024.0 * 1_024.0)

        switch totalGB {
        case 4.0...:
            return .argon2idStandard
        case 2.0..<4.0:
            return .argon2idLow
        default:
            return .bcryptHkdf
        }
    }

    /// Parse profile from wire byte
    static func fromByte(_ byte: UInt8) throws -> KdfProfile {
        guard let profile = KdfProfile(rawValue: byte) else {
            throw TieredKdfError.unknownProfile(byte)
        }
        return profile
    }

    /// Check if a salt uses the tiered format (17 bytes with valid profile byte)
    static func isTieredSalt(_ salt: Data) -> Bool {
        guard salt.count == wireSaltSize else { return false }
        return (0x01...0x03).contains(salt[salt.startIndex])
    }

    /// Create a salt with profile byte prepended: [profile_byte] || [16 random bytes]
    static func createSaltWithProfile(_ profile: KdfProfile) -> Data {
        var salt = Data(count: wireSaltSize)
        salt[0] = profile.rawValue
        _ = salt.withUnsafeMutableBytes { ptr in
            SecRandomCopyBytes(kSecRandomDefault, saltSize, ptr.baseAddress!.advanced(by: 1))
        }
        return salt
    }
}
