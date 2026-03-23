import XCTest

final class DeepLinkSmokeUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        app.launch()
    }

    func testInvalidDeepLinkDoesNotCrash() {
        // Open an invalid deep link — app should not crash
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        safari.launch()
        safari.textFields.firstMatch.tap()
        safari.textFields.firstMatch.typeText("ssdid-drive://invalid/path\n")

        // Switch back to app
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }
}
