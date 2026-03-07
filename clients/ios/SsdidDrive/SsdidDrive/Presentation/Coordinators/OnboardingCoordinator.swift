import UIKit

/// Delegate for onboarding coordinator events
protocol OnboardingCoordinatorDelegate: AnyObject {
    func onboardingDidComplete()
}

/// Coordinator for onboarding flow
final class OnboardingCoordinator: BaseCoordinator {

    // MARK: - Properties

    weak var delegate: OnboardingCoordinatorDelegate?

    // MARK: - Start

    override func start() {
        let viewModel = OnboardingViewModel(userDefaultsManager: container.userDefaultsManager)
        viewModel.coordinatorDelegate = self

        let onboardingVC = OnboardingViewController(viewModel: viewModel)
        onboardingVC.delegate = self
        navigationController.setViewControllers([onboardingVC], animated: true)
    }
}

// MARK: - OnboardingViewModelCoordinatorDelegate

extension OnboardingCoordinator: OnboardingViewModelCoordinatorDelegate {
    func onboardingDidComplete() {
        delegate?.onboardingDidComplete()
    }
}

// MARK: - OnboardingViewControllerDelegate

extension OnboardingCoordinator: OnboardingViewControllerDelegate {
    func onboardingViewControllerDidComplete() {
        container.userDefaultsManager.completeOnboarding()
        delegate?.onboardingDidComplete()
    }
}
