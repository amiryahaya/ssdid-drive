import UIKit

#if targetEnvironment(macCatalyst)
import ServiceManagement
class WindowManager: NSObject {

    static let shared = WindowManager()

    private override init() {
        super.init()
    }

    func configureMainWindow(_ windowScene: UIWindowScene) {
        // Set minimum window size
        windowScene.sizeRestrictions?.minimumSize = CGSize(width: 900, height: 600)
        windowScene.sizeRestrictions?.maximumSize = CGSize(width: CGFloat.greatestFiniteMagnitude,
                                                           height: CGFloat.greatestFiniteMagnitude)

        // Configure toolbar
        if let titlebar = windowScene.titlebar {
            titlebar.titleVisibility = .hidden
            titlebar.toolbarStyle = .unified

            let toolbar = NSToolbar(identifier: "MainToolbar")
            toolbar.delegate = self
            toolbar.displayMode = .iconOnly
            titlebar.toolbar = toolbar
        }

        // Register menu bar helper for login-item auto-launch
        registerMenuBarHelper()
    }

    /// Register or unregister the MenuBarHelper login item based on user preference.
    /// Defaults to enabled; user can opt out via a "menuBarHelperEnabled" UserDefaults key.
    private func registerMenuBarHelper() {
        if #available(macCatalyst 16.0, *) {
            let enabled = UserDefaults.standard.object(forKey: "menuBarHelperEnabled") as? Bool ?? true
            let service = SMAppService.loginItem(identifier: "my.ssdid.drive.SsdidDrive.MenuBarHelper")

            if enabled {
                guard service.status != .enabled else { return }
                do {
                    try service.register()
                } catch {
                    #if DEBUG
                    print("WindowManager: Failed to register MenuBarHelper login item - \(error)")
                    #endif
                }
            } else {
                guard service.status == .enabled else { return }
                do {
                    try service.unregister()
                } catch {
                    #if DEBUG
                    print("WindowManager: Failed to unregister MenuBarHelper login item - \(error)")
                    #endif
                }
            }
        }
    }

    func openNewWindow(for activity: NSUserActivity) {
        UIApplication.shared.requestSceneSessionActivation(
            nil,
            userActivity: activity,
            options: nil,
            errorHandler: nil
        )
    }
}

// MARK: - NSToolbarDelegate

extension WindowManager: NSToolbarDelegate {

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier.rawValue {
        case "upload":
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.image = UIImage(systemName: "arrow.up.doc")
            item.label = "Upload"
            item.toolTip = "Upload File (Cmd+U)"
            item.action = #selector(AppDelegate.uploadFile)
            return item
        case "newFolder":
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.image = UIImage(systemName: "folder.badge.plus")
            item.label = "New Folder"
            item.toolTip = "New Folder (Cmd+Shift+N)"
            item.action = #selector(AppDelegate.createFolder)
            return item
        default:
            return nil
        }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            NSToolbarItem.Identifier("upload"),
            NSToolbarItem.Identifier("newFolder"),
            .flexibleSpace
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return toolbarDefaultItemIdentifiers(toolbar)
    }
}
#endif
