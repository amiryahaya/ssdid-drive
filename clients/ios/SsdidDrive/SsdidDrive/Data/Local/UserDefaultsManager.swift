import Foundation
import SwiftUI

/// Manages non-sensitive app preferences using UserDefaults.
final class UserDefaultsManager: ObservableObject {

    private let defaults: UserDefaults

    /// Lock for thread-safe pending deep link operations
    private let deepLinkLock = NSLock()

    // MARK: - Initialization

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hasCompletedOnboarding = defaults.bool(forKey: Constants.UserDefaultsKeys.hasCompletedOnboarding)

        if let themeModeString = defaults.string(forKey: Constants.UserDefaultsKeys.themeMode),
           let mode = Constants.ThemeMode(rawValue: themeModeString) {
            self.themeMode = mode
        } else {
            self.themeMode = .system
        }

        self.biometricEnabled = defaults.bool(forKey: Constants.UserDefaultsKeys.biometricEnabled)

        // Auto-lock defaults to enabled
        if defaults.object(forKey: Constants.UserDefaultsKeys.autoLockEnabled) == nil {
            self.autoLockEnabled = true
        } else {
            self.autoLockEnabled = defaults.bool(forKey: Constants.UserDefaultsKeys.autoLockEnabled)
        }

        if let timeoutString = defaults.string(forKey: Constants.UserDefaultsKeys.autoLockTimeout),
           let timeout = Constants.AutoLockTimeout(rawValue: timeoutString) {
            self.autoLockTimeout = timeout
        } else {
            self.autoLockTimeout = .fiveMinutes
        }

        // Notifications default to enabled
        if defaults.object(forKey: Constants.UserDefaultsKeys.notificationsEnabled) == nil {
            self.notificationsEnabled = true
        } else {
            self.notificationsEnabled = defaults.bool(forKey: Constants.UserDefaultsKeys.notificationsEnabled)
        }

        if defaults.object(forKey: Constants.UserDefaultsKeys.shareNotificationsEnabled) == nil {
            self.shareNotificationsEnabled = true
        } else {
            self.shareNotificationsEnabled = defaults.bool(forKey: Constants.UserDefaultsKeys.shareNotificationsEnabled)
        }

        if defaults.object(forKey: Constants.UserDefaultsKeys.recoveryNotificationsEnabled) == nil {
            self.recoveryNotificationsEnabled = true
        } else {
            self.recoveryNotificationsEnabled = defaults.bool(forKey: Constants.UserDefaultsKeys.recoveryNotificationsEnabled)
        }

        self.compactViewEnabled = defaults.bool(forKey: Constants.UserDefaultsKeys.compactViewEnabled)

        // Show file sizes defaults to true
        if defaults.object(forKey: Constants.UserDefaultsKeys.showFileSizes) == nil {
            self.showFileSizes = true
        } else {
            self.showFileSizes = defaults.bool(forKey: Constants.UserDefaultsKeys.showFileSizes)
        }

