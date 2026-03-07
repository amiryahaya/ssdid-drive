import Foundation
import CryptoKit

/// Implementation of RecoveryRepository
final class RecoveryRepositoryImpl: RecoveryRepository {

    private let apiClient: APIClient
    private let keyManager: KeyManager

    init(apiClient: APIClient, keyManager: KeyManager) {
        self.apiClient = apiClient
        self.keyManager = keyManager
    }

    // MARK: - Configuration

    func getConfig() async throws -> RecoveryConfig {
        try await apiClient.request("/recovery/config")
    }

    func isConfigured() async throws -> Bool {
        let config = try await getConfig()
        return config.isConfigured
    }

    func setupRecovery(threshold: Int, trusteeEmails: [String]) async throws -> RecoveryConfig {
        // Generate shares if we have keys unlocked
        guard let keyBundle = keyManager.currentKeyBundle else {
            throw RecoveryError.keysNotUnlocked
        }

        // Split master key into shares
        let masterKeyData = serializeMasterKey(keyBundle)
        let shares = try splitMasterKey(masterKey: masterKeyData, threshold: threshold, totalShares: trusteeEmails.count)

        // Prepare trustee shares
        var trusteeShares: [SetupRecoveryRequest.TrusteeShare] = []
        for (index, email) in trusteeEmails.enumerated() {
            trusteeShares.append(SetupRecoveryRequest.TrusteeShare(
                trusteeEmail: email,
                encryptedShare: shares[index]
            ))
        }

        let body = SetupRecoveryRequest(threshold: threshold, shares: trusteeShares)
        let response: SetupRecoveryResponse = try await apiClient.request("/recovery/setup", method: .post, body: body)
        return response.config
    }

    func updateConfig(
        threshold: Int?,
        addTrustees: [String]?,
        removeTrustees: [String]?
    ) async throws -> RecoveryConfig {
        let body = UpdateRecoveryConfigRequest(
            threshold: threshold,
            addTrustees: addTrustees,
            removeTrustees: removeTrustees
        )
        return try await apiClient.request("/recovery/config", method: .patch, body: body)
    }

    func deleteConfig() async throws {
        try await apiClient.requestNoContent("/recovery/config", method: .delete)
    }

    // MARK: - Trustee Management

    func getTrustees() async throws -> [Trustee] {
        let response: TrusteesResponse = try await apiClient.request("/recovery/trustees")
        return response.trustees
    }

    func addTrustee(email: String) async throws -> Trustee {
        let body = AddTrusteeRequest(email: email)
        return try await apiClient.request("/recovery/trustees", method: .post, body: body)
    }

    func removeTrustee(trusteeId: String) async throws {
        try await apiClient.requestNoContent("/recovery/trustees/\(trusteeId)", method: .delete)
    }

    func resendTrusteeInvitation(trusteeId: String) async throws {
        try await apiClient.requestNoContent("/recovery/trustees/\(trusteeId)/resend", method: .post)
    }

    // MARK: - Recovery Shares (as Trustee)

    func getHeldShares() async throws -> [RecoveryShare] {
        let response: RecoverySharesResponse = try await apiClient.request("/recovery/shares/held")
        return response.shares
    }

    func acceptTrusteeInvitation(invitationId: String) async throws {
        try await apiClient.requestNoContent("/recovery/invitations/\(invitationId)/accept", method: .post)
    }

    func declineTrusteeInvitation(invitationId: String) async throws {
        try await apiClient.requestNoContent("/recovery/invitations/\(invitationId)/decline", method: .post)
    }

    // MARK: - Pending Requests (as Trustee)

    func getPendingRequests() async throws -> [RecoveryRequest] {
        let response: PendingRequestsResponse = try await apiClient.request("/recovery/requests/pending")
        return response.requests
    }

    func approveRequest(requestId: String) async throws {
        try await apiClient.requestNoContent("/recovery/requests/\(requestId)/approve", method: .post)
    }

    func rejectRequest(requestId: String) async throws {
        try await apiClient.requestNoContent("/recovery/requests/\(requestId)/reject", method: .post)
    }

