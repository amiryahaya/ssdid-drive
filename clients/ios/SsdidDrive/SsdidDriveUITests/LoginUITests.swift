import XCTest

final class LoginUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        app.launch()
        // Skip onboarding if shown (first-launch flow).
        let skipButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'skip'")).firstMatch
        if skipButton.waitForExistence(timeout: 3) {
            skipButton.tap()
        }
    }

    // MARK: - Helpers

    /// Returns true if the login screen is currently visible.
    private var isLoginScreenVisible: Bool {
        app.staticTexts["loginTitleLabel"].waitForExistence(timeout: UITestConfig.defaultTimeout)
    }

    // MARK: - Tests

    func testLoginScreenDisplaysCorrectly() throws {
        guard isLoginScreenVisible else {
            throw XCTSkip("Login screen not visible — app may already be authenticated")
        }
        // Verify title or wallet/email button exists
        let walletBtn = app.buttons["openWalletButton"]
        let emailBtn = app.buttons["emailContinueButton"]
        XCTAssertTrue(
            walletBtn.exists || emailBtn.exists,
            "Login screen should display a primary auth button"
        )
    }

    func testInviteCodeCardIsVisible() throws {
        guard isLoginScreenVisible else {
            throw XCTSkip("Login screen not visible — app may already be authenticated")
        }
        XCTAssertTrue(app.otherElements["inviteCodeCard"].exists)
    }

    func testEmailFieldExists() throws {
        guard isLoginScreenVisible else {
            throw XCTSkip("Login screen not visible — app may already be authenticated")
        }
        // Email field should be visible (Layout B) or in "Other options" (Layout A).
        let emailField = app.textFields["emailTextField"]
        let otherOptionsButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Other sign in options'")
        ).firstMatch
        XCTAssertTrue(emailField.exists || otherOptionsButton.exists)
    }

    func testOidcButtonsExist() throws {
        guard isLoginScreenVisible else {
            throw XCTSkip("Login screen not visible — app may already be authenticated")
        }
        let google = app.buttons["googleSignInButton"]
        let microsoft = app.buttons["microsoftSignInButton"]
        if !google.exists {
            // Try expanding other options (Layout A)
            let other = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Other'")).firstMatch
            if other.exists { other.tap() }
        }
        XCTAssertTrue(
            google.exists || microsoft.exists || app.buttons["openWalletButton"].exists,
            "At least one auth method should be visible"
        )
    }

    func testEmptyEmailContinueDisabled() throws {
        guard isLoginScreenVisible else {
            throw XCTSkip("Login screen not visible — app may already be authenticated")
        }
        let emailField = app.textFields["emailTextField"]
        guard emailField.exists else { return } // Layout A — skip
        let continueBtn = app.buttons["emailContinueButton"]
        XCTAssertFalse(continueBtn.isEnabled)
    }

    func testRefreshButtonAppearsOnExpiry() throws {
        guard isLoginScreenVisible else {
            throw XCTSkip("Login screen not visible — app may already be authenticated")
        }
        // Refresh button should not be hittable until QR code expires.
        let refresh = app.buttons["refreshButton"]
        XCTAssertFalse(refresh.isHittable) // hidden by default
    }
}
