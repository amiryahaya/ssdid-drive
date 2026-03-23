import XCTest

/// Page object for the login screen
final class LoginPage: BasePage {

    // MARK: - Accessibility Identifiers

    enum Identifiers {
        // Legacy identifiers (email/password auth — no longer in use)
        static let emailTextField_legacy = "loginEmailTextField"
        static let passwordTextField = "loginPasswordTextField"
        static let loginButton_legacy = "loginButton"
        static let showPasswordButton = "showPasswordButton"
        static let errorLabel = "loginErrorLabel"

        // Current wallet-based auth identifiers
        static let logoImageView = "loginLogoImageView"
        static let titleLabel = "loginTitleLabel"
        static let emailTextField = "emailTextField"
        static let emailContinueButton = "emailContinueButton"
        static let openWalletButton = "openWalletButton"
        static let googleSignInButton = "googleSignInButton"
        static let microsoftSignInButton = "microsoftSignInButton"
        static let inviteCodeCard = "inviteCodeCard"
        static let requestOrgButton = "requestOrgButton"
        static let refreshButton = "refreshButton"
    }

    // MARK: - Elements

    var emailTextField: XCUIElement {
        app.textFields[Identifiers.emailTextField]
    }

    /// Legacy password field — kept for backward compatibility (no longer exists in UI).
    var passwordTextField: XCUIElement {
        app.secureTextFields[Identifiers.passwordTextField]
    }

    /// Legacy visible password field — kept for backward compatibility.
    var visiblePasswordTextField: XCUIElement {
        app.textFields[Identifiers.passwordTextField]
    }

    var emailContinueButton: XCUIElement {
        app.buttons[Identifiers.emailContinueButton]
    }

    var openWalletButton: XCUIElement {
        app.buttons[Identifiers.openWalletButton]
    }

    var googleSignInButton: XCUIElement {
        app.buttons[Identifiers.googleSignInButton]
    }

    var microsoftSignInButton: XCUIElement {
        app.buttons[Identifiers.microsoftSignInButton]
    }

    var inviteCodeCard: XCUIElement {
        app.otherElements[Identifiers.inviteCodeCard]
    }

    var requestOrgButton: XCUIElement {
        app.buttons[Identifiers.requestOrgButton]
    }

    var refreshButton: XCUIElement {
        app.buttons[Identifiers.refreshButton]
    }

    /// Legacy login button — no longer present in wallet-based auth UI.
    var loginButton: XCUIElement {
        app.buttons[Identifiers.loginButton_legacy]
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

    /// Returns true when the login screen is displayed.
    ///
    /// Checks for the wallet button or the email continue button — both are
    /// present on the current wallet-based login screen.
    override func isDisplayed() -> Bool {
        openWalletButton.waitForExistence(timeout: UITestConfig.shortTimeout)
            || emailContinueButton.waitForExistence(timeout: UITestConfig.shortTimeout)
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
