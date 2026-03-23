import XCTest

/// Authentication UI tests
final class AuthUITests: XCTestCase {

    var app: XCUIApplication!
    var loginPage: LoginPage!

    // MARK: - Setup

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = UITestUtils.launchApp(resetState: true)
        loginPage = LoginPage(app: app)
    }

    override func tearDownWithError() throws {
        UITestUtils.takeScreenshot(name: "teardown_\(name)")
        app.terminate()
    }

    // MARK: - Test: Login/Logout Flow

    func testLoginAndLogoutFlow() throws {
        throw XCTSkip("Auth migrated to wallet-based")
        // Verify login screen is displayed
        XCTAssertTrue(loginPage.isDisplayed(), "Login screen should be displayed")

        // Perform login
        loginPage.login(
            email: UITestConfig.testUserEmail,
            password: UITestConfig.testUserPassword
        )

        // Verify file browser is displayed
        let fileBrowserPage = FileBrowserPage(app: app)
        XCTAssertTrue(fileBrowserPage.isDisplayed(), "File browser should be displayed after login")

        // Navigate to settings
        let settingsTab = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: UITestConfig.shortTimeout))
        settingsTab.tap()

        // Perform logout
        let settingsPage = SettingsPage(app: app)
        settingsPage.confirmLogout()

        // Verify we're back on login screen
        XCTAssertTrue(loginPage.isDisplayed(), "Login screen should be displayed after logout")
    }

    // MARK: - Test: Invalid Credentials Error

    func testInvalidCredentialsShowsError() throws {
        throw XCTSkip("Auth migrated to wallet-based")
        // Verify login screen is displayed
        XCTAssertTrue(loginPage.isDisplayed(), "Login screen should be displayed")

        // Attempt login with invalid credentials
        loginPage.attemptLogin(
            email: "invalid@example.com",
            password: "wrongpassword123"
        )

        // Wait for error to appear
        waitForLoadingToComplete(app)

        // Verify error message is shown
        // Either via error label or alert
        let hasError = loginPage.isErrorVisible || loginPage.isAlertDisplayed
        XCTAssertTrue(hasError, "Error should be displayed for invalid credentials")

        // Dismiss any alert
        if loginPage.isAlertDisplayed {
            loginPage.dismissAlert()
        }

        // Verify we're still on login screen
        XCTAssertTrue(loginPage.isDisplayed(), "Should remain on login screen after failed login")
    }

    // MARK: - Test: Biometric Authentication

    func testBiometricAuthenticationSetup() throws {
        throw XCTSkip("Auth migrated to wallet-based")
        // First, login normally
        loginPage.login(
            email: UITestConfig.testUserEmail,
            password: UITestConfig.testUserPassword
        )

        // Navigate to settings
        let settingsTab = app.tabBars.buttons["Settings"]
        settingsTab.tap()

        let settingsPage = SettingsPage(app: app)
        XCTAssertTrue(settingsPage.isDisplayed())

        // Find and check biometric toggle
        // Note: This test may be skipped on simulator as biometrics require hardware
        let biometricSwitch = settingsPage.biometricSwitch

        if biometricSwitch.exists {
            let initialState = settingsPage.isBiometricEnabled

            // Toggle biometric
            settingsPage.toggleBiometric()

            // Verify state changed (or system prompt appeared)
            // On real device, this would trigger Face ID/Touch ID enrollment
            Thread.sleep(forTimeInterval: 1)

            // Check if an alert appeared (for permissions)
            if app.alerts.element(boundBy: 0).exists {
                // Biometric prompt appeared - test passes
                app.alerts.buttons.element(boundBy: 0).tap()
            }

            UITestUtils.takeScreenshot(name: "biometric_toggle")
        } else {
            // Biometric not available on this device/simulator
            XCTSkip("Biometric authentication not available on this device")
        }
    }

    // MARK: - Test: Login Button Validation

    func testLoginButtonEnabledWithValidInput() throws {
        throw XCTSkip("Auth migrated to wallet-based")
        XCTAssertTrue(loginPage.isDisplayed())

        // Initially button should be disabled
        XCTAssertFalse(loginPage.isLoginButtonEnabled, "Login button should be disabled initially")

        // Enter valid email but no password
        loginPage.enterEmail("test@example.com")
        loginPage.dismissKeyboard()
        XCTAssertFalse(loginPage.isLoginButtonEnabled, "Login button should be disabled without password")

        // Enter short password
        loginPage.enterPassword("short")
        loginPage.dismissKeyboard()
        XCTAssertFalse(loginPage.isLoginButtonEnabled, "Login button should be disabled with short password")

        // Clear and enter valid password
        loginPage.clearPassword()
        loginPage.enterPassword("validpassword123")
        loginPage.dismissKeyboard()

        // Button should now be enabled
        XCTAssertTrue(loginPage.isLoginButtonEnabled, "Login button should be enabled with valid input")
    }

    // MARK: - Test: Password Visibility Toggle

    func testPasswordVisibilityToggle() throws {
        throw XCTSkip("Auth migrated to wallet-based")
        XCTAssertTrue(loginPage.isDisplayed())

        // Enter password
        loginPage.enterPassword("testpassword123")

        // Initially password should be hidden
        XCTAssertFalse(loginPage.isPasswordVisible, "Password should be hidden initially")

        // Toggle visibility
        loginPage.togglePasswordVisibility()

        // Password should now be visible
        XCTAssertTrue(loginPage.isPasswordVisible, "Password should be visible after toggle")

        // Toggle back
        loginPage.togglePasswordVisibility()

        // Password should be hidden again
        XCTAssertFalse(loginPage.isPasswordVisible, "Password should be hidden after second toggle")
    }
}
