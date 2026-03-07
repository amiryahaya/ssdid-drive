import UIKit

/// Delegate for auth coordinator events
protocol AuthCoordinatorDelegate: AnyObject {
    func authDidComplete()
    func authDidRequestLogout()
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
}

// MARK: - LoginViewModelCoordinatorDelegate

extension AuthCoordinator: LoginViewModelCoordinatorDelegate {
    func loginViewModelDidLogin() {
        delegate?.authDidComplete()
    }
}
