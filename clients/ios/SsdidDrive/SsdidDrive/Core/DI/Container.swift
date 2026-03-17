import Foundation
import SwiftUI
import UserNotifications

/// Dependency injection container for the app.
/// Provides singleton instances of services and repositories.
@MainActor
final class DependencyContainer: ObservableObject {

    // MARK: - Singleton

    static let shared = DependencyContainer()

    // MARK: - Local Storage

    lazy var keychainManager: KeychainManager = {
        KeychainManager()
    }()

    lazy var userDefaultsManager: UserDefaultsManager = {
        UserDefaultsManager()
    }()

    // MARK: - Crypto

    lazy var keyManager: KeyManager = {
        KeyManager(keychainManager: keychainManager)
    }()

    lazy var cryptoManager: CryptoManager = {
        CryptoManager(keyManager: keyManager)
    }()

    // MARK: - Network

    lazy var apiClient: APIClient = {
        APIClient(keychainManager: keychainManager)
    }()

    // MARK: - Repositories

    lazy var authRepository: AuthRepository = {
        AuthRepositoryImpl(
            apiClient: apiClient,
            keychainManager: keychainManager,
            keyManager: keyManager
        )
    }()

    lazy var fileRepository: FileRepository = {
        FileRepositoryImpl(
            apiClient: apiClient,
            cryptoManager: cryptoManager
        )
    }()

    lazy var shareRepository: ShareRepository = {
        ShareRepositoryImpl(
            apiClient: apiClient,
            cryptoManager: cryptoManager
        )
    }()

    lazy var recoveryRepository: RecoveryRepository = {
        RecoveryRepositoryImpl(apiClient: apiClient)
    }()

    lazy var tenantRepository: TenantRepository = {
        TenantRepositoryImpl(
            apiClient: apiClient,
            keychainManager: keychainManager,
            thumbnailCache: .shared,
            spotlightIndexer: .shared
        )
    }()

    lazy var notificationRepository: NotificationRepository = {
        NotificationRepositoryImpl(
            coreDataStack: .shared,
            authRepository: authRepository
        )
    }()

    lazy var oidcRepository: OidcRepository = {
        OidcRepositoryImpl(
            apiClient: apiClient,
            keychainManager: keychainManager,
            keyManager: keyManager
        )
    }()

    lazy var webAuthnRepository: WebAuthnRepository = {
        WebAuthnRepositoryImpl(
            apiClient: apiClient,
            keychainManager: keychainManager,
            keyManager: keyManager
        )
    }()

    lazy var activityRepository: ActivityRepository = {
        ActivityRepositoryImpl(apiClient: apiClient)
    }()

    lazy var piiRepository: PiiRepository = {
        PiiRepositoryImpl(keychainManager: keychainManager)
    }()

    // MARK: - Shared (App Group)

    let sharedDefaults = SharedDefaults.shared

    // MARK: - File Provider (macOS/Catalyst)

    lazy var fileProviderDomainManager: FileProviderDomainManager = {
        FileProviderDomainManager()
    }()

    // MARK: - Initialization

    private init() {}

    // MARK: - Reset (for logout)

    func reset() {
        // SECURITY: Clear in-memory tenant context BEFORE clearing keychain
        // This ensures no stale data remains in memory for next user
        Task {
            await tenantRepository.clearTenantData()
        }

        // D7: Disassociate OneSignal device from the current user on logout
        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
            appDelegate.logoutOneSignal()
        }

        // Clear Sentry user context
        SentryConfig.shared.clearUser()

        // Clear PII service KEM keys
        piiRepository.clearKemKeys()

        // Clear keychain (includes tenant data)
        keychainManager.clearAll()

        // Clear notification data for privacy on logout
        Task {
            do {
                try await notificationRepository.deleteAllNotifications()
            } catch {
                #if DEBUG
                print("DependencyContainer: Failed to clear notifications on logout - \(error)")
                #endif
            }
        }

        // Reset app badge to zero
        UNUserNotificationCenter.current().setBadgeCount(0) { error in
            #if DEBUG
            if let error = error {
                print("DependencyContainer: Failed to reset badge on logout - \(error)")
            }
            #endif
        }

        // Clear shared defaults (menu bar helper) and notify
        sharedDefaults.clearAll()
        sharedDefaults.notifyHelper()

        // Notify other scenes so they return to login (H3: multi-scene coordination)
        NotificationCenter.default.post(name: .userDidLogout, object: nil)

        // Note: UserDefaults preferences are kept (theme, etc.)
        // Only auth-related data is cleared
    }

    /// Reset tenant data only (for tenant switching edge cases)
    func resetTenantData() {
        Task {
            await tenantRepository.clearTenantData()
        }
        keychainManager.clearTenantData()
    }
}

// MARK: - Environment Key

private struct DependencyContainerKey: EnvironmentKey {
    static let defaultValue: DependencyContainer = .shared
}

extension EnvironmentValues {
    var container: DependencyContainer {
        get { self[DependencyContainerKey.self] }
        set { self[DependencyContainerKey.self] = newValue }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted by `DependencyContainer.reset()` when the user logs out.
    /// All active scenes should observe this and return to the login screen.
    static let userDidLogout = Notification.Name("my.ssdid.drive.userDidLogout")
}
