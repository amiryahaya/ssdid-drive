import XCTest

/// Main UI test configuration and launch tests
final class SecureSharingUITests: XCTestCase {

    var app: XCUIApplication!

    // MARK: - Setup

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app?.terminate()
    }

    // MARK: - Launch Test

    /// Basic launch test to verify app starts correctly
    func testAppLaunch() throws {
        app.launchArguments = UITestConfig.launchArguments
        app.launchEnvironment = UITestConfig.launchEnvironment
        app.launch()

        // Verify app launches
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

        // Should show either login screen or main app
        let loginButton = app.buttons["loginButton"]
        let fileBrowser = app.collectionViews["fileBrowserCollection"]
        let onboardingView = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'get started' OR label CONTAINS[c] 'continue'")
        ).element(boundBy: 0)

        let hasValidScreen = loginButton.waitForExistence(timeout: 5) ||
                            fileBrowser.waitForExistence(timeout: 5) ||
                            onboardingView.waitForExistence(timeout: 5)

        XCTAssertTrue(hasValidScreen, "App should show a valid initial screen")

        UITestUtils.takeScreenshot(name: "app_launch")
    }

    /// Test app launch performance
    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
}
