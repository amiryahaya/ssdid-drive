import UIKit
import CoreSpotlight

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    // MARK: - Properties

    var window: UIWindow?
    private var appCoordinator: AppCoordinator?

    // Background tracking for auto-lock
    private var backgroundTimestamp: Date?

    // NotificationCenter observers for proper cleanup
    private var pushNotificationObserver: NSObjectProtocol?
    private var lockAppObserver: NSObjectProtocol?
    private var logoutObserver: NSObjectProtocol?

    // MARK: - Scene Lifecycle

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        // Configure window for macOS (sizing, toolbar)
        #if targetEnvironment(macCatalyst)
        WindowManager.shared.configureMainWindow(windowScene)
        #endif

        // M2: Write initial sync status as syncing (not connected) — actual connection
        // is confirmed when FileBrowserViewModel successfully loads data
        SharedDefaults.shared.writeSyncStatus(.syncing)
        SharedDefaults.shared.notifyHelper()

        // Create window
        let window = UIWindow(windowScene: windowScene)
        self.window = window

        // Enable screen capture protection in release
        #if !DEBUG
        window.makeSecure()
        #endif

        // Create and start app coordinator
        let navigationController = UINavigationController()
        navigationController.setNavigationBarHidden(true, animated: false)

        appCoordinator = AppCoordinator(
            navigationController: navigationController,
            container: DependencyContainer.shared
        )

        window.rootViewController = navigationController
        window.makeKeyAndVisible()

        // Start the app flow
        appCoordinator?.start()

        // Observe push notification taps (using block-based API for proper lifecycle management)
        pushNotificationObserver = NotificationCenter.default.addObserver(
            forName: .didTapPushNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handlePushNotificationTap(notification)
        }

        // Observe lock app request from macOS menu/keyboard shortcut
        lockAppObserver = NotificationCenter.default.addObserver(
            forName: .lockAppRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleLockAppRequest()
        }

        // H3: Observe logout from other scenes so all windows return to lock/login
        logoutObserver = NotificationCenter.default.addObserver(
            forName: .userDidLogout,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleLockAppRequest()
        }

        // Handle deep links from launch (custom scheme)
        if let urlContext = connectionOptions.urlContexts.first {
            handleDeepLink(urlContext.url)
        }

        // D6: Iterate all user activities, not just the first one
        for userActivity in connectionOptions.userActivities {
            // Handle Spotlight search result from launch (app was killed)
            if userActivity.activityType == CSSearchableItemActionType,
               let uniqueIdentifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
               uniqueIdentifier.hasPrefix("file_") {
                let fileId = String(uniqueIdentifier.dropFirst(5))
                appCoordinator?.handleDeepLinkAction(.openFile(fileId: fileId))
            }

            // Handle Universal Links from launch
            if userActivity.activityType == NSUserActivityTypeBrowsingWeb,
               let url = userActivity.webpageURL {
                handleDeepLink(url)
            }
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        // Handle deep links when app is running
        if let url = URLContexts.first?.url {
            handleDeepLink(url)
        }
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        // Handle Spotlight search result taps
        if userActivity.activityType == CSSearchableItemActionType,
           let uniqueIdentifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
           uniqueIdentifier.hasPrefix("file_") {
            let fileId = String(uniqueIdentifier.dropFirst(5))
            appCoordinator?.handleDeepLinkAction(.openFile(fileId: fileId))
            return
        }

        // Handle Universal Links (HTTPS deep links)
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else {
            return
        }

        handleDeepLink(url)
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Remove notification observers to prevent memory leaks
        if let observer = pushNotificationObserver {
            NotificationCenter.default.removeObserver(observer)
            pushNotificationObserver = nil
        }
        if let observer = lockAppObserver {
            NotificationCenter.default.removeObserver(observer)
            lockAppObserver = nil
        }
        if let observer = logoutObserver {
            NotificationCenter.default.removeObserver(observer)
            logoutObserver = nil
        }
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Check auto-lock when returning to foreground
        checkAutoLock()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move to an inactive state
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Record background timestamp for auto-lock
        backgroundTimestamp = Date()

        // L5: Update sync status to offline when app is backgrounded
        SharedDefaults.shared.writeSyncStatus(.offline)
        SharedDefaults.shared.notifyHelper()
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called when scene transitions from background to foreground
    }

    // MARK: - Deep Links

    private func handleDeepLink(_ url: URL) {
        // C3: Resolve pending action tokens from MenuBarHelper before passing to coordinator.
        // ssdid-drive://action/{token} carries an opaque token instead of raw file IDs.
        if url.scheme == "ssdid-drive", url.host == "action",
           let token = url.pathComponents.last, token != "/" {
            guard let action = SharedDefaults.shared.readAndClearPendingAction(token: token) else {
                return // expired or unknown token — silently ignore
            }
            switch action.type {
            case .openFile:
                if let id = action.resourceId {
                    appCoordinator?.handleDeepLinkAction(.openFile(fileId: id))
                }
            case .openFolder:
                if let id = action.resourceId {
                    appCoordinator?.handleDeepLinkAction(.openFolder(folderId: id))
                }
            case .importFile:
                // Trigger the upload flow — the coordinator will show a file picker
                appCoordinator?.handleDeepLink(URL(string: "ssdid-drive://import")!)
            case .openApp:
                break // just bringing the app to front is sufficient
            }
            return
        }
        // Handle SSDID auth callback: ssdid-drive://auth/callback?session_token=...
        if let action = DeepLinkParser.parse(url), case .authCallback(let sessionToken) = action {
            handleAuthCallback(sessionToken: sessionToken)
            return
        }

        appCoordinator?.handleDeepLink(url)
    }

    /// Deliver auth callback token to the active LoginViewModel via the AuthCoordinator.
    /// D5: Only accepts callbacks when the login screen is actively waiting for one.
    private func handleAuthCallback(sessionToken: String) {
        guard let coordinator = appCoordinator else { return }
        // Find the AuthCoordinator in the child hierarchy
        guard let authCoordinator = coordinator.childCoordinators.first(where: { $0 is AuthCoordinator }) as? AuthCoordinator,
              let loginViewModel = authCoordinator.loginViewModel else {
            // No active login flow — ignore the callback to prevent URL scheme hijacking
            return
        }
        loginViewModel.handleAuthCallback(sessionToken: sessionToken)
    }

    // MARK: - Push Notifications

    private func handlePushNotificationTap(_ notification: Notification) {
        guard let appNotification = notification.object as? AppNotification else { return }

        // Navigate based on notification action
        if let action = appNotification.action {
            switch action.type {
            case .openShare:
                if let shareId = action.resourceId {
                    appCoordinator?.handleDeepLinkAction(.openShare(shareId: shareId))
                }
            case .openFile:
                if let fileId = action.resourceId {
                    appCoordinator?.handleDeepLinkAction(.openFile(fileId: fileId))
                }
            case .openFolder:
                if let folderId = action.resourceId {
                    appCoordinator?.handleDeepLinkAction(.openFolder(folderId: folderId))
                }
            case .openRecovery, .openSettings:
                // Navigate to notifications tab where user can see the notification
                if let mainCoordinator = appCoordinator?.childCoordinators.first(where: { $0 is MainCoordinator }) as? MainCoordinator {
                    mainCoordinator.showNotifications()
                }
            case .none:
                // Navigate to notifications tab
                if let mainCoordinator = appCoordinator?.childCoordinators.first(where: { $0 is MainCoordinator }) as? MainCoordinator {
                    mainCoordinator.showNotifications()
                }
            }
        } else {
            // No specific action, navigate to notifications tab
            if let mainCoordinator = appCoordinator?.childCoordinators.first(where: { $0 is MainCoordinator }) as? MainCoordinator {
                mainCoordinator.showNotifications()
            }
        }
    }

    // MARK: - Lock App (macOS Menu/Shortcut)

    private func handleLockAppRequest() {
        let container = DependencyContainer.shared
        Task {
            await container.authRepository.lockKeys()
            await MainActor.run {
                appCoordinator?.showLockScreen()
            }
        }
    }

    // MARK: - Auto Lock

    private func checkAutoLock() {
        guard let timestamp = backgroundTimestamp else { return }

        let container = DependencyContainer.shared
        let settings = container.userDefaultsManager

        guard settings.autoLockEnabled,
              settings.biometricEnabled else { return }

        let timeout = settings.autoLockTimeout
        let elapsed = Date().timeIntervalSince(timestamp)
        let timeoutSeconds = TimeInterval(timeout.minutes * 60)

        if timeout.minutes >= 0 && elapsed >= timeoutSeconds {
            // Lock the app
            Task {
                await container.authRepository.lockKeys()
                await MainActor.run {
                    appCoordinator?.showLockScreen()
                }
            }
        }

        backgroundTimestamp = nil
    }
}

// MARK: - Screen Capture Protection

extension UIWindow {
    func makeSecure() {
        let field = UITextField()
        field.isSecureTextEntry = true
        self.addSubview(field)
        field.centerYAnchor.constraint(equalTo: self.centerYAnchor).isActive = true
        field.centerXAnchor.constraint(equalTo: self.centerXAnchor).isActive = true
        self.layer.superlayer?.addSublayer(field.layer)
        field.layer.sublayers?.first?.addSublayer(self.layer)
    }
}
