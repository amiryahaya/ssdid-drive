import Foundation

/// Persists sync anchors in App Group UserDefaults.
/// Each container (folder) has its own sync anchor keyed by container ID.
enum FPSyncAnchorStore {

    private static let keyPrefix = "fp_sync_anchor_"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: FPConstants.appGroupSuite)
    }

    /// Read the sync anchor date for a container.
    static func readAnchor(for containerId: String) -> Date? {
        defaults?.object(forKey: keyPrefix + containerId) as? Date
    }

    /// Write a sync anchor date for a container.
    static func writeAnchor(_ date: Date, for containerId: String) {
        defaults?.set(date, forKey: keyPrefix + containerId)
    }

    /// Remove the sync anchor for a container.
    static func removeAnchor(for containerId: String) {
        defaults?.removeObject(forKey: keyPrefix + containerId)
    }
}
