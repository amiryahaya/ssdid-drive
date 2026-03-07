import Foundation
import Combine

/// Represents a pending share invitation
struct Invitation: Identifiable, Hashable {
    let id: String
    let fileName: String
    let ownerEmail: String
    let createdAt: Date
    let expiresAt: Date?
}

/// View model for invitations screen
final class InvitationsViewModel: BaseViewModel {

    // MARK: - Properties

    private let shareRepository: ShareRepository

    @Published var invitations: [Invitation] = []
    @Published var isRefreshing: Bool = false

    // MARK: - Initialization

    init(shareRepository: ShareRepository) {
        self.shareRepository = shareRepository
        super.init()
    }

    // MARK: - Data Loading

    func loadInvitations() {
        isLoading = true
        clearError()

        Task {
            do {
                let shareInvitations = try await shareRepository.getInvitations()
                await MainActor.run {
                    self.invitations = shareInvitations.map { invitation in
                        Invitation(
                            id: invitation.id,
                            fileName: invitation.resourceName,
                            ownerEmail: invitation.senderEmail,
                            createdAt: invitation.createdAt,
                            expiresAt: invitation.expiresAt
                        )
                    }
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

    func refreshInvitations() {
        isRefreshing = true
        loadInvitations()
    }

    // MARK: - Actions

    func acceptInvitation(_ invitation: Invitation) {
        isLoading = true

        Task {
            do {
                try await shareRepository.acceptInvitation(invitationId: invitation.id)
                await MainActor.run {
                    self.invitations.removeAll { $0.id == invitation.id }
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    handleError(error)
                }
            }
        }
    }

    func declineInvitation(_ invitation: Invitation) {
        isLoading = true

        Task {
            do {
                try await shareRepository.declineInvitation(invitationId: invitation.id)
                await MainActor.run {
                    self.invitations.removeAll { $0.id == invitation.id }
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

    var isEmpty: Bool {
        invitations.isEmpty && !isLoading
    }
}
