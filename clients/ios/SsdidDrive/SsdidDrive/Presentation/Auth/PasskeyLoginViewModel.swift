import Foundation
import Combine

// MARK: - Removed: Passkey/WebAuthn login replaced by SSDID wallet authentication

/// Stub: WebAuthn/Passkey login has been replaced by SSDID wallet QR-based authentication.
/// This file is kept as a stub to avoid breaking Xcode project references.

protocol PasskeyLoginViewModelDelegate: AnyObject {
    func passkeyLoginDidComplete()
}

final class PasskeyLoginViewModel: BaseViewModel {
    weak var delegate: PasskeyLoginViewModelDelegate?

    init(webAuthnRepository: WebAuthnRepository) {
        super.init()
    }
}
