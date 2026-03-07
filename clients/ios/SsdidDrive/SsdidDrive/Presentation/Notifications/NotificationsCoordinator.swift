import UIKit
import Combine

/// Delegate for notifications coordinator events
protocol NotificationsCoordinatorDelegate: AnyObject {
    func notificationsCoordinatorDidRequestOpenShare(shareId: String)
    func notificationsCoordinatorDidRequestOpenFile(fileId: String)
    func notificationsCoordinatorDidRequestOpenFolder(folderId: String)
    func notificationsCoordinatorDidRequestOpenRecovery()
    func notificationsCoordinatorDidRequestOpenSettings()
}

/// Coordinator for notifications flow
final class NotificationsCoordinator: BaseCoordinator {

    // MARK: - Properties

    weak var delegate: NotificationsCoordinatorDelegate?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Start

    override func start() {
        showNotificationList()
    }

    // MARK: - Navigation

    func showNotificationList() {
        let viewModel = NotificationListViewModel(
            notificationRepository: container.notificationRepository
        )
        viewModel.coordinatorDelegate = self

        let notificationsVC = NotificationListViewController(viewModel: viewModel)
        navigationController.setViewControllers([notificationsVC], animated: false)
    }

    // MARK: - Action Handling

    private func handleNotificationAction(_ action: NotificationAction?) {
        guard let action = action else { return }

        switch action.type {
        case .openShare:
            if let shareId = action.resourceId {
                delegate?.notificationsCoordinatorDidRequestOpenShare(shareId: shareId)
            }
        case .openFile:
            if let fileId = action.resourceId {
                delegate?.notificationsCoordinatorDidRequestOpenFile(fileId: fileId)
            }
        case .openFolder:
            if let folderId = action.resourceId {
                delegate?.notificationsCoordinatorDidRequestOpenFolder(folderId: folderId)
            }
        case .openRecovery:
            delegate?.notificationsCoordinatorDidRequestOpenRecovery()
        case .openSettings:
            delegate?.notificationsCoordinatorDidRequestOpenSettings()
        case .none:
            break
        }
    }
}

// MARK: - NotificationListViewModelCoordinatorDelegate

extension NotificationsCoordinator: NotificationListViewModelCoordinatorDelegate {
    func notificationListDidSelectNotification(_ notification: AppNotification) {
        handleNotificationAction(notification.action)
    }
}
