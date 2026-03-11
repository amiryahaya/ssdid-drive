import XCTest
import Combine
@testable import SsdidDrive

/// Unit tests for JoinTenantViewModel
@MainActor
final class JoinTenantViewModelTests: XCTestCase {

    // MARK: - Properties

    var mockAPIClient: MockAPIClient!
    var mockTenantRepository: MockTenantRepository!
    var mockDelegate: MockJoinTenantDelegate!
    var cancellables: Set<AnyCancellable>!

    // MARK: - Setup

    override func setUp() {
        super.setUp()
        mockAPIClient = MockAPIClient()
        mockTenantRepository = MockTenantRepository()
        mockDelegate = MockJoinTenantDelegate()
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() {
        mockAPIClient = nil
        mockTenantRepository = nil
        mockDelegate = nil
        cancellables = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func createAuthenticatedViewModel() -> JoinTenantViewModel {
        let vm = JoinTenantViewModel(apiClient: mockAPIClient, tenantRepository: mockTenantRepository)
        vm.delegate = mockDelegate
        return vm
    }

    private func createUnauthenticatedViewModel() -> JoinTenantViewModel {
        let vm = JoinTenantViewModel(apiClient: mockAPIClient)
        vm.delegate = mockDelegate
        return vm
    }

    private var validCodeInvitationJSON: String {
        let expiresAt = ISO8601DateFormatter().string(from: Date().addingTimeInterval(86400 * 7))
        return """
        {
            "data": {
                "id": "inv_abc123",
                "tenant_name": "Test Corp",
                "role": "member",
                "short_code": "ABCD1234",
                "expires_at": "\(expiresAt)"
            }
        }
        """
    }

    private var expiredCodeInvitationJSON: String {
        let expiresAt = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-86400))
        return """
        {
            "data": {
                "id": "inv_expired",
                "tenant_name": "Test Corp",
                "role": "member",
                "short_code": "EXPR1234",
                "expires_at": "\(expiresAt)"
            }
        }
        """
    }

    private var acceptResponseJSON: String {
        return """
        {
            "data": {
                "tenant_id": "ten_123",
                "role": "member"
            }
        }
        """
    }

    // MARK: - canLookUp Validation Tests

    func testCanLookUp_emptyCode_returnsFalse() {
        let vm = createAuthenticatedViewModel()
        vm.code = ""
        XCTAssertFalse(vm.canLookUp)
    }

    func testCanLookUp_shortCode_returnsFalse() {
        let vm = createAuthenticatedViewModel()
        vm.code = "AB"
        XCTAssertFalse(vm.canLookUp)
    }

    func testCanLookUp_threeCharCode_returnsFalse() {
        let vm = createAuthenticatedViewModel()
        vm.code = "ABC"
        XCTAssertFalse(vm.canLookUp)
    }

    func testCanLookUp_fourCharCode_returnsTrue() {
        let vm = createAuthenticatedViewModel()
        vm.code = "ABCD"
        XCTAssertTrue(vm.canLookUp)
    }

    func testCanLookUp_longCode_returnsTrue() {
        let vm = createAuthenticatedViewModel()
        vm.code = "ABCD1234"
        XCTAssertTrue(vm.canLookUp)
    }

    func testCanLookUp_whileLoadingState_returnsFalse() {
        let vm = createAuthenticatedViewModel()
        vm.code = "ABCD1234"
        vm.state = .lookingUp
        XCTAssertFalse(vm.canLookUp)
    }

    func testCanLookUp_whileJoiningState_returnsFalse() {
        let vm = createAuthenticatedViewModel()
        vm.code = "ABCD1234"
        vm.state = .joining
        XCTAssertFalse(vm.canLookUp)
    }

    func testCanLookUp_withWhitespace_usesTrimmedLength() {
        let vm = createAuthenticatedViewModel()
        vm.code = "  AB  " // Trimmed is "AB" (2 chars)
        XCTAssertFalse(vm.canLookUp)
    }

    // MARK: - sanitizedCode Tests

    func testSanitizedCode_uppercases() {
        let vm = createAuthenticatedViewModel()
        vm.code = "abcd1234"
        XCTAssertEqual(vm.sanitizedCode, "ABCD1234")
    }

    func testSanitizedCode_trims() {
        let vm = createAuthenticatedViewModel()
        vm.code = "  ABCD  "
        XCTAssertEqual(vm.sanitizedCode, "ABCD")
    }

    func testSanitizedCode_uppercasesAndTrims() {
        let vm = createAuthenticatedViewModel()
        vm.code = " abcd1234 \n"
        XCTAssertEqual(vm.sanitizedCode, "ABCD1234")
    }

    // MARK: - lookUpCode Tests

    func testLookUpCode_success_setsPreviewState() async throws {
        let vm = createAuthenticatedViewModel()
        vm.code = "ABCD1234"
        mockAPIClient.setResponse(validCodeInvitationJSON, for: "/api/invitations/code/ABCD1234")

        vm.lookUpCode()
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(vm.state, .preview)
        XCTAssertNotNil(vm.invitation)
        XCTAssertEqual(vm.invitation?.tenantName, "Test Corp")
    }

