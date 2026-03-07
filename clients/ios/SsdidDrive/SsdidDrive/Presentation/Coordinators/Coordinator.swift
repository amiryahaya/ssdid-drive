import UIKit

/// Protocol defining a coordinator
protocol Coordinator: AnyObject {
    var navigationController: UINavigationController { get set }
    var childCoordinators: [Coordinator] { get set }
    var parentCoordinator: Coordinator? { get set }

    func start()
    func finish()
}

extension Coordinator {
    func finish() {
        childCoordinators.removeAll()
        parentCoordinator?.removeChild(self)
    }

    func addChild(_ coordinator: Coordinator) {
        childCoordinators.append(coordinator)
        coordinator.parentCoordinator = self
    }

    func removeChild(_ coordinator: Coordinator) {
        childCoordinators.removeAll { $0 === coordinator }
    }
}

/// Base coordinator class with common functionality
@MainActor
class BaseCoordinator: Coordinator {
    var navigationController: UINavigationController
    var childCoordinators: [Coordinator] = []
    weak var parentCoordinator: Coordinator?

    let container: DependencyContainer

    init(navigationController: UINavigationController, container: DependencyContainer) {
        self.navigationController = navigationController
        self.container = container
    }

    func start() {
        fatalError("start() must be overridden")
    }

    func clearChildCoordinators() {
        childCoordinators.removeAll()
    }
}
