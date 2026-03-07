import Foundation
import Combine

/// Delegate for received shares view model coordinator events
protocol ReceivedSharesViewModelCoordinatorDelegate: AnyObject {
    func receivedSharesDidSelectFile(fileId: String)
    func receivedSharesDidSelectFolder(folderId: String)
    func receivedSharesDidRequestCreatedShares()
}

/// View model for received shares screen
final class ReceivedSharesViewModel: BaseViewModel {

    // MARK: - Properties

    private let shareRepository: ShareRepository
    weak var coordinatorDelegate: ReceivedSharesViewModelCoordinatorDelegate?

    @Published var shares: [Share] = []
    @Published var isRefreshing: Bool = false

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
                let fetchedShares = try await shareRepository.getReceivedShares()
                await MainActor.run {
                    self.shares = fetchedShares
                    self.isLoading = false
                    self.isRefreshing = false
                }
            } catch {
                await MainActor.run {
                    handleError(error)
                    self.isRefreshing = false
                }
            }
        }
    }

    func refreshShares() {
        isRefreshing = true
        loadShares()
    }

    // MARK: - Actions

    func selectShare(_ share: Share) {
        if share.isFolder {
            coordinatorDelegate?.receivedSharesDidSelectFolder(folderId: share.resourceId)
        } else {
            coordinatorDelegate?.receivedSharesDidSelectFile(fileId: share.resourceId)
        }
    }

    func showCreatedShares() {
        coordinatorDelegate?.receivedSharesDidRequestCreatedShares()
    }

    // MARK: - Computed

    var activeShares: [Share] {
        shares.filter { $0.isActive }
    }

    var revokedShares: [Share] {
        shares.filter { !$0.isActive }
    }

    var isEmpty: Bool {
        shares.isEmpty && !isLoading
    }
}
