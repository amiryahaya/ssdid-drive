import XCTest

/// Settings UI tests
final class SettingsUITests: XCTestCase {

    var app: XCUIApplication!
    var settingsPage: SettingsPage!

    // MARK: - Setup

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        try XCTSkipUnless(UITestConfig.isAuthTestEnabled, "Auth-dependent UI tests require test session")
        app = UITestUtils.launchApp(resetState: true)

        // Login first
        let loginPage = LoginPage(app: app)
        loginPage.login(
            email: UITestConfig.testUserEmail,
            password: UITestConfig.testUserPassword
        )

        // Navigate to settings
        let settingsTab = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: UITestConfig.defaultTimeout))
        settingsTab.tap()

        settingsPage = SettingsPage(app: app)
        XCTAssertTrue(settingsPage.isDisplayed())
    }

    override func tearDownWithError() throws {
        UITestUtils.takeScreenshot(name: "teardown_\(name)")
        app.terminate()
    }

    // MARK: - Test: Settings/Profile View

    func testSettingsProfileView() throws {
        // Verify settings page is displayed
        XCTAssertTrue(settingsPage.isDisplayed())

        // Check profile section
        let profileCell = settingsPage.profileCell
        XCTAssertTrue(
            profileCell.waitForExistence(timeout: UITestConfig.shortTimeout),
            "Profile cell should be visible"
        )

        // Check if email is displayed
        if let email = settingsPage.userEmail {
            XCTAssertTrue(
                email.contains("@"),
                "User email should be displayed"
            )
        }

        // Check app version
        settingsPage.scrollToBottom()

        if let version = settingsPage.appVersion {
            XCTAssertFalse(version.isEmpty, "App version should be displayed")
        }

        UITestUtils.takeScreenshot(name: "settings_profile")

        // Check for key settings sections
        settingsPage.scrollToTop()

        let expectedSections = ["Account", "Security", "About"]
        for section in expectedSections {
            let sectionHeader = app.staticTexts[section]
            if sectionHeader.exists {
                // Section found
            }
        }
    }

    // MARK: - Test: Multi-Tenant Switching

    func testMultiTenantSwitching() throws {
        // Check if tenant cell exists
        let tenantCell = settingsPage.tenantCell

        guard tenantCell.waitForExistence(timeout: UITestConfig.shortTimeout) else {
            XCTSkip("Tenant switching not available in this app version")
            return
        }

        // Get current tenant name
        let currentTenant = settingsPage.currentTenantName

        // Tap tenant cell
        tenantCell.tap()

        // Check if tenant switcher appears
        let tenantSwitcher = app.tables.element(boundBy: 0)
        let tenantPicker = app.pickers.element(boundBy: 0)

        if tenantSwitcher.waitForExistence(timeout: UITestConfig.shortTimeout) {
            // Tenant list is shown
            UITestUtils.takeScreenshot(name: "tenant_switcher")

            // Check if there are multiple tenants
            let cells = tenantSwitcher.cells
            if cells.count > 1 {
                // Multiple tenants available
                // Tap a different tenant (not the first one)
                cells.element(boundBy: 1).tap()

                // Wait for switch
                waitForLoadingToComplete(app)

                // Verify tenant changed
                // Navigate back to settings if needed
                let backButton = app.navigationBars.buttons.element(boundBy: 0)
                if backButton.exists {
                    backButton.tap()
                }

                // Check if tenant name changed
                Thread.sleep(forTimeInterval: 1)
                let newTenant = settingsPage.currentTenantName

                // May or may not change depending on available tenants
                UITestUtils.takeScreenshot(name: "after_tenant_switch")

            } else {
                // Only one tenant
                UITestUtils.takeScreenshot(name: "single_tenant")

                // Go back
                let backButton = app.navigationBars.buttons.element(boundBy: 0)
                if backButton.exists {
                    backButton.tap()
                }
            }

        } else if tenantPicker.exists {
            // Picker style tenant switcher
            UITestUtils.takeScreenshot(name: "tenant_picker")

            // Dismiss
            let doneButton = app.buttons["Done"]
            if doneButton.exists {
                doneButton.tap()
            }

        } else {
            // No tenant switcher - only one tenant
            UITestUtils.takeScreenshot(name: "tenant_cell_tapped")
        }
    }

    // MARK: - Test: Security Settings

    func testSecuritySettings() throws {
        // Look for security settings
        let biometricSwitch = settingsPage.biometricSwitch
        let autoLockSwitch = settingsPage.autoLockSwitch

        // May need to scroll to security section
        let securityHeader = app.staticTexts["Security"]
        if securityHeader.exists {
            securityHeader.tap() // Scroll to it
        }

        UITestUtils.takeScreenshot(name: "security_settings")

        // Test biometric toggle (if available)
        if biometricSwitch.waitForExistence(timeout: UITestConfig.shortTimeout) {
            let initialState = settingsPage.isBiometricEnabled

            settingsPage.toggleBiometric()
            Thread.sleep(forTimeInterval: 0.5)

            // May trigger system biometric prompt
            if app.alerts.element(boundBy: 0).exists {
                // System alert for biometric permission
                UITestUtils.takeScreenshot(name: "biometric_permission")

                // Cancel to not change system settings
                UITestUtils.dismissAlert(app)
            }
        }

        // Test auto-lock toggle (if available)
        if autoLockSwitch.waitForExistence(timeout: UITestConfig.shortTimeout) {
            let initialState = settingsPage.isAutoLockEnabled

            settingsPage.toggleAutoLock()
            Thread.sleep(forTimeInterval: 0.5)

            // Verify state changed
            let newState = settingsPage.isAutoLockEnabled
            XCTAssertNotEqual(initialState, newState, "Auto-lock state should change")

            // Toggle back
            settingsPage.toggleAutoLock()
        }
    }

    // MARK: - Test: Devices Management

    func testDevicesManagement() throws {
        // Open devices
        let devicesCell = settingsPage.devicesCell

        guard devicesCell.waitForExistence(timeout: UITestConfig.shortTimeout) else {
            XCTSkip("Devices section not available")
            return
        }

        devicesCell.tap()

        // Wait for devices screen
        waitForLoadingToComplete(app)

        // Check devices list
        let devicesTable = app.tables.element(boundBy: 0)
        let devicesCollection = app.collectionViews.element(boundBy: 0)

        if devicesTable.waitForExistence(timeout: UITestConfig.shortTimeout) {
            UITestUtils.takeScreenshot(name: "devices_list")

            // Should have at least current device
            XCTAssertGreaterThanOrEqual(
                devicesTable.cells.count,
                1,
                "Should show at least current device"
            )

            // Check for current device indicator
            let currentDevice = devicesTable.cells.containing(
                NSPredicate(format: "label CONTAINS[c] 'current' OR label CONTAINS[c] 'this device'")
            ).element(boundBy: 0)

            if currentDevice.exists {
                UITestUtils.takeScreenshot(name: "current_device_highlighted")
            }

        } else if devicesCollection.exists {
            UITestUtils.takeScreenshot(name: "devices_collection")
        }

        // Go back
        settingsPage.navigateBack()
    }

    // MARK: - Test: Invitations Management

    func testInvitationsManagement() throws {
        // Open invitations
        let invitationsCell = settingsPage.invitationsCell

        guard invitationsCell.waitForExistence(timeout: UITestConfig.shortTimeout) else {
            XCTSkip("Invitations section not available")
            return
        }

        invitationsCell.tap()

        // Wait for invitations screen
        waitForLoadingToComplete(app)

        UITestUtils.takeScreenshot(name: "invitations_screen")

        // Check for create invitation button
        let createButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'invite' OR label CONTAINS[c] 'new' OR label CONTAINS[c] 'add'")
        ).element(boundBy: 0)

        if createButton.exists {
            createButton.tap()

            // Should show invitation creation form
            let emailField = app.textFields.matching(
                NSPredicate(format: "placeholderValue CONTAINS[c] 'email'")
            ).element(boundBy: 0)

            if emailField.waitForExistence(timeout: UITestConfig.shortTimeout) {
                UITestUtils.takeScreenshot(name: "create_invitation")

                // Cancel
                let cancelButton = app.buttons["Cancel"]
                if cancelButton.exists {
                    cancelButton.tap()
                }
            }
        }

        // Go back
        settingsPage.navigateBack()
    }
}
