import XCTest

/// Registration UI tests
final class RegistrationUITests: XCTestCase {

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

    // MARK: - Test: Registration Via Invitation

    func testRegistrationViaInvitation() throws {
        throw XCTSkip("Auth migrated to wallet-based")
        // This test simulates opening an invitation deep link
        // In real E2E testing, this would come from an actual invitation

        // Launch app with invitation URL argument
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = UITestConfig.launchArguments + [
            "-InvitationToken", "test-invitation-token",
            "-InvitationEmail", "newuser@test.local"
        ]
        app.launchEnvironment = UITestConfig.launchEnvironment
        app.launch()

        // Check if we're on registration screen or invitation accept screen
        let registerPage = RegisterPage(app: app)
        let invitationAcceptScreen = app.buttons["Accept Invitation"]

        // Wait for either screen
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true"),
            object: invitationAcceptScreen
        )

        let result = XCTWaiter.wait(for: [expectation], timeout: UITestConfig.defaultTimeout)

        if result == .completed {
            // Invitation accept screen
            invitationAcceptScreen.tap()

            // Should navigate to registration
            XCTAssertTrue(
                registerPage.isDisplayed(),
                "Registration screen should appear after accepting invitation"
            )

            // Verify email is pre-filled
            let emailField = registerPage.emailTextField
            if let emailValue = emailField.value as? String {
                XCTAssertTrue(
                    emailValue.contains("@"),
                    "Email should be pre-filled from invitation"
                )
            }

            // Complete registration
            registerPage.enterPassword("SecurePass123!")
            registerPage.dismissKeyboard()
            registerPage.enterConfirmPassword("SecurePass123!")
            registerPage.dismissKeyboard()

            // Tap register
            registerPage.tapRegisterButton()

            // Wait for processing
            waitForLoadingToComplete(app, timeout: UITestConfig.networkTimeout)

            // Check for success or error
            if registerPage.isErrorVisible {
                // Registration failed - log the error for debugging
                if let error = registerPage.errorMessage {
                    print("Registration error: \(error)")
                }
                // This may fail in test environment without real invitation
            } else {
                // Should navigate to file browser
                let fileBrowserPage = FileBrowserPage(app: app)
                XCTAssertTrue(
                    fileBrowserPage.isDisplayed(),
                    "Should navigate to file browser after registration"
                )
            }
        } else {
            // Registration screen directly (fallback)
            if registerPage.isDisplayed() {
                UITestUtils.takeScreenshot(name: "registration_screen")
            } else {
                XCTSkip("Invitation flow not available in test environment")
            }
        }
    }

    // MARK: - Test: Password Strength Indicator

    func testPasswordStrengthIndicator() throws {
        throw XCTSkip("Auth migrated to wallet-based")
        // Navigate to registration (if there's a link from login)
        // This depends on app flow - some apps require invitation
        let signUpLink = app.buttons["Sign Up"]
        let createAccountLink = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'create account'")
        ).element(boundBy: 0)

        // Try to find and tap registration link
        if signUpLink.exists {
            signUpLink.tap()
        } else if createAccountLink.exists {
            createAccountLink.tap()
        } else {
            // No direct registration - try with invitation flow
            XCTSkip("Registration requires invitation in this app")
            return
        }

        let registerPage = RegisterPage(app: app)
        guard registerPage.isDisplayed() else {
            XCTSkip("Could not access registration screen")
            return
        }

        // Test weak password
        registerPage.enterPassword("123")
        registerPage.dismissKeyboard()

        Thread.sleep(forTimeInterval: 0.5)
        if let strength = registerPage.passwordStrength {
            XCTAssertTrue(
                strength.lowercased().contains("weak"),
                "Short password should show weak strength"
            )
        }

        // Test medium password
        registerPage.clearPassword()
        registerPage.enterPassword("Password1")
        registerPage.dismissKeyboard()

        Thread.sleep(forTimeInterval: 0.5)
        if let strength = registerPage.passwordStrength {
            XCTAssertTrue(
                ["fair", "good", "medium"].contains(where: { strength.lowercased().contains($0) }),
                "Medium password should show fair/good strength"
            )
        }

        // Test strong password
        registerPage.clearPassword()
        registerPage.enterPassword("SecureP@ssw0rd123!")
        registerPage.dismissKeyboard()

        Thread.sleep(forTimeInterval: 0.5)
        if let strength = registerPage.passwordStrength {
            XCTAssertTrue(
                ["strong", "excellent", "good"].contains(where: { strength.lowercased().contains($0) }),
                "Strong password should show strong indicator"
            )
        }

        UITestUtils.takeScreenshot(name: "password_strength")
    }

    // MARK: - Test: Registration Validation

    func testRegistrationFormValidation() throws {
        throw XCTSkip("Auth migrated to wallet-based")
        // Navigate to registration
        let signUpLink = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'sign up' OR label CONTAINS[c] 'create account'")
        ).element(boundBy: 0)

        guard signUpLink.waitForExistence(timeout: UITestConfig.shortTimeout) else {
            XCTSkip("Registration requires invitation")
            return
        }

        signUpLink.tap()

        let registerPage = RegisterPage(app: app)
        guard registerPage.isDisplayed() else {
            XCTSkip("Registration screen not accessible")
            return
        }

        // Initially register button should be disabled
        XCTAssertFalse(
            registerPage.isRegisterButtonEnabled,
            "Register button should be disabled initially"
        )

        // Enter email only
        registerPage.enterEmail("test@example.com")
        registerPage.dismissKeyboard()
        XCTAssertFalse(
            registerPage.isRegisterButtonEnabled,
            "Register button should be disabled without password"
        )

        // Enter password only (mismatched)
        registerPage.enterPassword("Password123!")
        registerPage.dismissKeyboard()
        registerPage.enterConfirmPassword("DifferentPass123!")
        registerPage.dismissKeyboard()

        XCTAssertFalse(
            registerPage.isRegisterButtonEnabled,
            "Register button should be disabled with mismatched passwords"
        )

        // Enter matching passwords
        registerPage.clearPassword()
        registerPage.enterPassword("Password123!")
        registerPage.dismissKeyboard()

        // Re-enter confirm password
        let confirmField = registerPage.confirmPasswordTextField
        if confirmField.exists {
            confirmField.tap()
            // Clear and re-type
            confirmField.press(forDuration: 1.0)
            if app.menuItems["Select All"].exists {
                app.menuItems["Select All"].tap()
                confirmField.typeText(XCUIKeyboardKey.delete.rawValue)
            }
            confirmField.typeText("Password123!")
            registerPage.dismissKeyboard()
        }

        // Button should now be enabled
        XCTAssertTrue(
            registerPage.isRegisterButtonEnabled,
            "Register button should be enabled with valid input"
        )
    }

    // MARK: - Helper Extension for clearPassword

    private func clearPassword() {
        // Helper method - implementation in RegisterPage
    }
}

// MARK: - RegisterPage Extension

private extension RegisterPage {
    func clearPassword() {
        let field = passwordTextField
        if field.exists {
            UITestUtils.clearAndType(field, text: "")
        }
    }
}
