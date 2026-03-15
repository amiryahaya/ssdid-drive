import Foundation
import Combine

/// Delegate for tenant request view model coordinator events
protocol TenantRequestViewModelDelegate: AnyObject {
    func tenantRequestDidComplete()
}

/// View model for the "Request Organization" screen where users submit a request
/// to create a new tenant/organization.
@MainActor
final class TenantRequestViewModel: ObservableObject {

    // MARK: - State

    enum ViewState: Equatable {
        case idle
        case loading
        case submitted
        case error(String)
    }

    // MARK: - Published Properties

    @Published var organizationName: String = ""
    @Published var reason: String = ""
    @Published var state: ViewState = .idle

    // MARK: - Properties

    private let apiClient: any APIClientProtocol
    weak var delegate: TenantRequestViewModelDelegate?

    // MARK: - Constants

    static let maxReasonLength = 500

    // MARK: - Computed Properties

    /// Whether the submit button should be enabled
    var canSubmit: Bool {
        !organizationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && state != .loading
    }

    /// Error message extracted from state
    var errorMessage: String? {
        if case .error(let message) = state {
            return message
        }
        return nil
    }

    /// Remaining characters for the reason field
    var reasonRemainingCharacters: Int {
        max(0, Self.maxReasonLength - reason.count)
    }

    // MARK: - Initialization

    init(apiClient: any APIClientProtocol) {
        self.apiClient = apiClient
    }

    // MARK: - Actions

    /// Submit a tenant creation request to the API
    func submitRequest() {
        let name = organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        state = .loading

        Task {
            do {
                let body = TenantRequestBody(
                    organizationName: name,
                    reason: reason.trimmingCharacters(in: .whitespacesAndNewlines)
                )

                let _: TenantRequestResponse = try await apiClient.request(
                    "/api/tenant-requests",
                    method: .post,
                    body: body,
                    queryItems: nil,
                    requiresAuth: true
                )

                self.state = .submitted
                self.delegate?.tenantRequestDidComplete()
            } catch let error as APIClient.APIError {
                switch error {
                case .httpError(409, _):
                    self.state = .error("You already have a pending request.")
                default:
                    self.state = .error(error.errorDescription ?? "Failed to submit request.")
                }
            } catch {
                self.state = .error(error.localizedDescription)
            }
        }
    }

    /// Reset the view to initial state
    func reset() {
        organizationName = ""
        reason = ""
        state = .idle
    }
}

// MARK: - Request / Response Models

struct TenantRequestBody: Encodable {
    let organizationName: String
    let reason: String

    enum CodingKeys: String, CodingKey {
        case organizationName = "organization_name"
        case reason
    }
}

struct TenantRequestResponse: Decodable {
    let id: String?
    let status: String?
}
