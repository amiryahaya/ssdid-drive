import UIKit
import SwiftUI

/// Delegate for settings coordinator events
protocol SettingsCoordinatorDelegate: AnyObject {
    func settingsCoordinatorDidRequestLogout()
    func settingsCoordinatorDidSwitchTenant()
}

/// Coordinator for settings flow
final class SettingsCoordinator: BaseCoordinator {

    // MARK: - Properties

    weak var delegate: SettingsCoordinatorDelegate?

    // MARK: - Start

    override func start() {
        showSettings()
    }

    // MARK: - Navigation

    func showSettings() {
        let viewModel = SettingsViewModel(
            authRepository: container.authRepository,
            tenantRepository: container.tenantRepository,
            userDefaultsManager: container.userDefaultsManager
        )
        viewModel.coordinatorDelegate = self

        let settingsVC = SettingsViewController(viewModel: viewModel)
        navigationController.setViewControllers([settingsVC], animated: false)
    }

    func showTenantSwitcher() {
        let viewModel = TenantSwitcherViewModel(tenantRepository: container.tenantRepository)
        viewModel.onTenantSwitched = { [weak self] _ in
            self?.delegate?.settingsCoordinatorDidSwitchTenant()
        }

        let tenantSwitcherView = TenantSwitcherView(viewModel: viewModel)
        let hostingController = UIHostingController(rootView: tenantSwitcherView)

        if let sheet = hostingController.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }

        navigationController.present(hostingController, animated: true)
    }

    func showRecoverySetup() {
        let viewModel = RecoverySetupViewModel(recoveryRepository: container.recoveryRepository)
        viewModel.coordinatorDelegate = self

        let recoveryVC = RecoverySetupViewController(viewModel: viewModel)
        navigationController.pushViewController(recoveryVC, animated: true)
    }

    func showTrusteeSelection(totalShares: Int) {
        let viewModel = TrusteeSelectionViewModel(
            totalShares: totalShares,
            recoveryRepository: container.recoveryRepository
        )
        viewModel.coordinatorDelegate = self

        let trusteeVC = TrusteeSelectionViewController(viewModel: viewModel)
        navigationController.pushViewController(trusteeVC, animated: true)
    }

    func showTrusteeDashboard() {
        let viewModel = PendingRequestsViewModel(recoveryRepository: container.recoveryRepository)

        let dashboardVC = PendingRequestsViewController(viewModel: viewModel)
        navigationController.pushViewController(dashboardVC, animated: true)
    }

    func showInitiateRecovery() {
        let viewModel = InitiateRecoveryViewModel(recoveryRepository: container.recoveryRepository)
        viewModel.coordinatorDelegate = self

        let recoveryVC = InitiateRecoveryViewController(viewModel: viewModel)
        navigationController.pushViewController(recoveryVC, animated: true)
    }

    func showDevices() {
        let viewModel = DevicesViewModel(authRepository: container.authRepository)

        let devicesVC = DevicesViewController(viewModel: viewModel)
        navigationController.pushViewController(devicesVC, animated: true)
    }

    func showInvitations() {
        let viewModel = InvitationsViewModel(shareRepository: container.shareRepository)

        let invitationsVC = InvitationsViewController(viewModel: viewModel)
        navigationController.pushViewController(invitationsVC, animated: true)
    }

    func showCredentials() {
        // Credential management (WebAuthn/OIDC) has been removed.
        // Authentication is now handled via SSDID wallet.
    }

    func showJoinTenant() {
        let viewModel = JoinTenantViewModel(
            apiClient: container.apiClient,
            tenantRepository: container.tenantRepository
        )
        viewModel.delegate = self

        let joinTenantView = JoinTenantView(viewModel: viewModel)
        let hostingController = UIHostingController(rootView: joinTenantView)

        if let sheet = hostingController.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }

        navigationController.present(hostingController, animated: true)
    }

    func showRequestTenant() {
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

    func showInvitationsList() {
        let viewModel = InvitationsListViewModel(apiClient: container.apiClient)

        let invitationsListView = InvitationsListView(viewModel: viewModel)
        let hostingController = UIHostingController(rootView: invitationsListView)

        if let sheet = hostingController.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }

        navigationController.present(hostingController, animated: true)
    }

    func showCreateInvitation() {
        let callerRole = getCurrentTenantRole()
        let viewModel = CreateInvitationViewModel(
            apiClient: container.apiClient,
            callerRole: callerRole
        )

        let createInvitationView = CreateInvitationView(viewModel: viewModel)
        let hostingController = UIHostingController(rootView: createInvitationView)

        if let sheet = hostingController.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }

        navigationController.present(hostingController, animated: true)
    }

    func showMembers() {
        guard let tenantId = container.tenantRepository.currentTenantId else { return }

        let callerRole = getCurrentTenantRole()
        let currentUserId = container.keychainManager.userId

        let viewModel = MembersViewModel(
            apiClient: container.apiClient,
            tenantId: tenantId,
            callerRole: callerRole,
            currentUserId: currentUserId
        )

        let membersView = MembersView(viewModel: viewModel)
        let hostingController = UIHostingController(rootView: membersView)

        if let sheet = hostingController.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }

        navigationController.present(hostingController, animated: true)
    }

    // MARK: - Helpers

    private func getCurrentTenantRole() -> UserRole {
        if let roleString = container.keychainManager.currentRole,
           let role = UserRole(rawValue: roleString) {
            return role
        }
        return .member
    }
}

