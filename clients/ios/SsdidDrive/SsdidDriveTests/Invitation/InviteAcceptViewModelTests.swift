import XCTest
import Combine
@testable import SsdidDrive

/// Unit tests for InviteAcceptViewModel (wallet-based flow)
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

    // MARK: - Initialization Tests

    func testInit_loadsInvitationInfo() async throws {
        // Given
        mockAuthRepository.getInvitationInfoResult = .success(InvitationTestFixtures.validInvitation)

        // When
        viewModel = createViewModel()

        // Wait for async load
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in !self.viewModel.isLoadingInvitation },
            object: nil
        )
        await fulfillment(of: [expectation], timeout: 2.0)

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
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in self.viewModel.invitation != nil },
            object: nil
        )
        await fulfillment(of: [expectation], timeout: 2.0)

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
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in self.viewModel.invitation != nil },
            object: nil
        )
        await fulfillment(of: [expectation], timeout: 2.0)

        // Then
        XCTAssertEqual(viewModel.email, "newuser@example.com")
    }

    func testLoadInvitation_expiredInvitation_setsError() async throws {
        // Given
        mockAuthRepository.getInvitationInfoResult = .success(InvitationTestFixtures.expiredInvitation)

        // When
        viewModel = createViewModel()
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in self.viewModel.invitationError != nil },
            object: nil
        )
        await fulfillment(of: [expectation], timeout: 2.0)

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
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in self.viewModel.invitationError != nil },
            object: nil
        )
        await fulfillment(of: [expectation], timeout: 2.0)

        // Then
        XCTAssertNotNil(viewModel.invitationError)
        XCTAssertEqual(viewModel.invitationError, TokenInvitationError.revoked.displayMessage)
    }

    func testLoadInvitation_alreadyUsedInvitation_setsError() async throws {
        // Given
        mockAuthRepository.getInvitationInfoResult = .success(InvitationTestFixtures.alreadyUsedInvitation)

        // When
        viewModel = createViewModel()
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in self.viewModel.invitationError != nil },
            object: nil
        )
        await fulfillment(of: [expectation], timeout: 2.0)

        // Then
        XCTAssertNotNil(viewModel.invitationError)
        XCTAssertEqual(viewModel.invitationError, TokenInvitationError.alreadyUsed.displayMessage)
    }

    func testLoadInvitation_notFoundInvitation_setsError() async throws {
        // Given
        mockAuthRepository.getInvitationInfoResult = .success(InvitationTestFixtures.notFoundInvitation)

        // When
        viewModel = createViewModel()
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in self.viewModel.invitationError != nil },
            object: nil
        )
        await fulfillment(of: [expectation], timeout: 2.0)

        // Then
        XCTAssertNotNil(viewModel.invitationError)
        XCTAssertEqual(viewModel.invitationError, TokenInvitationError.notFound.displayMessage)
    }

    func testLoadInvitation_networkError_setsError() async throws {
        // Given
        mockAuthRepository.getInvitationInfoResult = .failure(MockError.testError("Network error"))

        // When
        viewModel = createViewModel()
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in !self.viewModel.isLoadingInvitation },
            object: nil
        )
        await fulfillment(of: [expectation], timeout: 2.0)

        // Then
        XCTAssertFalse(viewModel.isLoadingInvitation)
        XCTAssertNotNil(viewModel.invitationError)
        XCTAssertTrue(viewModel.invitationError?.contains("Network error") == true)
    }

    // MARK: - Accept With Wallet Tests

    func testAcceptWithWallet_callsLaunchWalletInvite() async throws {
        // Given
        mockAuthRepository.getInvitationInfoResult = .success(InvitationTestFixtures.validInvitation)
        viewModel = createViewModel()
        let loadExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in !self.viewModel.isLoadingInvitation },
            object: nil
        )
        await fulfillment(of: [loadExpectation], timeout: 2.0)

        // When
        viewModel.acceptWithWallet()
        let walletExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in self.viewModel.isWaitingForWallet },
            object: nil
        )
        await fulfillment(of: [walletExpectation], timeout: 2.0)

        // Then
        XCTAssertEqual(mockAuthRepository.launchWalletInviteCallCount, 1)
        XCTAssertEqual(mockAuthRepository.lastLaunchWalletInviteToken, "test-token")
    }

    func testAcceptWithWallet_setsWaitingForWallet() async throws {
        // Given
        mockAuthRepository.getInvitationInfoResult = .success(InvitationTestFixtures.validInvitation)
        viewModel = createViewModel()
        let loadExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in !self.viewModel.isLoadingInvitation },
            object: nil
        )
        await fulfillment(of: [loadExpectation], timeout: 2.0)

        // When
        viewModel.acceptWithWallet()
        let walletExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in self.viewModel.isWaitingForWallet },
            object: nil
        )
        await fulfillment(of: [walletExpectation], timeout: 2.0)

        // Then
        XCTAssertTrue(viewModel.isWaitingForWallet)
    }

    func testAcceptWithWallet_failure_setsRegistrationError() async throws {
        // Given
        mockAuthRepository.getInvitationInfoResult = .success(InvitationTestFixtures.validInvitation)
        mockAuthRepository.launchWalletInviteResult = .failure(MockError.testError("Wallet not installed"))
        viewModel = createViewModel()
        let loadExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in !self.viewModel.isLoadingInvitation },
            object: nil
        )
        await fulfillment(of: [loadExpectation], timeout: 2.0)

        // When
        viewModel.acceptWithWallet()
        let errorExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in self.viewModel.registrationError != nil },
            object: nil
        )
        await fulfillment(of: [errorExpectation], timeout: 2.0)

        // Then
        XCTAssertNotNil(viewModel.registrationError)
        XCTAssertTrue(viewModel.registrationError?.contains("Wallet not installed") == true)
        XCTAssertFalse(viewModel.isWaitingForWallet)
    }

    func testAcceptWithWallet_preventsDoubleCall() async throws {
        // Given
        mockAuthRepository.getInvitationInfoResult = .success(InvitationTestFixtures.validInvitation)
        viewModel = createViewModel()
        let loadExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in !self.viewModel.isLoadingInvitation },
            object: nil
        )
        await fulfillment(of: [loadExpectation], timeout: 2.0)

        // When - First call
        viewModel.acceptWithWallet()
        let walletExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in self.viewModel.isWaitingForWallet },
            object: nil
        )
        await fulfillment(of: [walletExpectation], timeout: 2.0)

        // Then - Already waiting, second call should not launch again
        viewModel.acceptWithWallet()
        // Give a brief moment for any potential second call to process
        let stableExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in self.mockAuthRepository.launchWalletInviteCallCount == 1 },
            object: nil
        )
        await fulfillment(of: [stableExpectation], timeout: 2.0)
        XCTAssertEqual(mockAuthRepository.launchWalletInviteCallCount, 1)
    }

    // MARK: - Wallet Callback Tests

    func testHandleWalletCallback_success_savesSession() async throws {
        // Given
        mockAuthRepository.getInvitationInfoResult = .success(InvitationTestFixtures.validInvitation)
        viewModel = createViewModel()
        let loadExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in !self.viewModel.isLoadingInvitation },
            object: nil
        )
        await fulfillment(of: [loadExpectation], timeout: 2.0)
        viewModel.acceptWithWallet()
        let walletExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in self.viewModel.isWaitingForWallet },
            object: nil
        )
        await fulfillment(of: [walletExpectation], timeout: 2.0)

        // When
        viewModel.handleWalletCallback(sessionToken: "test-session-token")
        let doneExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in self.mockDelegate.didRegisterCalled },
            object: nil
        )
        await fulfillment(of: [doneExpectation], timeout: 2.0)

        // Then
        XCTAssertEqual(mockAuthRepository.saveSessionFromWalletCallCount, 1)
        XCTAssertEqual(mockAuthRepository.lastSaveSessionFromWalletToken, "test-session-token")
        XCTAssertTrue(mockDelegate.didRegisterCalled)
        XCTAssertFalse(viewModel.isWaitingForWallet)
    }

    func testHandleWalletCallback_failure_setsError() async throws {
        // Given
        mockAuthRepository.getInvitationInfoResult = .success(InvitationTestFixtures.validInvitation)
        mockAuthRepository.saveSessionFromWalletResult = .failure(MockError.testError("Save failed"))
        viewModel = createViewModel()
        let loadExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in !self.viewModel.isLoadingInvitation },
            object: nil
        )
        await fulfillment(of: [loadExpectation], timeout: 2.0)

        // When
        viewModel.handleWalletCallback(sessionToken: "test-session-token")
        let errorExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in self.viewModel.registrationError != nil },
            object: nil
        )
        await fulfillment(of: [errorExpectation], timeout: 2.0)

        // Then
        XCTAssertNotNil(viewModel.registrationError)
        XCTAssertTrue(viewModel.registrationError?.contains("Save failed") == true)
        XCTAssertFalse(viewModel.isWaitingForWallet)
        XCTAssertFalse(mockDelegate.didRegisterCalled)
    }

    // MARK: - Wallet Error Tests

    func testHandleWalletError_setsError() async throws {
        // Given
        mockAuthRepository.getInvitationInfoResult = .success(InvitationTestFixtures.validInvitation)
        viewModel = createViewModel()
        let loadExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in !self.viewModel.isLoadingInvitation },
            object: nil
        )
        await fulfillment(of: [loadExpectation], timeout: 2.0)
        viewModel.acceptWithWallet()
        let walletExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in self.viewModel.isWaitingForWallet },
            object: nil
        )
        await fulfillment(of: [walletExpectation], timeout: 2.0)

        // When
        viewModel.handleWalletError(message: "User rejected invitation")

        // Then
        XCTAssertEqual(viewModel.registrationError, "User rejected invitation")
        XCTAssertFalse(viewModel.isWaitingForWallet)
    }

    // MARK: - Navigation Tests

    func testRequestLogin_callsCoordinatorDelegate() async throws {
        // Given
        mockAuthRepository.getInvitationInfoResult = .success(InvitationTestFixtures.validInvitation)
        viewModel = createViewModel()
        let loadExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in !self.viewModel.isLoadingInvitation },
            object: nil
        )
        await fulfillment(of: [loadExpectation], timeout: 2.0)

        // When
        viewModel.requestLogin()

        // Then
        XCTAssertTrue(mockDelegate.didRequestLoginCalled)
    }

    // MARK: - Edge Cases

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
        let loadExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in !self.viewModel.isLoadingInvitation },
            object: nil
        )
        await fulfillment(of: [loadExpectation], timeout: 2.0)

        // When - Call load again (retry scenario)
        mockAuthRepository.getInvitationInfoResult = .success(InvitationTestFixtures.validInvitationNoMessage)
        viewModel.loadInvitationInfo()
        let reloadExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in self.viewModel.invitation?.message == nil && !self.viewModel.isLoadingInvitation },
            object: nil
        )
        await fulfillment(of: [reloadExpectation], timeout: 2.0)

        // Then
        XCTAssertEqual(mockAuthRepository.getInvitationInfoCallCount, 2)
        XCTAssertNil(viewModel.invitation?.message)
    }

    // MARK: - isLoading Transition Tests

    func testAcceptWithWallet_success_isLoadingTransitions() async throws {
        // Setup
        mockAuthRepository.getInvitationInfoResult = .success(InvitationTestFixtures.validInvitation)
        viewModel = createViewModel()
        let loadExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in !self.viewModel.isLoadingInvitation },
            object: nil
        )
        await fulfillment(of: [loadExpectation], timeout: 2.0)

        // Act
        viewModel.acceptWithWallet()

        // Assert isLoading transitions back to false after completion
        let doneExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in !self.viewModel.isLoading },
            object: nil
        )
        await fulfillment(of: [doneExpectation], timeout: 2.0)
        XCTAssertFalse(viewModel.isLoading)
    }

    // MARK: - Error Clearing Tests

    func testAcceptWithWallet_clearsErrorOnRetry() async throws {
        mockAuthRepository.getInvitationInfoResult = .success(InvitationTestFixtures.validInvitation)
        mockAuthRepository.launchWalletInviteResult = .failure(NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "First failure"]))
        viewModel = createViewModel()

        let loadExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in !self.viewModel.isLoadingInvitation },
            object: nil
        )
        await fulfillment(of: [loadExpectation], timeout: 2.0)

        // First attempt - should fail
        viewModel.acceptWithWallet()
        let errorExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in self.viewModel.registrationError != nil },
            object: nil
        )
        await fulfillment(of: [errorExpectation], timeout: 2.0)
        XCTAssertNotNil(viewModel.registrationError)

        // Fix stub and retry
        mockAuthRepository.launchWalletInviteResult = .success(())
        viewModel.acceptWithWallet()

        // Error should be cleared immediately
        XCTAssertNil(viewModel.registrationError)
    }

    // MARK: - Cold Callback Tests

    func testHandleWalletCallback_coldCallback_savesSession() async throws {
        mockAuthRepository.getInvitationInfoResult = .success(InvitationTestFixtures.validInvitation)
        viewModel = createViewModel()

        let loadExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in !self.viewModel.isLoadingInvitation },
            object: nil
        )
        await fulfillment(of: [loadExpectation], timeout: 2.0)

        // Call handleWalletCallback directly without acceptWithWallet
        viewModel.handleWalletCallback(sessionToken: "cold-session-token")

        let doneExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in self.mockDelegate.didRegisterCalled },
            object: nil
        )
        await fulfillment(of: [doneExpectation], timeout: 2.0)

        XCTAssertEqual(mockAuthRepository.saveSessionFromWalletCallCount, 1)
        XCTAssertEqual(mockAuthRepository.lastSaveSessionFromWalletToken, "cold-session-token")
        XCTAssertTrue(mockDelegate.didRegisterCalled)
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
