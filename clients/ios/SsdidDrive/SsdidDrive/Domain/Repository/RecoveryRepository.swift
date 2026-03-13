import Foundation

/// Repository for Shamir Secret Sharing recovery operations
protocol RecoveryRepository {
    /// Setup recovery by storing the server-held share and key proof.
    func setupRecovery(serverShare: String, keyProof: String) async throws

    /// Get current recovery status.
    func getStatus() async throws -> RecoveryStatusResponse

    /// Retrieve the server-held share for a given DID (unauthenticated).
    func getServerShare(did: String) async throws -> ServerShareResponse

    /// Complete recovery with DID migration (unauthenticated).
    func completeRecovery(
        oldDid: String,
        newDid: String,
        keyProof: String,
        kemPublicKey: String
    ) async throws -> CompleteRecoveryResponse

    /// Delete/deactivate recovery setup.
    func deleteSetup() async throws
}

struct RecoveryStatusResponse: Codable {
    let isActive: Bool
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case isActive = "is_active"
        case createdAt = "created_at"
    }
}

struct ServerShareResponse: Codable {
    let serverShare: String
    let shareIndex: Int

    enum CodingKeys: String, CodingKey {
        case serverShare = "server_share"
        case shareIndex = "share_index"
    }
}

struct CompleteRecoveryResponse: Codable {
    let token: String
    let userId: String

    enum CodingKeys: String, CodingKey {
        case token
        case userId = "user_id"
    }
}
