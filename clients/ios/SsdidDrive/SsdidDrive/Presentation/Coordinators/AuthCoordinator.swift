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

    /// Pending invite code to process after authentication
    private(set) var pendingInviteCode: String?
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
}

// MARK: - JoinTenantViewModelDelegate

extension AuthCoordinator: JoinTenantViewModelDelegate {
    func joinTenantDidComplete() {
        navigationController.dismiss(animated: true)
    }

    func joinTenantDidRequestLogin(inviteCode: String) {
        pendingInviteCode = inviteCode
        navigationController.dismiss(animated: true) { [weak self] in
            // The user needs to authenticate first, then the invite will be auto-accepted.
            // Store the pending code for the app coordinator to process after auth.
            self?.delegate?.authDidRequestLoginWithInvite(code: inviteCode)
        }
    }
}
