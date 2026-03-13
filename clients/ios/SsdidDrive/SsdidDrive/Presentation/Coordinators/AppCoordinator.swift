import UIKit

/// Main app coordinator that manages the root navigation flow.
///
/// The AppCoordinator manages the following navigation states:
/// - **Onboarding**: First-time user experience (if not completed)
/// - **Authentication**: Login/registration flow (if not authenticated)
/// - **Lock Screen**: Biometric unlock (if enabled and keys are locked)
/// - **Main**: Primary app experience with tab bar navigation
///
/// State transitions:
/// ```
/// start() -> determineInitialFlow()
///         -> showOnboarding() -> onboardingDidComplete() -> showAuth()
///         -> showAuth() -> authDidComplete() -> showMain()
///         -> showLockScreen() -> lockViewControllerDidUnlock() -> (remains on main)
/// ```
///
/// Deep links are processed immediately if authenticated, or deferred until after
/// authentication completes (except import actions which expire).
final class AppCoordinator: BaseCoordinator {

    // MARK: - Properties

    private var isShowingLock = false

    /// Active async task for cancellation on dealloc
    private var activeTask: Task<Void, Never>?

    // MARK: - Deinit

    deinit {
        activeTask?.cancel()
    }

    // MARK: - Start

    override func start() {
        determineInitialFlow()
    }

    // MARK: - Flow Determination

    private func determineInitialFlow() {
        activeTask?.cancel()
        activeTask = Task {
            guard !Task.isCancelled else { return }

            let settings = container.userDefaultsManager

            // Check onboarding
            if !settings.hasCompletedOnboarding {
                await MainActor.run {
                    showOnboarding()
                }
                return
            }

            guard !Task.isCancelled else { return }

            // Check authentication
            let isAuthenticated = await container.authRepository.isAuthenticated()
            if !isAuthenticated {
                await MainActor.run {
                    showAuth()
                }
                return
            }

            guard !Task.isCancelled else { return }

            // Check if lock screen needed
            let biometricEnabled = await container.authRepository.isBiometricUnlockEnabled()
            let keysUnlocked = await container.authRepository.areKeysUnlocked()

            guard !Task.isCancelled else { return }

            await MainActor.run {
                if biometricEnabled && !keysUnlocked {
                    showLockScreen()
                } else {
                    showMain()
                }
            }
        }
    }

    // MARK: - Flow Navigation

    private func showOnboarding() {
        let coordinator = OnboardingCoordinator(
            navigationController: navigationController,
            container: container
        )
        coordinator.delegate = self
        addChild(coordinator)
        coordinator.start()
    }

    private func showAuth() {
        let coordinator = AuthCoordinator(
            navigationController: navigationController,
            container: container
        )
        coordinator.delegate = self
        addChild(coordinator)
        coordinator.start()
    }

    func showLockScreen() {
        guard !isShowingLock else { return }
        isShowingLock = true

        let viewModel = LockViewModel(
            authRepository: container.authRepository,
            keychainManager: container.keychainManager
        )

        let lockVC = LockViewController(viewModel: viewModel)
        lockVC.delegate = self
        lockVC.modalPresentationStyle = .fullScreen

        if let presented = navigationController.presentedViewController {
            presented.dismiss(animated: false) { [weak self] in
                self?.navigationController.present(lockVC, animated: true)
            }
        } else {
            navigationController.present(lockVC, animated: true)
        }
    }

    private func showMain() {
        let coordinator = MainCoordinator(
            navigationController: navigationController,
            container: container
        )
        coordinator.delegate = self
        addChild(coordinator)
        coordinator.start()

        // Cleanup old notifications (runs in background)
        Task {
            do {
                try await container.notificationRepository.cleanupOldNotifications(daysOld: 30)
            } catch {
                #if DEBUG
                print("AppCoordinator: Failed to cleanup old notifications - \(error)")
                #endif
            }
        }
    }

    // MARK: - Deep Links

    /// Handle a deep link URL
    /// - Parameter url: The URL to handle (custom scheme or Universal Link)
    func handleDeepLink(_ url: URL) {
        guard let action = DeepLinkParser.parse(url) else {
            return
        }

        handleDeepLinkAction(action)
    }

    /// Handle a parsed deep link action
    /// - Parameter action: The action to handle
    func handleDeepLinkAction(_ action: DeepLinkAction) {
        // Check if user is authenticated
        activeTask?.cancel()
        activeTask = Task {
            guard !Task.isCancelled else { return }

            let isAuthenticated = await container.authRepository.isAuthenticated()

            guard !Task.isCancelled else { return }

            await MainActor.run {
                if isAuthenticated {
                    // User is authenticated, process immediately
                    processDeepLinkAction(action)
                } else {
                    // Save for later processing after auth (except import which expires)
                    savePendingDeepLinkIfAppropriate(action)

                    // If it's an invitation, still show auth flow with invitation
                    if case .acceptInvitation(let token) = action {
                        handleInvitationDeepLink(token: token)
                    }
                }
            }
        }
    }

