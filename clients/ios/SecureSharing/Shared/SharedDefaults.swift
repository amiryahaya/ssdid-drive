import Foundation

/// Cross-process data bridge between the main Catalyst app and the MenuBarHelper.
/// Writes are performed by the main app; the helper reads on notification or fallback timer.
/// Uses App Group UserDefaults (`group.com.securesharing`).
///
/// Sensitive data (recent files, user display name) is encrypted with AES-256-GCM via
/// ``SharedEncryption`` before being written. Non-sensitive status fields (sync status,
/// isAuthenticated) remain plaintext since they carry minimal risk.
///
/// - Important: Both targets must include the `com.apple.security.application-groups`
///   entitlement for `group.com.securesharing` for this class to function.
final class SharedDefaults {

    // MARK: - Singleton

    static let shared = SharedDefaults()

    // MARK: - Constants

    /// App Group suite name. Must match the value in all entitlements files.
    static let suiteName = "group.com.securesharing"

    /// Distributed notification name posted after writes so the helper refreshes immediately.
    static let changeNotificationName = "com.securesharing.sharedDefaultsChanged"

    private enum Key {
        static let recentFiles = "shared_recent_files"
        static let syncStatus = "shared_sync_status"
        static let lastSyncDate = "shared_last_sync_date"
        static let isAuthenticated = "shared_is_authenticated"
        static let userDisplayName = "shared_user_display_name"
        static let pendingActionPrefix = "pending_action_"
    }

    // MARK: - Sync Status

    enum SyncStatus: String, Codable {
        case connected
        case syncing
        case offline
        case error
    }

    // MARK: - Pending Action (for URL scheme hardening)

    struct PendingAction: Codable {
        let type: ActionType
        let resourceId: String?
        let createdAt: Date

        enum ActionType: String, Codable {
            case openFile
            case openFolder
            case importFile
            case openApp
        }
    }

    // MARK: - Properties

    private let defaults: UserDefaults?
    private let encryption: SharedEncryption

    /// Whether the App Group UserDefaults is available
    var isAvailable: Bool { defaults != nil }

    // MARK: - Initialization

    init() {
        self.defaults = UserDefaults(suiteName: SharedDefaults.suiteName)
        self.encryption = SharedEncryption()

        #if DEBUG
        if defaults == nil {
            assertionFailure(
                "SharedDefaults: App Group '\(SharedDefaults.suiteName)' is not configured. "
                + "Check entitlements and provisioning profile."
            )
        }
        #endif
    }

    // MARK: - Recent Files (Encrypted)

    func writeRecentFiles(_ files: [RecentFile]) {
        guard let defaults else { return }
        guard let json = try? JSONEncoder().encode(files),
              let encrypted = encryption.encrypt(json) else { return }
        defaults.set(encrypted, forKey: Key.recentFiles)
    }

    func readRecentFiles() -> [RecentFile] {
        guard let defaults,
              let encrypted = defaults.data(forKey: Key.recentFiles),
              let json = encryption.decrypt(encrypted),
              let files = try? JSONDecoder().decode([RecentFile].self, from: json)
        else { return [] }
        return files
    }

    // MARK: - Sync Status (Plaintext — low sensitivity)

    func writeSyncStatus(_ status: SyncStatus) {
        guard let defaults else { return }
        defaults.set(status.rawValue, forKey: Key.syncStatus)
    }

    func readSyncStatus() -> SyncStatus {
        guard let defaults,
              let raw = defaults.string(forKey: Key.syncStatus),
              let status = SyncStatus(rawValue: raw)
        else { return .offline }
        return status
    }

    // MARK: - Last Sync Date

    func writeLastSyncDate(_ date: Date) {
        guard let defaults else { return }
        defaults.set(date, forKey: Key.lastSyncDate)
    }

    func readLastSyncDate() -> Date? {
        defaults?.object(forKey: Key.lastSyncDate) as? Date
    }

    // MARK: - Auth State (Plaintext — boolean only, low sensitivity)

    func writeIsAuthenticated(_ value: Bool) {
        guard let defaults else { return }
        defaults.set(value, forKey: Key.isAuthenticated)
    }

    func readIsAuthenticated() -> Bool {
        defaults?.bool(forKey: Key.isAuthenticated) ?? false
    }

    // MARK: - User Display Name (Encrypted)

    func writeUserDisplayName(_ name: String?) {
        guard let defaults else { return }
        if let name, let data = name.data(using: .utf8), let encrypted = encryption.encrypt(data) {
            defaults.set(encrypted, forKey: Key.userDisplayName)
        } else {
            defaults.removeObject(forKey: Key.userDisplayName)
        }
    }

    func readUserDisplayName() -> String? {
        guard let defaults,
              let encrypted = defaults.data(forKey: Key.userDisplayName),
              let data = encryption.decrypt(encrypted)
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Pending Actions (Encrypted, for URL scheme hardening)

    /// Write a pending action that can be resolved by the main app via a token.
    /// Actions expire after 30 seconds.
    func writePendingAction(token: String, action: PendingAction) {
        guard let defaults else { return }
        guard let json = try? JSONEncoder().encode(action),
              let encrypted = encryption.encrypt(json) else { return }
        defaults.set(encrypted, forKey: Key.pendingActionPrefix + token)
    }

    /// Read and atomically clear a pending action. Returns nil if expired (>30s) or not found.
    func readAndClearPendingAction(token: String) -> PendingAction? {
        guard let defaults else { return nil }
        let key = Key.pendingActionPrefix + token
        guard let encrypted = defaults.data(forKey: key),
              let json = encryption.decrypt(encrypted),
              let action = try? JSONDecoder().decode(PendingAction.self, from: json)
        else { return nil }
        defaults.removeObject(forKey: key)
        // Reject stale actions (>30 seconds old)
        guard Date().timeIntervalSince(action.createdAt) < 30 else { return nil }
        return action
    }

    // MARK: - Cross-Process Notification

    /// Post a distributed notification so the MenuBarHelper refreshes immediately.
    /// Only effective on macOS / Mac Catalyst; no-op on iOS.
    func notifyHelper() {
        #if os(macOS) || targetEnvironment(macCatalyst)
        DistributedNotificationCenter.default().post(
            name: .init(SharedDefaults.changeNotificationName),
            object: nil
        )
        #endif
    }

    // MARK: - Cleanup

    func clearAll() {
        guard let defaults else { return }
        for key in [Key.recentFiles, Key.syncStatus, Key.lastSyncDate,
                    Key.isAuthenticated, Key.userDisplayName] {
            defaults.removeObject(forKey: key)
        }
    }
}
