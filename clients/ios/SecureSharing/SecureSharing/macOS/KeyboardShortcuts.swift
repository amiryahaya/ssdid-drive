import UIKit

#if targetEnvironment(macCatalyst)
extension AppDelegate {

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)

        guard builder.system == .main else { return }

        // File menu additions
        let uploadCommand = UIKeyCommand(
            title: "Upload File...",
            action: #selector(uploadFile),
            input: "U",
            modifierFlags: .command
        )

        let newFolderCommand = UIKeyCommand(
            title: "New Folder",
            action: #selector(createFolder),
            input: "N",
            modifierFlags: [.command, .shift]
        )

        let fileMenu = UIMenu(
            title: "",
            options: .displayInline,
            children: [uploadCommand, newFolderCommand]
        )

        builder.insertChild(fileMenu, atStartOfMenu: .file)

        // App menu - lock command
        let lockCommand = UIKeyCommand(
            title: "Lock App",
            action: #selector(lockApp),
            input: "L",
            modifierFlags: [.command, .control]
        )

        let appMenu = UIMenu(
            title: "",
            options: .displayInline,
            children: [lockCommand]
        )
        builder.insertSibling(appMenu, afterMenu: .about)
    }

    @objc func uploadFile() {
        NotificationCenter.default.post(name: .uploadFileRequested, object: nil)
    }

    @objc func createFolder() {
        NotificationCenter.default.post(name: .createFolderRequested, object: nil)
    }

    @objc func lockApp() {
        NotificationCenter.default.post(name: .lockAppRequested, object: nil)
    }
}
#endif
