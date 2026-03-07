import Foundation
import Combine

/// Delegate for share file view model coordinator events
protocol ShareFileViewModelCoordinatorDelegate: AnyObject {
    func shareFileDidComplete()
    func shareFileDidCancel()
}

/// View model for share file screen
final class ShareFileViewModel: BaseViewModel {

    // MARK: - Properties

    private let shareRepository: ShareRepository
    private let cryptoManager: CryptoManager
    weak var coordinatorDelegate: ShareFileViewModelCoordinatorDelegate?

    let file: FileItem
    @Published var searchQuery: String = ""
    @Published var searchResults: [User] = []
    @Published var selectedUser: User?
    @Published var permission: SharePermission = .read
    @Published var expirationDate: Date?
    @Published var isSearching: Bool = false

    enum SharePermission: String, CaseIterable {
        case read = "View Only"
        case write = "Edit"
        case admin = "Full Access"

        var description: String {
            switch self {
            case .read: return "Can view the file but not modify"
            case .write: return "Can view and modify the file"
            case .admin: return "Can view, modify, and share the file"
            }
        }
    }

    private var searchDebouncer: AnyCancellable?

    // MARK: - Initialization

    init(file: FileItem, shareRepository: ShareRepository, cryptoManager: CryptoManager) {
        self.file = file
        self.shareRepository = shareRepository
        self.cryptoManager = cryptoManager
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
                let users = try await shareRepository.searchUsers(query: query)
                await MainActor.run {
                    self.searchResults = users
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

    func selectUser(_ user: User) {
        selectedUser = user
        searchQuery = ""
        searchResults = []
    }

    func clearSelectedUser() {
        selectedUser = nil
    }

    func setPermission(_ permission: SharePermission) {
        self.permission = permission
    }

    func setExpirationDate(_ date: Date?) {
        self.expirationDate = date
    }

    func createShare() {
        guard let recipient = selectedUser else { return }

        // Validate that recipient has public keys for secure sharing
        guard let recipientPublicKeys = recipient.publicKeys else {
            errorMessage = "Cannot share: recipient's public keys are not available. They may need to complete registration."
            return
        }

        // Validate that the file has an encrypted key
        guard let fileEncryptedKey = file.encryptedKey else {
            errorMessage = "Cannot share: file encryption key is missing."
            return
        }

        isLoading = true
        clearError()

        Task {
            do {
                // Map local permission to Share.Permission
                let sharePermission: Share.Permission
                switch permission {
                case .read: sharePermission = .read
                case .write: sharePermission = .write
                case .admin: sharePermission = .admin
                }

                // Create share with proper key wrapping for the recipient
                _ = try await shareRepository.shareFile(
                    fileId: file.id,
                    granteeId: recipient.id,
                    granteePublicKeys: recipientPublicKeys,
                    fileEncryptedKey: fileEncryptedKey,
                    permission: sharePermission,
                    expiresAt: expirationDate
                )

                await MainActor.run {
                    self.isLoading = false
                    self.coordinatorDelegate?.shareFileDidComplete()
                }
            } catch {
                await MainActor.run {
                    handleError(error)
                }
            }
        }
    }

    func cancel() {
        coordinatorDelegate?.shareFileDidCancel()
    }

    // MARK: - Computed

    var canShare: Bool {
        guard let user = selectedUser else { return false }
        // Ensure recipient has public keys and file has encrypted key
        return user.publicKeys != nil && file.encryptedKey != nil
    }

    /// Message explaining why sharing is not available
    var shareUnavailableReason: String? {
        guard selectedUser != nil else { return nil }

        if selectedUser?.publicKeys == nil {
            return "This user hasn't set up secure sharing yet"
        }
        if file.encryptedKey == nil {
            return "This file doesn't have encryption enabled"
        }
        return nil
    }
}
