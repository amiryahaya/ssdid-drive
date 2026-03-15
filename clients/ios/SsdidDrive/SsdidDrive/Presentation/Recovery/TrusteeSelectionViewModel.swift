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
    @Published var searchResults: [User] = []
    @Published var selectedTrustees: [User] = []
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
                    // Filter trustees by query (simple email/name search)
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

    func selectTrustee(_ user: User) {
        guard !selectedTrustees.contains(where: { $0.id == user.id }) else { return }
        guard selectedTrustees.count < totalShares else { return }

        selectedTrustees.append(user)
        searchQuery = ""
        searchResults = []
    }

    func removeTrustee(_ user: User) {
        selectedTrustees.removeAll { $0.id == user.id }
    }

    func completeSelection() {
        guard canComplete else { return }

        isLoading = true
        clearError()

        Task {
            do {
                // Setup recovery with selected trustees
                // TODO: Implement full Shamir split + trustee invitation flow
                // For now, this calls the low-level setupRecovery with placeholder values.
                // The full implementation should:
                // 1. Generate Shamir shares from the master key
                // 2. Encrypt each share for the respective trustee
                // 3. Send encrypted shares to trustees via the backend
                _ = try await recoveryRepository.setupRecovery(
                    serverShare: "",  // TODO: generate and split master key
                    keyProof: ""      // TODO: sign proof with master key
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
