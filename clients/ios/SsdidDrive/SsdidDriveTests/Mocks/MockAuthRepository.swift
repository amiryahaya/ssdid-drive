import Foundation
@testable import SsdidDrive

/// Mock implementation of AuthRepository for testing
final class MockAuthRepository: AuthRepository {

    // MARK: - Stub Results

    var logoutResult: Result<Void, Error> = .success(())
    var refreshTokenResult: Result<Void, Error> = .success(())
    var getCurrentUserResult: Result<User, Error> = .failure(MockError.notImplemented)
    var isAuthenticatedResult: Bool = false
    var isBiometricAvailableResult: Bool = false
    var isBiometricUnlockEnabledResult: Bool = false
    var disableBiometricUnlockResult: Result<Void, Error> = .success(())
    var authenticateWithBiometricResult: Result<Bool, Error> = .success(false)
    var areKeysUnlockedResult: Bool = false
    var enrollDeviceResult: Result<Device, Error> = .failure(MockError.notImplemented)
    var getDevicesResult: Result<[Device], Error> = .success([])
    var revokeDeviceResult: Result<Void, Error> = .success(())
    var getInvitationInfoResult: Result<TokenInvitation, Error> = .failure(MockError.notImplemented)
    var acceptInvitationResult: Result<InviteUser, Error> = .failure(MockError.notImplemented)
    var launchWalletInviteResult: Result<Void, Error> = .success(())
    var saveSessionFromWalletResult: Result<Void, Error> = .success(())

    // MARK: - Call Tracking

    var logoutCallCount = 0
    var refreshTokenCallCount = 0
    var getCurrentUserCallCount = 0
    var isAuthenticatedCallCount = 0
    var isBiometricAvailableCallCount = 0
    var isBiometricUnlockEnabledCallCount = 0
    var disableBiometricUnlockCallCount = 0
    var authenticateWithBiometricCallCount = 0
    var areKeysUnlockedCallCount = 0
    var lockKeysCallCount = 0
    var enrollDeviceCallCount = 0
    var getDevicesCallCount = 0
    var revokeDeviceCallCount = 0
    var getInvitationInfoCallCount = 0
    var acceptInvitationCallCount = 0
    var launchWalletInviteCallCount = 0
    var saveSessionFromWalletCallCount = 0

    // MARK: - Last Call Parameters

    var lastEnrollDeviceName: String?
    var lastRevokeDeviceId: String?
    var lastGetInvitationInfoToken: String?
    var lastAcceptInvitationToken: String?
    var lastAcceptInvitationDisplayName: String?
    var lastAcceptInvitationPassword: String?
    var lastLaunchWalletInviteToken: String?
    var lastSaveSessionFromWalletToken: String?

    // MARK: - Properties

    var stubbedCurrentUserId: String?
    var stubbedCurrentDeviceId: String?

    var currentUserId: String? {
        stubbedCurrentUserId
    }

    var currentDeviceId: String? {
        stubbedCurrentDeviceId
    }

    // MARK: - Authentication

    func logout() async throws {
        logoutCallCount += 1
        try logoutResult.get()
    }

    func refreshToken() async throws {
        refreshTokenCallCount += 1
        try refreshTokenResult.get()
    }

    func getCurrentUser() async throws -> User {
        getCurrentUserCallCount += 1
        return try getCurrentUserResult.get()
    }

    // MARK: - Authentication State

    func isAuthenticated() async -> Bool {
        isAuthenticatedCallCount += 1
        return isAuthenticatedResult
    }

    // MARK: - Biometric Authentication

    func isBiometricAvailable() -> Bool {
        isBiometricAvailableCallCount += 1
        return isBiometricAvailableResult
    }

    func isBiometricUnlockEnabled() async -> Bool {
        isBiometricUnlockEnabledCallCount += 1
        return isBiometricUnlockEnabledResult
    }

    func disableBiometricUnlock() async throws {
        disableBiometricUnlockCallCount += 1
        try disableBiometricUnlockResult.get()
    }

    func authenticateWithBiometric() async throws -> Bool {
        authenticateWithBiometricCallCount += 1
        return try authenticateWithBiometricResult.get()
    }

