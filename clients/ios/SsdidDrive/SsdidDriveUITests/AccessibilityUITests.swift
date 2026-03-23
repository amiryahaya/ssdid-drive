import XCTest

final class AccessibilityUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        app.launch()
    }

    func testLoginScreenAccessibilityLabels() {
        // All interactive elements should have accessibility labels
        let buttons = app.buttons.allElementsBoundByAccessibilityElement
        for button in buttons {
            XCTAssertFalse(button.label.isEmpty, "Button without accessibility label found")
        }
    }

    func testLoginScreenVoiceOverOrder() {
        // Logo should come before title
        let logo = app.images["loginLogoImageView"]
        let title = app.staticTexts["loginTitleLabel"]
        if logo.exists && title.exists {
            XCTAssertTrue(logo.frame.midY < title.frame.midY, "Logo should be above title")
        }
    }
}
