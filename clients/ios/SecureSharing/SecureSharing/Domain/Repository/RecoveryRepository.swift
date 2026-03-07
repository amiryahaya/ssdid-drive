import Foundation

/// Repository for account recovery operations
protocol RecoveryRepository {

    // MARK: - Configuration

    /// Get current recovery configuration
    func getConfig() async throws -> RecoveryConfig

    /// Check if recovery is configured
    func isConfigured() async throws -> Bool

    /// Setup recovery with trustees
    func setupRecovery(
        threshold: Int,
        trusteeEmails: [String]
    ) async throws -> RecoveryConfig

    /// Update recovery configuration
    func updateConfig(
        threshold: Int?,
        addTrustees: [String]?,
        removeTrustees: [String]?
    ) async throws -> RecoveryConfig

    /// Delete recovery configuration
    func deleteConfig() async throws

    // MARK: - Trustee Management

    /// Get list of trustees
    func getTrustees() async throws -> [Trustee]

    /// Add a trustee
    func addTrustee(email: String) async throws -> Trustee

    /// Remove a trustee
    func removeTrustee(trusteeId: String) async throws

    /// Resend invitation to trustee
    func resendTrusteeInvitation(trusteeId: String) async throws

    // MARK: - Recovery Shares (as Trustee)

    /// Get recovery shares I hold for others
    func getHeldShares() async throws -> [RecoveryShare]

    /// Accept a trustee invitation
    func acceptTrusteeInvitation(invitationId: String) async throws

    /// Decline a trustee invitation
    func declineTrusteeInvitation(invitationId: String) async throws

    // MARK: - Pending Requests (as Trustee)

    /// Get pending recovery requests for which I'm a trustee
    func getPendingRequests() async throws -> [RecoveryRequest]

    /// Approve a recovery request (release my share)
    func approveRequest(requestId: String) async throws

    /// Reject a recovery request
    func rejectRequest(requestId: String) async throws

    // MARK: - Initiate Recovery

    /// Start the recovery process
    func initiateRecovery() async throws -> RecoveryRequest

    /// Get status of my recovery request
    func getMyRecoveryRequest() async throws -> RecoveryRequest?

    /// Cancel my recovery request
    func cancelRecoveryRequest() async throws

    /// Complete recovery (after threshold is met)
    func completeRecovery() async throws -> Data  // Returns recovered master key

    // MARK: - Shamir Secret Sharing

    /// Split master key into shares using Shamir's scheme
    func splitMasterKey(
        masterKey: Data,
        threshold: Int,
        totalShares: Int
    ) throws -> [Data]

    /// Reconstruct master key from shares
    func reconstructMasterKey(shares: [Data], threshold: Int) throws -> Data
}
