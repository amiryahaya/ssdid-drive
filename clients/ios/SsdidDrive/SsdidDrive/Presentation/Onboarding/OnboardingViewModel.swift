import Foundation
import Combine

/// Delegate for onboarding view model coordinator events
protocol OnboardingViewModelCoordinatorDelegate: AnyObject {
    func onboardingDidComplete()
}

/// Represents an onboarding page
struct OnboardingPage {
    let icon: String
    let title: String
    let description: String
    let color: String // System color name
}

/// View model for onboarding flow
final class OnboardingViewModel: BaseViewModel {

    // MARK: - Properties

    weak var coordinatorDelegate: OnboardingViewModelCoordinatorDelegate?
    private let userDefaultsManager: UserDefaultsManager

    @Published var currentPage: Int = 0
    let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "lock.shield.fill",
            title: "Welcome to SsdidDrive",
            description: "The most secure way to share files using quantum-resistant encryption.",
            color: "systemBlue"
        ),
        OnboardingPage(
            icon: "shield.checkered",
            title: "Post-Quantum Security",
            description: "Your files are protected with ML-KEM and KAZ-KEM algorithms, safe from both classical and quantum computers.",
            color: "systemPurple"
        ),
        OnboardingPage(
            icon: "person.2.fill",
            title: "Share Securely",
            description: "Share files with trusted contacts. Only authorized recipients can decrypt your data.",
            color: "systemGreen"
        ),
        OnboardingPage(
            icon: "arrow.triangle.2.circlepath",
            title: "Account Recovery",
            description: "Set up social recovery with trusted contacts to recover your account if you lose access.",
            color: "systemOrange"
        )
    ]

    // MARK: - Initialization

    init(userDefaultsManager: UserDefaultsManager) {
        self.userDefaultsManager = userDefaultsManager
        super.init()
    }

    // MARK: - Actions

    func nextPage() {
        if currentPage < pages.count - 1 {
            currentPage += 1
        } else {
            completeOnboarding()
        }
    }

    func previousPage() {
        if currentPage > 0 {
            currentPage -= 1
        }
    }

    func skipToEnd() {
        completeOnboarding()
    }

    func goToPage(_ index: Int) {
        guard index >= 0 && index < pages.count else { return }
        currentPage = index
    }

    private func completeOnboarding() {
        userDefaultsManager.completeOnboarding()
        coordinatorDelegate?.onboardingDidComplete()
    }

    // MARK: - Computed

    var isLastPage: Bool {
        currentPage == pages.count - 1
    }

    var isFirstPage: Bool {
        currentPage == 0
    }
}
