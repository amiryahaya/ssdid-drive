import Foundation
import Combine

/// Delegate for recovery setup view model coordinator events
protocol RecoverySetupViewModelCoordinatorDelegate: AnyObject {
    func recoverySetupDidRequestTrusteeSelection(totalShares: Int)
}

/// View model for recovery setup screen
final class RecoverySetupViewModel: BaseViewModel {

    // MARK: - Properties

    private let recoveryRepository: RecoveryRepository
    weak var coordinatorDelegate: RecoverySetupViewModelCoordinatorDelegate?

    @Published var threshold: Int = 3
    @Published var totalShares: Int = 5
    @Published var hasExistingSetup: Bool = false

    let minThreshold = 2
    let maxThreshold = 10
    let minShares = 3
    let maxShares = 10

    // MARK: - Initialization

    init(recoveryRepository: RecoveryRepository) {
        self.recoveryRepository = recoveryRepository
        super.init()
    }

    // MARK: - Actions

    func incrementThreshold() {
        if threshold < maxThreshold && threshold < totalShares {
            threshold += 1
        }
    }

    func decrementThreshold() {
        if threshold > minThreshold {
            threshold -= 1
        }
    }

    func incrementShares() {
        if totalShares < maxShares {
            totalShares += 1
        }
    }

    func decrementShares() {
        if totalShares > minShares && totalShares > threshold {
            totalShares -= 1
        }
    }

    func proceedToTrusteeSelection() {
        coordinatorDelegate?.recoverySetupDidRequestTrusteeSelection(totalShares: totalShares)
    }

    // MARK: - Computed

    var isValid: Bool {
        threshold >= minThreshold && threshold <= totalShares && totalShares >= minShares
    }

    var explanation: String {
        "You'll need \(threshold) out of \(totalShares) trustees to recover your account."
    }
}