    // MARK: - Initiate Recovery

    func initiateRecovery() async throws -> RecoveryRequest {
        let response: InitiateRecoveryResponse = try await apiClient.request("/recovery/initiate", method: .post)
        return response.request
    }

    func getMyRecoveryRequest() async throws -> RecoveryRequest? {
        let response: MyRecoveryRequestResponse = try await apiClient.request("/recovery/request")
        return response.request
    }

    func cancelRecoveryRequest() async throws {
        try await apiClient.requestNoContent("/recovery/request", method: .delete)
    }

    func completeRecovery() async throws -> Data {
        let response: RecoveryCompleteResponse = try await apiClient.request("/recovery/complete", method: .post)
        return response.masterKey
    }

    // MARK: - Shamir Secret Sharing

    /// Split the master key into shares using real Shamir's Secret Sharing
    /// - Parameters:
    ///   - masterKey: The master key data to split
    ///   - threshold: Minimum number of shares needed to reconstruct
    ///   - totalShares: Total number of shares to create
    /// - Returns: Array of serialized shares
    func splitMasterKey(masterKey: Data, threshold: Int, totalShares: Int) throws -> [Data] {
        guard threshold >= 2 else {
            throw RecoveryError.invalidThreshold
        }

        guard threshold <= totalShares else {
            throw RecoveryError.invalidThreshold
        }

        // Use real Shamir's Secret Sharing
        do {
            return try ShamirSecretSharing.splitToSerializedShares(
                secret: masterKey,
                threshold: threshold,
                totalShares: totalShares
            )
        } catch let error as ShamirSecretSharing.Error {
            switch error {
            case .invalidThreshold:
                throw RecoveryError.invalidThreshold
            case .emptySecret:
                throw RecoveryError.invalidShare
            default:
                throw RecoveryError.invalidShare
            }
        }
    }

    /// Reconstruct the master key from shares using real Shamir's Secret Sharing
    /// - Parameters:
    ///   - shares: Array of serialized shares
    ///   - threshold: The threshold that was used when splitting
    /// - Returns: The reconstructed master key
    func reconstructMasterKey(shares: [Data], threshold: Int) throws -> Data {
        guard shares.count >= threshold else {
            throw RecoveryError.insufficientShares
        }

        // Use real Shamir's Secret Sharing
        do {
            return try ShamirSecretSharing.reconstructFromSerializedShares(
                serializedShares: shares,
                threshold: threshold
            )
        } catch let error as ShamirSecretSharing.Error {
            switch error {
            case .insufficientShares:
                throw RecoveryError.insufficientShares
            case .invalidShareFormat, .duplicateShareIndices:
                throw RecoveryError.invalidShare
            default:
                throw RecoveryError.invalidShare
            }
        }
    }

    // MARK: - Private Helpers

    private func serializeMasterKey(_ keyBundle: KeyManager.KeyBundle) -> Data {
        var data = Data()
        data.append(keyBundle.kazKemPrivateKey)
        data.append(keyBundle.mlKemPrivateKey)
        data.append(keyBundle.kazSignPrivateKey)
        data.append(keyBundle.mlDsaPrivateKey)
        return data
    }
}

// MARK: - Errors

enum RecoveryError: Error {
    case keysNotUnlocked
    case invalidThreshold
    case insufficientShares
    case invalidShare
}

// MARK: - Request Types

private struct UpdateRecoveryConfigRequest: Codable {
    let threshold: Int?
    let addTrustees: [String]?
    let removeTrustees: [String]?

    enum CodingKeys: String, CodingKey {
        case threshold
        case addTrustees = "add_trustees"
        case removeTrustees = "remove_trustees"
    }
}

private struct AddTrusteeRequest: Codable {
    let email: String
}

// MARK: - Response Types

private struct TrusteesResponse: Codable {
    let trustees: [Trustee]
}

private struct RecoverySharesResponse: Codable {
    let shares: [RecoveryShare]
}

private struct MyRecoveryRequestResponse: Codable {
    let request: RecoveryRequest?
}
