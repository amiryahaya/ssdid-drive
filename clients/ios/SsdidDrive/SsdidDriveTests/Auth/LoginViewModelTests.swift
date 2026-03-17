import XCTest
import Combine
@testable import SsdidDrive

/// Unit tests for LoginViewModel — session token validation, auth callback handling,
/// and email login validation.
@MainActor
final class LoginViewModelTests: XCTestCase {

    // MARK: - Properties

    var viewModel: LoginViewModel!
    var mockKeychainManager: InvitationMockKeychainManager!
    var cancellables: Set<AnyCancellable>!

    // MARK: - Setup

    override func setUp() {
        super.setUp()
        mockKeychainManager = InvitationMockKeychainManager()
        viewModel = LoginViewModel(keychainManager: mockKeychainManager)
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() {
        viewModel = nil
        mockKeychainManager = nil
        cancellables = nil
        super.tearDown()
    }

    // MARK: - isValidSessionToken Tests

    func testIsValidSessionToken_validUUID_returnsTrue() {
        // Given
        let token = "550e8400-e29b-41d4-a716-446655440000"

        // Then
        XCTAssertTrue(LoginViewModel.isValidSessionToken(token))
    }

    func testIsValidSessionToken_emptyString_returnsFalse() {
        XCTAssertFalse(LoginViewModel.isValidSessionToken(""))
    }

    func testIsValidSessionToken_tooShort_returnsFalse() {
        // Minimum is 16 characters
        let shortToken = String(repeating: "a", count: 15)
        XCTAssertFalse(LoginViewModel.isValidSessionToken(shortToken))
    }

    func testIsValidSessionToken_tooLong_returnsFalse() {
        // Maximum is 512 characters
        let longToken = String(repeating: "a", count: 513)
        XCTAssertFalse(LoginViewModel.isValidSessionToken(longToken))
    }

    func testIsValidSessionToken_invalidCharacters_spaces_returnsFalse() {
        XCTAssertFalse(LoginViewModel.isValidSessionToken("token with spaces here"))
    }

    func testIsValidSessionToken_invalidCharacters_angleBrackets_returnsFalse() {
        XCTAssertFalse(LoginViewModel.isValidSessionToken("token<script>alert(1)</script>"))
    }

    func testIsValidSessionToken_validWithHyphens_returnsTrue() {
        let token = "abc-def-ghi-jkl-mno"
        XCTAssertTrue(LoginViewModel.isValidSessionToken(token))
    }

    func testIsValidSessionToken_validWithUnderscores_returnsTrue() {
        let token = "abc_def_ghi_jkl_mno"
        XCTAssertTrue(LoginViewModel.isValidSessionToken(token))
    }

    func testIsValidSessionToken_validWithDots_returnsTrue() {
        // JWT-style token with dots
        let token = "eyJhbGciOiJSUzI1NiJ9.payload.signature"
        XCTAssertTrue(LoginViewModel.isValidSessionToken(token))
    }

    func testIsValidSessionToken_validWithColons_returnsTrue() {
        // Token character set includes colons
        let token = "abc:def:ghi:jkl:mno"
        XCTAssertTrue(LoginViewModel.isValidSessionToken(token))
    }

    func testIsValidSessionToken_exactMinLength_returnsTrue() {
        let token = String(repeating: "a", count: 16)
        XCTAssertTrue(LoginViewModel.isValidSessionToken(token))
    }

    func testIsValidSessionToken_exactMaxLength_returnsTrue() {
        let token = String(repeating: "a", count: 512)
        XCTAssertTrue(LoginViewModel.isValidSessionToken(token))
    }

    // MARK: - handleAuthCallback Tests

    func testHandleAuthCallback_validToken_savesToKeychain() {
        // Given
        let validToken = "550e8400-e29b-41d4-a716-446655440000"

        // When
        viewModel.handleAuthCallback(sessionToken: validToken)

        // Then — token should be saved to keychain
        let savedToken = mockKeychainManager.getString(for: Constants.Keychain.accessToken)
        XCTAssertEqual(savedToken, validToken)
    }

    func testHandleAuthCallback_invalidToken_setsErrorMessage() {
        // Given — a token that is too short
        let invalidToken = "abc"

        // When
        viewModel.handleAuthCallback(sessionToken: invalidToken)

        // Then
        XCTAssertEqual(viewModel.errorMessage, "Invalid session token received")
        // Token should NOT be saved
        XCTAssertNil(mockKeychainManager.getString(for: Constants.Keychain.accessToken))
    }

    func testHandleAuthCallback_emptyToken_setsErrorMessage() {
        // When
        viewModel.handleAuthCallback(sessionToken: "")

        // Then
        XCTAssertEqual(viewModel.errorMessage, "Invalid session token received")
    }

    func testHandleAuthCallback_scriptInjection_setsErrorMessage() {
        // Given — injection attempt
        let maliciousToken = "<script>alert('xss')</script>"

        // When
        viewModel.handleAuthCallback(sessionToken: maliciousToken)

        // Then
        XCTAssertEqual(viewModel.errorMessage, "Invalid session token received")
        XCTAssertNil(mockKeychainManager.getString(for: Constants.Keychain.accessToken))
    }

    // MARK: - emailLogin Tests

    func testEmailLogin_emptyEmail_setsError() {
        // Given
        viewModel.email = ""

        // When
        viewModel.emailLogin()

        // Then
        XCTAssertEqual(viewModel.errorMessage, "Email is required")
        XCTAssertFalse(viewModel.isLoading, "Should not be loading after validation error")
    }

    func testEmailLogin_whitespaceOnlyEmail_setsError() {
        // Given
        viewModel.email = "   "

        // When
        viewModel.emailLogin()

        // Then
        XCTAssertEqual(viewModel.errorMessage, "Email is required")
    }

    // MARK: - createChallenge Tests

    func testCreateChallenge_setsIsLoading() {
        // When
        viewModel.createChallenge()

        // Then — isLoading should be set immediately
        XCTAssertTrue(viewModel.isLoading)
    }

    func testCreateChallenge_clearsExpiredState() {
        // Given
        viewModel.isExpired = true

        // When
        viewModel.createChallenge()

        // Then
        XCTAssertFalse(viewModel.isExpired)
    }

    func testCreateChallenge_clearsError() {
        // Given
        viewModel.errorMessage = "Some previous error"

        // When
        viewModel.createChallenge()

        // Then
        XCTAssertNil(viewModel.errorMessage)
    }

    // MARK: - Initial State Tests

    func testInitialState_isNotLoading() {
        XCTAssertFalse(viewModel.isLoading)
    }

    func testInitialState_noErrorMessage() {
        XCTAssertNil(viewModel.errorMessage)
    }

    func testInitialState_isNotExpired() {
        XCTAssertFalse(viewModel.isExpired)
    }

    func testInitialState_emptyEmail() {
        XCTAssertEqual(viewModel.email, "")
    }

    func testInitialState_noQrPayload() {
        XCTAssertNil(viewModel.qrPayload)
    }

    func testInitialState_noWalletDeepLink() {
        XCTAssertNil(viewModel.walletDeepLink)
    }

    // MARK: - pendingInviteCode Tests

    func testPendingInviteCode_defaultsToNil() {
        XCTAssertNil(viewModel.pendingInviteCode)
    }

    func testPendingInviteCode_canBeSet() {
        viewModel.pendingInviteCode = "INVITE-CODE-123"
        XCTAssertEqual(viewModel.pendingInviteCode, "INVITE-CODE-123")
    }
}