    // MARK: - Key Management

    func areKeysUnlocked() async -> Bool {
        areKeysUnlockedCallCount += 1
        return areKeysUnlockedResult
    }

    func lockKeys() async {
        lockKeysCallCount += 1
    }

    // MARK: - Device Management

    func enrollDevice(name: String) async throws -> Device {
        enrollDeviceCallCount += 1
        lastEnrollDeviceName = name
        return try enrollDeviceResult.get()
    }

    func getDevices() async throws -> [Device] {
        getDevicesCallCount += 1
        return try getDevicesResult.get()
    }

    func revokeDevice(deviceId: String) async throws {
        revokeDeviceCallCount += 1
        lastRevokeDeviceId = deviceId
        try revokeDeviceResult.get()
    }

    // MARK: - Invitation

    func getInvitationInfo(token: String) async throws -> TokenInvitation {
        getInvitationInfoCallCount += 1
        lastGetInvitationInfoToken = token
        return try getInvitationInfoResult.get()
    }

    func acceptInvitation(token: String, displayName: String, password: String) async throws -> InviteUser {
        acceptInvitationCallCount += 1
        lastAcceptInvitationToken = token
        lastAcceptInvitationDisplayName = displayName
        lastAcceptInvitationPassword = password
        return try acceptInvitationResult.get()
    }

    // MARK: - Wallet-Based Invitation

    func launchWalletInvite(token: String) async throws {
        launchWalletInviteCallCount += 1
        lastLaunchWalletInviteToken = token
        try launchWalletInviteResult.get()
    }

    func saveSessionFromWallet(sessionToken: String) async throws {
        saveSessionFromWalletCallCount += 1
        lastSaveSessionFromWalletToken = sessionToken
        try saveSessionFromWalletResult.get()
    }

    // MARK: - Reset

    func reset() {
        // Reset stub results
        logoutResult = .success(())
        refreshTokenResult = .success(())
        getCurrentUserResult = .failure(MockError.notImplemented)
        isAuthenticatedResult = false
        isBiometricAvailableResult = false
        isBiometricUnlockEnabledResult = false
        disableBiometricUnlockResult = .success(())
        authenticateWithBiometricResult = .success(false)
        areKeysUnlockedResult = false
        enrollDeviceResult = .failure(MockError.notImplemented)
        getDevicesResult = .success([])
        revokeDeviceResult = .success(())
        getInvitationInfoResult = .failure(MockError.notImplemented)
        acceptInvitationResult = .failure(MockError.notImplemented)
        launchWalletInviteResult = .success(())
        saveSessionFromWalletResult = .success(())

        // Reset call counts
        logoutCallCount = 0
        refreshTokenCallCount = 0
        getCurrentUserCallCount = 0
        isAuthenticatedCallCount = 0
        isBiometricAvailableCallCount = 0
        isBiometricUnlockEnabledCallCount = 0
        disableBiometricUnlockCallCount = 0
        authenticateWithBiometricCallCount = 0
        areKeysUnlockedCallCount = 0
        lockKeysCallCount = 0
        enrollDeviceCallCount = 0
        getDevicesCallCount = 0
        revokeDeviceCallCount = 0
        getInvitationInfoCallCount = 0
        acceptInvitationCallCount = 0
        launchWalletInviteCallCount = 0
        saveSessionFromWalletCallCount = 0

        // Reset last call parameters
        lastEnrollDeviceName = nil
        lastRevokeDeviceId = nil
        lastGetInvitationInfoToken = nil
        lastAcceptInvitationToken = nil
        lastAcceptInvitationDisplayName = nil
        lastAcceptInvitationPassword = nil
        lastLaunchWalletInviteToken = nil
        lastSaveSessionFromWalletToken = nil

        // Reset properties
        stubbedCurrentUserId = nil
        stubbedCurrentDeviceId = nil
    }
}

// MARK: - Mock Errors

enum MockError: Error, LocalizedError {
    case notImplemented
    case testError(String)

    var errorDescription: String? {
        switch self {
        case .notImplemented:
            return "Not implemented"
        case .testError(let message):
            return message
        }
    }
}
