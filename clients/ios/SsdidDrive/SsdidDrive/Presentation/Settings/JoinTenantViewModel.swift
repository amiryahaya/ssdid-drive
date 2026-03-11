import Foundation
import Combine

/// Delegate for join tenant view model coordinator events
protocol JoinTenantViewModelDelegate: AnyObject {
    func joinTenantDidComplete()
    func joinTenantDidRequestLogin(inviteCode: String)
}

/// View model for the "Join Tenant" screen where users enter a short invite code.
/// Supports two flows:
/// - Authenticated users: look up code, preview, accept
/// - Unauthenticated users: look up code, preview, redirect to login with invite context
@MainActor
final class JoinTenantViewModel: ObservableObject {

    // MARK: - State

    enum ViewState: Equatable {
        case idle
        case lookingUp
        case preview
        case joining
        case success
        case error(String)
    }

    // MARK: - Published Properties

    @Published var code: String = ""
    @Published var state: ViewState = .idle
    @Published var invitation: CodeInvitation?

    // MARK: - Properties

    private let apiClient: APIClient
    private let tenantRepository: TenantRepository?
    private let isAuthenticated: Bool
    weak var delegate: JoinTenantViewModelDelegate?

    // MARK: - Computed Properties

    /// Sanitized code: uppercased, trimmed
    var sanitizedCode: String {
        code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    /// Whether the look up button should be enabled
    var canLookUp: Bool {
        sanitizedCode.count >= 4 && state != .lookingUp && state != .joining
    }

    /// Error message extracted from state
    var errorMessage: String? {
        if case .error(let message) = state {
            return message
        }
        return nil
    }

    // MARK: - Initialization

    /// Initialize for authenticated users (from settings)
    init(apiClient: APIClient, tenantRepository: TenantRepository) {
        self.apiClient = apiClient
        self.tenantRepository = tenantRepository
        self.isAuthenticated = true
    }

    /// Initialize for unauthenticated users (from login screen)
    init(apiClient: APIClient) {
        self.apiClient = apiClient
        self.tenantRepository = nil
        self.isAuthenticated = false
    }

    // MARK: - Actions

    /// Look up invite code via the public API endpoint
    func lookUpCode() {
        let codeValue = sanitizedCode
        guard !codeValue.isEmpty else { return }

        state = .lookingUp
        invitation = nil

        Task {
            do {
                let response: CodeInvitationResponse = try await apiClient.request(
                    "/api/invitations/code/\(codeValue)",
                    method: .get,
                    requiresAuth: false
                )

                let invite = response.data
                if invite.isExpired {
                    self.state = .error("This invite code has expired.")
                } else {
                    self.invitation = invite
                    self.state = .preview
                }
            } catch let error as APIClient.APIError {
                switch error {
                case .notFound:
                    self.state = .error("Invalid invite code. Please check and try again.")
                default:
                    self.state = .error(error.errorDescription ?? "An error occurred.")
                }
            } catch {
                self.state = .error(error.localizedDescription)
            }
        }
    }

    /// Accept the invitation (authenticated flow only)
    func acceptInvitation() {
        guard let invitation = invitation else { return }

        if !isAuthenticated {
            // For unauthenticated users, redirect to login with invite context
            delegate?.joinTenantDidRequestLogin(inviteCode: sanitizedCode)
            return
        }

        state = .joining

        Task {
            do {
                let _: AcceptCodeInvitationResponse = try await apiClient.request(
                    "/api/invitations/\(invitation.id)/accept",
                    method: .post,
                    requiresAuth: true
                )

                // Refresh tenant list
                if let tenantRepository = tenantRepository {
                    _ = try? await tenantRepository.refreshTenants()
                }

                self.state = .success
                self.delegate?.joinTenantDidComplete()
            } catch let error as APIClient.APIError {
                switch error {
                case .httpError(409, _):
                    self.state = .error("You are already a member of this organization.")
                default:
                    self.state = .error(error.errorDescription ?? "Failed to join organization.")
                }
            } catch {
                self.state = .error(error.localizedDescription)
            }
        }
    }

    /// Reset the view to initial state
    func reset() {
        code = ""
        invitation = nil
        state = .idle
    }

    /// Go back from preview to code entry
    func clearPreview() {
        invitation = nil
        state = .idle
    }
}
