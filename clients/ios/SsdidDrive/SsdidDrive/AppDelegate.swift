import UIKit
import os.log
#if canImport(OneSignalFramework)
import OneSignalFramework
#endif
#if canImport(Sentry)
import Sentry
#endif

private let logger = Logger(subsystem: "my.ssdid.drive", category: "AppDelegate")

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    // MARK: - Properties

    var window: UIWindow?

    /// Stored launch options to pass to OneSignal on initialization
    private var storedLaunchOptions: [UIApplication.LaunchOptionsKey: Any]?

    // MARK: - Application Lifecycle

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Initialize Sentry crash reporting early
        SentryConfig.shared.initialize()

        // Security check - refuse to run on jailbroken devices
        performSecurityCheck()

        // D10: Validate SSL pinning is configured for production builds
        #if !DEBUG
        if !Constants.API.isSSLPinningConfigured {
            logger.critical("SSL certificate pinning is not configured — placeholder hashes detected. Replace with real certificate hashes before release.")
            assertionFailure("SSL pinning not configured for production")
        }
        #endif

        // Store launch options for OneSignal (D1)
        storedLaunchOptions = launchOptions

        // Configure push notifications with OneSignal
        configureOneSignal(launchOptions: launchOptions)

        // Configure appearance
        configureAppearance()

        return true
    }

    // MARK: - OneSignal Configuration

    private func configureOneSignal(launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        #if canImport(OneSignalFramework)
        // SECURITY: Use WARN level even in debug to prevent sensitive push data in logs
        #if DEBUG
        OneSignal.Debug.setLogLevel(.LL_WARN)
        #endif

        // Initialize OneSignal with app ID and actual launch options (D1)
        OneSignal.initialize(Constants.OneSignal.appId, withLaunchOptions: launchOptions)

        // Set notification lifecycle listener
        OneSignal.Notifications.addForegroundLifecycleListener(self)

        // Set notification click listener
        OneSignal.Notifications.addClickListener(self)

        // D3: Permission request is NOT called here.
        // Call requestPushPermissionIfNeeded() after login/onboarding completes.
        #else
        #if DEBUG
        print("OneSignal: Framework not available, push notifications disabled")
        #endif
        #endif
    }

    // MARK: - Push Permission (D3)

    /// Request push notification permission. Call this after onboarding/login completes.
    /// Only prompts if permission has not already been granted.
    func requestPushPermissionIfNeeded() {
        #if canImport(OneSignalFramework)
        // Don't prompt again if already granted
        guard !OneSignal.Notifications.permission else { return }

        OneSignal.Notifications.requestPermission({ accepted in
            #if DEBUG
            print("OneSignal: User \(accepted ? "accepted" : "declined") push notifications")
            #endif
        }, fallbackToSettings: true)
        #endif
    }

    // MARK: - OneSignal Identity (D7)

    /// Associate the OneSignal device with the authenticated user.
    /// Call this after successful authentication.
    func loginOneSignal(userId: String) {
        #if canImport(OneSignalFramework)
        OneSignal.login(externalId: userId, token: nil)
        #if DEBUG
        print("OneSignal: Logged in with userId: \(userId)")
        #endif
        #endif
    }

    /// Disassociate the OneSignal device from the current user.
    /// Call this on logout.
    func logoutOneSignal() {
        #if canImport(OneSignalFramework)
        OneSignal.logout()
        #if DEBUG
        print("OneSignal: Logged out")
        #endif
        #endif
    }

    // MARK: - Notification Parsing

    #if canImport(OneSignalFramework)
    private func parseNotification(from osNotification: OSNotification) -> AppNotification? {
        // Extract data from OneSignal notification
        let additionalData = osNotification.additionalData ?? [:]

        // Get notification ID (use OneSignal notification ID or generate one)
        let notificationId = (additionalData["notification_id"] as? String)
            ?? osNotification.notificationId
            ?? UUID().uuidString

        // Parse notification type
        let typeString = (additionalData["type"] as? String) ?? "INFO"
        let notificationType = NotificationType(rawValue: typeString) ?? .info

        // Get title and message
        let title = osNotification.title ?? ""
        let message = osNotification.body ?? ""

        // Parse action if available
        var action: NotificationAction? = nil
        if let actionTypeString = additionalData["action_type"] as? String,
           let actionType = NotificationAction.ActionType(rawValue: actionTypeString) {
            let resourceId = additionalData["resource_id"] as? String
            action = NotificationAction(type: actionType, resourceId: resourceId)
        }

        return AppNotification(
            id: notificationId,
            type: notificationType,
            title: title,
            message: message,
            isRead: false,
            action: action,
            createdAt: Date(),
            readAt: nil
        )
    }
    #endif

    // MARK: - Security

    private func performSecurityCheck() {
        #if !DEBUG
        // In release builds, perform comprehensive security check
        // This includes: jailbreak detection, hooking framework detection, debugger detection
        if SecurityManager.shared.isCompromised {
            // Will show alert and exit app when scene is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                SecurityManager.shared.enforceFullSecurityCheck(on: nil)
            }
        }
        #endif

        // Initialize screenshot prevention (works in all builds)
        #if !targetEnvironment(macCatalyst)
        ScreenshotPrevention.shared.enable()
        #endif
    }

    // MARK: - UISceneSession Lifecycle

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(
        _ application: UIApplication,
        didDiscardSceneSessions sceneSessions: Set<UISceneSession>
    ) {
        // Called when the user discards a scene session
    }

    // MARK: - Private Methods

    private func configureAppearance() {
        // Navigation bar appearance
        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithOpaqueBackground()
        navBarAppearance.backgroundColor = .systemBackground
        navBarAppearance.titleTextAttributes = [.foregroundColor: UIColor.label]
        navBarAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor.label]

        UINavigationBar.appearance().standardAppearance = navBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance
        UINavigationBar.appearance().compactAppearance = navBarAppearance
        UINavigationBar.appearance().tintColor = .systemBlue

        // Tab bar appearance
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBarAppearance.backgroundColor = .systemBackground

        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
        UITabBar.appearance().tintColor = .systemBlue
    }
}

