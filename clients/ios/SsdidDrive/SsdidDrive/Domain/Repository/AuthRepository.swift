import Foundation

/// Repository for authentication operations.
/// Authentication is SSDID wallet-based (QR challenge-response).
/// Password is only used for client-side key encryption during invitation acceptance.
protocol AuthRepository: AnyObject {

    // MARK: - Authentication

    /// Logout the current user
    func logout() async throws

    /// Refresh the access token
    func refreshToken() async throws

    /// Get current user info
    func getCurrentUser() async throws -> User

    // MARK: - Authentication State

    /// Check if user is authenticated
    func isAuthenticated() async -> Bool

    /// Get the current user ID
    var currentUserId: String? { get }

    // MARK: - Biometric Authentication

    /// Check if biometric unlock is available on device
    func isBiometricAvailable() -> Bool

    /// Check if biometric unlock is enabled
    func isBiometricUnlockEnabled() async -> Bool

    /// Disable biometric unlock
    func disableBiometricUnlock() async throws

    /// Authenticate using biometric and unlock keys
    func authenticateWithBiometric() async throws -> Bool

    // MARK: - Key Management

    /// Check if keys are currently unlocked
    func areKeysUnlocked() async -> Bool

    /// Lock keys (clear from memory)
    func lockKeys() async

    // MARK: - Device Management

    /// Enroll current device
    func enrollDevice(name: String) async throws -> Device

    /// Get list of user's devices
    func getDevices() async throws -> [Device]

    /// Revoke a device
    func revokeDevice(deviceId: String) async throws

    /// Get current device ID
    var currentDeviceId: String? { get }

    // MARK: - Invitation Token (Public - for new users)

    /// Get public invitation info by token.
    /// This is for new users who received an invitation link.
    /// No authentication required.
    func getInvitationInfo(token: String) async throws -> TokenInvitation

    /// Accept an invitation and register a new account.
    /// Generates key pairs and encrypts them with the password.
    /// No authentication required - this creates the account.
    func acceptInvitation(token: String, displayName: String, password: String) async throws -> InviteUser

    // MARK: - Wallet-Based Invitation

    /// Launch SSDID Wallet to accept an invitation.
    func launchWalletInvite(token: String) async throws

    /// Save session from wallet callback (invitation acceptance).
    func saveSessionFromWallet(sessionToken: String) async throws

    // MARK: - Multi-Auth Invitation Acceptance

    /// Accept an invitation as an already-authenticated user.
    /// No key generation needed — the user already has an account.
    func acceptInvitationAsExistingUser(token: String) async throws

    /// Accept an invitation via OIDC provider authentication.
    /// Registers a new user using OIDC and accepts the invitation in one step.
    func acceptInvitationWithOidc(token: String, provider: String, idToken: String) async throws
}
