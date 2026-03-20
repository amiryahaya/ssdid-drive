import Foundation

/// Implementation of RecoveryRepository using the API client
final class RecoveryRepositoryImpl: RecoveryRepository {

    // MARK: - Properties

    private let apiClient: APIClient

    // MARK: - Initialization

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    // MARK: - RecoveryRepository

    func setupRecovery(serverShare: String, keyProof: String) async throws {
        struct Request: Encodable {
            let server_share: String
            let key_proof: String
        }
        let _: EmptyResponse = try await apiClient.request(
            "/recovery/setup",
            method: .post,
            body: Request(server_share: serverShare, key_proof: keyProof),
            requiresAuth: true
        )
    }

    func getStatus() async throws -> RecoveryStatusResponse {
        return try await apiClient.request(
            "/recovery/status",
            method: .get,
            body: nil as String?,
            requiresAuth: true
        )
    }

    func getServerShare(did: String) async throws -> ServerShareResponse {
        let queryItems = [URLQueryItem(name: "did", value: did)]
        return try await apiClient.request(
            "/recovery/share",
            method: .get,
            body: nil as String?,
            queryItems: queryItems,
            requiresAuth: false
        )
    }

    func completeRecovery(
        oldDid: String,
        newDid: String,
        keyProof: String,
        kemPublicKey: String
    ) async throws -> CompleteRecoveryResponse {
        struct Request: Encodable {
            let old_did: String
            let new_did: String
            let key_proof: String
            let kem_public_key: String
        }
        return try await apiClient.request(
            "/recovery/complete",
            method: .post,
            body: Request(old_did: oldDid, new_did: newDid, key_proof: keyProof, kem_public_key: kemPublicKey),
            requiresAuth: false
        )
    }

    func deleteSetup() async throws {
        let _: EmptyResponse = try await apiClient.request(
            "/recovery/setup",
            method: .delete,
            body: nil as String?,
            requiresAuth: true
        )
    }

    // MARK: - Trustee Recovery

    func setupTrustees(threshold: Int, shares: [TrusteeShareRequest]) async throws {
        struct Request: Encodable {
            let threshold: Int
            let shares: [TrusteeShareRequest]
        }
        try await apiClient.requestNoContent(
            "/recovery/trustees/setup",
            method: .post,
            body: Request(threshold: threshold, shares: shares),
            requiresAuth: true
        )
    }

    func getTrustees() async throws -> [Trustee] {
        struct TrusteesResponse: Decodable {
            let trustees: [Trustee]
            let threshold: Int
        }
        let response: TrusteesResponse = try await apiClient.request(
            "/recovery/trustees",
            method: .get,
            body: nil as String?,
            requiresAuth: true
        )
        return response.trustees
    }

    func getPendingRequests() async throws -> [RecoveryRequest] {
        let response: PendingRequestsResponse = try await apiClient.request(
            "/recovery/requests/pending",
            method: .get,
            body: nil as String?,
            requiresAuth: true
        )
        return response.requests
    }

    func getHeldShares() async throws -> [RecoveryShare] {
        // Trustees see pending requests via getPendingRequests().
        // There is no separate held-shares endpoint — return empty.
        return []
    }

    func approveRequest(requestId: String) async throws {
        try await apiClient.requestNoContent(
            "/recovery/requests/\(requestId)/approve",
            method: .post,
            body: nil as String?,
            requiresAuth: true
        )
    }

    func rejectRequest(requestId: String) async throws {
        try await apiClient.requestNoContent(
            "/recovery/requests/\(requestId)/reject",
            method: .post,
            body: nil as String?,
            requiresAuth: true
        )
    }

    func getMyRecoveryRequest() async throws -> RecoveryRequest? {
        // The requester's own request is tracked client-side after createRecoveryRequest().
        // There is no "my request" endpoint — return nil.
        return nil
    }

    func createRecoveryRequest(did: String) async throws -> RecoveryRequest {
        struct Request: Encodable { let did: String }
        struct Response: Decodable {
            let id: String
            let did: String
            let status: String
            let approvedShares: Int
            let requiredShares: Int
            let expiresAt: Date
            let createdAt: Date

            enum CodingKeys: String, CodingKey {
                case id
                case did
                case status
                case approvedShares = "approved_shares"
                case requiredShares = "required_shares"
                case expiresAt = "expires_at"
                case createdAt = "created_at"
            }
        }
        let response: Response = try await apiClient.request(
            "/recovery/requests",
            method: .post,
            body: Request(did: did),
            requiresAuth: false
        )
        return RecoveryRequest(
            id: response.id,
            requesterId: response.did,
            requesterEmail: "",
            requesterName: nil,
            status: RecoveryRequest.Status(rawValue: response.status) ?? .pending,
            approvedShares: response.approvedShares,
            requiredShares: response.requiredShares,
            expiresAt: response.expiresAt,
            createdAt: response.createdAt
        )
    }

    func getReleasedShares(requestId: String, did: String) async throws -> [ReleasedShare] {
        struct Response: Decodable {
            let shares: [ReleasedShare]
        }
        let queryItems = [URLQueryItem(name: "did", value: did)]
        let response: Response = try await apiClient.request(
            "/recovery/requests/\(requestId)/shares",
            method: .get,
            body: nil as String?,
            queryItems: queryItems,
            requiresAuth: false
        )
        return response.shares
    }

    func initiateRecovery() async throws -> RecoveryRequest {
        // This endpoint is for the unauthenticated recovery flow (locked-out user).
        // From the settings/authenticated context there is no direct initiate endpoint.
        throw APIClient.APIError.serverError
    }
}

/// Empty response for endpoints that return 201/204
private struct EmptyResponse: Decodable {}
