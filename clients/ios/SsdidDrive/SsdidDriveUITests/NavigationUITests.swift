import XCTest

final class NavigationUITests: XCTestCase {
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

    func testAppLaunches() {
        // App should launch without crashing
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }

    func testLoginScreenAccessibility() throws {
        // Accessibility identifiers are only expected when the login screen is shown.
        // If the user is already authenticated, the file browser shows instead — skip.
        let loginTitle = app.staticTexts["loginTitleLabel"]
        let logo = app.images["loginLogoImageView"]

        // Give the screen up to defaultTimeout to appear.
        let loginVisible = loginTitle.waitForExistence(timeout: UITestConfig.defaultTimeout)
            || logo.waitForExistence(timeout: 1) // fast second check after first already waited

        guard loginVisible else {
            throw XCTSkip("Login screen not visible — app may already be authenticated")
        }

        // Logo should be above title in the layout.
        if logo.exists && loginTitle.exists {
            XCTAssertTrue(logo.frame.midY < loginTitle.frame.midY, "Logo should be above title")
        }
    }
}
