import XCTest

/// Share flow UI tests
final class ShareFlowUITests: XCTestCase {

    var app: XCUIApplication!
    var fileBrowserPage: FileBrowserPage!

    // MARK: - Setup

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = UITestUtils.launchApp(resetState: true)

        // Login first
        let loginPage = LoginPage(app: app)
        loginPage.login(
            email: UITestConfig.testUserEmail,
            password: UITestConfig.testUserPassword
        )

        fileBrowserPage = FileBrowserPage(app: app)
        XCTAssertTrue(fileBrowserPage.isDisplayed())
    }

    override func tearDownWithError() throws {
        UITestUtils.takeScreenshot(name: "teardown_\(name)")
        app.terminate()
    }

    // MARK: - Test: Share File Flow

    func testShareFileFlow() throws {
        // Wait for files to load
        fileBrowserPage.waitForPageToLoad()

        // Check if there are files to share
        guard fileBrowserPage.itemCount > 0 else {
            XCTSkip("No files available to share")
            return
        }

        // Long press first item to show context menu
        let firstCell = fileBrowserPage.collectionView.cells.element(boundBy: 0)
        firstCell.press(forDuration: 1.0)

        // Wait for context menu
        let shareOption = app.buttons["Share"]
        guard shareOption.waitForExistence(timeout: UITestConfig.shortTimeout) else {
            // Context menu might not be available, try swipe
            firstCell.swipeLeft()

            let swipeShareButton = app.buttons["Share"]
            guard swipeShareButton.waitForExistence(timeout: UITestConfig.shortTimeout) else {
                XCTFail("Share option not available")
                return
            }
            swipeShareButton.tap()
            return
        }

        shareOption.tap()

        // Verify share screen appears
        let sharePage = ShareFilePage(app: app)
        XCTAssertTrue(sharePage.isDisplayed(), "Share screen should appear")

        UITestUtils.takeScreenshot(name: "share_screen")

        // Enter recipient
        sharePage.enterRecipient("recipient@test.local")
        sharePage.dismissKeyboard()

        // Check share button state
        if sharePage.isShareButtonEnabled {
            // Don't actually share in test - just verify UI
            UITestUtils.takeScreenshot(name: "share_ready")
        }

        // Cancel sharing
        sharePage.tapCancelButton()

        // Verify back on file browser
        XCTAssertTrue(fileBrowserPage.isDisplayed())
    }

    // MARK: - Test: Accept Invitation Deep Link

    func testAcceptInvitationDeepLink() throws {
        // This test simulates opening a share invitation deep link
        // Terminate and relaunch with deep link

        app.terminate()

        app = XCUIApplication()
        app.launchArguments = UITestConfig.launchArguments + [
            "-ShareInvitationURL", "ssdid-drive://share/accept?token=test-share-token"
        ]
        app.launchEnvironment = UITestConfig.launchEnvironment
        app.launch()

        // Wait for the app to handle deep link
        Thread.sleep(forTimeInterval: 2)

        // Check what screen we're on
        let acceptButton = app.buttons["Accept"]
        let loginPage = LoginPage(app: app)
        let fileBrowser = FileBrowserPage(app: app)

        if acceptButton.waitForExistence(timeout: UITestConfig.defaultTimeout) {
            // Share acceptance screen
            UITestUtils.takeScreenshot(name: "share_acceptance")

            acceptButton.tap()

            // Should navigate to shared file or require login
            waitForLoadingToComplete(app)

        } else if loginPage.isDisplayed() {
            // Need to login first
            loginPage.login(
                email: UITestConfig.testUserEmail,
                password: UITestConfig.testUserPassword
            )

            // After login, should process the deep link
            waitForLoadingToComplete(app)

            // Check if share acceptance appears or we're in file browser
            let postLoginAccept = app.buttons["Accept"]
            if postLoginAccept.waitForExistence(timeout: UITestConfig.shortTimeout) {
                postLoginAccept.tap()
            }

        } else if fileBrowser.isDisplayed() {
            // Already logged in, deep link processed
            UITestUtils.takeScreenshot(name: "deep_link_processed")
        }

        // Final state check
        UITestUtils.takeScreenshot(name: "after_deep_link")
    }

    // MARK: - Test: Received Shares View

    func testReceivedSharesView() throws {
        // Navigate to Shares tab
        let sharesTab = app.tabBars.buttons["Shares"]

        guard sharesTab.waitForExistence(timeout: UITestConfig.shortTimeout) else {
            // No shares tab - may be in different location
            // Try Settings -> Shares
            let settingsTab = app.tabBars.buttons["Settings"]
            if settingsTab.exists {
                settingsTab.tap()

                let sharesOption = app.cells.staticTexts["Shares"]
                if sharesOption.waitForExistence(timeout: UITestConfig.shortTimeout) {
                    sharesOption.tap()
                } else {
                    XCTSkip("Shares view not found in navigation")
                    return
                }
            } else {
                XCTSkip("Shares navigation not available")
                return
            }
            return
        }

        sharesTab.tap()

        // Wait for shares to load
        waitForLoadingToComplete(app)

        // Check for segmented control or tabs for Received/Created
        let receivedSegment = app.buttons["Received"]
        let sharedWithMe = app.staticTexts["Shared with me"]

        if receivedSegment.exists {
            receivedSegment.tap()
        } else if sharedWithMe.exists {
            // Already showing received shares
        }

        UITestUtils.takeScreenshot(name: "received_shares")

        // Check content
        let sharesTable = app.tables.element(boundBy: 0)
        let sharesCollection = app.collectionViews.element(boundBy: 0)

        if sharesTable.exists && sharesTable.cells.count > 0 {
            // Has received shares
            let firstShare = sharesTable.cells.element(boundBy: 0)
            firstShare.tap()

            // Should open the shared file/folder
            waitForLoadingToComplete(app)
            UITestUtils.takeScreenshot(name: "shared_file_opened")

        } else if sharesCollection.exists && sharesCollection.cells.count > 0 {
            // Collection view layout
            let firstShare = sharesCollection.cells.element(boundBy: 0)
            firstShare.tap()

            waitForLoadingToComplete(app)
            UITestUtils.takeScreenshot(name: "shared_file_opened")

        } else {
            // No received shares - check for empty state
            let emptyState = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] 'no shares' OR label CONTAINS[c] 'nothing shared'")
            ).element(boundBy: 0)

            if emptyState.exists {
                UITestUtils.takeScreenshot(name: "no_received_shares")
            }
        }
    }

    // MARK: - Test: Share Permissions

    func testSharePermissionOptions() throws {
        // This test verifies permission options are available when sharing
        fileBrowserPage.waitForPageToLoad()

        guard fileBrowserPage.itemCount > 0 else {
            XCTSkip("No files available to test share permissions")
            return
        }

        // Open share dialog
        let firstCell = fileBrowserPage.collectionView.cells.element(boundBy: 0)
        firstCell.press(forDuration: 1.0)

        let shareOption = app.buttons["Share"]
        guard shareOption.waitForExistence(timeout: UITestConfig.shortTimeout) else {
            XCTSkip("Share option not available via context menu")
            return
        }

        shareOption.tap()

        let sharePage = ShareFilePage(app: app)
        XCTAssertTrue(sharePage.isDisplayed())

        // Look for permission selector
        let permissionButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'permission' OR label CONTAINS[c] 'view' OR label CONTAINS[c] 'edit'")
        ).element(boundBy: 0)

        if permissionButton.waitForExistence(timeout: UITestConfig.shortTimeout) {
            permissionButton.tap()

            // Check for permission options
            let viewOption = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] 'view'")
            ).element(boundBy: 0)
            let editOption = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] 'edit'")
            ).element(boundBy: 0)

            let hasPermissionOptions = viewOption.exists || editOption.exists
            XCTAssertTrue(hasPermissionOptions, "Permission options should be available")

            UITestUtils.takeScreenshot(name: "permission_options")

            // Cancel/dismiss
            let cancelButton = app.buttons["Cancel"]
            if cancelButton.exists {
                cancelButton.tap()
            } else {
                app.tap() // Tap outside to dismiss
            }
        }

        // Cancel share
        sharePage.tapCancelButton()
    }
}
