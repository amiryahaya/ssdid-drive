import Foundation

/// Recovery configuration for a user
struct RecoveryConfig: Codable, Equatable {
    let isConfigured: Bool
    let threshold: Int
    let totalShares: Int
    let trustees: [Trustee]
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case isConfigured = "is_configured"
        case threshold
        case totalShares = "total_shares"
        case trustees
        case createdAt = "created_at"
    }

    /// Empty/not configured state
    static let notConfigured = RecoveryConfig(
        isConfigured: false,
        threshold: 0,
        totalShares: 0,
        trustees: [],
        createdAt: nil
    )
}

/// A trustee who holds a recovery share
struct Trustee: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let userId: String
    let email: String
    let displayName: String?
    let hasAccepted: Bool
    let acceptedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case email
        case displayName = "display_name"
        case hasAccepted = "has_accepted"
        case acceptedAt = "accepted_at"
    }
}

/// A recovery share (Shamir secret sharing)
struct RecoveryShare: Codable, Identifiable, Equatable {
    let id: String
    let trusteeId: String
    let encryptedShare: Data
    let shareIndex: Int
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case trusteeId = "trustee_id"
        case encryptedShare = "encrypted_share"
        case shareIndex = "share_index"
        case createdAt = "created_at"
    }
}

/// A pending recovery request
struct RecoveryRequest: Codable, Identifiable, Equatable {
    let id: String
    let requesterId: String
    let requesterEmail: String
    let requesterName: String?
    let status: Status
    let approvedShares: Int
    let requiredShares: Int
    let expiresAt: Date
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case requesterId = "requester_id"
        case requesterEmail = "requester_email"
        case requesterName = "requester_name"
        case status
        case approvedShares = "approved_shares"
        case requiredShares = "required_shares"
        case expiresAt = "expires_at"
        case createdAt = "created_at"
    }

    enum Status: String, Codable {
        case pending
        case approved
        case rejected
        case expired
        case completed

        var displayName: String {
            rawValue.capitalized
        }
    }

    /// Progress towards threshold
    var progress: Double {
        guard requiredShares > 0 else { return 0 }
        return Double(approvedShares) / Double(requiredShares)
    }

    /// Has enough shares been collected
    var hasThresholdMet: Bool {
        approvedShares >= requiredShares
    }
}

/// Request to setup recovery
struct SetupRecoveryRequest: Codable {
    let threshold: Int
    let shares: [TrusteeShare]

    struct TrusteeShare: Codable {
        let trusteeEmail: String
        let encryptedShare: Data

        enum CodingKeys: String, CodingKey {
            case trusteeEmail = "trustee_email"
            case encryptedShare = "encrypted_share"
        }
    }
}

/// Response from recovery setup
struct SetupRecoveryResponse: Codable {
    let config: RecoveryConfig
}

/// Pending requests response
struct PendingRequestsResponse: Codable {
    let requests: [RecoveryRequest]
}

/// Request to approve recovery
struct ApproveRecoveryRequest: Codable {
    let share: Data
}

/// Response from initiating recovery
struct InitiateRecoveryResponse: Codable {
    let request: RecoveryRequest
}

/// Response when recovery is complete
struct RecoveryCompleteResponse: Codable {
    let masterKey: Data
    let message: String

    enum CodingKeys: String, CodingKey {
        case masterKey = "master_key"
        case message
    }
}
