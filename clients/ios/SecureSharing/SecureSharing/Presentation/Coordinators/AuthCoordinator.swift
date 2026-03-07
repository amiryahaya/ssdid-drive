import UIKit

/// Delegate for auth coordinator events
protocol AuthCoordinatorDelegate: AnyObject {
    func authDidComplete()
    func authDidRequestLogout()
}

/// Coordinator for authentication flow (login, register, invitation)
final class AuthCoordinator: BaseCoordinator {

    // MARK: - Properties

    weak var delegate: AuthCoordinatorDelegate?
    private var pendingInviteToken: String?

    // MARK: - Start

    override func start() {
        showLogin()
    }

    // MARK: - Navigation

    func showLogin() {
        let viewModel = LoginViewModel(authRepository: container.authRepository)
        viewModel.coordinatorDelegate = self

        let oidcViewModel = OidcLoginViewModel(oidcRepository: container.oidcRepository)
        oidcViewModel.delegate = self

        let passkeyViewModel = PasskeyLoginViewModel(webAuthnRepository: container.webAuthnRepository)
        passkeyViewModel.delegate = self

        let loginVC = LoginViewController(
            viewModel: viewModel,
            oidcViewModel: oidcViewModel,
            passkeyViewModel: passkeyViewModel
        )
        navigationController.setViewControllers([loginVC], animated: true)
    }

    func showRegister() {
        let viewModel = RegisterViewModel(authRepository: container.authRepository)
        viewModel.coordinatorDelegate = self

        let registerVC = RegisterViewController(viewModel: viewModel)
        navigationController.pushViewController(registerVC, animated: true)
    }

    func showInviteAccept(token: String) {
        let viewModel = InviteAcceptViewModel(authRepository: container.authRepository, token: token)
        viewModel.coordinatorDelegate = self

        let inviteVC = InviteAcceptViewController(viewModel: viewModel)
        navigationController.setViewControllers([inviteVC], animated: true)
    }

    func showOidcRegister(keyMaterial: String, keySalt: String) {
        let viewModel = OidcRegisterViewModel(
            oidcRepository: container.oidcRepository,
            keyManager: container.keyManager,
            keyMaterial: keyMaterial,
            keySalt: keySalt
        )
        viewModel.coordinatorDelegate = self

        let oidcRegisterVC = OidcRegisterViewController(viewModel: viewModel)
        navigationController.pushViewController(oidcRegisterVC, animated: true)
    }

    /// Handle invitation deep link
    func handleInvitation(token: String) {
        showInviteAccept(token: token)
    }
}

// MARK: - LoginViewModelCoordinatorDelegate

extension AuthCoordinator: LoginViewModelCoordinatorDelegate {
    func loginViewModelDidRequestRegister() {
        showRegister()
    }

    func loginViewModelDidLogin() {
        delegate?.authDidComplete()
    }
}

// MARK: - RegisterViewModelCoordinatorDelegate

extension AuthCoordinator: RegisterViewModelCoordinatorDelegate {
    func registerViewModelDidRequestLogin() {
        navigationController.popViewController(animated: true)
    }

    func registerViewModelDidRegister() {
        delegate?.authDidComplete()
    }
}

// MARK: - OidcLoginViewModelDelegate

extension AuthCoordinator: OidcLoginViewModelDelegate {
    func oidcLoginDidComplete() {
        delegate?.authDidComplete()
    }

    func oidcLoginDidRequireRegistration(keyMaterial: String, keySalt: String) {
        showOidcRegister(keyMaterial: keyMaterial, keySalt: keySalt)
    }
}

// MARK: - PasskeyLoginViewModelDelegate

extension AuthCoordinator: PasskeyLoginViewModelDelegate {
    func passkeyLoginDidComplete() {
        delegate?.authDidComplete()
    }
}

// MARK: - OidcRegisterViewModelCoordinatorDelegate

extension AuthCoordinator: OidcRegisterViewModelCoordinatorDelegate {
    func oidcRegisterViewModelDidComplete() {
        delegate?.authDidComplete()
    }
}

// MARK: - InviteAcceptViewModelCoordinatorDelegate

extension AuthCoordinator: InviteAcceptViewModelCoordinatorDelegate {
    func inviteAcceptViewModelDidRegister() {
        delegate?.authDidComplete()
    }

    func inviteAcceptViewModelDidRequestLogin() {
        showLogin()
    }
}
