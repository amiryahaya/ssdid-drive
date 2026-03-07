import XCTest

/// XCTestCase extensions for waiting on elements
extension XCTestCase {

    // MARK: - Element Waiting

    /// Wait for an element to exist
    func waitForElement(
        _ element: XCUIElement,
        timeout: TimeInterval = UITestConfig.defaultTimeout,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let exists = element.waitForExistence(timeout: timeout)
        XCTAssertTrue(
            exists,
            "Element '\(element.identifier)' did not appear within \(timeout) seconds",
            file: file,
            line: line
        )
    }

    /// Wait for an element to disappear
    func waitForElementToDisappear(
        _ element: XCUIElement,
        timeout: TimeInterval = UITestConfig.defaultTimeout,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let disappeared = element.waitForNonExistence(timeout: timeout)
        XCTAssertTrue(
            disappeared,
            "Element '\(element.identifier)' did not disappear within \(timeout) seconds",
            file: file,
            line: line
        )
    }

    /// Wait for element to be hittable (visible and enabled)
    func waitForElementToBeHittable(
        _ element: XCUIElement,
        timeout: TimeInterval = UITestConfig.defaultTimeout,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let hittable = element.waitUntilHittable(timeout: timeout)
        XCTAssertTrue(
            hittable,
            "Element '\(element.identifier)' did not become hittable within \(timeout) seconds",
            file: file,
            line: line
        )
    }

    // MARK: - Screen Waiting

    /// Wait for a specific screen to appear by checking for a key element
    func waitForScreen(
        identifiedBy elementIdentifier: String,
        in app: XCUIApplication,
        timeout: TimeInterval = UITestConfig.defaultTimeout,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let element = app.descendants(matching: .any)[elementIdentifier]
        waitForElement(element, timeout: timeout, file: file, line: line)
    }

    /// Wait for login screen to appear
    func waitForLoginScreen(
        _ app: XCUIApplication,
        timeout: TimeInterval = UITestConfig.defaultTimeout
    ) {
        let loginButton = app.buttons["loginButton"]
        _ = loginButton.waitForExistence(timeout: timeout)
    }

    /// Wait for home screen (file browser) to appear
    func waitForHomeScreen(
        _ app: XCUIApplication,
        timeout: TimeInterval = UITestConfig.defaultTimeout
    ) {
        let fileBrowser = app.collectionViews["fileBrowserCollection"]
        _ = fileBrowser.waitForExistence(timeout: timeout)
    }

    // MARK: - Loading State

    /// Wait for loading to complete
    func waitForLoadingToComplete(
        _ app: XCUIApplication,
        timeout: TimeInterval = UITestConfig.networkTimeout
    ) {
        let loadingIndicator = app.activityIndicators.element(boundBy: 0)
        if loadingIndicator.exists {
            _ = loadingIndicator.waitForNonExistence(timeout: timeout)
        }
    }

    /// Wait for refresh control to finish
    func waitForRefreshToComplete(
        _ app: XCUIApplication,
        timeout: TimeInterval = UITestConfig.networkTimeout
    ) {
        // Wait a moment for refresh to start
        Thread.sleep(forTimeInterval: 0.5)

        // Wait for any loading to complete
        waitForLoadingToComplete(app, timeout: timeout)
    }

    // MARK: - Alert Handling

    /// Wait for alert and tap a button
    func waitForAlertAndTap(
        buttonLabel: String,
        in app: XCUIApplication,
        timeout: TimeInterval = UITestConfig.defaultTimeout
    ) {
        let alert = app.alerts.element(boundBy: 0)
        guard alert.waitForExistence(timeout: timeout) else {
            XCTFail("Alert did not appear")
            return
        }

        let button = alert.buttons[buttonLabel]
        guard button.waitForExistence(timeout: UITestConfig.shortTimeout) else {
            XCTFail("Button '\(buttonLabel)' not found in alert")
            return
        }

        button.tap()
    }

    /// Wait for confirmation alert and confirm
    func waitForConfirmationAndConfirm(
        _ app: XCUIApplication,
        timeout: TimeInterval = UITestConfig.defaultTimeout
    ) {
        waitForAlertAndTap(buttonLabel: "OK", in: app, timeout: timeout)
    }

    // MARK: - Assertion Helpers

    /// Assert element contains text
    func assertElementContainsText(
        _ element: XCUIElement,
        text: String,
        timeout: TimeInterval = UITestConfig.defaultTimeout,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let containsText = element.waitForText(text, timeout: timeout)
        XCTAssertTrue(
            containsText,
            "Element '\(element.identifier)' does not contain text '\(text)'",
            file: file,
            line: line
        )
    }

    /// Assert screen is visible
    func assertScreenIsVisible(
        _ screenIdentifier: String,
        in app: XCUIApplication,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let screen = app.descendants(matching: .any)[screenIdentifier]
        XCTAssertTrue(
            screen.exists,
            "Screen '\(screenIdentifier)' is not visible",
            file: file,
            line: line
        )
    }
}
