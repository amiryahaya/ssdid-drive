import Foundation
import Combine

// MARK: - Removed: Password-based registration replaced by SSDID wallet authentication

/// Stub: Registration is now handled through SSDID wallet.
/// This file is kept as a stub to avoid breaking Xcode project references.

protocol RegisterViewModelCoordinatorDelegate: AnyObject {
    func registerViewModelDidRequestLogin()
    func registerViewModelDidRegister()
}

final class RegisterViewModel: BaseViewModel {
    weak var coordinatorDelegate: RegisterViewModelCoordinatorDelegate?

    init(authRepository: AuthRepository) {
        super.init()
    }
}
