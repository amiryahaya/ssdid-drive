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

    // MARK: - Trustee Dashboard (pending backend implementation)

    /// Get pending recovery requests where the current user is a trustee.
    func getPendingRequests() async throws -> [RecoveryRequest]

    /// Get recovery shares held by the current user as a trustee.
    func getHeldShares() async throws -> [RecoveryShare]

    /// Approve a recovery request (release share to requester).
    func approveRequest(requestId: String) async throws

    /// Reject a recovery request.
    func rejectRequest(requestId: String) async throws
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
