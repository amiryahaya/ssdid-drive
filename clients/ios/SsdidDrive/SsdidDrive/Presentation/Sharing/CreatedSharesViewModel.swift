import Foundation
import Combine

/// View model for created shares screen
final class CreatedSharesViewModel: BaseViewModel {

    // MARK: - Properties

    private let shareRepository: ShareRepository

    @Published var shares: [Share] = []

    // MARK: - Initialization

    init(shareRepository: ShareRepository) {
        self.shareRepository = shareRepository
        super.init()
    }

    // MARK: - Data Loading

    func loadShares() {
        isLoading = true
        clearError()

        Task {
            do {
                let fetchedShares = try await shareRepository.getCreatedShares()
                await MainActor.run {
                    self.shares = fetchedShares
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

    func revokeShare(_ share: Share) {
        isLoading = true

        Task {
            do {
                try await shareRepository.revokeShare(shareId: share.id)
                await MainActor.run {
                    self.shares.removeAll { $0.id == share.id }
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    handleError(error)
                }
            }
        }
    }
}
