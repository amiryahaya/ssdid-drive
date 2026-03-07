import XCTest

/// Page object for the login screen
final class LoginPage: BasePage {

    // MARK: - Accessibility Identifiers

    enum Identifiers {
        static let emailTextField = "loginEmailTextField"
        static let passwordTextField = "loginPasswordTextField"
        static let loginButton = "loginButton"
        static let showPasswordButton = "showPasswordButton"
        static let errorLabel = "loginErrorLabel"
        static let logoImageView = "loginLogoImageView"
        static let titleLabel = "loginTitleLabel"
    }

    // MARK: - Elements

    var emailTextField: XCUIElement {
        app.textFields[Identifiers.emailTextField]
    }

    var passwordTextField: XCUIElement {
        app.secureTextFields[Identifiers.passwordTextField]
    }

    var visiblePasswordTextField: XCUIElement {
        app.textFields[Identifiers.passwordTextField]
    }

    var loginButton: XCUIElement {
        app.buttons[Identifiers.loginButton]
    }

    var showPasswordButton: XCUIElement {
        app.buttons[Identifiers.showPasswordButton]
    }

    var errorLabel: XCUIElement {
        app.staticTexts[Identifiers.errorLabel]
    }

    var logoImageView: XCUIElement {
        app.images[Identifiers.logoImageView]
    }

    var titleLabel: XCUIElement {
        app.staticTexts[Identifiers.titleLabel]
    }

    // MARK: - Page Status

    override func isDisplayed() -> Bool {
        loginButton.waitForExistence(timeout: UITestConfig.shortTimeout)
    }

    // MARK: - Actions

    /// Enter email in the email field
    func enterEmail(_ email: String) {
        emailTextField.tap()
        emailTextField.typeText(email)
    }

    /// Enter password in the password field
    func enterPassword(_ password: String) {
        let field = passwordTextField.exists ? passwordTextField : visiblePasswordTextField
        field.tap()
        field.typeText(password)
    }

    /// Clear email field
    func clearEmail() {
        if emailTextField.exists {
            UITestUtils.clearAndType(emailTextField, text: "")
        }
    }

    /// Clear password field
    func clearPassword() {
        let field = passwordTextField.exists ? passwordTextField : visiblePasswordTextField
        if field.exists {
            UITestUtils.clearAndType(field, text: "")
        }
    }

    /// Toggle password visibility
    func togglePasswordVisibility() {
        showPasswordButton.tap()
    }

    /// Tap the login button
    func tapLoginButton() {
        loginButton.tap()
    }

    /// Perform full login flow
    @discardableResult
    func login(email: String, password: String) -> FileBrowserPage {
        enterEmail(email)
        dismissKeyboard()
        enterPassword(password)
        dismissKeyboard()
        tapLoginButton()

        let fileBrowserPage = FileBrowserPage(app: app)
        _ = fileBrowserPage.isDisplayed()
        return fileBrowserPage
    }

    /// Attempt login (may fail)
    func attemptLogin(email: String, password: String) {
        enterEmail(email)
        dismissKeyboard()
        enterPassword(password)
        dismissKeyboard()
        tapLoginButton()
    }

    // MARK: - Assertions

    /// Check if login button is enabled
    var isLoginButtonEnabled: Bool {
        loginButton.isEnabled
    }

    /// Check if error message is visible
    var isErrorVisible: Bool {
        errorLabel.exists && !errorLabel.label.isEmpty
    }

    /// Get error message text
    var errorMessage: String? {
        guard isErrorVisible else { return nil }
        return errorLabel.label
    }

    /// Check if password is visible (not secure)
    var isPasswordVisible: Bool {
        visiblePasswordTextField.exists
    }
}
