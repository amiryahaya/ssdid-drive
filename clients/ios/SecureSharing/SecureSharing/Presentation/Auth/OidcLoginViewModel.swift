import Foundation
import AuthenticationServices
import Combine

/// Delegate for OIDC login coordinator events
protocol OidcLoginViewModelDelegate: AnyObject {
    func oidcLoginDidComplete()
    func oidcLoginDidRequireRegistration(keyMaterial: String, keySalt: String)
}

/// View model for OIDC login flow using ASWebAuthenticationSession
final class OidcLoginViewModel: BaseViewModel {

    // MARK: - Published Properties

    @Published var providers: [AuthProvider] = []
    @Published var isLoadingProviders = false

    // MARK: - Properties

    private let oidcRepository: OidcRepository
    weak var delegate: OidcLoginViewModelDelegate?
    private var webAuthSession: ASWebAuthenticationSession?

    // MARK: - Initialization

    init(oidcRepository: OidcRepository) {
        self.oidcRepository = oidcRepository
        super.init()
    }

    // MARK: - Actions

    func loadProviders(tenantSlug: String) {
        isLoadingProviders = true

        Task {
            do {
                let allProviders = try await oidcRepository.getProviders(tenantSlug: tenantSlug)
                await MainActor.run {
                    self.providers = allProviders.filter { $0.enabled }
                    self.isLoadingProviders = false
                }
            } catch {
                await MainActor.run {
                    self.isLoadingProviders = false
                    self.handleError(error)
                }
            }
        }
    }

    func beginLogin(providerId: String, presentationAnchor: ASPresentationAnchor) {
        isLoading = true
        clearError()

        Task {
            do {
                let result = try await oidcRepository.beginAuthorize(providerId: providerId)

                await MainActor.run {
                    guard let url = URL(string: result.authorizationUrl) else {
                        self.handleError(AuthError.invalidCredentials)
                        return
                    }

                    self.startWebAuthSession(url: url, state: result.state, presentationAnchor: presentationAnchor)
                }
            } catch {
                await MainActor.run {
                    self.handleError(error)
                }
            }
        }
    }

    // MARK: - Private

    private func startWebAuthSession(url: URL, state: String, presentationAnchor: ASPresentationAnchor) {
        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: "securesharing"
        ) { [weak self] callbackURL, error in
            guard let self = self else { return }

            if let error = error {
                Task { @MainActor in
                    if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        self.isLoading = false
                    } else {
                        self.handleError(error)
                    }
                }
                return
            }

            guard let callbackURL = callbackURL,
                  let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                  let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
                  let returnedState = components.queryItems?.first(where: { $0.name == "state" })?.value else {
                Task { @MainActor in
                    self.handleError(AuthError.invalidCredentials)
                }
                return
            }

            guard returnedState == state else {
                Task { @MainActor in
                    self.handleError(AuthError.invalidCredentials)
                }
                return
            }

            self.handleCallback(code: code, state: returnedState)
        }

        // Use the class method to provide the presentation anchor
        let contextProvider = WebAuthContextProvider(anchor: presentationAnchor)
        session.presentationContextProvider = contextProvider
        session.prefersEphemeralWebBrowserSession = true
        session.start()

        self.webAuthSession = session
    }

    private func handleCallback(code: String, state: String) {
        Task {
            do {
                let result = try await oidcRepository.handleCallback(code: code, state: state)

                await MainActor.run {
                    self.isLoading = false

                    switch result {
                    case .authenticated:
                        self.delegate?.oidcLoginDidComplete()
                    case .newUser(let keyMaterial, let keySalt):
                        self.delegate?.oidcLoginDidRequireRegistration(
                            keyMaterial: keyMaterial,
                            keySalt: keySalt
                        )
                    }
                }
            } catch {
                await MainActor.run {
                    self.handleError(error)
                }
            }
        }
    }
}

/// Provides the presentation anchor for ASWebAuthenticationSession
private class WebAuthContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    let anchor: ASPresentationAnchor

    init(anchor: ASPresentationAnchor) {
        self.anchor = anchor
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return anchor
    }
}
