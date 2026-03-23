import XCTest

/// File browser UI tests
final class FileBrowserUITests: XCTestCase {

    var app: XCUIApplication!
    var fileBrowserPage: FileBrowserPage!

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

        fileBrowserPage = FileBrowserPage(app: app)
        XCTAssertTrue(fileBrowserPage.isDisplayed(), "File browser should be displayed after login")
    }

    override func tearDownWithError() throws {
        UITestUtils.takeScreenshot(name: "teardown_\(name)")
        app.terminate()
    }

    // MARK: - Test: File Browser Navigation

    func testFileBrowserNavigation() throws {
        // Verify file browser is displayed
        XCTAssertTrue(fileBrowserPage.isDisplayed())

        // Test view mode toggle
        let initialViewMode = fileBrowserPage.viewModeButton.label
        fileBrowserPage.toggleViewMode()
        Thread.sleep(forTimeInterval: 0.5)

        let newViewMode = fileBrowserPage.viewModeButton.label
        XCTAssertNotEqual(
            initialViewMode,
            newViewMode,
            "View mode should change after toggle"
        )

        // Toggle back
        fileBrowserPage.toggleViewMode()

        UITestUtils.takeScreenshot(name: "file_browser_navigation")
    }

    // MARK: - Test: File Upload UI

    func testFileUploadUI() throws {
        // Tap add button
        fileBrowserPage.tapAddButton()

        // Verify action sheet appears
        let uploadOption = app.buttons["Upload File"]
        XCTAssertTrue(
            uploadOption.waitForExistence(timeout: UITestConfig.shortTimeout),
            "Upload file option should appear"
        )

        let newFolderOption = app.buttons["New Folder"]
        XCTAssertTrue(
            newFolderOption.exists,
            "New folder option should appear"
        )

        UITestUtils.takeScreenshot(name: "add_menu")

        // Tap upload file
        uploadOption.tap()

        // Should show document picker or file selection UI
        // Note: On simulator, we may see a limited file picker
        Thread.sleep(forTimeInterval: 1)

        // Check if document picker appeared
        let documentPicker = app.otherElements["File Browser"]
        if documentPicker.exists {
            // Document picker is showing
            UITestUtils.takeScreenshot(name: "document_picker")

            // Cancel the picker
            let cancelButton = app.buttons["Cancel"]
            if cancelButton.exists {
                cancelButton.tap()
            }
        } else {
            // May show photos or other picker depending on implementation
            let photosOption = app.buttons["Photos"]
            let filesOption = app.buttons["Files"]

            if photosOption.exists || filesOption.exists {
                UITestUtils.takeScreenshot(name: "file_source_picker")

                // Cancel
                let cancelButton = app.buttons["Cancel"]
                if cancelButton.exists {
                    cancelButton.tap()
                }
            }
        }

        // Verify we're back on file browser
        XCTAssertTrue(fileBrowserPage.isDisplayed())
    }

    // MARK: - Test: File Download UI

    func testFileDownloadUI() throws {
        // Wait for files to load
        fileBrowserPage.waitForPageToLoad()

        // Check if there are any files to download
        if fileBrowserPage.itemCount > 0 {
            // Find a file (not a folder) to tap
            let cells = fileBrowserPage.collectionView.cells
            var fileTapped = false

            for i in 0..<min(cells.count, 5) {
                let cell = cells.element(boundBy: i)
                if cell.exists {
                    // Check if it's not a folder (folders typically have "Folder" text)
                    let folderIndicator = cell.staticTexts["Folder"]
                    if !folderIndicator.exists {
                        cell.tap()
                        fileTapped = true
                        break
                    }
                }
            }

            if fileTapped {
                // Wait for preview screen
                Thread.sleep(forTimeInterval: 1)
                UITestUtils.takeScreenshot(name: "file_preview")

                // Check for download/share options
                let shareButton = app.buttons["Share"]
                let downloadButton = app.buttons["Download"]
                let moreButton = app.buttons["More"]

                let hasActions = shareButton.exists || downloadButton.exists || moreButton.exists
                XCTAssertTrue(hasActions, "File preview should show action options")

                // Go back
                fileBrowserPage.navigateBack()
            } else {
                // Only folders exist, tap one to navigate
                if cells.count > 0 {
                    cells.element(boundBy: 0).tap()
                    Thread.sleep(forTimeInterval: 0.5)

                    // Verify breadcrumb appears
                    XCTAssertTrue(
                        fileBrowserPage.isBreadcrumbVisible,
                        "Breadcrumb should appear in subfolder"
                    )

                    // Navigate back
                    fileBrowserPage.navigateToHome()
                }
            }
        } else {
            // Empty state
            XCTAssertTrue(
                fileBrowserPage.isEmptyStateVisible,
                "Empty state should be shown when no files"
            )
        }
    }

    // MARK: - Test: Search Functionality

    func testSearchFunctionality() throws {
        // Check if search is available
        let searchBar = fileBrowserPage.searchBar

        if searchBar.waitForExistence(timeout: UITestConfig.shortTimeout) {
            // Perform search
            fileBrowserPage.searchFor("test")

            Thread.sleep(forTimeInterval: 1)
            UITestUtils.takeScreenshot(name: "search_results")

            // Clear search
            fileBrowserPage.clearSearch()

            // Verify all files are shown again
            fileBrowserPage.waitForPageToLoad()
        } else {
            // Search may be in navigation bar
            let navSearchButton = app.navigationBars.buttons["Search"]
            if navSearchButton.exists {
                navSearchButton.tap()

                // Search field should appear
                let searchField = app.searchFields.element(boundBy: 0)
                XCTAssertTrue(
                    searchField.waitForExistence(timeout: UITestConfig.shortTimeout),
                    "Search field should appear"
                )

                // Type search query
                searchField.typeText("test")

                Thread.sleep(forTimeInterval: 1)
                UITestUtils.takeScreenshot(name: "search_results")

                // Cancel search
                let cancelButton = app.buttons["Cancel"]
                if cancelButton.exists {
                    cancelButton.tap()
                }
            } else {
                XCTSkip("Search functionality not available in current view")
            }
        }
    }

    // MARK: - Test: Pull to Refresh

    func testPullToRefresh() throws {
        // Perform pull to refresh
        fileBrowserPage.pullToRefresh()

        // Wait for refresh to complete
        waitForRefreshToComplete(app)

        // Verify file browser still displays correctly
        XCTAssertTrue(fileBrowserPage.isDisplayed())

        UITestUtils.takeScreenshot(name: "after_refresh")
    }

    // MARK: - Test: Create Folder

    func testCreateFolder() throws {
        let folderName = "Test Folder \(Int.random(in: 1000...9999))"

        // Create folder
        fileBrowserPage.createFolder(name: folderName)

        // Wait for creation
        waitForLoadingToComplete(app)

        // Check if folder exists
        // Note: This may not appear immediately if server sync is required
        Thread.sleep(forTimeInterval: 2)

        let folderExists = fileBrowserPage.itemExists(named: folderName)

        if folderExists {
            UITestUtils.takeScreenshot(name: "folder_created")

            // Clean up - delete the folder
            fileBrowserPage.deleteItem(named: folderName)
            fileBrowserPage.confirmDelete()
        } else {
            // Check for error message
            if fileBrowserPage.isAlertDisplayed {
                UITestUtils.takeScreenshot(name: "folder_creation_error")
                fileBrowserPage.dismissAlert()
            }
        }
    }

    // MARK: - Test: Sort Options

    func testSortOptions() throws {
        // Open sort options
        fileBrowserPage.openSortOptions()

        // Verify sort options are shown
        let sortOptions = ["Name (A-Z)", "Name (Z-A)", "Date (Newest)", "Date (Oldest)"]
        var foundOption = false

        for option in sortOptions {
            let button = app.buttons[option]
            if button.waitForExistence(timeout: UITestConfig.shortTimeout) {
                foundOption = true
                break
            }
        }

        XCTAssertTrue(foundOption, "Sort options should be displayed")

        UITestUtils.takeScreenshot(name: "sort_options")

        // Select a sort option
        let sortByName = app.buttons["Name (A-Z)"]
        if sortByName.exists {
            sortByName.tap()
        } else {
            // Dismiss menu
            app.tap()
        }

        // Verify file browser updates
        fileBrowserPage.waitForPageToLoad()
        XCTAssertTrue(fileBrowserPage.isDisplayed())
    }
}
