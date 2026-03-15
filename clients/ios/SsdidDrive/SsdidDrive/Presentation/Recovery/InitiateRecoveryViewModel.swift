import Foundation
import Combine

/// Delegate for initiate recovery view model coordinator events
protocol InitiateRecoveryViewModelCoordinatorDelegate: AnyObject {
    func initiateRecoveryDidComplete()
}

/// View model for initiate recovery screen
final class InitiateRecoveryViewModel: BaseViewModel {

    // MARK: - Properties

    private let recoveryRepository: RecoveryRepository
    weak var coordinatorDelegate: InitiateRecoveryViewModelCoordinatorDelegate?

    @Published var email: String = ""
    @Published var hasRecoverySetup: Bool = false
    @Published var recoveryStatus: RecoveryStatus?

    enum RecoveryStatus {
        case notStarted
        case pending(approvalsReceived: Int, approvalsNeeded: Int)
        case ready
        case failed
    }

    // MARK: - Initialization

    init(recoveryRepository: RecoveryRepository) {
        self.recoveryRepository = recoveryRepository
        super.init()
    }

    // MARK: - Actions

    func checkRecoveryStatus() {
        isLoading = true
        clearError()

        Task {
            do {
                // Check if there's an existing recovery request
                let request = try await recoveryRepository.getMyRecoveryRequest()
                await MainActor.run {
                    if let request = request {
                        self.hasRecoverySetup = true
                        let approvalsReceived = request.approvedShares
                        let requiredShares = request.requiredShares
                        if approvalsReceived >= requiredShares {
                            self.recoveryStatus = .ready
                        } else {
                            self.recoveryStatus = .pending(
                                approvalsReceived: approvalsReceived,
                                approvalsNeeded: requiredShares
                            )
                        }
                    } else {
                        self.hasRecoverySetup = false
                        self.recoveryStatus = .notStarted
                    }
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    handleError(error)
                }
            }
        }
    }

    func initiateRecovery() {
        isLoading = true
        clearError()

        Task {
            do {
                let request = try await recoveryRepository.initiateRecovery()
                await MainActor.run {
                    self.recoveryStatus = .pending(
                        approvalsReceived: 0,
                        approvalsNeeded: request.requiredShares
                    )
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    handleError(error)
                }
            }
        }
    }

    func completeRecovery(newPassword: String) {
        isLoading = true
        clearError()

        Task {
            do {
                // Complete recovery and get the recovered master key
                // TODO: Pass actual DID migration params from recovery flow
                _ = try await recoveryRepository.completeRecovery(
                    oldDid: "",       // TODO: from recovery request
                    newDid: "",       // TODO: generate new DID
                    keyProof: "",     // TODO: sign with recovered key
                    kemPublicKey: ""  // TODO: new KEM keypair
                )
                await MainActor.run {
                    self.isLoading = false
                    self.coordinatorDelegate?.initiateRecoveryDidComplete()
                }
            } catch {
                await MainActor.run {
                    handleError(error)
                }
            }
        }
    }

    // MARK: - Computed

    var canCheckStatus: Bool {
        email.contains("@") && email.count > 5
    }
}
