import UIKit
import SwiftUI

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

    /// Reference to the current login view model so the SceneDelegate can
    /// deliver auth callback tokens to it.
    private(set) var loginViewModel: LoginViewModel?

    /// Reference to the current invite accept view model so wallet callbacks
    /// can be delivered to it.
    private(set) var inviteAcceptViewModel: InviteAcceptViewModel?

    /// Navigation delegate adapter for cleaning up invite ViewModel on back-swipe
    private var navDelegateAdapter: NavigationDelegateAdapter?

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
            sheet.detents = [.medium(), .large()]
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
        // TODO: Launch ASWebAuthenticationSession for OIDC provider
        let alert = UIAlertController(
            title: "\(provider.capitalized) Sign In",
            message: "OIDC sign-in with \(provider.capitalized) is coming soon.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        navigationController.present(alert, animated: true)
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
        // TODO: Navigate to OIDC authentication flow with provider and invitation token
    }
}

// MARK: - JoinTenantViewModelDelegate

extension AuthCoordinator: JoinTenantViewModelDelegate {
    func joinTenantDidComplete() {
        navigationController.dismiss(animated: true)
    }

    func joinTenantDidRequestLogin(inviteCode: String) {
        navigationController.dismiss(animated: true) { [weak self] in
            // The user needs to authenticate first, then the invite will be auto-accepted.
            // Store the pending code for the app coordinator to process after auth.
            self?.delegate?.authDidRequestLoginWithInvite(code: inviteCode)
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
