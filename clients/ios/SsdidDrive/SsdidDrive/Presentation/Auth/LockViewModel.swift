import Foundation
import Combine
import LocalAuthentication

/// Delegate for lock view model coordinator events
protocol LockViewModelCoordinatorDelegate: AnyObject {
    func lockViewModelDidUnlock()
    func lockViewModelDidRequestLogout()
}

/// View model for lock screen
final class LockViewModel: BaseViewModel {

    // MARK: - Properties

    private let authRepository: AuthRepository
    private let keychainManager: KeychainManager
    weak var coordinatorDelegate: LockViewModelCoordinatorDelegate?

    @Published var isBiometricAvailable = false
    @Published var biometricType: LABiometryType = .none

    // MARK: - Initialization

    init(authRepository: AuthRepository, keychainManager: KeychainManager) {
        self.authRepository = authRepository
        self.keychainManager = keychainManager
        super.init()
        checkBiometricAvailability()
    }

    // MARK: - Biometric Check

    private func checkBiometricAvailability() {
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            isBiometricAvailable = true
            biometricType = context.biometryType
        } else {
            isBiometricAvailable = false
            biometricType = .none
        }
    }

    // MARK: - Actions

    func unlockWithBiometrics() {
        let context = LAContext()
        context.localizedCancelTitle = "Use PIN"

        let reason = biometricType == .faceID
            ? "Unlock SsdidDrive with Face ID"
            : "Unlock SsdidDrive with Touch ID"

        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { [weak self] success, error in
            DispatchQueue.main.async {
                if success {
                    self?.coordinatorDelegate?.lockViewModelDidUnlock()
                } else if let error = error as? LAError {
                    switch error.code {
                    case .userCancel, .userFallback:
                        // User cancelled or wants to use PIN
                        break
                    case .biometryLockout:
                        self?.errorMessage = "Too many failed attempts. Please use your PIN."
                    case .biometryNotAvailable:
                        self?.errorMessage = "Biometric authentication is not available."
                    default:
                        self?.errorMessage = "Authentication failed. Please try again."
                    }
                }
            }
        }
    }

    func unlockWithPIN(_ pin: String) {
        isLoading = true
        clearError()

        // Verify PIN against stored hash
        guard let storedPINHash = try? keychainManager.load(key: Constants.Keychain.pinHash) else {
            isLoading = false
            errorMessage = "PIN not set. Please log in again."
            return
        }

        let inputPINHash = hashPIN(pin)

        if inputPINHash == storedPINHash {
            isLoading = false
            coordinatorDelegate?.lockViewModelDidUnlock()
        } else {
            isLoading = false
            errorMessage = "Incorrect PIN. Please try again."
        }
    }

    func requestLogout() {
        coordinatorDelegate?.lockViewModelDidRequestLogout()
    }

    // MARK: - Helpers

    private func hashPIN(_ pin: String) -> Data {
        // Simple SHA-256 hash for PIN verification
        // In production, use a proper key derivation function like Argon2
        guard let pinData = pin.data(using: .utf8) else {
            return Data()
        }

        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        pinData.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &hash)
        }
        return Data(hash)
    }
}

// MARK: - CommonCrypto Import

import CommonCrypto
