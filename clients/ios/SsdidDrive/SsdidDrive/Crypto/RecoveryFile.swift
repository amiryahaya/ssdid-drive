import Foundation
import CryptoKit

/// A serialized Shamir share stored as a recovery file.
struct RecoveryFile: Codable {
    let version: Int
    let scheme: String
    let threshold: Int
    let shareIndex: Int
    let shareData: String
    let checksum: String
    let userDid: String
    let kemPublicKey: String?   // base64-encoded KEM public key (for recovery completion)
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case version, scheme, threshold, checksum
        case shareIndex = "share_index"
        case shareData = "share_data"
        case userDid = "user_did"
        case kemPublicKey = "kem_public_key"
        case createdAt = "created_at"
    }

    /// Validate the file and return the raw share bytes on success.
    func validate() throws -> Data {
        guard version == 1 else {
            throw RecoveryError.unsupportedVersion
        }

        guard let rawBytes = Data(base64Encoded: shareData) else {
            throw RecoveryError.invalidShareData
        }

        let hash = SHA256.hash(data: rawBytes)
        let expectedChecksum = hash.map { String(format: "%02x", $0) }.joined()

        guard checksum == expectedChecksum else {
            throw RecoveryError.corruptedFile
        }

        return rawBytes
    }

    /// Create a recovery file from a Shamir share.
    ///
    /// The `share_data` field stores only the y-bytes (not the index prefix),
    /// matching the Desktop and Android implementations for cross-platform compatibility.
    static func create(share: ShamirSecretSharing.Share, userDid: String, kemPublicKey: Data? = nil) -> RecoveryFile {
        let hash = SHA256.hash(data: share.data)
        let checksum = hash.map { String(format: "%02x", $0) }.joined()

        return RecoveryFile(
            version: 1,
            scheme: "shamir-gf256",
            threshold: 2,
            shareIndex: Int(share.index),
            shareData: share.data.base64EncodedString(),
            checksum: checksum,
            userDid: userDid,
            kemPublicKey: kemPublicKey?.base64EncodedString(),
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    /// Deserialize and validate, returning the underlying share.
    ///
    /// Since `shareData` stores only the y-bytes (not the index prefix),
    /// we reconstruct the Share from `shareIndex` + validated raw bytes.
    func toShare() throws -> ShamirSecretSharing.Share {
        let raw = try validate()
        guard shareIndex > 0, shareIndex <= 255 else {
            throw RecoveryError.invalidShareData
        }
        return ShamirSecretSharing.Share(index: UInt8(shareIndex), data: raw)
    }
}

// MARK: - Errors

enum RecoveryError: LocalizedError {
    case unsupportedVersion
    case invalidShareData
    case corruptedFile
    case sameShare
    case differentAccounts
    case reconstructionFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion:
            return "This recovery file requires a newer version of SSDID Drive"
        case .invalidShareData:
            return "Invalid share data in recovery file"
        case .corruptedFile:
            return "Recovery file is damaged (checksum mismatch)"
        case .sameShare:
            return "Both files contain the same share"
        case .differentAccounts:
            return "Recovery files belong to different accounts"
        case .reconstructionFailed:
            return "Failed to reconstruct encryption key"
        }
    }
}
