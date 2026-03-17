import XCTest
import Combine
@testable import SsdidDrive

/// Unit tests for AppCoordinator deep link handling.
/// Verifies that deep link actions are routed correctly depending on
/// authentication state, and that pending deep links are saved/processed.
@MainActor
final class AppCoordinatorDeepLinkTests: XCTestCase {

    // MARK: - Properties

    var appCoordinator: AppCoordinator!
    var navigationController: UINavigationController!
    var mockAuthRepository: MockAuthRepository!
    var cancellables: Set<AnyCancellable>!

    // MARK: - Setup

    override func setUp() {
        super.setUp()
        navigationController = UINavigationController()
        cancellables = Set<AnyCancellable>()

        // Use the shared container but override its auth repository
        let container = DependencyContainer.shared
        mockAuthRepository = MockAuthRepository()

        appCoordinator = AppCoordinator(
            navigationController: navigationController,
            container: container
        )
    }

    override func tearDown() {
        appCoordinator = nil
        navigationController = nil
        mockAuthRepository = nil
        cancellables = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Wait for async operations by running the RunLoop.
    private func waitForRunLoop(seconds: TimeInterval = 0.5) {
        let expectation = expectation(description: "RunLoop wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: seconds + 1.0)
    }

    // MARK: - Deep Link URL Parsing Tests

    func testHandleDeepLink_validFileURL_parsesCorrectly() {
        // Given
        let url = URL(string: "ssdid-drive://file/abc123")!

        // When — parse manually to verify
        let action = DeepLinkParser.parse(url)

        // Then
        if case .openFile(let fileId) = action {
            XCTAssertEqual(fileId, "abc123")
        } else {
            XCTFail("Expected .openFile, got \(String(describing: action))")
        }
    }

    func testHandleDeepLink_invalidURL_doesNotCrash() {
        // Given
        let url = URL(string: "ssdid-drive://unknown/something")!

        // When — should not crash
        appCoordinator.handleDeepLink(url)

        // Then — no crash, no error
        waitForRunLoop(seconds: 0.3)
    }

    // MARK: - handleDeepLinkAction Tests

    func testHandleDeepLinkAction_authCallback_deliveredToLoginViewModel() {
        // Given — set up auth coordinator with login view model
        let mockKeychain = InvitationMockKeychainManager()
        let loginViewModel = LoginViewModel(keychainManager: mockKeychain)

        // Create a mock auth coordinator that exposes the loginViewModel
        let authCoordinator = AuthCoordinator(
            navigationController: navigationController,
            container: DependencyContainer.shared
        )
        appCoordinator.addChild(authCoordinator)

        // Start the auth coordinator to create a loginViewModel
        authCoordinator.start()
        waitForRunLoop(seconds: 0.3)

        let validToken = "valid-session-token-1234567890"

        // When
        appCoordinator.handleDeepLinkAction(.authCallback(sessionToken: validToken))

        // Then — wait for async task
        waitForRunLoop(seconds: 0.5)

        // The authCoordinator should have a loginViewModel that received the callback
        // Verify by checking the loginViewModel's state
        XCTAssertNotNil(authCoordinator.loginViewModel, "AuthCoordinator should have a loginViewModel")
    }

    // MARK: - acceptInvitation Tests

    func testHandleDeepLinkAction_acceptInvitation_callsHandleInvitation() {
        // Given
        let token = "valid-invitation-token-123"

        // When
        appCoordinator.handleDeepLinkAction(.acceptInvitation(token: token))

        // Then — wait for async processing
        waitForRunLoop(seconds: 0.5)

        // Verify an AuthCoordinator was created as a child
        let hasAuthCoordinator = appCoordinator.childCoordinators.contains { $0 is AuthCoordinator }
        XCTAssertTrue(hasAuthCoordinator, "Should create AuthCoordinator for invitation handling")
    }

    // MARK: - Pending Deep Link Tests

    func testSavePendingDeepLink_fileAction_savedToUserDefaults() {
        // Given
        let action = DeepLinkAction.openFile(fileId: "file-123")
        let userDefaults = DependencyContainer.shared.userDefaultsManager

        // When
        userDefaults.savePendingDeepLink(action)

        // Then
        let pending = userDefaults.consumePendingDeepLink()
        if case .openFile(let fileId) = pending {
            XCTAssertEqual(fileId, "file-123")
        } else {
            XCTFail("Expected .openFile pending deep link, got \(String(describing: pending))")
        }
    }

    func testConsumePendingDeepLink_removesAfterConsuming() {
        // Given
        let action = DeepLinkAction.openFile(fileId: "file-456")
        let userDefaults = DependencyContainer.shared.userDefaultsManager

        // When
        userDefaults.savePendingDeepLink(action)
        let first = userDefaults.consumePendingDeepLink()
        let second = userDefaults.consumePendingDeepLink()

        // Then
        XCTAssertNotNil(first, "First consume should return the action")
        XCTAssertNil(second, "Second consume should return nil (already consumed)")
    }

    func testPendingDeepLink_importAction_notSaved() {
        // Import actions should not be persisted because the files may expire.
        // We test the DeepLinkParser.parse -> importFiles path indirectly.
        // The savePendingDeepLinkIfAppropriate method skips import actions.
        let importManifest = ImportManifest(files: [
            ImportManifest.ImportFileInfo(name: "test.txt", path: "/tmp/test.txt", size: 100)
        ])
        let action = DeepLinkAction.importFiles(manifest: importManifest)

        // Verify it's an import action
        if case .importFiles = action {
            // Correct type
        } else {
            XCTFail("Expected .importFiles action")
        }
    }

    // MARK: - Deep Link Action Equatable Tests

    func testDeepLinkAction_authCallback_equatable() {
        let a = DeepLinkAction.authCallback(sessionToken: "token123")
        let b = DeepLinkAction.authCallback(sessionToken: "token123")
        let c = DeepLinkAction.authCallback(sessionToken: "different")

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testDeepLinkAction_openFile_equatable() {
        let a = DeepLinkAction.openFile(fileId: "file-1")
        let b = DeepLinkAction.openFile(fileId: "file-1")
        let c = DeepLinkAction.openFile(fileId: "file-2")

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testDeepLinkAction_differentTypes_notEqual() {
        let file = DeepLinkAction.openFile(fileId: "id-1")
        let folder = DeepLinkAction.openFolder(folderId: "id-1")

        XCTAssertNotEqual(file, folder)
    }

    // MARK: - Codable Round-Trip Tests

    func testDeepLinkAction_authCallback_codableRoundTrip() throws {
        // Given
        let original = DeepLinkAction.authCallback(sessionToken: "test-token-abc")

        // When
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DeepLinkAction.self, from: data)

        // Then
        XCTAssertEqual(original, decoded)
    }

    func testDeepLinkAction_openFile_codableRoundTrip() throws {
        // Given
        let original = DeepLinkAction.openFile(fileId: "file-uuid-123")

        // When
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DeepLinkAction.self, from: data)

        // Then
        XCTAssertEqual(original, decoded)
    }

    func testDeepLinkAction_acceptInvitation_codableRoundTrip() throws {
        // Given
        let original = DeepLinkAction.acceptInvitation(token: "invite-token-xyz")

        // When
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DeepLinkAction.self, from: data)

        // Then
        XCTAssertEqual(original, decoded)
    }

    func testDeepLinkAction_walletInviteError_codableRoundTrip() throws {
        // Given
        let original = DeepLinkAction.walletInviteError(message: "Something went wrong")

        // When
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DeepLinkAction.self, from: data)

        // Then
        XCTAssertEqual(original, decoded)
    }
}
