import Foundation

/// Lightweight model for sharing recent file info between the main app and MenuBarHelper
/// via App Group UserDefaults. Foundation-only — no UIKit or AppKit imports.
struct RecentFile: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let mimeType: String
    let size: Int64
    let updatedAt: Date
    let isFolder: Bool

    /// Human-readable file size
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    /// SF Symbol name for the file type
    var iconName: String {
        if isFolder { return "folder.fill" }
        if mimeType.hasPrefix("image/") { return "photo" }
        if mimeType.hasPrefix("video/") { return "video" }
        if mimeType.hasPrefix("audio/") { return "music.note" }
        if mimeType == "application/pdf" { return "doc.text" }
        return "doc"
    }

}
