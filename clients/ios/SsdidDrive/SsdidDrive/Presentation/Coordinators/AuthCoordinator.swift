import UIKit
import SwiftUI
import Combine
import AuthenticationServices

/// Delegate for auth coordinator events
protocol AuthCoordinatorDelegate: AnyObject {
    func authDidComplete()
    func authDidRequestLogout()
    func authDidRequestLoginWithInvite(code: String)
}

/// Coordinator for SSDID wallet authentication flow.
/// Displays a QR code for wallet scanning (iPad/Mac cross-device) and
/// an "Open SSDID Wallet" button for same-device iPhone flow.
final class AuthCoordinator: BaseCoordinator {

    // MARK: - Properties

    weak var delegate: AuthCoordinatorDelegate?
    private var cancellables = Set<AnyCancellable>()

    /// Reference to the current login view model so the SceneDelegate can
    /// deliver auth callback tokens to it.
    private(set) var loginViewModel: LoginViewModel?

    /// Reference to the current invite accept view model so wallet callbacks
    /// can be delivered to it.
    private(set) var inviteAcceptViewModel: InviteAcceptViewModel?

    /// Navigation delegate adapter for cleaning up invite ViewModel on back-swipe
    private var navDelegateAdapter: NavigationDelegateAdapter?

    /// Retained ASWebAuthenticationSession — must be kept alive for the duration of the session
    private var authSession: ASWebAuthenticationSession?

    // MARK: - Start

    override func start() {
        showLogin()
    }

    // MARK: - Navigation

    func showLogin() {
        let viewModel = LoginViewModel(keychainManager: container.keychainManager)
        viewModel.coordinatorDelegate = self
        self.loginViewModel = viewModel

        let loginVC = LoginViewController(viewModel: viewModel)
        loginVC.delegate = self
        navigationController.setViewControllers([loginVC], animated: true)
    }

    /// Handle invitation deep link — show the wallet-based invite acceptance screen
    func handleInvitation(token: String) {
        let viewModel = InviteAcceptViewModel(
            authRepository: container.authRepository,
            token: token
        )
        viewModel.coordinatorDelegate = self
        self.inviteAcceptViewModel = viewModel

        let inviteVC = InviteAcceptViewController(viewModel: viewModel)
        navDelegateAdapter = NavigationDelegateAdapter { [weak self] vc in
            if !(vc is InviteAcceptViewController) {
                self?.inviteAcceptViewModel = nil
            }
        }
        navigationController.delegate = navDelegateAdapter
        navigationController.setViewControllers([inviteVC], animated: true)
    }

    /// Show the "Join Tenant" screen as a modal from the login screen
    func showJoinTenant() {
        let viewModel = JoinTenantViewModel(apiClient: container.apiClient)
        viewModel.delegate = self

        let joinTenantView = JoinTenantView(viewModel: viewModel)
        let hostingController = UIHostingController(rootView: joinTenantView)

        if let sheet = hostingController.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }

        navigationController.present(hostingController, animated: true)
    }

    /// Show the TOTP verification screen after email login
    func showTotpVerify(email: String) {
        let viewModel = TotpVerifyViewModel(
            email: email,
            apiClient: container.apiClient,
            keychainManager: container.keychainManager
        )
        viewModel.coordinatorDelegate = self

        let totpVC = TotpVerifyViewController(viewModel: viewModel)
        navigationController.pushViewController(totpVC, animated: true)
    }

    /// Show the "Request Organization" screen as a modal
    func showTenantRequest() {
        let viewModel = TenantRequestViewModel(apiClient: container.apiClient)
        viewModel.delegate = self

        let tenantRequestView = TenantRequestView(viewModel: viewModel)
        let hostingController = UIHostingController(rootView: tenantRequestView)

        if let sheet = hostingController.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }

        navigationController.present(hostingController, animated: true)
    }

}

// MARK: - LoginViewModelCoordinatorDelegate

extension AuthCoordinator: LoginViewModelCoordinatorDelegate {
    func loginViewModelDidLogin() {
        delegate?.authDidComplete()
    }

    func loginViewModelDidRequestJoinTenant() {
        showJoinTenant()
    }
}

// MARK: - LoginViewControllerDelegate

extension AuthCoordinator: LoginViewControllerDelegate {
    func loginDidRequestInviteCode() {
        showJoinTenant()
    }

    func loginDidRequestTotpVerify(email: String) {
        showTotpVerify(email: email)
    }

    func loginDidRequestOidc(provider: String) {
        let inviteCode = loginViewModel?.pendingInviteCode ?? ""
        let callbackScheme = "ssdid-drive"

        var urlString = "\(Constants.API.baseURL)/api/auth/oidc/\(provider)/authorize"
        urlString += "?redirect_uri=\(callbackScheme)://auth/callback"
        if !inviteCode.isEmpty {
            urlString += "&invitation_token=\(inviteCode.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? inviteCode)"
        }

        guard let url = URL(string: urlString) else { return }

        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: callbackScheme
        ) { [weak self] callbackURL, error in
            self?.authSession = nil

            if let error = error as? ASWebAuthenticationSessionError,
               error.code == .canceledLogin { return }

            guard let callbackURL = callbackURL else {
                self?.loginViewModel?.errorMessage = "Sign-in was cancelled or failed"
                return
            }

            let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
            let queryItems = components?.queryItems ?? []

            if let errorMsg = queryItems.first(where: { $0.name == "error" })?.value {
                self?.loginViewModel?.errorMessage = errorMsg
                return
            }

            if let token = queryItems.first(where: { $0.name == "token" })?.value, !token.isEmpty {
                self?.loginViewModel?.handleAuthCallback(sessionToken: token)
            } else {
                self?.loginViewModel?.errorMessage = "No session token received"
            }
        }

