import XCTest

/// Page object for file sharing screens
final class ShareFilePage: BasePage {

    // MARK: - Accessibility Identifiers

    enum Identifiers {
        static let recipientTextField = "shareRecipientTextField"
        static let permissionPicker = "sharePermissionPicker"
        static let shareButton = "shareButton"
        static let cancelButton = "shareCancelButton"
        static let recipientList = "shareRecipientList"
        static let expirationDatePicker = "shareExpirationDatePicker"
    }

    // MARK: - Elements

    var recipientTextField: XCUIElement {
        app.textFields[Identifiers.recipientTextField]
    }

    var permissionPicker: XCUIElement {
        app.pickers[Identifiers.permissionPicker]
    }

    var shareButton: XCUIElement {
        app.buttons[Identifiers.shareButton]
    }

    var cancelButton: XCUIElement {
        app.buttons[Identifiers.cancelButton]
    }

    var recipientList: XCUIElement {
        app.tables[Identifiers.recipientList]
    }

    var expirationDatePicker: XCUIElement {
        app.datePickers[Identifiers.expirationDatePicker]
    }

    // MARK: - Page Status

    override func isDisplayed() -> Bool {
        shareButton.waitForExistence(timeout: UITestConfig.defaultTimeout)
    }

    // MARK: - Actions

    /// Enter recipient email
    func enterRecipient(_ email: String) {
        recipientTextField.tap()
        recipientTextField.typeText(email)
    }

    /// Select permission level
    func selectPermission(_ permission: SharePermission) {
        // Tap on permission selector
        let currentPermission = app.buttons.matching(NSPredicate(format: "label CONTAINS 'permission'")).element(boundBy: 0)
        if currentPermission.exists {
            currentPermission.tap()

            // Select from action sheet
            let option = app.buttons[permission.displayName]
            _ = option.waitForExistence(timeout: UITestConfig.shortTimeout)
            option.tap()
        }
    }

    /// Tap share button
    func tapShareButton() {
        shareButton.tap()
    }

    /// Tap cancel button
    func tapCancelButton() {
        cancelButton.tap()
    }

    /// Complete share flow
    func shareWith(email: String, permission: SharePermission = .viewer) {
        enterRecipient(email)
        dismissKeyboard()
        selectPermission(permission)
        tapShareButton()
    }

    /// Add multiple recipients
    func addRecipients(_ emails: [String]) {
        for email in emails {
            enterRecipient(email)
            // Assuming there's an add button or auto-complete
            dismissKeyboard()
        }
    }

    // MARK: - Recipient Management

    /// Check if recipient is in list
    func hasRecipient(_ email: String) -> Bool {
        let recipientCell = recipientList.cells.containing(.staticText, identifier: email).element
        return recipientCell.exists
    }

    /// Remove recipient from list
    func removeRecipient(_ email: String) {
        let recipientCell = recipientList.cells.containing(.staticText, identifier: email).element
        if recipientCell.exists {
            recipientCell.swipeLeft()
            let deleteButton = recipientCell.buttons["Delete"]
            if deleteButton.exists {
                deleteButton.tap()
            }
        }
    }

    // MARK: - State Checks

    /// Check if share button is enabled
    var isShareButtonEnabled: Bool {
        shareButton.isEnabled
    }

    /// Check if error is displayed
    var isErrorDisplayed: Bool {
        let errorLabel = app.staticTexts["shareErrorLabel"]
        return errorLabel.exists
    }
}

// MARK: - Share Permission Enum

enum SharePermission: String {
    case viewer
    case editor
    case owner

    var displayName: String {
        switch self {
        case .viewer: return "View Only"
        case .editor: return "Can Edit"
        case .owner: return "Full Access"
        }
    }
}
