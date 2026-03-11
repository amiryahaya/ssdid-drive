import XCTest
import Combine
@testable import SsdidDrive

/// Unit tests for CreateInvitationViewModel
@MainActor
final class CreateInvitationViewModelTests: XCTestCase {

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

    private func createViewModel(callerRole: UserRole = .owner) -> CreateInvitationViewModel {
        CreateInvitationViewModel(apiClient: mockAPIClient, callerRole: callerRole)
    }

    private var successResponseJSON: String {
        let createdAt = ISO8601DateFormatter().string(from: Date())
        let expiresAt = ISO8601DateFormatter().string(from: Date().addingTimeInterval(86400 * 7))
        return """
        {
            "data": {
                "id": "inv_new123",
                "email": "test@example.com",
                "role": "member",
                "short_code": "XY9Z1234",
                "status": "pending",
                "message": "Welcome!",
                "tenant_id": "ten_abc",
                "tenant_name": "Test Corp",
                "created_at": "\(createdAt)",
                "expires_at": "\(expiresAt)"
            }
        }
        """
    }

    // MARK: - availableRoles Tests

    func testAvailableRoles_forOwner_returnsMemberAndAdmin() {
        let vm = createViewModel(callerRole: .owner)
        XCTAssertEqual(vm.availableRoles, [.member, .admin])
    }

    func testAvailableRoles_forAdmin_returnsMemberOnly() {
        let vm = createViewModel(callerRole: .admin)
        XCTAssertEqual(vm.availableRoles, [.member])
    }

    func testAvailableRoles_forMember_returnsMemberOnly() {
        let vm = createViewModel(callerRole: .member)
        XCTAssertEqual(vm.availableRoles, [.member])
    }

    func testAvailableRoles_forViewer_returnsMemberOnly() {
        let vm = createViewModel(callerRole: .viewer)
        XCTAssertEqual(vm.availableRoles, [.member])
    }

    // MARK: - isEmailValid Tests

    func testIsEmailValid_emptyEmail_returnsTrue() {
        let vm = createViewModel()
        vm.email = ""
        XCTAssertTrue(vm.isEmailValid)
    }

    func testIsEmailValid_validEmail_returnsTrue() {
        let vm = createViewModel()
        vm.email = "test@example.com"
        XCTAssertTrue(vm.isEmailValid)
    }

    func testIsEmailValid_invalidEmail_returnsFalse() {
        let vm = createViewModel()
        vm.email = "not-an-email"
        XCTAssertFalse(vm.isEmailValid)
    }

    func testIsEmailValid_whitespaceOnly_returnsTrue() {
        let vm = createViewModel()
        vm.email = "   "
        XCTAssertTrue(vm.isEmailValid) // Treated as empty/optional
    }

    func testIsEmailValid_missingDomain_returnsFalse() {
        let vm = createViewModel()
        vm.email = "test@"
        XCTAssertFalse(vm.isEmailValid)
    }

    func testIsEmailValid_missingAt_returnsFalse() {
        let vm = createViewModel()
        vm.email = "testexample.com"
        XCTAssertFalse(vm.isEmailValid)
    }

    // MARK: - canCreate Tests

    func testCanCreate_validState_returnsTrue() {
        let vm = createViewModel()
        XCTAssertTrue(vm.canCreate)
    }

    func testCanCreate_invalidEmail_returnsFalse() {
        let vm = createViewModel()
        vm.email = "bad-email"
        XCTAssertFalse(vm.canCreate)
    }

    func testCanCreate_whileCreating_returnsFalse() {
        let vm = createViewModel()
        vm.state = .creating
        XCTAssertFalse(vm.canCreate)
    }

    func testCanCreate_messageAtMaxLength_returnsTrue() {
        let vm = createViewModel()
        vm.message = String(repeating: "a", count: 500)
        XCTAssertTrue(vm.canCreate)
    }

    func testCanCreate_messageOverMaxLength_returnsFalse() {
        let vm = createViewModel()
        vm.message = String(repeating: "a", count: 501)
        XCTAssertFalse(vm.canCreate)
    }

    // MARK: - createInvitation Tests

    func testCreateInvitation_success_setsSuccessState() async throws {
        let vm = createViewModel()
        vm.email = "test@example.com"
        vm.message = "Welcome!"

        mockAPIClient.setResponse(successResponseJSON, for: Constants.API.Endpoints.createInvitation)

        vm.createInvitation()
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(vm.state, .success)
        XCTAssertNotNil(vm.createdInvitation)
        XCTAssertEqual(vm.createdInvitation?.shortCode, "XY9Z1234")
    }

    func testCreateInvitation_error_setsErrorState() async throws {
        let vm = createViewModel()
        mockAPIClient.setError(
            MockError.testError("Server error"),
            for: Constants.API.Endpoints.createInvitation
        )

        vm.createInvitation()
        try await Task.sleep(nanoseconds: 200_000_000)

        if case .error(let message) = vm.state {
            XCTAssertTrue(message.contains("Server error"))
        } else {
            XCTFail("Expected error state")
        }
    }

    // MARK: - resetForNew Tests

    func testResetForNew_resetsAllFields() async throws {
        let vm = createViewModel()
        vm.email = "test@example.com"
        vm.message = "Welcome!"
        vm.selectedRole = .admin

        mockAPIClient.setResponse(successResponseJSON, for: Constants.API.Endpoints.createInvitation)
        vm.createInvitation()
        try await Task.sleep(nanoseconds: 200_000_000)

        vm.resetForNew()

        XCTAssertEqual(vm.email, "")
        XCTAssertEqual(vm.message, "")
        XCTAssertEqual(vm.selectedRole, .member)
        XCTAssertNil(vm.createdInvitation)
        XCTAssertEqual(vm.state, .idle)
    }

    // MARK: - remainingCharacters Tests

    func testRemainingCharacters_emptyMessage_returnsMax() {
        let vm = createViewModel()
        vm.message = ""
        XCTAssertEqual(vm.remainingCharacters, 500)
    }

    func testRemainingCharacters_withMessage_returnsCorrect() {
        let vm = createViewModel()
        vm.message = "Hello"
        XCTAssertEqual(vm.remainingCharacters, 495)
    }
}