    /// Process a deep link action (user must be authenticated)
    private func processDeepLinkAction(_ action: DeepLinkAction) {
        switch action {
        case .openShare(let shareId):
            if let mainCoordinator = childCoordinators.first(where: { $0 is MainCoordinator }) as? MainCoordinator {
                mainCoordinator.showShareDetail(shareId: shareId)
            }

        case .openFile(let fileId):
            if let mainCoordinator = childCoordinators.first(where: { $0 is MainCoordinator }) as? MainCoordinator {
                mainCoordinator.showFilePreview(fileId: fileId)
            }

        case .openFolder(let folderId):
            if let mainCoordinator = childCoordinators.first(where: { $0 is MainCoordinator }) as? MainCoordinator {
                mainCoordinator.showFolder(folderId: folderId)
            }

        case .acceptInvitation(let token):
            handleInvitationDeepLink(token: token)

        case .importFiles(let manifest):
            if let mainCoordinator = childCoordinators.first(where: { $0 is MainCoordinator }) as? MainCoordinator {
                mainCoordinator.showImportFlow(manifest: manifest)
            }

        case .authCallback(let sessionToken):
            // Deliver to the active AuthCoordinator's login view model
            if let authCoordinator = childCoordinators.first(where: { $0 is AuthCoordinator }) as? AuthCoordinator {
                authCoordinator.loginViewModel?.handleAuthCallback(sessionToken: sessionToken)
            }

        case .walletInviteCallback(let sessionToken):
            // Deliver to active invite accept screen via AuthCoordinator
            if let authCoordinator = childCoordinators.first(where: { $0 is AuthCoordinator }) as? AuthCoordinator {
                authCoordinator.inviteAcceptViewModel?.handleWalletCallback(sessionToken: sessionToken)
            }

        case .walletInviteError(let message):
            if let authCoordinator = childCoordinators.first(where: { $0 is AuthCoordinator }) as? AuthCoordinator {
                authCoordinator.inviteAcceptViewModel?.handleWalletError(message: message)
            }
        }
    }

    /// Save pending deep link for processing after authentication
    private func savePendingDeepLinkIfAppropriate(_ action: DeepLinkAction) {
        // Don't save import actions - files may expire in App Group
        if case .importFiles = action {
            DeepLinkParser.cleanupImportFiles()
            return
        }

        container.userDefaultsManager.savePendingDeepLink(action)
    }

    /// Process any pending deep link after authentication
    private func processPendingDeepLink() {
        guard let action = container.userDefaultsManager.consumePendingDeepLink() else {
            return
        }

        processDeepLinkAction(action)
    }

    /// Handle invitation deep link - navigate directly to invitation acceptance
    private func handleInvitationDeepLink(token: String) {
        // Double-check token validation before processing
        guard DeepLinkParser.isValidInvitationToken(token) else {
            return
        }

        // Clear existing coordinators and show invitation screen
        clearChildCoordinators()
        navigationController.setViewControllers([], animated: false)

        // Create auth coordinator and show invitation screen
        let coordinator = AuthCoordinator(
            navigationController: navigationController,
            container: container
        )
        coordinator.delegate = self
        addChild(coordinator)
        coordinator.handleInvitation(token: token)
    }

}

// MARK: - OnboardingCoordinatorDelegate

extension AppCoordinator: OnboardingCoordinatorDelegate {
    func onboardingDidComplete() {
        // Clear previous coordinator hierarchy and navigation stack before transitioning
        // to ensure clean state for the next flow
        clearChildCoordinators()
        navigationController.setViewControllers([], animated: false)
        showAuth()
    }
}

// MARK: - AuthCoordinatorDelegate

extension AppCoordinator: AuthCoordinatorDelegate {
    func authDidComplete() {
        clearChildCoordinators()
        navigationController.setViewControllers([], animated: false)

        // D7: Associate OneSignal device with the authenticated user
        if let userId = container.authRepository.currentUserId,
           let appDelegate = UIApplication.shared.delegate as? AppDelegate {
            appDelegate.loginOneSignal(userId: userId)
        }

        // D3: Request push permission after login (only prompts if not already granted)
        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
            appDelegate.requestPushPermissionIfNeeded()
        }

        // Use CATransaction to ensure navigation is complete before processing deep link
        // This is more deterministic than an arbitrary delay
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            self?.processPendingDeepLink()
        }
        showMain()
        CATransaction.commit()
    }

    func authDidRequestLogout() {
        // Clear any pending deep link on logout
        container.userDefaultsManager.clearPendingDeepLink()

        clearChildCoordinators()
        navigationController.setViewControllers([], animated: false)
        showAuth()
    }

    func authDidRequestLoginWithInvite(code: String) {
        // Store the invite code so it can be auto-accepted after auth completes.
        // The user will be shown the login screen and after authentication,
        // the invite code will be processed.
        container.userDefaultsManager.pendingInviteCode = code
    }
}

// MARK: - LockViewControllerDelegate

extension AppCoordinator: LockViewControllerDelegate {
    func lockViewControllerDidUnlock() {
        isShowingLock = false
        navigationController.dismiss(animated: true)
    }
}

// MARK: - MainCoordinatorDelegate

extension AppCoordinator: MainCoordinatorDelegate {
    func mainCoordinatorDidRequestLogout() {
        clearChildCoordinators()
        navigationController.setViewControllers([], animated: false)
        showAuth()
    }
}