    func testLookUpCode_expired_setsErrorState() async throws {
        let vm = createAuthenticatedViewModel()
        vm.code = "EXPR1234"
        mockAPIClient.setResponse(expiredCodeInvitationJSON, for: "/api/invitations/code/EXPR1234")

        vm.lookUpCode()
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(vm.state, .error("This invite code has expired."))
    }

    func testLookUpCode_notFound_setsErrorState() async throws {
        let vm = createAuthenticatedViewModel()
        vm.code = "INVALID1"
        mockAPIClient.setAPIError(.notFound, for: "/api/invitations/code/INVALID1")

        vm.lookUpCode()
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(vm.state, .error("Invalid invite code. Please check and try again."))
    }

    func testLookUpCode_genericError_setsErrorState() async throws {
        let vm = createAuthenticatedViewModel()
        vm.code = "FAIL1234"
        mockAPIClient.setError(MockError.testError("Server error"), for: "/api/invitations/code/FAIL1234")

        vm.lookUpCode()
        try await Task.sleep(nanoseconds: 200_000_000)

        if case .error(let message) = vm.state {
            XCTAssertTrue(message.contains("Server error"))
        } else {
            XCTFail("Expected error state")
        }
    }

    // MARK: - acceptInvitation Tests (Unauthenticated)

    func testAcceptInvitation_unauthenticated_callsDelegateRequestLogin() async throws {
        let vm = createUnauthenticatedViewModel()
        vm.code = "ABCD1234"
        mockAPIClient.setResponse(validCodeInvitationJSON, for: "/api/invitations/code/ABCD1234")

        vm.lookUpCode()
        try await Task.sleep(nanoseconds: 200_000_000)

        vm.acceptInvitation()

        XCTAssertTrue(mockDelegate.didRequestLoginCalled)
        XCTAssertEqual(mockDelegate.lastInviteCode, "ABCD1234")
    }

    // MARK: - acceptInvitation Tests (Authenticated)

    func testAcceptInvitation_authenticated_success_callsDelegateComplete() async throws {
        let vm = createAuthenticatedViewModel()
        vm.code = "ABCD1234"
        mockAPIClient.setResponse(validCodeInvitationJSON, for: "/api/invitations/code/ABCD1234")

        vm.lookUpCode()
        try await Task.sleep(nanoseconds: 200_000_000)

        mockAPIClient.setResponse(acceptResponseJSON, for: "/api/invitations/inv_abc123/accept")

        vm.acceptInvitation()
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(vm.state, .success)
        XCTAssertTrue(mockDelegate.didCompleteCalled)
    }

    func testAcceptInvitation_authenticated_409_setsError() async throws {
        let vm = createAuthenticatedViewModel()
        vm.code = "ABCD1234"
        mockAPIClient.setResponse(validCodeInvitationJSON, for: "/api/invitations/code/ABCD1234")

        vm.lookUpCode()
        try await Task.sleep(nanoseconds: 200_000_000)

        mockAPIClient.setAPIError(
            .httpError(statusCode: 409, message: "Conflict"),
            for: "/api/invitations/inv_abc123/accept"
        )

        vm.acceptInvitation()
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(vm.state, .error("You are already a member of this organization."))
    }

    // MARK: - reset Tests

    func testReset_clearsState() async throws {
        let vm = createAuthenticatedViewModel()
        vm.code = "ABCD1234"
        mockAPIClient.setResponse(validCodeInvitationJSON, for: "/api/invitations/code/ABCD1234")

        vm.lookUpCode()
        try await Task.sleep(nanoseconds: 200_000_000)

        vm.reset()

        XCTAssertEqual(vm.code, "")
        XCTAssertNil(vm.invitation)
        XCTAssertEqual(vm.state, .idle)
    }

    // MARK: - clearPreview Tests

    func testClearPreview_returnsToIdle() async throws {
        let vm = createAuthenticatedViewModel()
        vm.code = "ABCD1234"
        mockAPIClient.setResponse(validCodeInvitationJSON, for: "/api/invitations/code/ABCD1234")

        vm.lookUpCode()
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(vm.state, .preview)

        vm.clearPreview()

        XCTAssertNil(vm.invitation)
        XCTAssertEqual(vm.state, .idle)
        // Code is preserved
        XCTAssertEqual(vm.code, "ABCD1234")
    }
}

// MARK: - Mock Delegate

final class MockJoinTenantDelegate: JoinTenantViewModelDelegate {
    var didCompleteCalled = false
    var didRequestLoginCalled = false
    var lastInviteCode: String?

    func joinTenantDidComplete() {
        didCompleteCalled = true
    }

    func joinTenantDidRequestLogin(inviteCode: String) {
        didRequestLoginCalled = true
        lastInviteCode = inviteCode
    }
}
