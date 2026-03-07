import Foundation
import Combine

/// Delegate for shares view model coordinator events
protocol SharesViewModelCoordinatorDelegate: AnyObject {
    func sharesDidSelectShare(_ share: Share)
    func sharesDidRequestNewShare()
}

/// View model for shares list screen
final class SharesViewModel: BaseViewModel {

    // MARK: - Properties

    private let shareRepository: ShareRepository
    weak var coordinatorDelegate: SharesViewModelCoordinatorDelegate?

    @Published var receivedShares: [Share] = []
    @Published var createdShares: [Share] = []
    @Published var selectedTab: Tab = .received
    @Published var isRefreshing: Bool = false

    enum Tab: Int, CaseIterable {
        case received = 0
        case created = 1

        var title: String {
            switch self {
            case .received: return "Received"
            case .created: return "Created"
            }
        }
    }

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
                async let received = shareRepository.getReceivedShares()
                async let created = shareRepository.getCreatedShares()

                let (fetchedReceived, fetchedCreated) = try await (received, created)

                await MainActor.run {
                    self.receivedShares = fetchedReceived
                    self.createdShares = fetchedCreated
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
        coordinatorDelegate?.sharesDidSelectShare(share)
    }

    func revokeShare(_ share: Share) {
        isLoading = true

        Task {
            do {
                try await shareRepository.revokeShare(shareId: share.id)
                await MainActor.run {
                    self.createdShares.removeAll { $0.id == share.id }
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    handleError(error)
                }
            }
        }
    }

    func setTab(_ tab: Tab) {
        selectedTab = tab
    }

    // MARK: - Computed

    var currentShares: [Share] {
        selectedTab == .received ? receivedShares : createdShares
    }

    var isEmpty: Bool {
        currentShares.isEmpty && !isLoading
    }

    var emptyMessage: String {
        selectedTab == .received
            ? "No files have been shared with you yet."
            : "You haven't shared any files yet."
    }
}
