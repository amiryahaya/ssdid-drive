import UIKit

/// Coordinator for the activity log flow
@MainActor
final class ActivityCoordinator: BaseCoordinator {

    // MARK: - Start

    override func start() {
        showActivity()
    }

    // MARK: - Navigation

    func showActivity() {
        let viewModel = ActivityViewModel(
            activityRepository: container.activityRepository
        )
        viewModel.coordinatorDelegate = self

        let activityVC = ActivityViewController(viewModel: viewModel)
        navigationController.setViewControllers([activityVC], animated: false)
    }

    func showFileActivity(resourceId: String, resourceName: String) {
        let viewModel = FileActivityViewModel(
            activityRepository: container.activityRepository,
            resourceId: resourceId,
            resourceName: resourceName
        )

        let fileActivityVC = FileActivityViewController(viewModel: viewModel)
        navigationController.pushViewController(fileActivityVC, animated: true)
    }
}

// MARK: - ActivityViewModelCoordinatorDelegate

extension ActivityCoordinator: ActivityViewModelCoordinatorDelegate {
    func activityDidSelectResource(resourceId: String, resourceName: String) {
        showFileActivity(resourceId: resourceId, resourceName: resourceName)
    }
}
