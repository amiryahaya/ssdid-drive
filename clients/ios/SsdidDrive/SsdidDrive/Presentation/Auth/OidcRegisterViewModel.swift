import Foundation
import Combine

// MARK: - Removed: OIDC registration replaced by SSDID wallet authentication

/// Stub: OIDC registration has been replaced by SSDID wallet QR-based authentication.
/// This file is kept as a stub to avoid breaking Xcode project references.

protocol OidcRegisterViewModelCoordinatorDelegate: AnyObject {
    func oidcRegisterViewModelDidComplete()
}

final class OidcRegisterViewModel: BaseViewModel {
    weak var coordinatorDelegate: OidcRegisterViewModelCoordinatorDelegate?

    init(
        oidcRepository: OidcRepository,
        keyManager: KeyManager,
        keyMaterial: String,
        keySalt: String
    ) {
        super.init()
    }

    func completeRegistration(password: String) {}
}
