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

    /// Handle invitation deep link (kept for compatibility)
    func handleInvitation(token: String) {
        // Invitations now go through the wallet flow as well.
        // Show the standard QR login screen; the invitation will be
        // processed after authentication completes.
        showLogin()
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
