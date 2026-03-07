import XCTest

/// Error state handling UI tests
final class ErrorStateUITests: XCTestCase {

    var app: XCUIApplication!

    // MARK: - Setup

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        UITestUtils.takeScreenshot(name: "teardown_\(name)")
        app.terminate()
    }

    // MARK: - Test: Error State Handling

    func testErrorStateHandling() throws {
        // Launch with error simulation flags
        app.launchArguments = UITestConfig.launchArguments + [
            "-SimulateNetworkError", "true"
        ]
        app.launchEnvironment = UITestConfig.launchEnvironment
        app.launch()

        // Try to login
        let loginPage = LoginPage(app: app)

        guard loginPage.isDisplayed() else {
            XCTSkip("Login page not displayed")
            return
        }

        // Attempt login (should fail with simulated error)
        loginPage.attemptLogin(
            email: UITestConfig.testUserEmail,
            password: UITestConfig.testUserPassword
        )

        // Wait for response
        Thread.sleep(forTimeInterval: 3)

        // Check for error handling
        let hasError = loginPage.isErrorVisible ||
                      loginPage.isAlertDisplayed

        if hasError {
            UITestUtils.takeScreenshot(name: "error_displayed")

            // Verify error message is user-friendly
            if let errorMessage = loginPage.errorMessage {
                // Error should not contain stack traces or technical details
                XCTAssertFalse(
                    errorMessage.contains("Error:") && errorMessage.contains("at "),
                    "Error message should be user-friendly"
                )
            } else if loginPage.isAlertDisplayed {
                if let alertMessage = loginPage.alertMessage {
                    XCTAssertFalse(
                        alertMessage.contains("Error:") && alertMessage.contains("at "),
                        "Alert message should be user-friendly"
                    )
                }
            }

            // Dismiss error
            if loginPage.isAlertDisplayed {
                loginPage.dismissAlert()
            }
        }

        // Verify app is still functional after error
        XCTAssertTrue(loginPage.isDisplayed(), "Should remain on login page after error")

        // Try again with valid credentials (without error simulation)
        app.terminate()

        // Relaunch without error simulation
        app = UITestUtils.launchApp(resetState: true)
        let loginPage2 = LoginPage(app: app)

        loginPage2.login(
            email: UITestConfig.testUserEmail,
            password: UITestConfig.testUserPassword
        )

        let fileBrowserPage = FileBrowserPage(app: app)
        XCTAssertTrue(
            fileBrowserPage.isDisplayed(),
            "Should successfully login after error recovery"
        )
    }

    // MARK: - Test: Session Expiry Handling

    func testSessionExpiryHandling() throws {
        // Launch normally and login
        app = UITestUtils.launchApp(resetState: true)

        let loginPage = LoginPage(app: app)
        loginPage.login(
            email: UITestConfig.testUserEmail,
            password: UITestConfig.testUserPassword
        )

        let fileBrowserPage = FileBrowserPage(app: app)
        XCTAssertTrue(fileBrowserPage.isDisplayed())

        // Simulate session expiry by relaunching with expired token flag
        app.terminate()

        app = XCUIApplication()
        app.launchArguments = UITestConfig.launchArguments + [
            "-SimulateExpiredSession", "true"
        ]
        app.launchEnvironment = UITestConfig.launchEnvironment
        app.launch()

        // Wait for app to detect expired session
        Thread.sleep(forTimeInterval: 2)

        // Try to perform an action that requires authentication
        let fileBrowserPage2 = FileBrowserPage(app: app)
        if fileBrowserPage2.isDisplayed() {
            fileBrowserPage2.pullToRefresh()
            Thread.sleep(forTimeInterval: 2)
        }

        // Should be redirected to login or shown session expired message
        let loginPage2 = LoginPage(app: app)
        let sessionExpiredAlert = app.alerts.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'session' OR label CONTAINS[c] 'expired' OR label CONTAINS[c] 'login again'")
        ).element(boundBy: 0)

        let isOnLogin = loginPage2.isDisplayed()
        let hasSessionAlert = sessionExpiredAlert.exists

        UITestUtils.takeScreenshot(name: "session_expiry_state")

        // Either should be true
        let handledExpiry = isOnLogin || hasSessionAlert
        XCTAssertTrue(
            handledExpiry,
            "App should handle session expiry gracefully"
        )

        // If alert shown, dismiss and verify login screen
        if hasSessionAlert {
            UITestUtils.dismissAlert(app)
            XCTAssertTrue(
                loginPage2.isDisplayed(),
                "Should navigate to login after dismissing session expiry alert"
            )
        }
    }

    // MARK: - Test: Network Error Recovery

    func testNetworkErrorRecovery() throws {
        // Launch and login normally
        app = UITestUtils.launchApp(resetState: true)

        let loginPage = LoginPage(app: app)
        loginPage.login(
            email: UITestConfig.testUserEmail,
            password: UITestConfig.testUserPassword
        )

        let fileBrowserPage = FileBrowserPage(app: app)
        XCTAssertTrue(fileBrowserPage.isDisplayed())

        // Take baseline screenshot
        UITestUtils.takeScreenshot(name: "before_network_error")

        // Perform multiple refresh attempts to test stability
        for i in 0..<5 {
            fileBrowserPage.pullToRefresh()
            Thread.sleep(forTimeInterval: 1)

            // Dismiss any errors
            if app.alerts.element(boundBy: 0).exists {
                UITestUtils.dismissAlert(app)
            }

            // Verify app remains functional
            XCTAssertTrue(
                fileBrowserPage.isDisplayed(),
                "App should remain stable after refresh \(i + 1)"
            )
        }

        // Test navigation still works
        let settingsTab = app.tabBars.buttons["Settings"]
        if settingsTab.exists {
            settingsTab.tap()

            let settingsPage = SettingsPage(app: app)
            XCTAssertTrue(settingsPage.isDisplayed())

            // Navigate back to files
            let filesTab = app.tabBars.buttons["Files"]
            filesTab.tap()

            XCTAssertTrue(fileBrowserPage.isDisplayed())
        }

        UITestUtils.takeScreenshot(name: "after_error_recovery")
    }

    // MARK: - Test: Retry Button Functionality

    func testRetryButtonFunctionality() throws {
        // Launch with error simulation
        app.launchArguments = UITestConfig.launchArguments + [
            "-SimulateNetworkError", "true",
            "-ErrorRetryEnabled", "true"
        ]
        app.launchEnvironment = UITestConfig.launchEnvironment
        app.launch()

        let loginPage = LoginPage(app: app)

        // Skip if login page doesn't show
        guard loginPage.isDisplayed() else {
            XCTSkip("Login page not accessible")
            return
        }

        // Trigger login (should fail)
        loginPage.attemptLogin(
            email: UITestConfig.testUserEmail,
            password: UITestConfig.testUserPassword
        )

        Thread.sleep(forTimeInterval: 3)

        // Look for retry button
        let retryButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'retry' OR label CONTAINS[c] 'try again'")
        ).element(boundBy: 0)

        if retryButton.waitForExistence(timeout: UITestConfig.shortTimeout) {
            UITestUtils.takeScreenshot(name: "retry_button_visible")

            // Tap retry
            retryButton.tap()

            // Wait for retry attempt
            Thread.sleep(forTimeInterval: 2)

            UITestUtils.takeScreenshot(name: "after_retry")
        } else {
            // May show error differently
            if loginPage.isAlertDisplayed {
                UITestUtils.takeScreenshot(name: "error_alert")
                loginPage.dismissAlert()
            }
        }
    }
}
