import SwiftUI

/// Navigation coordinator for the app.
/// Handles navigation state and provides type-safe routing.
@MainActor
final class AppNavigator: ObservableObject {

    // MARK: - Navigation State

    @Published var path = NavigationPath()
    @Published var showLockScreen = false

    // MARK: - Routes

    enum Route: Hashable {
        // Auth
        case onboarding
        case login
        case register
        case lock

        // Files
        case files
        case fileBrowser(folderId: String)
        case filePreview(fileId: String)
        case shareIntent

        // Sharing
        case receivedShares
        case createdShares
        case shareFile(fileId: String)
        case shareFolder(folderId: String)

        // Recovery
        case recoverySetup
        case trusteeSelection(totalShares: Int)
        case trusteeDashboard
        case initiateRecovery

        // Settings
        case settings
        case invitations
    }

    // MARK: - Navigation Actions

    /// Navigate to a route
    func navigate(to route: Route) {
        path.append(route)
    }

    /// Pop the last route from the stack
    func pop() {
        if !path.isEmpty {
            path.removeLast()
        }
    }

    /// Pop to root
    func popToRoot() {
        path = NavigationPath()
    }

    /// Pop to a specific count
    func pop(count: Int) {
        let removeCount = min(count, path.count)
        path.removeLast(removeCount)
    }

    /// Replace the entire navigation stack
    func replace(with route: Route) {
        path = NavigationPath()
        path.append(route)
    }

    /// Navigate to files (usually after login)
    func navigateToFiles() {
        path = NavigationPath()
        // Files is the root, no need to append
    }

    /// Show lock screen
    func lock() {
        showLockScreen = true
    }

    /// Dismiss lock screen
    func unlock() {
        showLockScreen = false
    }

    // MARK: - Deep Link Handling

    enum DeepLinkAction {
        case openShare(shareId: String)
        case openFile(fileId: String)
        case openFolder(folderId: String)
        case uploadFiles(urls: [URL])
    }

    func handleDeepLink(_ action: DeepLinkAction) {
        switch action {
        case .openShare(let shareId):
            navigate(to: .receivedShares)
            // TODO: Navigate to specific share
        case .openFile(let fileId):
            navigate(to: .filePreview(fileId: fileId))
        case .openFolder(let folderId):
            navigate(to: .fileBrowser(folderId: folderId))
        case .uploadFiles:
            navigate(to: .shareIntent)
        }
    }

    // MARK: - URL Handling

    func handleURL(_ url: URL) -> Bool {
        // Parse URL scheme: ssdid-drive://
        guard url.scheme == "ssdid-drive" else { return false }

        let host = url.host
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        switch host {
        case "share":
            if let shareId = pathComponents.first {
                handleDeepLink(.openShare(shareId: shareId))
                return true
            }
        case "file":
            if let fileId = pathComponents.first {
                handleDeepLink(.openFile(fileId: fileId))
                return true
            }
        case "folder":
            if let folderId = pathComponents.first {
                handleDeepLink(.openFolder(folderId: folderId))
                return true
            }
        default:
            break
        }

        return false
    }
}
