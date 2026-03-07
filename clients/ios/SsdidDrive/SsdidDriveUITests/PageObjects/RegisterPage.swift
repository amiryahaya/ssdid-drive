import XCTest

/// Page object for the registration screen
final class RegisterPage: BasePage {

    // MARK: - Accessibility Identifiers

    enum Identifiers {
        static let emailTextField = "registerEmailTextField"
        static let passwordTextField = "registerPasswordTextField"
        static let confirmPasswordTextField = "registerConfirmPasswordTextField"
        static let registerButton = "registerButton"
        static let loginButton = "registerLoginButton"
        static let errorLabel = "registerErrorLabel"
        static let passwordStrengthView = "passwordStrengthView"
    }

    // MARK: - Elements

    var emailTextField: XCUIElement {
        app.textFields[Identifiers.emailTextField]
    }

    var passwordTextField: XCUIElement {
        app.secureTextFields[Identifiers.passwordTextField]
    }

    var confirmPasswordTextField: XCUIElement {
        app.secureTextFields[Identifiers.confirmPasswordTextField]
    }

    var registerButton: XCUIElement {
        app.buttons[Identifiers.registerButton]
    }

    var loginButton: XCUIElement {
        app.buttons[Identifiers.loginButton]
    }

    var errorLabel: XCUIElement {
        app.staticTexts[Identifiers.errorLabel]
    }

    var passwordStrengthView: XCUIElement {
        app.otherElements[Identifiers.passwordStrengthView]
    }

    // MARK: - Page Status

    override func isDisplayed() -> Bool {
        registerButton.waitForExistence(timeout: UITestConfig.defaultTimeout)
    }

    // MARK: - Actions

    /// Enter email
    func enterEmail(_ email: String) {
        emailTextField.tap()
        emailTextField.typeText(email)
    }

    /// Enter password
    func enterPassword(_ password: String) {
        passwordTextField.tap()
        passwordTextField.typeText(password)
    }

    /// Enter confirm password
    func enterConfirmPassword(_ password: String) {
        confirmPasswordTextField.tap()
        confirmPasswordTextField.typeText(password)
    }

    /// Tap register button
    func tapRegisterButton() {
        registerButton.tap()
    }

    /// Tap login button to go back to login
    func tapLoginButton() {
        loginButton.tap()
    }

    /// Complete registration flow
    @discardableResult
    func register(email: String, password: String) -> FileBrowserPage {
        enterEmail(email)
        dismissKeyboard()
        enterPassword(password)
        dismissKeyboard()
        enterConfirmPassword(password)
        dismissKeyboard()
        tapRegisterButton()

        let fileBrowserPage = FileBrowserPage(app: app)
        _ = fileBrowserPage.isDisplayed()
        return fileBrowserPage
    }

    /// Attempt registration (may fail)
    func attemptRegister(email: String, password: String, confirmPassword: String) {
        enterEmail(email)
        dismissKeyboard()
        enterPassword(password)
        dismissKeyboard()
        enterConfirmPassword(confirmPassword)
        dismissKeyboard()
        tapRegisterButton()
    }

    // MARK: - State Checks

    /// Check if register button is enabled
    var isRegisterButtonEnabled: Bool {
        registerButton.isEnabled
    }

    /// Check if error is visible
    var isErrorVisible: Bool {
        errorLabel.exists && !errorLabel.label.isEmpty
    }

    /// Get error message
    var errorMessage: String? {
        guard isErrorVisible else { return nil }
        return errorLabel.label
    }

    /// Get password strength indicator text
    var passwordStrength: String? {
        let strengthLabel = passwordStrengthView.staticTexts.element(boundBy: 0)
        return strengthLabel.exists ? strengthLabel.label : nil
    }
}
