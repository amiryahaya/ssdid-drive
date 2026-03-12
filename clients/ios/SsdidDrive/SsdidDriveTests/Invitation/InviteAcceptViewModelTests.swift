import XCTest
import Combine
@testable import SsdidDrive

/// Unit tests for InviteAcceptViewModel
@MainActor
final class InviteAcceptViewModelTests: XCTestCase {

    // MARK: - Properties

    var viewModel: InviteAcceptViewModel!
    var mockAuthRepository: MockAuthRepository!
    var cancellables: Set<AnyCancellable>!
    var mockDelegate: MockCoordinatorDelegate!

    // MARK: - Setup

    override func setUp() {
        super.setUp()
        mockAuthRepository = MockAuthRepository()
        cancellables = Set<AnyCancellable>()
        mockDelegate = MockCoordinatorDelegate()
    }

    override func tearDown() {
        viewModel = nil
        mockAuthRepository = nil
        cancellables = nil
        mockDelegate = nil
        super.tearDown()
    }

    // MARK: - Helper Methods

    private func createViewModel(token: String = "test-token") -> InviteAcceptViewModel {
        let vm = InviteAcceptViewModel(
            authRepository: mockAuthRepository,
            token: token
        )
        vm.coordinatorDelegate = mockDelegate
        return vm
    }

