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
    weak var coordinatorDelegate: TrusteeSelectionViewModelCoordinatorDelegate?

    let totalShares: Int
    @Published var searchQuery: String = ""
    @Published var searchResults: [Trustee] = []
    @Published var selectedTrustees: [Trustee] = []
    @Published var isSearching: Bool = false

    private var searchDebouncer: AnyCancellable?

    // MARK: - Initialization

    init(totalShares: Int, recoveryRepository: RecoveryRepository) {
        self.totalShares = totalShares
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
                let trustees = try await recoveryRepository.getTrustees()
                await MainActor.run {
                    // Filter trustees by query against email and display name
                    self.searchResults = trustees.filter { trustee in
                        trustee.email.lowercased().contains(query.lowercased()) ||
                        (trustee.displayName?.lowercased().contains(query.lowercased()) ?? false)
                    }
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

    /// Call after generating and encrypting Shamir shares for each selected trustee.
    /// - Parameter encryptedShares: Map of trustee.userId → base64-encoded encrypted share.
    func completeSelection(encryptedShares: [String: String] = [:]) {
        guard canComplete else { return }

        isLoading = true
        clearError()

        Task {
            do {
                // Build per-trustee share payloads
                let threshold = max(2, selectedTrustees.count - 1)
                let shareRequests: [TrusteeShareRequest] = selectedTrustees.enumerated().map { index, trustee in
                    TrusteeShareRequest(
                        trusteeUserId: trustee.userId,
                        encryptedShare: encryptedShares[trustee.userId] ?? "",
                        shareIndex: index + 1
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