// MARK: - OneSignal Notification Handlers

#if canImport(OneSignalFramework)
extension AppDelegate: OSNotificationLifecycleListener {
    /// Called when a notification is received while app is in foreground
    func onWillDisplay(event: OSNotificationWillDisplayEvent) {
        // Save notification to local database
        if let notification = parseNotification(from: event.notification) {
            Task { @MainActor in
                // D8: Check if user is authenticated before saving
                let userId = DependencyContainer.shared.authRepository.currentUserId
                guard userId != nil else {
                    logger.warning("Notification received but no authenticated user — dropping: \(notification.title, privacy: .public)")
                    return
                }

                do {
                    try await DependencyContainer.shared.notificationRepository.saveNotification(notification)
                    #if DEBUG
                    print("AppDelegate: Saved foreground notification: \(notification.title)")
                    #endif
                } catch {
                    #if DEBUG
                    print("AppDelegate: Failed to save notification - \(error)")
                    #endif
                }
            }
        }

        // D9: Removed dead preventDefault() + display() pattern.
        // Default behavior already shows the notification banner in foreground.
    }
}

extension AppDelegate: OSNotificationClickListener {
    /// Called when user taps on a notification
    func onClick(event: OSNotificationClickEvent) {
        // Parse notification once and reuse
        guard let notification = parseNotification(from: event.notification) else {
            #if DEBUG
            print("AppDelegate: Failed to parse notification from click event")
            #endif
            return
        }

        // D10: Save and mark as read, then post navigation notification after DB writes complete
        Task { @MainActor in
            do {
                // Save first (in case it wasn't saved from foreground)
                try await DependencyContainer.shared.notificationRepository.saveNotification(notification)
                // Mark as read since user tapped it
                try await DependencyContainer.shared.notificationRepository.markAsRead(notificationId: notification.id)
                #if DEBUG
                print("AppDelegate: Handled notification click: \(notification.title)")
                #endif
            } catch {
                #if DEBUG
                print("AppDelegate: Failed to handle notification click - \(error)")
                #endif
            }

            // D10: Post navigation notification AFTER DB writes complete
            NotificationCenter.default.post(
                name: .didTapPushNotification,
                object: notification
            )
        }
    }
}
#endif

// Notification.Name extensions are defined in Core/Constants.swift for sharing between iOS and macOS
