import Foundation
import Combine

/// Delegate for trustee selection view model coordinator events
protocol TrusteeSelectionViewModelCoordinatorDelegate: AnyObject {
    func trusteeSelectionDidComplete()
}

/// View model for trustee selection screen
final class TrusteeSelectionViewModel: BaseViewModel {

    // MARK: - Properties

    private let recoveryRepository: RecoveryRepository
    private let masterKey: Data
    weak var coordinatorDelegate: TrusteeSelectionViewModelCoordinatorDelegate?

    let totalShares: Int
    @Published var searchQuery: String = ""
    @Published var searchResults: [Trustee] = []
    @Published var selectedTrustees: [Trustee] = []
    @Published var isSearching: Bool = false

    private var searchDebouncer: AnyCancellable?

    // MARK: - Initialization

    init(totalShares: Int, masterKey: Data, recoveryRepository: RecoveryRepository) {
        self.totalShares = totalShares
        self.masterKey = masterKey
        self.recoveryRepository = recoveryRepository
        super.init()

        setupSearchDebouncer()
    }

    private func setupSearchDebouncer() {
        searchDebouncer = $searchQuery
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] query in
                self?.performSearch(query)
            }
    }

    // MARK: - Search

    private func performSearch(_ query: String) {
        guard query.count >= 2 else {
            searchResults = []
            return
        }

        isSearching = true

        Task {
            do {
                // Search org members via the members endpoint, filtering locally by query
                let members = try await recoveryRepository.searchMembers(query: query)
                await MainActor.run {
                    // Exclude already-selected trustees from results
                    let selectedIds = Set(self.selectedTrustees.map { $0.userId })
                    self.searchResults = members.filter { !selectedIds.contains($0.userId) }
                    self.isSearching = false
                }
            } catch {
                await MainActor.run {
                    self.searchResults = []
                    self.isSearching = false
                }
            }
        }
    }

    // MARK: - Actions

    func selectTrustee(_ trustee: Trustee) {
        guard !selectedTrustees.contains(where: { $0.id == trustee.id }) else { return }
        guard selectedTrustees.count < totalShares else { return }

        selectedTrustees.append(trustee)
        searchQuery = ""
        searchResults = []
    }

    func removeTrustee(_ trustee: Trustee) {
        selectedTrustees.removeAll { $0.id == trustee.id }
    }

    /// Split the master key into Shamir shares, one per selected trustee, and submit to the backend.
    func completeSelection() {
        guard canComplete else { return }
        isLoading = true
        clearError()

        Task {
            do {
                let threshold = max(2, selectedTrustees.count - 1)
                let shares = try ShamirSecretSharing.split(
                    secret: masterKey,
                    threshold: threshold,
                    totalShares: selectedTrustees.count
                )

                // Each share is serialized (1-byte index prefix + share data) and base64-encoded.
                // Shamir provides information-theoretic security — a single share reveals nothing
                // about the secret without threshold-many other shares.
                let shareRequests: [TrusteeShareRequest] = zip(selectedTrustees, shares).map { trustee, share in
                    TrusteeShareRequest(
                        trusteeUserId: trustee.userId,
                        encryptedShare: share.serialize().base64EncodedString(),
                        shareIndex: Int(share.index)
                    )
                }

                try await recoveryRepository.setupTrustees(
                    threshold: threshold,
                    shares: shareRequests
                )

                await MainActor.run {
                    self.isLoading = false
                    self.coordinatorDelegate?.trusteeSelectionDidComplete()
                }
            } catch {
                await MainActor.run {
                    handleError(error)
                }
            }
        }
    }

    // MARK: - Computed

    var canComplete: Bool {
        selectedTrustees.count >= 2
    }

    var selectionStatus: String {
        "\(selectedTrustees.count) of \(totalShares) trustees selected"
    }
}
