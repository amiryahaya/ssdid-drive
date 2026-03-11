import UIKit
#if canImport(OneSignalFramework)
import OneSignalFramework
#endif
#if canImport(Sentry)
import Sentry
#endif

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    // MARK: - Properties

    var window: UIWindow?

    // MARK: - Application Lifecycle

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Initialize Sentry crash reporting early
        SentryConfig.shared.initialize()

        // Security check - refuse to run on jailbroken devices
        performSecurityCheck()

        // Configure push notifications with OneSignal
        configureOneSignal()

        // Configure appearance
        configureAppearance()

        return true
    }

    // MARK: - OneSignal Configuration

    private func configureOneSignal() {
        #if canImport(OneSignalFramework)
        // SECURITY: Use WARN level even in debug to prevent sensitive push data in logs
        #if DEBUG
        OneSignal.Debug.setLogLevel(.LL_WARN)
        #endif

        // Initialize OneSignal with app ID
        OneSignal.initialize(Constants.OneSignal.appId, withLaunchOptions: nil)

        // Set notification lifecycle listener
        OneSignal.Notifications.addForegroundLifecycleListener(self)

        // Set notification click listener
        OneSignal.Notifications.addClickListener(self)

        // Request push notification permission
        // This will show the iOS permission dialog
        OneSignal.Notifications.requestPermission({ accepted in
            print("OneSignal: User \(accepted ? "accepted" : "declined") push notifications")
        }, fallbackToSettings: true)
        #else
        print("OneSignal: Framework not available, push notifications disabled")
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

        // Allow notification to display (show the system notification banner)
        event.preventDefault()
        event.notification.display()
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

        // Save and mark as read
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
        }

        // Post notification for coordinator to handle navigation (reuse parsed notification)
        NotificationCenter.default.post(
            name: .didTapPushNotification,
            object: notification
        )
    }
}
#endif

// Notification.Name extensions are defined in Core/Constants.swift for sharing between iOS and macOS
