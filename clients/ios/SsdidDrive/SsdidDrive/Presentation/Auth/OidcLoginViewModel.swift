import Foundation
import Combine

// MARK: - Removed: OIDC login replaced by SSDID wallet authentication

/// Stub: OIDC login has been replaced by SSDID wallet QR-based authentication.
/// This file is kept as a stub to avoid breaking Xcode project references.

protocol OidcLoginViewModelDelegate: AnyObject {
    func oidcLoginDidComplete()
    func oidcLoginDidRequireRegistration(keyMaterial: String, keySalt: String)
}

final class OidcLoginViewModel: BaseViewModel {
    @Published var providers: [AuthProvider] = []
    weak var delegate: OidcLoginViewModelDelegate?

    init(oidcRepository: OidcRepository) {
        super.init()
    }

    func loadProviders(tenantSlug: String) {}
}
