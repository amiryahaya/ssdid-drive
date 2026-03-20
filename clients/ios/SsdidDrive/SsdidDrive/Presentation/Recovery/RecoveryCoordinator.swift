import UIKit

/// Delegate for recovery coordinator events
protocol RecoveryCoordinatorDelegate: AnyObject {
    /// Called after the recovery setup wizard completes successfully
    func recoveryCoordinatorDidCompleteSetup(_ coordinator: RecoveryCoordinator)
    /// Called after the recovery flow completes and the user has a new session token
    func recoveryCoordinatorDidCompleteRecovery(_ coordinator: RecoveryCoordinator, token: String)
    /// Called when the user cancels either flow
    func recoveryCoordinatorDidCancel(_ coordinator: RecoveryCoordinator)
}

/// Coordinator managing both the recovery setup wizard and the recovery (unlock) flow.
@MainActor
final class RecoveryCoordinator: BaseCoordinator {

    // MARK: - Properties

    weak var delegate: RecoveryCoordinatorDelegate?

    // MARK: - Start

    override func start() {
        // Default to the setup wizard; callers may override by calling showSetupWizard() or showRecoveryFlow().
        showSetupWizard()
    }

    // MARK: - Navigation

    /// Present the recovery setup wizard as a full-screen modal navigation stack.
    func showSetupWizard() {
        let viewModel = RecoverySetupViewModel(recoveryRepository: container.recoveryRepository)
        viewModel.coordinatorDelegate = self

        let viewController = RecoverySetupViewController(viewModel: viewModel)
        let nav = UINavigationController(rootViewController: viewController)
        nav.modalPresentationStyle = .fullScreen

        navigationController.present(nav, animated: true)
    }

    /// Push the recovery flow onto the existing navigation stack.
    /// Typically called from the login screen for locked-out users.
    func showRecoveryFlow() {
        let viewModel = RecoveryViewModel(recoveryRepository: container.recoveryRepository)
        viewModel.coordinatorDelegate = self

        let viewController = RecoveryViewController(viewModel: viewModel)
        navigationController.pushViewController(viewController, animated: true)
    }

    /// Present the recovery flow modally (alternative entry point from non-navigation contexts).
    func showRecoveryFlowModal() {
        let viewModel = RecoveryViewModel(recoveryRepository: container.recoveryRepository)
        viewModel.coordinatorDelegate = self

        let viewController = RecoveryViewController(viewModel: viewModel)
        let nav = UINavigationController(rootViewController: viewController)
        nav.modalPresentationStyle = .fullScreen

        navigationController.present(nav, animated: true)
    }
}

// MARK: - RecoverySetupViewModelCoordinatorDelegate

extension RecoveryCoordinator: RecoverySetupViewModelCoordinatorDelegate {
    func recoverySetupDidComplete() {
        // Dismiss the modal setup wizard
        navigationController.presentedViewController?.dismiss(animated: true) { [weak self] in
            guard let self else { return }
            self.delegate?.recoveryCoordinatorDidCompleteSetup(self)
            self.finish()
        }
    }

    func recoverySetupDidCancel() {
        navigationController.presentedViewController?.dismiss(animated: true) { [weak self] in
            guard let self else { return }
            self.delegate?.recoveryCoordinatorDidCancel(self)
            self.finish()
        }
    }

    func recoverySetupDidRequestTrusteeSelection(totalShares: Int, masterKey: Data) {
        // Trustee selection from recovery coordinator context — not used in this flow.
        // The recovery setup wizard (files-based) does not branch into trustee selection.
    }
}

// MARK: - RecoveryViewModelCoordinatorDelegate

extension RecoveryCoordinator: RecoveryViewModelCoordinatorDelegate {
    func recoveryDidComplete(token: String) {
        // If pushed: pop back
        if navigationController.presentedViewController == nil {
            navigationController.popViewController(animated: true)
        } else {
            navigationController.presentedViewController?.dismiss(animated: true)
        }
        delegate?.recoveryCoordinatorDidCompleteRecovery(self, token: token)
        finish()
    }

    func recoveryDidCancel() {
        if navigationController.presentedViewController == nil {
            navigationController.popViewController(animated: true)
        } else {
            navigationController.presentedViewController?.dismiss(animated: true)
        }
        delegate?.recoveryCoordinatorDidCancel(self)
        finish()
    }
}
