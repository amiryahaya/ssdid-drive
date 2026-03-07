import XCTest

/// Utility functions for UI testing
enum UITestUtils {

    // MARK: - App Setup

    /// Launch the app with test configuration
    @discardableResult
    static func launchApp(
        resetState: Bool = true,
        additionalArguments: [String] = [],
        additionalEnvironment: [String: String] = [:]
    ) -> XCUIApplication {
        let app = XCUIApplication()

        // Set launch arguments
        var arguments = UITestConfig.launchArguments
        if resetState {
            arguments.append("-ResetStateOnLaunch")
        }
        arguments.append(contentsOf: additionalArguments)
        app.launchArguments = arguments

        // Set launch environment
        var environment = UITestConfig.launchEnvironment
        environment.merge(additionalEnvironment) { _, new in new }
        app.launchEnvironment = environment

        app.launch()
        return app
    }

    /// Terminate and relaunch the app
    @discardableResult
    static func relaunchApp(_ app: XCUIApplication) -> XCUIApplication {
        app.terminate()
        return launchApp(resetState: false)
    }

    // MARK: - Screenshots

    /// Take a screenshot and attach it to the test
    static func takeScreenshot(
        name: String,
        activity: XCTActivity? = nil
    ) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways

        if let activity = activity {
            activity.add(attachment)
        } else {
            XCTContext.runActivity(named: "Screenshot: \(name)") { activity in
                activity.add(attachment)
            }
        }
    }

    /// Take a screenshot of a specific element
    static func takeElementScreenshot(
        _ element: XCUIElement,
        name: String
    ) {
        let screenshot = element.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways

        XCTContext.runActivity(named: "Element Screenshot: \(name)") { activity in
            activity.add(attachment)
        }
    }

    // MARK: - Element Helpers

    /// Safely tap an element if it exists
    @discardableResult
    static func safeTap(
        _ element: XCUIElement,
        timeout: TimeInterval = UITestConfig.defaultTimeout
    ) -> Bool {
        guard element.waitForExistence(timeout: timeout) else {
            return false
        }
        element.tap()
        return true
    }

    /// Clear and type text in a text field
    static func clearAndType(
        _ textField: XCUIElement,
        text: String
    ) {
        textField.tap()

        // Select all and delete
        if let currentText = textField.value as? String, !currentText.isEmpty {
            textField.tap()
            textField.press(forDuration: 1.0)

            let selectAll = XCUIApplication().menuItems["Select All"]
            if selectAll.waitForExistence(timeout: 2) {
                selectAll.tap()
            }
            textField.typeText(XCUIKeyboardKey.delete.rawValue)
        }

        textField.typeText(text)
    }

    /// Dismiss keyboard if visible
    static func dismissKeyboard(_ app: XCUIApplication) {
        if app.keyboards.element(boundBy: 0).exists {
            app.typeText("\n")
        }
    }

    // MARK: - Scrolling

    /// Scroll until element is visible
    static func scrollToElement(
        _ element: XCUIElement,
        in scrollView: XCUIElement,
        maxScrolls: Int = 10
    ) -> Bool {
        var scrollCount = 0

        while !element.isHittable && scrollCount < maxScrolls {
            scrollView.swipeUp()
            scrollCount += 1
        }

        return element.isHittable
    }

    /// Pull to refresh
    static func pullToRefresh(
        _ scrollView: XCUIElement
    ) {
        let start = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        let end = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        start.press(forDuration: 0.1, thenDragTo: end)
    }

    // MARK: - Alerts

    /// Handle system alert by accepting it
    static func acceptSystemAlert(_ app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allowButton = springboard.buttons["Allow"]
        if allowButton.waitForExistence(timeout: 2) {
            allowButton.tap()
        }
    }

    /// Dismiss any visible alert
    static func dismissAlert(_ app: XCUIApplication) {
        let alert = app.alerts.element(boundBy: 0)
        if alert.exists {
            let buttons = ["OK", "Cancel", "Dismiss", "Close"]
            for buttonLabel in buttons {
                let button = alert.buttons[buttonLabel]
                if button.exists {
                    button.tap()
                    return
                }
            }
        }
    }

    // MARK: - Waiting

    /// Wait for app to become idle
    static func waitForAppToBeIdle(
        _ app: XCUIApplication,
        timeout: TimeInterval = 5
    ) {
        // Wait for any loading indicators to disappear
        let loadingIndicator = app.activityIndicators.element(boundBy: 0)
        if loadingIndicator.exists {
            _ = loadingIndicator.waitForNonExistence(timeout: timeout)
        }
    }
}

// MARK: - XCUIElement Extension

extension XCUIElement {

    /// Wait for element to not exist
    func waitForNonExistence(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        return result == .completed
    }

    /// Wait for element to become hittable
    func waitUntilHittable(timeout: TimeInterval = UITestConfig.defaultTimeout) -> Bool {
        let predicate = NSPredicate(format: "isHittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        return result == .completed
    }

    /// Wait for element to contain specific text
    func waitForText(
        _ text: String,
        timeout: TimeInterval = UITestConfig.defaultTimeout
    ) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS[c] %@", text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        return result == .completed
    }
}
