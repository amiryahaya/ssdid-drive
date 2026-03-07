import Foundation
@testable import SsdidDrive

/// Mock implementation of AuthRepository for testing
final class MockAuthRepository: AuthRepository {

    // MARK: - Stub Results

    var loginResult: Result<User, Error> = .failure(MockError.notImplemented)
    var registerResult: Result<User, Error> = .failure(MockError.notImplemented)
    var logoutResult: Result<Void, Error> = .success(())
    var refreshTokenResult: Result<Void, Error> = .success(())
    var getCurrentUserResult: Result<User, Error> = .failure(MockError.notImplemented)
    var isAuthenticatedResult: Bool = false
    var isBiometricAvailableResult: Bool = false
    var isBiometricUnlockEnabledResult: Bool = false
    var enableBiometricUnlockResult: Result<Void, Error> = .success(())
    var disableBiometricUnlockResult: Result<Void, Error> = .success(())
    var authenticateWithBiometricResult: Result<Bool, Error> = .success(false)
    var areKeysUnlockedResult: Bool = false
    var unlockKeysResult: Result<Void, Error> = .success(())
    var enrollDeviceResult: Result<Device, Error> = .failure(MockError.notImplemented)
    var getDevicesResult: Result<[Device], Error> = .success([])
    var revokeDeviceResult: Result<Void, Error> = .success(())
    var changePasswordResult: Result<Void, Error> = .success(())
    var verifyPasswordResult: Result<Bool, Error> = .success(true)
    var getInvitationInfoResult: Result<TokenInvitation, Error> = .failure(MockError.notImplemented)
    var acceptInvitationResult: Result<InviteUser, Error> = .failure(MockError.notImplemented)

    // MARK: - Call Tracking

    var loginCallCount = 0
    var registerCallCount = 0
    var logoutCallCount = 0
    var refreshTokenCallCount = 0
    var getCurrentUserCallCount = 0
    var isAuthenticatedCallCount = 0
    var isBiometricAvailableCallCount = 0
    var isBiometricUnlockEnabledCallCount = 0
    var enableBiometricUnlockCallCount = 0
    var disableBiometricUnlockCallCount = 0
    var authenticateWithBiometricCallCount = 0
    var areKeysUnlockedCallCount = 0
    var lockKeysCallCount = 0
    var unlockKeysCallCount = 0
    var enrollDeviceCallCount = 0
    var getDevicesCallCount = 0
    var revokeDeviceCallCount = 0
    var changePasswordCallCount = 0
    var verifyPasswordCallCount = 0
    var getInvitationInfoCallCount = 0
    var acceptInvitationCallCount = 0

    // MARK: - Last Call Parameters

    var lastLoginEmail: String?
    var lastLoginPassword: String?
    var lastRegisterEmail: String?
    var lastRegisterPassword: String?
    var lastUnlockKeysPassword: String?
    var lastEnrollDeviceName: String?
    var lastRevokeDeviceId: String?
    var lastChangePasswordCurrent: String?
    var lastChangePasswordNew: String?
    var lastVerifyPassword: String?
    var lastGetInvitationInfoToken: String?
    var lastAcceptInvitationToken: String?
    var lastAcceptInvitationDisplayName: String?
    var lastAcceptInvitationPassword: String?

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

    func login(email: String, password: String) async throws -> User {
        loginCallCount += 1
        lastLoginEmail = email
        lastLoginPassword = password
        return try loginResult.get()
    }

    func register(email: String, password: String) async throws -> User {
        registerCallCount += 1
        lastRegisterEmail = email
        lastRegisterPassword = password
        return try registerResult.get()
    }

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

    func enableBiometricUnlock(password: String) async throws {
        enableBiometricUnlockCallCount += 1
        try enableBiometricUnlockResult.get()
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

    func unlockKeys(password: String) async throws {
        unlockKeysCallCount += 1
        lastUnlockKeysPassword = password
        try unlockKeysResult.get()
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

    // MARK: - Password

    func changePassword(currentPassword: String, newPassword: String) async throws {
        changePasswordCallCount += 1
        lastChangePasswordCurrent = currentPassword
        lastChangePasswordNew = newPassword
        try changePasswordResult.get()
    }

    func verifyPassword(_ password: String) async throws -> Bool {
        verifyPasswordCallCount += 1
        lastVerifyPassword = password
        return try verifyPasswordResult.get()
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

    // MARK: - Reset

    func reset() {
        loginCallCount = 0
        registerCallCount = 0
        logoutCallCount = 0
        refreshTokenCallCount = 0
        getCurrentUserCallCount = 0
        isAuthenticatedCallCount = 0
        isBiometricAvailableCallCount = 0
        isBiometricUnlockEnabledCallCount = 0
        enableBiometricUnlockCallCount = 0
        disableBiometricUnlockCallCount = 0
        authenticateWithBiometricCallCount = 0
        areKeysUnlockedCallCount = 0
        lockKeysCallCount = 0
        unlockKeysCallCount = 0
        enrollDeviceCallCount = 0
        getDevicesCallCount = 0
        revokeDeviceCallCount = 0
        changePasswordCallCount = 0
        verifyPasswordCallCount = 0
        getInvitationInfoCallCount = 0
        acceptInvitationCallCount = 0

        lastLoginEmail = nil
        lastLoginPassword = nil
        lastRegisterEmail = nil
        lastRegisterPassword = nil
        lastUnlockKeysPassword = nil
        lastEnrollDeviceName = nil
        lastRevokeDeviceId = nil
        lastChangePasswordCurrent = nil
        lastChangePasswordNew = nil
        lastVerifyPassword = nil
        lastGetInvitationInfoToken = nil
        lastAcceptInvitationToken = nil
        lastAcceptInvitationDisplayName = nil
        lastAcceptInvitationPassword = nil
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
