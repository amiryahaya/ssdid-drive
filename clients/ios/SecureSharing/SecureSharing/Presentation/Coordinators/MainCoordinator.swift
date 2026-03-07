import UIKit
import Combine

/// Delegate for main coordinator events
protocol MainCoordinatorDelegate: AnyObject {
    func mainCoordinatorDidRequestLogout()
}

/// Coordinator for main app flow (files, sharing, notifications, settings)
final class MainCoordinator: BaseCoordinator {

    // MARK: - Properties

    weak var delegate: MainCoordinatorDelegate?
    private var tabBarController: UITabBarController?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Start

    override func start() {
        setupTabBar()
    }

    // MARK: - Tab Bar Setup

    private func setupTabBar() {
        let tabBar = UITabBarController()

        // Files tab
        let filesNav = UINavigationController()
        filesNav.tabBarItem = UITabBarItem(
            title: "Files",
            image: UIImage(systemName: "folder"),
            selectedImage: UIImage(systemName: "folder.fill")
        )
        let filesCoordinator = FilesCoordinator(
            navigationController: filesNav,
            container: container
        )
        filesCoordinator.delegate = self
        addChild(filesCoordinator)
        filesCoordinator.start()

        // Shares tab
        let sharesNav = UINavigationController()
        sharesNav.tabBarItem = UITabBarItem(
            title: "Shares",
            image: UIImage(systemName: "person.2"),
            selectedImage: UIImage(systemName: "person.2.fill")
        )
        let sharesCoordinator = SharesCoordinator(
            navigationController: sharesNav,
            container: container
        )
        addChild(sharesCoordinator)
        sharesCoordinator.start()

        // Notifications tab
        let notificationsNav = UINavigationController()
        notificationsNav.tabBarItem = UITabBarItem(
            title: "Notifications",
            image: UIImage(systemName: "bell"),
            selectedImage: UIImage(systemName: "bell.fill")
        )
        let notificationsCoordinator = NotificationsCoordinator(
            navigationController: notificationsNav,
            container: container
        )
        notificationsCoordinator.delegate = self
        addChild(notificationsCoordinator)
        notificationsCoordinator.start()

        // Setup badge observation for notifications tab
        container.notificationRepository.observeUnreadCount()
            .receive(on: DispatchQueue.main)
            .sink { [weak notificationsNav] count in
                notificationsNav?.tabBarItem.badgeValue = count > 0 ? "\(count)" : nil
            }
            .store(in: &cancellables)

        // AI Chat tab
        let piiChatNav = UINavigationController()
        piiChatNav.tabBarItem = UITabBarItem(
            title: "AI Chat",
            image: UIImage(systemName: "bubble.left.and.text.bubble.right"),
            selectedImage: UIImage(systemName: "bubble.left.and.text.bubble.right.fill")
        )
        let piiChatCoordinator = PiiChatCoordinator(
            navigationController: piiChatNav,
            container: container
        )
        addChild(piiChatCoordinator)
        piiChatCoordinator.start()

        // Settings tab
        let settingsNav = UINavigationController()
        settingsNav.tabBarItem = UITabBarItem(
            title: "Settings",
            image: UIImage(systemName: "gearshape"),
            selectedImage: UIImage(systemName: "gearshape.fill")
        )
        let settingsCoordinator = SettingsCoordinator(
            navigationController: settingsNav,
            container: container
        )
        settingsCoordinator.delegate = self
        addChild(settingsCoordinator)
        settingsCoordinator.start()

        tabBar.viewControllers = [filesNav, sharesNav, notificationsNav, piiChatNav, settingsNav]
        tabBarController = tabBar

        navigationController.setNavigationBarHidden(true, animated: false)
        navigationController.setViewControllers([tabBar], animated: true)
    }

    // MARK: - Deep Link Navigation

    func showReceivedShares() {
        tabBarController?.selectedIndex = 1
    }

    func showShareDetail(shareId: String) {
        tabBarController?.selectedIndex = 1
        if let sharesCoordinator = childCoordinators.first(where: { $0 is SharesCoordinator }) as? SharesCoordinator {
            sharesCoordinator.showShareDetail(shareId: shareId)
        }
    }

    func showFilePreview(fileId: String) {
        tabBarController?.selectedIndex = 0
        if let filesCoordinator = childCoordinators.first(where: { $0 is FilesCoordinator }) as? FilesCoordinator {
            filesCoordinator.showFilePreview(fileId: fileId)
        }
    }

    func showFolder(folderId: String) {
        tabBarController?.selectedIndex = 0
        if let filesCoordinator = childCoordinators.first(where: { $0 is FilesCoordinator }) as? FilesCoordinator {
            filesCoordinator.showFolder(folderId: folderId)
        }
    }

    // MARK: - Import Flow (from Share Extension)

    func showImportFlow(manifest: ImportManifest) {
        // Switch to Files tab
        tabBarController?.selectedIndex = 0

        // Get the files coordinator
        if let filesCoordinator = childCoordinators.first(where: { $0 is FilesCoordinator }) as? FilesCoordinator {
            filesCoordinator.showBatchUpload(manifest: manifest)
        }
    }
}

// MARK: - FilesCoordinatorDelegate

extension MainCoordinator: FilesCoordinatorDelegate {
    func filesCoordinatorDidRequestShare(fileId: String) {
        // Handle share request
    }
}

// MARK: - SettingsCoordinatorDelegate

extension MainCoordinator: SettingsCoordinatorDelegate {
    func settingsCoordinatorDidRequestLogout() {
        delegate?.mainCoordinatorDidRequestLogout()
    }

    func settingsCoordinatorDidSwitchTenant() {
        // Post notification for all views to refresh when tenant is switched
        NotificationCenter.default.post(name: .tenantDidSwitch, object: nil)
    }
}

// MARK: - NotificationsCoordinatorDelegate

extension MainCoordinator: NotificationsCoordinatorDelegate {
    func notificationsCoordinatorDidRequestOpenShare(shareId: String) {
        showShareDetail(shareId: shareId)
    }

    func notificationsCoordinatorDidRequestOpenFile(fileId: String) {
        showFilePreview(fileId: fileId)
    }

    func notificationsCoordinatorDidRequestOpenFolder(folderId: String) {
        showFolder(folderId: folderId)
    }

    func notificationsCoordinatorDidRequestOpenRecovery() {
        // Navigate to settings where recovery is handled
        // Tab order: Files(0), Shares(1), Notifications(2), AI Chat(3), Settings(4)
        tabBarController?.selectedIndex = 4
    }

    func notificationsCoordinatorDidRequestOpenSettings() {
        tabBarController?.selectedIndex = 4
    }
}

// MARK: - Notification Navigation

extension MainCoordinator {
    /// Show notifications tab and optionally navigate to a specific notification
    func showNotifications() {
        tabBarController?.selectedIndex = 2
    }
}