        session.presentationContextProvider = navigationController.topViewController as? ASWebAuthenticationPresentationContextProviding
        session.prefersEphemeralWebBrowserSession = true
        session.start()
        authSession = session
    }

    func loginDidRequestTenantRequest() {
        showTenantRequest()
    }
}

// MARK: - TotpVerifyViewModelCoordinatorDelegate

extension AuthCoordinator: TotpVerifyViewModelCoordinatorDelegate {
    func totpVerifyDidComplete() {
        delegate?.authDidComplete()
    }

    func totpVerifyDidRequestRecovery(email: String) {
        // TODO: Navigate to recovery flow if available
    }
}

// MARK: - InviteAcceptViewModelCoordinatorDelegate

extension AuthCoordinator: InviteAcceptViewModelCoordinatorDelegate {
    func inviteAcceptViewModelDidRegister() {
        inviteAcceptViewModel = nil
        delegate?.authDidComplete()
    }

    func inviteAcceptViewModelDidRequestLogin() {
        inviteAcceptViewModel = nil
        showLogin()
    }

    func inviteAcceptViewModelDidRequestEmailRegister(token: String) {
        // TODO: Navigate to email registration flow with invitation token
    }

    func inviteAcceptViewModelDidRequestOidc(provider: String, token: String) {
        let callbackScheme = "ssdid-drive"

        var urlString = "\(Constants.API.baseURL)/api/auth/oidc/\(provider)/authorize"
        urlString += "?redirect_uri=\(callbackScheme)://auth/callback"
        if !token.isEmpty {
            urlString += "&invitation_token=\(token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token)"
        }

        guard let url = URL(string: urlString) else { return }

        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: callbackScheme
        ) { [weak self] callbackURL, error in
            self?.authSession = nil

            if let error = error as? ASWebAuthenticationSessionError,
               error.code == .canceledLogin { return }

            guard let callbackURL = callbackURL else {
                self?.inviteAcceptViewModel?.registrationError = "Sign-in was cancelled or failed"
                return
            }

            let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
            let queryItems = components?.queryItems ?? []

            if let errorMsg = queryItems.first(where: { $0.name == "error" })?.value {
                self?.inviteAcceptViewModel?.registrationError = errorMsg
                return
            }

            if let sessionToken = queryItems.first(where: { $0.name == "token" })?.value, !sessionToken.isEmpty {
                self?.loginViewModel?.handleAuthCallback(sessionToken: sessionToken)
            } else {
                self?.inviteAcceptViewModel?.registrationError = "No session token received"
            }
        }

        session.presentationContextProvider = navigationController.topViewController as? ASWebAuthenticationPresentationContextProviding
        session.prefersEphemeralWebBrowserSession = true
        session.start()
        authSession = session
    }
}

// MARK: - JoinTenantViewModelDelegate

extension AuthCoordinator: JoinTenantViewModelDelegate {
    func joinTenantDidComplete() {
        navigationController.dismiss(animated: true)
    }

    func joinTenantDidRequestLogin(inviteCode: String) {
        navigationController.dismiss(animated: true) { [weak self] in
            guard let self else { return }
            // Store the pending invite code for auto-accept after authentication
            self.delegate?.authDidRequestLoginWithInvite(code: inviteCode)

            // Pass invite code to login view model so it's included in the wallet deeplink
            self.loginViewModel?.pendingInviteCode = inviteCode

            // Clear old deeplink so we wait for the NEW challenge that includes invite_code
            self.loginViewModel?.walletDeepLink = nil

            // Create a fresh challenge (with invite code in deeplink), then open wallet
            self.loginViewModel?.createChallenge()
            self.loginViewModel?.$walletDeepLink
                .compactMap { $0 }
                .first()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.loginViewModel?.openWallet()
                }
                .store(in: &self.cancellables)
        }
    }
}

// MARK: - TenantRequestViewModelDelegate

extension AuthCoordinator: TenantRequestViewModelDelegate {
    func tenantRequestDidComplete() {
        navigationController.dismiss(animated: true)
    }
}

// MARK: - Navigation Delegate Adapter

/// NSObject adapter for UINavigationControllerDelegate since BaseCoordinator
/// does not inherit from NSObject.
private final class NavigationDelegateAdapter: NSObject, UINavigationControllerDelegate {
    private let onDidShow: (UIViewController) -> Void

    init(onDidShow: @escaping (UIViewController) -> Void) {
        self.onDidShow = onDidShow
    }

    func navigationController(
        _ navigationController: UINavigationController,
        didShow viewController: UIViewController,
        animated: Bool
    ) {
        onDidShow(viewController)
    }
}