// MARK: - SettingsViewModelCoordinatorDelegate

extension SettingsCoordinator: SettingsViewModelCoordinatorDelegate {
    func settingsDidRequestRecoverySetup() {
        showRecoverySetup()
    }

    func settingsDidRequestTrusteeDashboard() {
        showTrusteeDashboard()
    }

    func settingsDidRequestInitiateRecovery() {
        showInitiateRecovery()
    }

    func settingsDidRequestDevices() {
        showDevices()
    }

    func settingsDidRequestInvitations() {
        showInvitations()
    }

    func settingsDidRequestInvitationsList() {
        showInvitationsList()
    }

    func settingsDidRequestCreateInvitation() {
        showCreateInvitation()
    }

    func settingsDidRequestMembers() {
        showMembers()
    }

    func settingsDidRequestCredentials() {
        showCredentials()
    }

    func settingsDidRequestTenantSwitcher() {
        showTenantSwitcher()
    }

    func settingsDidRequestJoinTenant() {
        showJoinTenant()
    }

    func settingsDidRequestRequestTenant() {
        showRequestTenant()
    }

    func settingsDidRequestLogout() {
        delegate?.settingsCoordinatorDidRequestLogout()
    }
}

// MARK: - RecoverySetupViewModelCoordinatorDelegate

extension SettingsCoordinator: RecoverySetupViewModelCoordinatorDelegate {
    func recoverySetupDidRequestTrusteeSelection(totalShares: Int) {
        showTrusteeSelection(totalShares: totalShares)
    }
}

// MARK: - TrusteeSelectionViewModelCoordinatorDelegate

extension SettingsCoordinator: TrusteeSelectionViewModelCoordinatorDelegate {
    func trusteeSelectionDidComplete() {
        // Pop back to settings
        if let settingsVC = navigationController.viewControllers.first(where: { $0 is SettingsViewController }) {
            navigationController.popToViewController(settingsVC, animated: true)
        }
    }
}

// MARK: - InitiateRecoveryViewModelCoordinatorDelegate

extension SettingsCoordinator: InitiateRecoveryViewModelCoordinatorDelegate {
    func initiateRecoveryDidComplete() {
        delegate?.settingsCoordinatorDidRequestLogout()
    }
}

// MARK: - JoinTenantViewModelDelegate

extension SettingsCoordinator: JoinTenantViewModelDelegate {
    func joinTenantDidComplete() {
        navigationController.dismiss(animated: true) { [weak self] in
            self?.delegate?.settingsCoordinatorDidSwitchTenant()
        }
    }

    func joinTenantDidRequestLogin(inviteCode: String) {
        // Authenticated flow only in settings, so this is a no-op.
        // The unauthenticated flow is handled by AuthCoordinator.
    }
}

// MARK: - TenantRequestViewModelDelegate

extension SettingsCoordinator: TenantRequestViewModelDelegate {
    func tenantRequestDidComplete() {
        navigationController.dismiss(animated: true)
    }
}
