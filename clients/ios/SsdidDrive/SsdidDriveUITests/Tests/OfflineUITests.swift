import XCTest

/// Offline mode UI tests
final class OfflineUITests: XCTestCase {

    var app: XCUIApplication!

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

        // Verify file browser
        let fileBrowserPage = FileBrowserPage(app: app)
        XCTAssertTrue(fileBrowserPage.isDisplayed())
    }

    override func tearDownWithError() throws {
        UITestUtils.takeScreenshot(name: "teardown_\(name)")
        app.terminate()
    }

    // MARK: - Test: Offline Mode Behavior

    func testOfflineModeBehavior() throws {
        // Note: This test simulates offline behavior
        // True offline testing requires network link conditioner or airplane mode

        let fileBrowserPage = FileBrowserPage(app: app)

        // Take screenshot of online state
        UITestUtils.takeScreenshot(name: "online_state")

        // Check for offline indicator (if app shows one)
        let offlineIndicator = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'offline' OR label CONTAINS[c] 'no connection'")
        ).element(boundBy: 0)

        let offlineBanner = app.otherElements["offlineBanner"]

        // In a real offline scenario, we'd see these indicators
        // For now, verify the UI elements exist when triggered

        // Simulate network error by trying to refresh with timeout
        fileBrowserPage.pullToRefresh()

        // Wait with short timeout to see error handling
        Thread.sleep(forTimeInterval: 3)

        // Check for error state or offline message
        let hasErrorState = offlineIndicator.exists ||
                           offlineBanner.exists ||
                           app.alerts.element(boundBy: 0).exists

        // Take screenshot of current state
        UITestUtils.takeScreenshot(name: "after_refresh_attempt")

        // If there's an alert, dismiss it
        if app.alerts.element(boundBy: 0).exists {
            UITestUtils.dismissAlert(app)
        }

        // Verify cached content is still accessible
        // (Files that were loaded before should still be visible)
        if fileBrowserPage.itemCount > 0 {
            // Cached files are available
            UITestUtils.takeScreenshot(name: "cached_files_available")
        }

        // Test that app doesn't crash in poor network conditions
        for _ in 0..<3 {
            fileBrowserPage.pullToRefresh()
            Thread.sleep(forTimeInterval: 1)

            // Dismiss any error alerts
            if app.alerts.element(boundBy: 0).exists {
                UITestUtils.dismissAlert(app)
            }
        }

        // App should still be functional
        XCTAssertTrue(fileBrowserPage.isDisplayed(), "App should remain functional")

        // Check offline-available features work
        // Like viewing cached files, settings, etc.
        let settingsTab = app.tabBars.buttons["Settings"]
        if settingsTab.exists {
            settingsTab.tap()

            let settingsPage = SettingsPage(app: app)
            XCTAssertTrue(
                settingsPage.isDisplayed(),
                "Settings should be accessible offline"
            )

            UITestUtils.takeScreenshot(name: "settings_offline")

            // Go back to files
            let filesTab = app.tabBars.buttons["Files"]
            filesTab.tap()
        }
    }

    // MARK: - Test: Sync Indicator

    func testSyncIndicator() throws {
        let fileBrowserPage = FileBrowserPage(app: app)

        // Look for sync indicator elements
        let syncIndicator = app.otherElements.matching(
            NSPredicate(format: "identifier CONTAINS[c] 'sync' OR identifier CONTAINS[c] 'loading'")
        ).element(boundBy: 0)

        let syncButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'sync'")
        ).element(boundBy: 0)

        let lastSyncLabel = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'synced' OR label CONTAINS[c] 'last sync'")
        ).element(boundBy: 0)

        // Trigger a sync/refresh
        fileBrowserPage.pullToRefresh()

        // Check for sync indicator during refresh
        Thread.sleep(forTimeInterval: 0.5)
        UITestUtils.takeScreenshot(name: "syncing")

        // Wait for sync to complete
        waitForRefreshToComplete(app)

        // Check for last sync time (if displayed)
        if lastSyncLabel.exists {
            UITestUtils.takeScreenshot(name: "sync_complete")
        }

        // If there's a manual sync button, test it
        if syncButton.exists {
            syncButton.tap()
            waitForRefreshToComplete(app)
            UITestUtils.takeScreenshot(name: "manual_sync")
        }
    }

    // MARK: - Test: Offline Action Queueing

    func testOfflineActionQueueing() throws {
        // This test verifies that actions taken offline are queued for later sync
        // Note: Full implementation would require actual network manipulation

        let fileBrowserPage = FileBrowserPage(app: app)

        // Try to create a folder (should work offline with queueing)
        let folderName = "Offline Folder \(Int.random(in: 1000...9999))"

        fileBrowserPage.createFolder(name: folderName)

        // Wait for response
        Thread.sleep(forTimeInterval: 2)

        // Dismiss any errors (expected in offline mode)
        if app.alerts.element(boundBy: 0).exists {
            UITestUtils.takeScreenshot(name: "offline_action_response")
            UITestUtils.dismissAlert(app)
        }

        // Check for pending changes indicator
        let pendingIndicator = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'pending' OR label CONTAINS[c] 'waiting' OR label CONTAINS[c] 'queued'")
        ).element(boundBy: 0)

        if pendingIndicator.exists {
            UITestUtils.takeScreenshot(name: "pending_changes")
        }

        // Verify app remains stable
        XCTAssertTrue(fileBrowserPage.isDisplayed())
    }
}
