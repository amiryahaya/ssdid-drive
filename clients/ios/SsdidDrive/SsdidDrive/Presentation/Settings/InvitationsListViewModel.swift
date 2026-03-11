import Foundation
import Combine

/// View model for the invitations list (received + sent)
final class InvitationsListViewModel: BaseViewModel {

    // MARK: - Types

    enum Tab: Int, CaseIterable {
        case received = 0
        case sent = 1

        var title: String {
            switch self {
            case .received: return "Received"
            case .sent: return "Sent"
            }
        }
    }

    // MARK: - Published Properties

    @Published var selectedTab: Tab = .received
    @Published var receivedInvitations: [TenantInvitation] = []
    @Published var sentInvitations: [SentInvitation] = []
    @Published var isRefreshing: Bool = false

    // MARK: - Properties

    private let apiClient: any APIClientProtocol

    // MARK: - Computed Properties

    var isReceivedEmpty: Bool {
        receivedInvitations.isEmpty && !isLoading
    }

    var isSentEmpty: Bool {
        sentInvitations.isEmpty && !isLoading
    }

    // MARK: - Initialization

    init(apiClient: any APIClientProtocol) {
        self.apiClient = apiClient
        super.init()
    }

    // MARK: - Data Loading

    func loadAll() {
        isLoading = true
        clearError()

        Task {
            do {
                async let receivedTask: ReceivedInvitationsResponse = apiClient.request(
                    Constants.API.Endpoints.receivedInvitations,
                    method: .get,
                    body: nil,
                    queryItems: nil,
                    requiresAuth: true
                )

                async let sentTask: SentInvitationsResponse = apiClient.request(
                    Constants.API.Endpoints.sentInvitations,
                    method: .get,
                    body: nil,
                    queryItems: nil,
                    requiresAuth: true
                )

                let (received, sent) = try await (receivedTask, sentTask)

                self.receivedInvitations = received.data
                self.sentInvitations = sent.data
                self.isLoading = false
                self.isRefreshing = false
            } catch {
                handleError(error)
                self.isRefreshing = false
            }
        }
    }

    func refresh() {
        isRefreshing = true
        loadAll()
    }

    // MARK: - Received Actions

    func acceptInvitation(_ invitation: TenantInvitation) {
        isLoading = true

        Task {
            do {
                let _: AcceptCodeInvitationResponse = try await apiClient.request(
                    "/api/invitations/\(invitation.id)/accept",
                    method: .post,
                    body: nil,
                    queryItems: nil,
                    requiresAuth: true
                )

                self.receivedInvitations.removeAll { $0.id == invitation.id }
                self.isLoading = false
            } catch {
                handleError(error)
            }
        }
    }

    func declineInvitation(_ invitation: TenantInvitation) {
        isLoading = true

        Task {
            do {
                try await apiClient.requestNoContent(
                    "/api/invitations/\(invitation.id)/decline",
                    method: .post,
                    body: nil,
                    queryItems: nil,
                    requiresAuth: true
                )

                self.receivedInvitations.removeAll { $0.id == invitation.id }
                self.isLoading = false
            } catch {
                handleError(error)
            }
        }
    }

    // MARK: - Sent Actions

    func revokeInvitation(_ invitation: SentInvitation) {
        isLoading = true

        let endpoint = Constants.API.Endpoints.revokeInvitation
            .replacingOccurrences(of: "{id}", with: invitation.id)

        Task {
            do {
                try await apiClient.requestNoContent(
                    endpoint,
                    method: .delete,
                    body: nil,
                    queryItems: nil,
                    requiresAuth: true
                )

                if let index = self.sentInvitations.firstIndex(where: { $0.id == invitation.id }) {
                    // Update status locally to .revoked instead of removing
                    let original = self.sentInvitations[index]
                    let revoked = SentInvitation(
                        id: original.id,
                        email: original.email,
                        role: original.role,
                        shortCode: original.shortCode,
                        status: .revoked,
                        message: original.message,
                        tenantId: original.tenantId,
                        tenantName: original.tenantName,
                        createdAt: original.createdAt,
                        expiresAt: original.expiresAt
                    )
                    self.sentInvitations[index] = revoked
                }
                self.isLoading = false
            } catch {
                handleError(error)
            }
        }
    }
}
