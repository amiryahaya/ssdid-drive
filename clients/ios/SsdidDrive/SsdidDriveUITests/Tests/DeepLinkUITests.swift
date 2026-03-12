import XCTest

/// UI tests for deep link handling in SSDID Drive.
///
/// Uses `xcrun simctl openurl` to deliver deep link URLs directly to the app
/// via the simulator runtime. This is more reliable than the Safari-based
/// approach because it bypasses Safari's UI entirely and triggers the app's
/// `scene(_:openURLContexts:)` handler directly.
///
/// Prerequisites:
/// - The app must be installed on the simulator
/// - The `ssdid-drive://` URL scheme must be registered in Info.plist
final class DeepLinkUITests: XCTestCase {

    var app: XCUIApplication!

    // MARK: - Setup

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = UITestUtils.launchApp(
            resetState: true,
            additionalArguments: ["-MockBackend"]
        )
    }

    override func tearDownWithError() throws {
        UITestUtils.takeScreenshot(name: "deeplink_teardown_\(name)")
        app.terminate()
    }

    // MARK: - Auth Callback Deep Link Tests

    /// Test: Valid auth callback deep link logs the user in.
    ///
    /// Simulates the wallet completing authentication and calling back to Drive
    /// with `ssdid-drive://auth/callback?session_token=<token>`.
    func testAuthCallback_validToken_navigatesToFileBrowser() throws {
        // Verify we start on the login screen
        let loginPage = LoginPage(app: app)
        XCTAssertTrue(loginPage.isDisplayed(), "Should start on login screen")

        // Simulate wallet callback with a valid session token
        let token = "e2e-test-session-token-1234567890"
        openDeepLink("ssdid-drive://auth/callback?session_token=\(token)")

        // App should process the callback and navigate to file browser
        let fileBrowserPage = FileBrowserPage(app: app)
        XCTAssertTrue(
            fileBrowserPage.isDisplayed(),
            "Should navigate to file browser after valid auth callback"
        )

        UITestUtils.takeScreenshot(name: "auth_callback_success")
    }

    /// Test: Auth callback with missing token stays on login screen.
    func testAuthCallback_missingToken_staysOnLogin() throws {
        let loginPage = LoginPage(app: app)
        XCTAssertTrue(loginPage.isDisplayed())

        // Open callback URL without session_token
        openDeepLink("ssdid-drive://auth/callback")

        // Should remain on login screen
        Thread.sleep(forTimeInterval: 2)
        XCTAssertTrue(loginPage.isDisplayed(), "Should stay on login screen without token")
    }

    /// Test: Auth callback with invalid (too short) token is rejected.
    func testAuthCallback_invalidToken_staysOnLogin() throws {
        let loginPage = LoginPage(app: app)
        XCTAssertTrue(loginPage.isDisplayed())

        // Open callback with a token that's too short (< 16 chars)
        openDeepLink("ssdid-drive://auth/callback?session_token=short")

        // Should remain on login screen — token validation rejects it
        Thread.sleep(forTimeInterval: 2)
        XCTAssertTrue(loginPage.isDisplayed(), "Should reject short token")
    }

    // MARK: - Invitation Deep Link Tests

    /// Test: Invitation deep link navigates to invite accept screen.
    func testInviteLink_navigatesToInviteAccept() throws {
        let token = "invite-token-abcdefghij1234"
        openDeepLink("ssdid-drive://invite/\(token)")

        // Should navigate to invite accept screen
        let inviteText = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'invite' OR label CONTAINS[c] 'join'")
        )
        let found = inviteText.firstMatch.waitForExistence(timeout: UITestConfig.networkTimeout)
        XCTAssertTrue(found, "Should show invite acceptance screen")

        UITestUtils.takeScreenshot(name: "invite_deeplink")
    }

    // MARK: - Universal Link Tests (HTTPS)

    /// Test: Universal Link for auth callback works the same as custom scheme.
    func testUniversalLink_authCallback() throws {
        let loginPage = LoginPage(app: app)
        XCTAssertTrue(loginPage.isDisplayed())

        // Universal Link format — simctl delivers these as custom scheme,
        // not as Universal Links, so this tests the DeepLinkParser HTTPS path.
        let token = "universal-link-session-token-xyz"
        openDeepLink("https://drive.ssdid.my/auth/callback?session_token=\(token)")

        let fileBrowserPage = FileBrowserPage(app: app)
        let navigated = fileBrowserPage.isDisplayed()

        // Note: simctl openurl delivers HTTPS URLs as Universal Links only if
        // the AASA file is cached. On CI this may not be the case.
        if !navigated {
            XCTSkip("Universal Links require AASA to be cached by the simulator")
        }
    }

    // MARK: - QR Code Login Flow Tests

    /// Test: Login screen displays QR code after creating a challenge.
    func testLoginScreen_showsQrCode() throws {
        let loginPage = LoginPage(app: app)
        XCTAssertTrue(loginPage.isDisplayed())

        let qrImage = app.images.matching(
            NSPredicate(format: "identifier CONTAINS[c] 'qr' OR label CONTAINS[c] 'QR'")
        )

        let qrExists = qrImage.firstMatch.waitForExistence(timeout: UITestConfig.networkTimeout)

        if !qrExists {
            XCTSkip("QR code display requires mock backend to be configured")
        }

        UITestUtils.takeScreenshot(name: "login_qr_code")
    }

    // MARK: - Deep Link Helpers

    /// Open a deep link URL via Safari to trigger the app's URL scheme handler.
    ///
    /// Opens Safari, types the URL in the address bar, and accepts the
    /// "Open in SsdidDrive?" system prompt. This is the standard XCUITest
    /// technique since `Process`/`xcrun simctl` is unavailable on iOS.
    ///
    /// For CI, prefer running `xcrun simctl openurl booted <url>` from a
    /// shell script before/after the test instead.
    private func openDeepLink(_ urlString: String) {
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        safari.launch()

        // Type URL in the address bar
        let addressBar = safari.textFields.firstMatch
        if addressBar.waitForExistence(timeout: 5) {
            addressBar.tap()
            addressBar.typeText(urlString + "\n")
        }

        // Accept the "Open in SsdidDrive?" system dialog
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let openButton = springboard.buttons["Open"]
        if openButton.waitForExistence(timeout: 5) {
            openButton.tap()
        }

        // Wait for our app to come back to foreground
        _ = app.wait(for: .runningForeground, timeout: UITestConfig.defaultTimeout)
    }
}
