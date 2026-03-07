import Foundation
import Combine

/// View model for pending recovery requests screen (trustee dashboard)
final class PendingRequestsViewModel: BaseViewModel {

    // MARK: - Properties

    private let recoveryRepository: RecoveryRepository

    @Published var pendingRequests: [RecoveryRequest] = []
    @Published var heldShares: [RecoveryShare] = []

    // MARK: - Initialization

    init(recoveryRepository: RecoveryRepository) {
        self.recoveryRepository = recoveryRepository
        super.init()
    }

    // MARK: - Data Loading

    func loadData() {
        isLoading = true
        clearError()

        Task {
            do {
                async let requestsTask = recoveryRepository.getPendingRequests()
                async let sharesTask = recoveryRepository.getHeldShares()

                let (requests, shares) = try await (requestsTask, sharesTask)

                await MainActor.run {
                    self.pendingRequests = requests
                    self.heldShares = shares
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    handleError(error)
                }
            }
        }
    }

    // MARK: - Actions

    func approveRequest(_ request: RecoveryRequest) {
        isLoading = true
        clearError()

        Task {
            do {
                try await recoveryRepository.approveRequest(requestId: request.id)
                await MainActor.run {
                    self.pendingRequests.removeAll { $0.id == request.id }
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    handleError(error)
                }
            }
        }
    }

    func rejectRequest(_ request: RecoveryRequest) {
        isLoading = true
        clearError()

        Task {
            do {
                try await recoveryRepository.rejectRequest(requestId: request.id)
                await MainActor.run {
                    self.pendingRequests.removeAll { $0.id == request.id }
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    handleError(error)
                }
            }
        }
    }

    // MARK: - Computed

    var hasPendingRequests: Bool {
        !pendingRequests.isEmpty
    }

    var hasHeldShares: Bool {
        !heldShares.isEmpty
    }
}
