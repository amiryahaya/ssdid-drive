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
            "/api/recovery/setup",
            method: .post,
            body: Request(server_share: serverShare, key_proof: keyProof),
            requiresAuth: true
        )
    }

    func getStatus() async throws -> RecoveryStatusResponse {
        return try await apiClient.request(
            "/api/recovery/status",
            method: .get,
            body: nil as String?,
            requiresAuth: true
        )
    }

    func getServerShare(did: String) async throws -> ServerShareResponse {
        let queryItems = [URLQueryItem(name: "did", value: did)]
        return try await apiClient.request(
            "/api/recovery/share",
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
            "/api/recovery/complete",
            method: .post,
            body: Request(old_did: oldDid, new_did: newDid, key_proof: keyProof, kem_public_key: kemPublicKey),
            requiresAuth: false
        )
    }

    func deleteSetup() async throws {
        let _: EmptyResponse = try await apiClient.request(
            "/api/recovery/setup",
            method: .delete,
            body: nil as String?,
            requiresAuth: true
        )
    }
}

/// Empty response for endpoints that return 201/204
private struct EmptyResponse: Decodable {}
