import Foundation
import Combine

/// Delegate for create invitation view model events
protocol CreateInvitationViewModelDelegate: AnyObject {
    func createInvitationDidComplete()
}

/// View model for creating a new tenant invitation (Admin/Owner only)
@MainActor
final class CreateInvitationViewModel: ObservableObject {

    // MARK: - State

    enum ViewState: Equatable {
        case idle
        case creating
        case success
        case error(String)
    }

    // MARK: - Published Properties

    @Published var email: String = ""
    @Published var selectedRole: UserRole = .member
    @Published var message: String = ""
    @Published var state: ViewState = .idle
    @Published var createdInvitation: SentInvitation?

    // MARK: - Properties

    private let apiClient: any APIClientProtocol
    private let callerRole: UserRole
    weak var delegate: CreateInvitationViewModelDelegate?

    /// Maximum message length
    let maxMessageLength = 500

    // MARK: - Computed Properties

    /// Available roles the caller can assign
    var availableRoles: [UserRole] {
        switch callerRole {
        case .owner:
            return [.member, .admin]
        case .admin:
            return [.member]
        default:
            return [.member]
        }
    }

    /// Whether the email is valid (if provided)
    var isEmailValid: Bool {
        if email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true // Optional field
        }
        let emailRegex = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return email.range(of: emailRegex, options: .regularExpression) != nil
    }

    /// Whether creation is allowed
    var canCreate: Bool {
        isEmailValid && state != .creating && message.count <= maxMessageLength
    }

    /// Error message extracted from state
    var errorMessage: String? {
        if case .error(let msg) = state {
            return msg
        }
        return nil
    }

    /// Remaining characters for message
    var remainingCharacters: Int {
        maxMessageLength - message.count
    }

    // MARK: - Initialization

    init(apiClient: any APIClientProtocol, callerRole: UserRole) {
        self.apiClient = apiClient
        self.callerRole = callerRole
    }

    // MARK: - Actions

    /// Create a new invitation
    func createInvitation() {
        guard canCreate else { return }

        state = .creating

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)

        let request = CreateInvitationRequest(
            email: trimmedEmail.isEmpty ? nil : trimmedEmail,
            role: selectedRole.rawValue,
            message: trimmedMessage.isEmpty ? nil : trimmedMessage
        )

        Task {
            do {
                let response: CreateInvitationResponse = try await apiClient.request(
                    Constants.API.Endpoints.createInvitation,
                    method: .post,
                    body: request,
                    queryItems: nil,
                    requiresAuth: true
                )

                self.createdInvitation = response.data
                self.state = .success
            } catch let error as APIClient.APIError {
                self.state = .error(error.errorDescription ?? "Failed to create invitation.")
            } catch {
                self.state = .error(error.localizedDescription)
            }
        }
    }

    /// Reset to create another invitation
    func resetForNew() {
        email = ""
        message = ""
        selectedRole = .member
        createdInvitation = nil
        state = .idle
    }
}
