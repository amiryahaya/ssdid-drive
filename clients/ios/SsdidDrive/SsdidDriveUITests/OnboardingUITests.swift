import XCTest

final class OnboardingUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        app.launchArguments = ["--reset-onboarding"] // if supported
        app.launch()
    }

    func testOnboardingSkipNavigatesToLogin() {
        // If onboarding is shown, skip button should be available
        let skipButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'skip'")).firstMatch
        if skipButton.waitForExistence(timeout: 3) {
            skipButton.tap()
            XCTAssertTrue(app.staticTexts["SSDID Drive"].waitForExistence(timeout: 5))
        }
    }
}
