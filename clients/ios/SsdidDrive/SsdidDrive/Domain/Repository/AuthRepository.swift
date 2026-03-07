import Foundation

/// Repository for authentication operations
protocol AuthRepository: AnyObject {

    // MARK: - Authentication

    /// Login with email and password
    func login(email: String, password: String) async throws -> User

    /// Register a new user
    func register(email: String, password: String) async throws -> User

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

    /// Enable biometric unlock (stores master key protected by biometric)
    func enableBiometricUnlock(password: String) async throws

    /// Disable biometric unlock
    func disableBiometricUnlock() async throws

    /// Authenticate using biometric and unlock keys
    func authenticateWithBiometric() async throws -> Bool

    // MARK: - Key Management

    /// Check if keys are currently unlocked
    func areKeysUnlocked() async -> Bool

    /// Lock keys (clear from memory)
    func lockKeys() async

    /// Unlock keys with password
    func unlockKeys(password: String) async throws

    // MARK: - Device Management

    /// Enroll current device
    func enrollDevice(name: String) async throws -> Device

    /// Get list of user's devices
    func getDevices() async throws -> [Device]

    /// Revoke a device
    func revokeDevice(deviceId: String) async throws

    /// Get current device ID
    var currentDeviceId: String? { get }

    // MARK: - Password

    /// Change user's password
    func changePassword(currentPassword: String, newPassword: String) async throws

    /// Verify password is correct
    func verifyPassword(_ password: String) async throws -> Bool

    // MARK: - Invitation Token (Public - for new users)

    /// Get public invitation info by token.
    /// This is for new users who received an invitation link.
    /// No authentication required.
    func getInvitationInfo(token: String) async throws -> TokenInvitation

    /// Accept an invitation and register a new account.
    /// Generates key pairs and encrypts them with the password.
    /// No authentication required - this creates the account.
    func acceptInvitation(token: String, displayName: String, password: String) async throws -> InviteUser
}