    private func waitForPublisher<T: Publisher>(
        _ publisher: T,
        timeout: TimeInterval = 1.0,
        file: StaticString = #file,
        line: UInt = #line
    ) where T.Failure == Never {
        let expectation = expectation(description: "Publisher expectation")
        var hasReceived = false

        publisher
            .sink { _ in
                if !hasReceived {
                    hasReceived = true
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: timeout)
    }

    // MARK: - Initialization Tests

    func testInit_loadsInvitationInfo() async throws {
        // Given
        mockAuthRepository.getInvitationInfoResult = .success(InvitationTestFixtures.validInvitation)

        // When
        viewModel = createViewModel()

        // Wait for async load
        try await Task.sleep(nanoseconds: 100_000_000)

        // Then
        XCTAssertEqual(mockAuthRepository.getInvitationInfoCallCount, 1)
        XCTAssertEqual(mockAuthRepository.lastGetInvitationInfoToken, "test-token")
    }

    func testInit_startsInLoadingState() {
        // Given
        mockAuthRepository.getInvitationInfoResult = .success(InvitationTestFixtures.validInvitation)

        // When
        viewModel = createViewModel()

        // Then - Initially loading
        XCTAssertTrue(viewModel.isLoadingInvitation)
    }

    // MARK: - Load Invitation Tests

    func testLoadInvitation_success_updatesInvitation() async throws {
        // Given
        let expectedInvitation = InvitationTestFixtures.validInvitation
        mockAuthRepository.getInvitationInfoResult = .success(expectedInvitation)

        // When
        viewModel = createViewModel()
        try await Task.sleep(nanoseconds: 200_000_000)

        // Then
        XCTAssertEqual(viewModel.invitation, expectedInvitation)
        XCTAssertFalse(viewModel.isLoadingInvitation)
        XCTAssertNil(viewModel.invitationError)
    }

    func testLoadInvitation_success_setsEmail() async throws {
        // Given
        mockAuthRepository.getInvitationInfoResult = .success(InvitationTestFixtures.validInvitation)

        // When
        viewModel = createViewModel()
        try await Task.sleep(nanoseconds: 200_000_000)

        // Then
        XCTAssertEqual(viewModel.email, "newuser@example.com")
    }

    func testLoadInvitation_expiredInvitation_setsError() async throws {
        // Given
        mockAuthRepository.getInvitationInfoResult = .success(InvitationTestFixtures.expiredInvitation)

        // When
        viewModel = createViewModel()
        try await Task.sleep(nanoseconds: 200_000_000)

        // Then
        XCTAssertNotNil(viewModel.invitation)
        XCTAssertFalse(viewModel.invitation!.valid)
        XCTAssertNotNil(viewModel.invitationError)
        XCTAssertEqual(viewModel.invitationError, TokenInvitationError.expired.displayMessage)
    }

    func testLoadInvitation_revokedInvitation_setsError() async throws {
        // Given
        mockAuthRepository.getInvitationInfoResult = .success(InvitationTestFixtures.revokedInvitation)

        // When
        viewModel = createViewModel()
        try await Task.sleep(nanoseconds: 200_000_000)

        // Then
        XCTAssertNotNil(viewModel.invitationError)
        XCTAssertEqual(viewModel.invitationError, TokenInvitationError.revoked.displayMessage)
    }

    func testLoadInvitation_alreadyUsedInvitation_setsError() async throws {
        // Given
        mockAuthRepository.getInvitationInfoResult = .success(InvitationTestFixtures.alreadyUsedInvitation)

        // When
        viewModel = createViewModel()
        try await Task.sleep(nanoseconds: 200_000_000)

        // Then
        XCTAssertNotNil(viewModel.invitationError)
        XCTAssertEqual(viewModel.invitationError, TokenInvitationError.alreadyUsed.displayMessage)
    }

    func testLoadInvitation_notFoundInvitation_setsError() async throws {
        // Given
        mockAuthRepository.getInvitationInfoResult = .success(InvitationTestFixtures.notFoundInvitation)

        // When
        viewModel = createViewModel()
        try await Task.sleep(nanoseconds: 200_000_000)

        // Then
        XCTAssertNotNil(viewModel.invitationError)
        XCTAssertEqual(viewModel.invitationError, TokenInvitationError.notFound.displayMessage)
    }

    func testLoadInvitation_networkError_setsError() async throws {
        // Given
        mockAuthRepository.getInvitationInfoResult = .failure(MockError.testError("Network error"))

        // When
        viewModel = createViewModel()
        try await Task.sleep(nanoseconds: 200_000_000)

        // Then
        XCTAssertFalse(viewModel.isLoadingInvitation)
        XCTAssertNotNil(viewModel.invitationError)
        XCTAssertTrue(viewModel.invitationError?.contains("Network error") == true)
    }

    // MARK: - Form Validation Tests

    func testIsFormValid_allFieldsValid_returnsTrue() async throws {
        // Given
        mockAuthRepository.getInvitationInfoResult = .success(InvitationTestFixtures.validInvitation)
        viewModel = createViewModel()
        try await Task.sleep(nanoseconds: 200_000_000)

        // When
        viewModel.displayName = InvitationTestFixtures.FormInput.validDisplayName
        viewModel.password = InvitationTestFixtures.FormInput.validPassword
        viewModel.confirmPassword = InvitationTestFixtures.FormInput.validConfirmPassword

        // Then
        XCTAssertTrue(viewModel.isFormValid)
    }

    func testIsFormValid_emptyDisplayName_returnsFalse() async throws {
        // Given
        mockAuthRepository.getInvitationInfoResult = .success(InvitationTestFixtures.validInvitation)
        viewModel = createViewModel()
        try await Task.sleep(nanoseconds: 200_000_000)

        // When
        viewModel.displayName = ""
        viewModel.password = InvitationTestFixtures.FormInput.validPassword
        viewModel.confirmPassword = InvitationTestFixtures.FormInput.validConfirmPassword

        // Then
        XCTAssertFalse(viewModel.isFormValid)
    }

    func testIsFormValid_displayNameTooLong_returnsFalse() async throws {
        // Given
        mockAuthRepository.getInvitationInfoResult = .success(InvitationTestFixtures.validInvitation)
        viewModel = createViewModel()
        try await Task.sleep(nanoseconds: 200_000_000)

        // When
        viewModel.displayName = InvitationTestFixtures.FormInput.longDisplayName
        viewModel.password = InvitationTestFixtures.FormInput.validPassword
        viewModel.confirmPassword = InvitationTestFixtures.FormInput.validConfirmPassword

        // Then
        XCTAssertFalse(viewModel.isFormValid)
    }

    func testIsFormValid_passwordTooShort_returnsFalse() async throws {
        // Given
        mockAuthRepository.getInvitationInfoResult = .success(InvitationTestFixtures.validInvitation)
        viewModel = createViewModel()
        try await Task.sleep(nanoseconds: 200_000_000)

        // When
        viewModel.displayName = InvitationTestFixtures.FormInput.validDisplayName
        viewModel.password = InvitationTestFixtures.FormInput.shortPassword
        viewModel.confirmPassword = InvitationTestFixtures.FormInput.shortPassword

        // Then
        XCTAssertFalse(viewModel.isFormValid)
    }

    func testIsFormValid_passwordMismatch_returnsFalse() async throws {
        // Given
        mockAuthRepository.getInvitationInfoResult = .success(InvitationTestFixtures.validInvitation)
        viewModel = createViewModel()
        try await Task.sleep(nanoseconds: 200_000_000)

        // When
        viewModel.displayName = InvitationTestFixtures.FormInput.validDisplayName
        viewModel.password = "ValidPassword123"
        viewModel.confirmPassword = "DifferentPassword456"

        // Then
        XCTAssertFalse(viewModel.isFormValid)
    }

    // MARK: - Accept Invitation Tests

    func testAcceptInvitation_success_callsRepository() async throws {
        // Given
        mockAuthRepository.getInvitationInfoResult = .success(InvitationTestFixtures.validInvitation)
        mockAuthRepository.acceptInvitationResult = .success(InvitationTestFixtures.acceptedUser)
        viewModel = createViewModel()
        try await Task.sleep(nanoseconds: 200_000_000)

        viewModel.displayName = InvitationTestFixtures.FormInput.validDisplayName
        viewModel.password = InvitationTestFixtures.FormInput.validPassword
        viewModel.confirmPassword = InvitationTestFixtures.FormInput.validConfirmPassword

        // When
        viewModel.acceptInvitation()
        try await Task.sleep(nanoseconds: 200_000_000)

        // Then
        XCTAssertEqual(mockAuthRepository.acceptInvitationCallCount, 1)
        XCTAssertEqual(mockAuthRepository.lastAcceptInvitationToken, "test-token")
        XCTAssertEqual(mockAuthRepository.lastAcceptInvitationDisplayName, InvitationTestFixtures.FormInput.validDisplayName)
        XCTAssertEqual(mockAuthRepository.lastAcceptInvitationPassword, InvitationTestFixtures.FormInput.validPassword)
    }

    func testAcceptInvitation_success_callsCoordinatorDelegate() async throws {
        // Given
        mockAuthRepository.getInvitationInfoResult = .success(InvitationTestFixtures.validInvitation)
        mockAuthRepository.acceptInvitationResult = .success(InvitationTestFixtures.acceptedUser)
        viewModel = createViewModel()
        try await Task.sleep(nanoseconds: 200_000_000)

        viewModel.displayName = InvitationTestFixtures.FormInput.validDisplayName
        viewModel.password = InvitationTestFixtures.FormInput.validPassword
        viewModel.confirmPassword = InvitationTestFixtures.FormInput.validConfirmPassword

        // When
        viewModel.acceptInvitation()
        try await Task.sleep(nanoseconds: 200_000_000)

        // Then
        XCTAssertTrue(mockDelegate.didRegisterCalled)
    }

    func testAcceptInvitation_success_clearsPasswordFields() async throws {
        // Given
        mockAuthRepository.getInvitationInfoResult = .success(InvitationTestFixtures.validInvitation)
        mockAuthRepository.acceptInvitationResult = .success(InvitationTestFixtures.acceptedUser)
        viewModel = createViewModel()
        try await Task.sleep(nanoseconds: 200_000_000)

        viewModel.displayName = InvitationTestFixtures.FormInput.validDisplayName
        viewModel.password = InvitationTestFixtures.FormInput.validPassword
        viewModel.confirmPassword = InvitationTestFixtures.FormInput.validConfirmPassword

        // When
        viewModel.acceptInvitation()
        try await Task.sleep(nanoseconds: 200_000_000)

        // Then
        XCTAssertTrue(viewModel.password.isEmpty)
        XCTAssertTrue(viewModel.confirmPassword.isEmpty)
    }

    func testAcceptInvitation_invalidForm_doesNotCallRepository() async throws {
        // Given
        mockAuthRepository.getInvitationInfoResult = .success(InvitationTestFixtures.validInvitation)
        viewModel = createViewModel()
        try await Task.sleep(nanoseconds: 200_000_000)

        viewModel.displayName = "" // Invalid
        viewModel.password = InvitationTestFixtures.FormInput.validPassword
        viewModel.confirmPassword = InvitationTestFixtures.FormInput.validConfirmPassword

        // When
        viewModel.acceptInvitation()
        try await Task.sleep(nanoseconds: 100_000_000)

        // Then
        XCTAssertEqual(mockAuthRepository.acceptInvitationCallCount, 0)
        XCTAssertNotNil(viewModel.registrationError)
    }

    func testAcceptInvitation_invalidForm_emptyDisplayName_setsError() async throws {
        // Given
        mockAuthRepository.getInvitationInfoResult = .success(InvitationTestFixtures.validInvitation)
        viewModel = createViewModel()
        try await Task.sleep(nanoseconds: 200_000_000)

        viewModel.displayName = ""
        viewModel.password = InvitationTestFixtures.FormInput.validPassword
        viewModel.confirmPassword = InvitationTestFixtures.FormInput.validConfirmPassword

        // When
        viewModel.acceptInvitation()

        // Then
        XCTAssertEqual(viewModel.registrationError, "Name is required")
    }

    func testAcceptInvitation_invalidForm_displayNameTooLong_setsError() async throws {
        // Given
        mockAuthRepository.getInvitationInfoResult = .success(InvitationTestFixtures.validInvitation)
        viewModel = createViewModel()
        try await Task.sleep(nanoseconds: 200_000_000)

        viewModel.displayName = InvitationTestFixtures.FormInput.longDisplayName
        viewModel.password = InvitationTestFixtures.FormInput.validPassword
        viewModel.confirmPassword = InvitationTestFixtures.FormInput.validConfirmPassword

        // When
        viewModel.acceptInvitation()

        // Then
        XCTAssertEqual(viewModel.registrationError, "Name is too long")
    }

    func testAcceptInvitation_invalidForm_passwordTooShort_setsError() async throws {
        // Given
        mockAuthRepository.getInvitationInfoResult = .success(InvitationTestFixtures.validInvitation)
        viewModel = createViewModel()
        try await Task.sleep(nanoseconds: 200_000_000)

        viewModel.displayName = InvitationTestFixtures.FormInput.validDisplayName
        viewModel.password = InvitationTestFixtures.FormInput.shortPassword
        viewModel.confirmPassword = InvitationTestFixtures.FormInput.shortPassword

        // When
        viewModel.acceptInvitation()

        // Then
        XCTAssertEqual(viewModel.registrationError, "Password must be at least 8 characters")
    }

    func testAcceptInvitation_invalidForm_passwordMismatch_setsError() async throws {
        // Given
        mockAuthRepository.getInvitationInfoResult = .success(InvitationTestFixtures.validInvitation)
        viewModel = createViewModel()
        try await Task.sleep(nanoseconds: 200_000_000)

        viewModel.displayName = InvitationTestFixtures.FormInput.validDisplayName
        viewModel.password = "ValidPassword123"
        viewModel.confirmPassword = "DifferentPassword456"

        // When
        viewModel.acceptInvitation()

        // Then
        XCTAssertEqual(viewModel.registrationError, "Passwords do not match")
    }

    func testAcceptInvitation_failure_setsRegistrationError() async throws {
        // Given
        mockAuthRepository.getInvitationInfoResult = .success(InvitationTestFixtures.validInvitation)
        mockAuthRepository.acceptInvitationResult = .failure(MockError.testError("Registration failed"))
        viewModel = createViewModel()
        try await Task.sleep(nanoseconds: 200_000_000)

        viewModel.displayName = InvitationTestFixtures.FormInput.validDisplayName
        viewModel.password = InvitationTestFixtures.FormInput.validPassword
        viewModel.confirmPassword = InvitationTestFixtures.FormInput.validConfirmPassword

        // When
        viewModel.acceptInvitation()
        try await Task.sleep(nanoseconds: 200_000_000)

        // Then
        XCTAssertNotNil(viewModel.registrationError)
        XCTAssertTrue(viewModel.registrationError?.contains("Registration failed") == true)
    }

    func testAcceptInvitation_setsIsRegistering() async throws {
        // Given
        mockAuthRepository.getInvitationInfoResult = .success(InvitationTestFixtures.validInvitation)
        mockAuthRepository.acceptInvitationResult = .success(InvitationTestFixtures.acceptedUser)
        viewModel = createViewModel()
        try await Task.sleep(nanoseconds: 200_000_000)

        viewModel.displayName = InvitationTestFixtures.FormInput.validDisplayName
        viewModel.password = InvitationTestFixtures.FormInput.validPassword
        viewModel.confirmPassword = InvitationTestFixtures.FormInput.validConfirmPassword

        // When
        viewModel.acceptInvitation()

        // Then - Initially registering
        XCTAssertTrue(viewModel.isRegistering)
    }

    func testAcceptInvitation_failure_clearsIsRegistering() async throws {
        // Given
        mockAuthRepository.getInvitationInfoResult = .success(InvitationTestFixtures.validInvitation)
        mockAuthRepository.acceptInvitationResult = .failure(MockError.testError("Failed"))
        viewModel = createViewModel()
        try await Task.sleep(nanoseconds: 200_000_000)

        viewModel.displayName = InvitationTestFixtures.FormInput.validDisplayName
        viewModel.password = InvitationTestFixtures.FormInput.validPassword
        viewModel.confirmPassword = InvitationTestFixtures.FormInput.validConfirmPassword

        // When
        viewModel.acceptInvitation()
        try await Task.sleep(nanoseconds: 200_000_000)

        // Then
        XCTAssertFalse(viewModel.isRegistering)
    }

    // MARK: - Navigation Tests

    func testRequestLogin_callsCoordinatorDelegate() async throws {
        // Given
        mockAuthRepository.getInvitationInfoResult = .success(InvitationTestFixtures.validInvitation)
        viewModel = createViewModel()
        try await Task.sleep(nanoseconds: 200_000_000)

        // When
        viewModel.requestLogin()

        // Then
        XCTAssertTrue(mockDelegate.didRequestLoginCalled)
    }

    // MARK: - Edge Cases

    func testFormValidation_unicodeDisplayName() async throws {
        // Given
        mockAuthRepository.getInvitationInfoResult = .success(InvitationTestFixtures.validInvitation)
        viewModel = createViewModel()
        try await Task.sleep(nanoseconds: 200_000_000)

        // When
        viewModel.displayName = InvitationTestFixtures.FormInput.unicodeDisplayName
        viewModel.password = InvitationTestFixtures.FormInput.validPassword
        viewModel.confirmPassword = InvitationTestFixtures.FormInput.validConfirmPassword

        // Then
        XCTAssertTrue(viewModel.isFormValid)
    }

    func testFormValidation_specialCharsPassword() async throws {
        // Given
        mockAuthRepository.getInvitationInfoResult = .success(InvitationTestFixtures.validInvitation)
        viewModel = createViewModel()
        try await Task.sleep(nanoseconds: 200_000_000)

        // When
        viewModel.displayName = InvitationTestFixtures.FormInput.validDisplayName
        viewModel.password = InvitationTestFixtures.FormInput.specialCharsPassword
        viewModel.confirmPassword = InvitationTestFixtures.FormInput.specialCharsPassword

        // Then
        XCTAssertTrue(viewModel.isFormValid)
    }

    func testEmail_beforeLoadComplete_returnsEmpty() {
        // Given
        mockAuthRepository.getInvitationInfoResult = .success(InvitationTestFixtures.validInvitation)

        // When
        viewModel = createViewModel()

        // Then - Before load completes
        XCTAssertEqual(viewModel.email, "")
    }

    func testLoadInvitation_canBeCalledMultipleTimes() async throws {
        // Given
        mockAuthRepository.getInvitationInfoResult = .success(InvitationTestFixtures.validInvitation)
        viewModel = createViewModel()
        try await Task.sleep(nanoseconds: 200_000_000)

        // When - Call load again (retry scenario)
        mockAuthRepository.getInvitationInfoResult = .success(InvitationTestFixtures.validInvitationNoMessage)
        viewModel.loadInvitationInfo()
        try await Task.sleep(nanoseconds: 200_000_000)

        // Then
        XCTAssertEqual(mockAuthRepository.getInvitationInfoCallCount, 2)
        XCTAssertNil(viewModel.invitation?.message)
    }
}

// MARK: - Mock Coordinator Delegate

final class MockCoordinatorDelegate: InviteAcceptViewModelCoordinatorDelegate {
    var didRegisterCalled = false
    var didRequestLoginCalled = false

    func inviteAcceptViewModelDidRegister() {
        didRegisterCalled = true
    }

    func inviteAcceptViewModelDidRequestLogin() {
        didRequestLoginCalled = true
    }
}
