import XCTest

/// Page object for the settings screen
final class SettingsPage: BasePage {

    // MARK: - Accessibility Identifiers

    enum Identifiers {
        static let tableView = "settingsTableView"
        static let profileCell = "settingsProfileCell"
        static let devicesCell = "settingsDevicesCell"
        static let invitationsCell = "settingsInvitationsCell"
        static let tenantCell = "settingsTenantCell"
        static let biometricSwitch = "settingsBiometricSwitch"
        static let autoLockSwitch = "settingsAutoLockSwitch"
        static let logoutButton = "settingsLogoutButton"
        static let versionLabel = "settingsVersionLabel"
    }

    // MARK: - Elements

    var tableView: XCUIElement {
        app.tables[Identifiers.tableView]
    }

    var profileCell: XCUIElement {
        app.cells[Identifiers.profileCell]
    }

    var devicesCell: XCUIElement {
        app.cells[Identifiers.devicesCell]
    }

    var invitationsCell: XCUIElement {
        app.cells[Identifiers.invitationsCell]
    }

    var tenantCell: XCUIElement {
        app.cells[Identifiers.tenantCell]
    }

    var biometricSwitch: XCUIElement {
        app.switches[Identifiers.biometricSwitch]
    }

    var autoLockSwitch: XCUIElement {
        app.switches[Identifiers.autoLockSwitch]
    }

    var logoutButton: XCUIElement {
        // Logout is in a cell, not a button
        app.cells.staticTexts["Log Out"]
    }

    var versionLabel: XCUIElement {
        app.staticTexts[Identifiers.versionLabel]
    }

    // MARK: - Page Status

    override func isDisplayed() -> Bool {
        tableView.waitForExistence(timeout: UITestConfig.defaultTimeout)
    }

    // MARK: - Navigation

    /// Open Devices screen
    func openDevices() {
        devicesCell.tap()
    }

    /// Open Invitations screen
    func openInvitations() {
        invitationsCell.tap()
    }

    /// Open Tenant Switcher
    func openTenantSwitcher() {
        tenantCell.tap()
    }

    // MARK: - Security Settings

    /// Toggle biometric authentication
    func toggleBiometric() {
        biometricSwitch.tap()
    }

    /// Toggle auto-lock
    func toggleAutoLock() {
        autoLockSwitch.tap()
    }

    /// Check if biometric is enabled
    var isBiometricEnabled: Bool {
        biometricSwitch.value as? String == "1"
    }

    /// Check if auto-lock is enabled
    var isAutoLockEnabled: Bool {
        autoLockSwitch.value as? String == "1"
    }

    /// Set auto-lock timeout
    func setAutoLockTimeout(_ minutes: Int) {
        let timeoutCell = app.cells.staticTexts["Lock After"]
        if timeoutCell.exists {
            timeoutCell.tap()

            let option = app.buttons["\(minutes) minute\(minutes == 1 ? "" : "s")"]
            if option.waitForExistence(timeout: UITestConfig.shortTimeout) {
                option.tap()
            }
        }
    }

    // MARK: - Account Actions

    /// Tap logout button
    func tapLogout() {
        // Scroll to bottom if needed
        if !logoutButton.isHittable {
            tableView.swipeUp()
        }
        logoutButton.tap()
    }

    /// Confirm logout
    func confirmLogout() {
        tapLogout()

        // Wait for confirmation alert
        let alert = app.alerts.element(boundBy: 0)
        _ = alert.waitForExistence(timeout: UITestConfig.shortTimeout)

        // Tap Log Out button
        let confirmButton = alert.buttons["Log Out"]
        confirmButton.tap()
    }

    /// Cancel logout
    func cancelLogout() {
        tapLogout()

        let alert = app.alerts.element(boundBy: 0)
        _ = alert.waitForExistence(timeout: UITestConfig.shortTimeout)

        alert.buttons["Cancel"].tap()
    }

    // MARK: - Profile Information

    /// Get user email from profile
    var userEmail: String? {
        let emailLabel = profileCell.staticTexts.element(boundBy: 1)
        return emailLabel.exists ? emailLabel.label : nil
    }

    /// Get current tenant name
    var currentTenantName: String? {
        let tenantLabel = tenantCell.staticTexts.element(boundBy: 0)
        return tenantLabel.exists ? tenantLabel.label : nil
    }

    /// Get app version
    var appVersion: String? {
        let versionCell = app.cells.containing(.staticText, identifier: "Version").element
        if versionCell.exists {
            let versionText = versionCell.staticTexts.element(boundBy: 1)
            return versionText.exists ? versionText.label : nil
        }
        return nil
    }

    // MARK: - Scrolling

    /// Scroll to bottom of settings
    func scrollToBottom() {
        tableView.swipeUp()
    }

    /// Scroll to top of settings
    func scrollToTop() {
        tableView.swipeDown()
    }
}
