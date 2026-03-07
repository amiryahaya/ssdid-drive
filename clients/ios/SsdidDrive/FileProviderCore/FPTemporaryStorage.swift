import Foundation

/// Manages temporary file storage for the File Provider extension.
/// Files are stored in the App Group container for download/upload staging.
final class FPTemporaryStorage {

    private let baseDirectory: URL

    init() {
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: FPConstants.appGroupSuite) {
            baseDirectory = groupURL.appendingPathComponent("FileProviderTemp", isDirectory: true)
        } else {
            baseDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("FileProviderTemp", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    }

    /// Return a unique temporary URL for the given item identifier.
    func temporaryURL(for itemIdentifier: String, filename: String) -> URL {
        let safeId = itemIdentifier.replacingOccurrences(of: "/", with: "_")
        let dir = baseDirectory.appendingPathComponent(safeId, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Sanitize filename to prevent path traversal
        let safeFilename = URL(fileURLWithPath: filename).lastPathComponent
        return dir.appendingPathComponent(safeFilename)
    }

    /// Remove stale temp files older than the given interval.
    func cleanup(olderThan interval: TimeInterval = 3600) {
        let cutoff = Date().addingTimeInterval(-interval)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for url in contents {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modified = values.contentModificationDate,
                  modified < cutoff else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Remove all temporary files.
    func removeAll() {
        try? FileManager.default.removeItem(at: baseDirectory)
        try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    }
}
