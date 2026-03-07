import XCTest

/// Base page object with common functionality
class BasePage {

    // MARK: - Properties

    let app: XCUIApplication

    // MARK: - Initialization

    init(app: XCUIApplication) {
        self.app = app
    }

    // MARK: - Common Elements

    /// Navigation back button
    var backButton: XCUIElement {
        app.navigationBars.buttons.element(boundBy: 0)
    }

    /// Navigation bar title
    var navigationTitle: XCUIElement {
        app.navigationBars.staticTexts.element(boundBy: 0)
    }

    /// Tab bar
    var tabBar: XCUIElement {
        app.tabBars.element(boundBy: 0)
    }

    /// Loading indicator
    var loadingIndicator: XCUIElement {
        app.activityIndicators.element(boundBy: 0)
    }

    // MARK: - Common Actions

    /// Navigate back
    func navigateBack() {
        if backButton.exists && backButton.isHittable {
            backButton.tap()
        }
    }

    /// Wait for page to load
    func waitForPageToLoad(timeout: TimeInterval = UITestConfig.defaultTimeout) {
        // Wait for loading indicator to disappear
        if loadingIndicator.exists {
            _ = loadingIndicator.waitForNonExistence(timeout: timeout)
        }
    }

    /// Check if page is displayed
    func isDisplayed() -> Bool {
        // Override in subclasses
        return true
    }

    /// Dismiss keyboard if visible
    func dismissKeyboard() {
        UITestUtils.dismissKeyboard(app)
    }

    /// Take screenshot of current page
    func takeScreenshot(name: String) {
        UITestUtils.takeScreenshot(name: name)
    }

    // MARK: - Alert Handling

    /// Check if an alert is displayed
    var isAlertDisplayed: Bool {
        app.alerts.element(boundBy: 0).exists
    }

    /// Get alert message
    var alertMessage: String? {
        guard isAlertDisplayed else { return nil }
        return app.alerts.element(boundBy: 0).staticTexts.element(boundBy: 1).label
    }

    /// Tap alert button
    func tapAlertButton(_ label: String) {
        guard isAlertDisplayed else { return }
        let button = app.alerts.element(boundBy: 0).buttons[label]
        if button.exists {
            button.tap()
        }
    }

    /// Dismiss alert
    func dismissAlert() {
        UITestUtils.dismissAlert(app)
    }
}
