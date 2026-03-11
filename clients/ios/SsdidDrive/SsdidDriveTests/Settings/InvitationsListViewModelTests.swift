import XCTest
import Combine
@testable import SsdidDrive

/// Unit tests for InvitationsListViewModel
@MainActor
final class InvitationsListViewModelTests: XCTestCase {

    // MARK: - Properties

    var mockAPIClient: MockAPIClient!
    var cancellables: Set<AnyCancellable>!

    // MARK: - Setup

    override func setUp() {
        super.setUp()
        mockAPIClient = MockAPIClient()
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() {
        mockAPIClient = nil
        cancellables = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func createViewModel() -> InvitationsListViewModel {
        InvitationsListViewModel(apiClient: mockAPIClient)
    }

    private var receivedInvitationsJSON: String {
        let expiresAt = ISO8601DateFormatter().string(from: Date().addingTimeInterval(86400 * 7))
        let createdAt = ISO8601DateFormatter().string(from: Date())
        return """
        {
            "data": [
                {
                    "id": "tinv_001",
                    "tenant_id": "ten_abc",
                    "tenant_name": "Alpha Corp",
                    "role": "member",
                    "invited_by": {
                        "id": "usr_inviter",
                        "email": "boss@alpha.com",
                        "display_name": "Boss"
                    },
                    "expires_at": "\(expiresAt)",
                    "created_at": "\(createdAt)"
                },
                {
                    "id": "tinv_002",
                    "tenant_id": "ten_def",
                    "tenant_name": "Beta Inc",
                    "role": "admin",
                    "invited_by": null,
                    "expires_at": "\(expiresAt)",
                    "created_at": "\(createdAt)"
                }
            ]
        }
        """
    }

    private var sentInvitationsJSON: String {
        let expiresAt = ISO8601DateFormatter().string(from: Date().addingTimeInterval(86400 * 7))
        let createdAt = ISO8601DateFormatter().string(from: Date())
        return """
        {
            "data": [
                {
                    "id": "sinv_001",
                    "email": "user1@example.com",
                    "role": "member",
                    "short_code": "CODE1234",
                    "status": "pending",
                    "message": null,
                    "tenant_id": "ten_abc",
                    "tenant_name": "Alpha Corp",
                    "created_at": "\(createdAt)",
                    "expires_at": "\(expiresAt)"
                }
            ]
        }
        """
    }

    private var emptyListJSON: String {
        return """
        {
            "data": []
        }
        """
    }

    private var acceptResponseJSON: String {
        return """
        {
            "data": {
                "tenant_id": "ten_abc",
                "role": "member"
            }
        }
        """
    }

    // MARK: - loadAll Tests

    func testLoadAll_loadsBothReceivedAndSent() async throws {
        let vm = createViewModel()
        mockAPIClient.setResponse(receivedInvitationsJSON, for: Constants.API.Endpoints.receivedInvitations)
        mockAPIClient.setResponse(sentInvitationsJSON, for: Constants.API.Endpoints.sentInvitations)

        vm.loadAll()
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(vm.receivedInvitations.count, 2)
        XCTAssertEqual(vm.sentInvitations.count, 1)
        XCTAssertFalse(vm.isLoading)
    }

    func testLoadAll_error_setsErrorMessage() async throws {
        let vm = createViewModel()
        mockAPIClient.shouldFailAllRequests = true
        mockAPIClient.failAllRequestsError = MockError.testError("Network failure")

        vm.loadAll()
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - acceptInvitation Tests

    func testAcceptInvitation_success_removesFromReceived() async throws {
        let vm = createViewModel()
        mockAPIClient.setResponse(receivedInvitationsJSON, for: Constants.API.Endpoints.receivedInvitations)
        mockAPIClient.setResponse(sentInvitationsJSON, for: Constants.API.Endpoints.sentInvitations)

        vm.loadAll()
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(vm.receivedInvitations.count, 2)

        let invitation = vm.receivedInvitations[0]
        mockAPIClient.setResponse(acceptResponseJSON, for: "/api/invitations/\(invitation.id)/accept")

        vm.acceptInvitation(invitation)
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(vm.receivedInvitations.count, 1)
        XCTAssertFalse(vm.receivedInvitations.contains(where: { $0.id == invitation.id }))
    }

    // MARK: - declineInvitation Tests

    func testDeclineInvitation_success_removesFromReceived() async throws {
        let vm = createViewModel()
        mockAPIClient.setResponse(receivedInvitationsJSON, for: Constants.API.Endpoints.receivedInvitations)
        mockAPIClient.setResponse(sentInvitationsJSON, for: Constants.API.Endpoints.sentInvitations)

        vm.loadAll()
        try await Task.sleep(nanoseconds: 300_000_000)

        let invitation = vm.receivedInvitations[0]

        // requestNoContent looks at the endpoint for errors, but won't fail if no error is set
        vm.declineInvitation(invitation)
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(vm.receivedInvitations.count, 1)
        XCTAssertFalse(vm.receivedInvitations.contains(where: { $0.id == invitation.id }))
    }

    // MARK: - revokeInvitation Tests

    func testRevokeInvitation_updatesStatusToRevoked() async throws {
        let vm = createViewModel()
        mockAPIClient.setResponse(receivedInvitationsJSON, for: Constants.API.Endpoints.receivedInvitations)
        mockAPIClient.setResponse(sentInvitationsJSON, for: Constants.API.Endpoints.sentInvitations)

        vm.loadAll()
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(vm.sentInvitations.count, 1)
        let invitation = vm.sentInvitations[0]
        XCTAssertEqual(invitation.status, .pending)

        let revokeEndpoint = Constants.API.Endpoints.revokeInvitation
            .replacingOccurrences(of: "{id}", with: invitation.id)

        // requestNoContent won't fail if no error is configured for this endpoint
        vm.revokeInvitation(invitation)
        try await Task.sleep(nanoseconds: 200_000_000)

        // Should still contain the invitation, but with revoked status
        XCTAssertEqual(vm.sentInvitations.count, 1)
        XCTAssertEqual(vm.sentInvitations[0].id, invitation.id)
        XCTAssertEqual(vm.sentInvitations[0].status, .revoked)
    }

    // MARK: - Error Handling Tests

    func testAcceptInvitation_error_setsErrorMessage() async throws {
        let vm = createViewModel()
        mockAPIClient.setResponse(receivedInvitationsJSON, for: Constants.API.Endpoints.receivedInvitations)
        mockAPIClient.setResponse(sentInvitationsJSON, for: Constants.API.Endpoints.sentInvitations)

        vm.loadAll()
        try await Task.sleep(nanoseconds: 300_000_000)

        let invitation = vm.receivedInvitations[0]
        mockAPIClient.setError(
            MockError.testError("Accept failed"),
            for: "/api/invitations/\(invitation.id)/accept"
        )

        vm.acceptInvitation(invitation)
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - Empty State Tests

    func testIsReceivedEmpty_whenEmpty_returnsTrue() async throws {
        let vm = createViewModel()
        mockAPIClient.setResponse(emptyListJSON, for: Constants.API.Endpoints.receivedInvitations)
        mockAPIClient.setResponse(emptyListJSON, for: Constants.API.Endpoints.sentInvitations)

        vm.loadAll()
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertTrue(vm.isReceivedEmpty)
    }

    func testIsSentEmpty_whenEmpty_returnsTrue() async throws {
        let vm = createViewModel()
        mockAPIClient.setResponse(emptyListJSON, for: Constants.API.Endpoints.receivedInvitations)
        mockAPIClient.setResponse(emptyListJSON, for: Constants.API.Endpoints.sentInvitations)

        vm.loadAll()
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertTrue(vm.isSentEmpty)
    }
}
