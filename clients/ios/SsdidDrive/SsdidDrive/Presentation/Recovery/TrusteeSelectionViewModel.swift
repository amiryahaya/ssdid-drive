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
                    self.searchResults = trustees.compactMap { trustee in
                        guard trustee.email.lowercased().contains(query.lowercased()) ||
                              (trustee.displayName?.lowercased().contains(query.lowercased()) ?? false) else {
                            return nil
                        }
                        // Convert Trustee to User for selection
                        return User(
                            id: trustee.userId,
                            email: trustee.email,
                            displayName: trustee.displayName,
                            tenantId: nil,
                            createdAt: Date(),
                            updatedAt: Date(),
                            encryptedMasterKey: nil,
                            keyDerivationSalt: nil
                        )
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
                let trusteeEmails = selectedTrustees.map { $0.email }
                let threshold = max(2, selectedTrustees.count / 2 + 1) // Default threshold

                _ = try await recoveryRepository.setupRecovery(
                    threshold: threshold,
                    trusteeEmails: trusteeEmails
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