        if let favoriteIds = defaults.array(forKey: Constants.UserDefaultsKeys.favoriteFileIds) as? [String] {
            self.favoriteFileIds = Set(favoriteIds)
        } else {
            self.favoriteFileIds = []
        }
    }

    // MARK: - Onboarding

    @Published var hasCompletedOnboarding: Bool {
        didSet {
            defaults.set(hasCompletedOnboarding, forKey: Constants.UserDefaultsKeys.hasCompletedOnboarding)
        }
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
    }

    // MARK: - Theme

    @Published var themeMode: Constants.ThemeMode {
        didSet {
            defaults.set(themeMode.rawValue, forKey: Constants.UserDefaultsKeys.themeMode)
        }
    }

    var colorScheme: ColorScheme? {
        switch themeMode {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }

    // MARK: - Security

    @Published var biometricEnabled: Bool {
        didSet {
            defaults.set(biometricEnabled, forKey: Constants.UserDefaultsKeys.biometricEnabled)
        }
    }

    @Published var autoLockEnabled: Bool {
        didSet {
            defaults.set(autoLockEnabled, forKey: Constants.UserDefaultsKeys.autoLockEnabled)
        }
    }

    @Published var autoLockTimeout: Constants.AutoLockTimeout {
        didSet {
            defaults.set(autoLockTimeout.rawValue, forKey: Constants.UserDefaultsKeys.autoLockTimeout)
        }
    }

    // MARK: - Notifications

    @Published var notificationsEnabled: Bool {
        didSet {
            defaults.set(notificationsEnabled, forKey: Constants.UserDefaultsKeys.notificationsEnabled)
        }
    }

    @Published var shareNotificationsEnabled: Bool {
        didSet {
            defaults.set(shareNotificationsEnabled, forKey: Constants.UserDefaultsKeys.shareNotificationsEnabled)
        }
    }

    @Published var recoveryNotificationsEnabled: Bool {
        didSet {
            defaults.set(recoveryNotificationsEnabled, forKey: Constants.UserDefaultsKeys.recoveryNotificationsEnabled)
        }
    }

    // MARK: - Display

    @Published var compactViewEnabled: Bool {
        didSet {
            defaults.set(compactViewEnabled, forKey: Constants.UserDefaultsKeys.compactViewEnabled)
        }
    }

    @Published var showFileSizes: Bool {
        didSet {
            defaults.set(showFileSizes, forKey: Constants.UserDefaultsKeys.showFileSizes)
        }
    }

    // MARK: - Favorites

    @Published var favoriteFileIds: Set<String> {
        didSet {
            defaults.set(Array(favoriteFileIds), forKey: Constants.UserDefaultsKeys.favoriteFileIds)
        }
    }

    func isFavorite(_ fileId: String) -> Bool {
        favoriteFileIds.contains(fileId)
    }

    func toggleFavorite(_ fileId: String) {
        if favoriteFileIds.contains(fileId) {
            favoriteFileIds.remove(fileId)
        } else {
            favoriteFileIds.insert(fileId)
        }
    }

    func addFavorite(_ fileId: String) {
        favoriteFileIds.insert(fileId)
    }

    func removeFavorite(_ fileId: String) {
        favoriteFileIds.remove(fileId)
    }

    // MARK: - Pending Deep Link

    /// Save a pending deep link action to process after authentication
    /// Thread-safe operation using lock to prevent race conditions
    /// - Note: UserDefaults automatically synchronizes data to disk periodically.
    ///         For critical data that must survive unexpected termination, consider
    ///         using Keychain or file-based storage instead.
    /// - Parameter action: The deep link action to save
    func savePendingDeepLink(_ action: DeepLinkAction) {
        deepLinkLock.lock()
        defer { deepLinkLock.unlock() }

        do {
            let data = try JSONEncoder().encode(action)
            defaults.set(data, forKey: Constants.UserDefaultsKeys.pendingDeepLink)
        } catch {
            #if DEBUG
            print("UserDefaultsManager: Failed to save pending deep link: \(error.localizedDescription)")
            #endif
        }
    }

    /// Retrieve and clear the pending deep link action atomically
    /// Thread-safe operation using lock to prevent race conditions
    /// - Returns: The pending action if one exists, nil otherwise
    func consumePendingDeepLink() -> DeepLinkAction? {
        deepLinkLock.lock()
        defer { deepLinkLock.unlock() }

        guard let data = defaults.data(forKey: Constants.UserDefaultsKeys.pendingDeepLink) else {
            return nil
        }

        // Clear immediately to prevent duplicate processing
        defaults.removeObject(forKey: Constants.UserDefaultsKeys.pendingDeepLink)

        do {
            return try JSONDecoder().decode(DeepLinkAction.self, from: data)
        } catch {
            #if DEBUG
            print("UserDefaultsManager: Failed to decode pending deep link: \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    /// Check if there's a pending deep link without consuming it
    /// Thread-safe operation using lock
    /// - Returns: true if a pending deep link exists
    func hasPendingDeepLink() -> Bool {
        deepLinkLock.lock()
        defer { deepLinkLock.unlock() }
        return defaults.data(forKey: Constants.UserDefaultsKeys.pendingDeepLink) != nil
    }

    /// Clear pending deep link without processing
    /// Thread-safe operation using lock
    func clearPendingDeepLink() {
        deepLinkLock.lock()
        defer { deepLinkLock.unlock() }
        defaults.removeObject(forKey: Constants.UserDefaultsKeys.pendingDeepLink)
    }

    // MARK: - Pending Invite Code

    /// Pending invite code to auto-accept after authentication
    var pendingInviteCode: String? {
        get { defaults.string(forKey: "pending_invite_code") }
        set {
            if let newValue = newValue {
                defaults.set(newValue, forKey: "pending_invite_code")
            } else {
                defaults.removeObject(forKey: "pending_invite_code")
            }
        }
    }

    /// Consume the pending invite code (read and clear atomically)
    func consumePendingInviteCode() -> String? {
        let code = pendingInviteCode
        pendingInviteCode = nil
        return code
    }

    // MARK: - Reset

    func clearAll() {
        let keys = [
            Constants.UserDefaultsKeys.hasCompletedOnboarding,
            Constants.UserDefaultsKeys.themeMode,
            Constants.UserDefaultsKeys.biometricEnabled,
            Constants.UserDefaultsKeys.autoLockEnabled,
            Constants.UserDefaultsKeys.autoLockTimeout,
            Constants.UserDefaultsKeys.notificationsEnabled,
            Constants.UserDefaultsKeys.shareNotificationsEnabled,
            Constants.UserDefaultsKeys.recoveryNotificationsEnabled,
            Constants.UserDefaultsKeys.compactViewEnabled,
            Constants.UserDefaultsKeys.showFileSizes,
            Constants.UserDefaultsKeys.favoriteFileIds,
            Constants.UserDefaultsKeys.pendingDeepLink,
            "pending_invite_code"
        ]

        keys.forEach { defaults.removeObject(forKey: $0) }

        // Reset published properties to defaults
        hasCompletedOnboarding = false
        themeMode = .system
        biometricEnabled = false
        autoLockEnabled = true
        autoLockTimeout = .fiveMinutes
        notificationsEnabled = true
        shareNotificationsEnabled = true
        recoveryNotificationsEnabled = true
        compactViewEnabled = false
        showFileSizes = true
        favoriteFileIds = []
    }
}
