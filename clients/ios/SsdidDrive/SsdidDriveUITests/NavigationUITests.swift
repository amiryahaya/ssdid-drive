import XCTest

final class NavigationUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        app.launch()
    }

    func testAppLaunches() {
        // App should launch without crashing
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }

    func testLoginScreenAccessibility() {
        // Verify accessibility identifiers are set correctly
        let loginTitle = app.staticTexts["loginTitleLabel"]
        let logo = app.images["loginLogoImageView"]
        XCTAssertTrue(loginTitle.waitForExistence(timeout: 5) || logo.waitForExistence(timeout: 5))
    }
}
