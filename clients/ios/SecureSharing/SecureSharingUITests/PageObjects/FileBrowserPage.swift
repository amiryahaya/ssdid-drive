import XCTest

/// Page object for the file browser screen
final class FileBrowserPage: BasePage {

    // MARK: - Accessibility Identifiers

    enum Identifiers {
        static let collectionView = "fileBrowserCollection"
        static let addButton = "addFileButton"
        static let emptyStateView = "emptyStateView"
        static let breadcrumbView = "breadcrumbView"
        static let viewModeButton = "viewModeButton"
        static let sortButton = "sortButton"
        static let searchBar = "fileSearchBar"
        static let refreshControl = "fileBrowserRefreshControl"
    }

    // MARK: - Elements

    var collectionView: XCUIElement {
        app.collectionViews[Identifiers.collectionView]
    }

    var addButton: XCUIElement {
        app.buttons[Identifiers.addButton]
    }

    var emptyStateView: XCUIElement {
        app.otherElements[Identifiers.emptyStateView]
    }

    var breadcrumbView: XCUIElement {
        app.otherElements[Identifiers.breadcrumbView]
    }

    var viewModeButton: XCUIElement {
        app.buttons[Identifiers.viewModeButton]
    }

    var sortButton: XCUIElement {
        app.buttons[Identifiers.sortButton]
    }

    var searchBar: XCUIElement {
        app.searchFields[Identifiers.searchBar]
    }

    // MARK: - Page Status

    override func isDisplayed() -> Bool {
        collectionView.waitForExistence(timeout: UITestConfig.networkTimeout)
    }

    // MARK: - File/Folder Actions

    /// Tap the add button to show options
    func tapAddButton() {
        addButton.tap()
    }

    /// Select "Upload File" from add menu
    func selectUploadFile() {
        tapAddButton()
        let uploadButton = app.buttons["Upload File"]
        _ = uploadButton.waitForExistence(timeout: UITestConfig.shortTimeout)
        uploadButton.tap()
    }

    /// Select "New Folder" from add menu
    func selectNewFolder() {
        tapAddButton()
        let newFolderButton = app.buttons["New Folder"]
        _ = newFolderButton.waitForExistence(timeout: UITestConfig.shortTimeout)
        newFolderButton.tap()
    }

    /// Create a new folder
    func createFolder(name: String) {
        selectNewFolder()

        // Wait for alert
        let alert = app.alerts.element(boundBy: 0)
        _ = alert.waitForExistence(timeout: UITestConfig.shortTimeout)

        // Enter folder name
        let textField = alert.textFields.element(boundBy: 0)
        textField.tap()
        textField.typeText(name)

        // Tap Create
        alert.buttons["Create"].tap()
    }

    /// Tap on a file or folder by name
    func tapItem(named name: String) {
        let cell = collectionView.cells.containing(.staticText, identifier: name).element
        if cell.waitForExistence(timeout: UITestConfig.defaultTimeout) {
            cell.tap()
        }
    }

    /// Long press on a file or folder by name
    func longPressItem(named name: String) {
        let cell = collectionView.cells.containing(.staticText, identifier: name).element
        if cell.waitForExistence(timeout: UITestConfig.defaultTimeout) {
            cell.press(forDuration: 1.0)
        }
    }

    /// Get the number of items in the collection
    var itemCount: Int {
        collectionView.cells.count
    }

    /// Check if a file/folder exists
    func itemExists(named name: String) -> Bool {
        let cell = collectionView.cells.containing(.staticText, identifier: name).element
        return cell.waitForExistence(timeout: UITestConfig.shortTimeout)
    }

    // MARK: - Navigation

    /// Toggle between grid and list view
    func toggleViewMode() {
        viewModeButton.tap()
    }

    /// Open sort options
    func openSortOptions() {
        sortButton.tap()
    }

    /// Select a sort option
    func selectSortOption(_ option: String) {
        openSortOptions()
        let optionButton = app.buttons[option]
        _ = optionButton.waitForExistence(timeout: UITestConfig.shortTimeout)
        optionButton.tap()
    }

    /// Pull to refresh
    func pullToRefresh() {
        UITestUtils.pullToRefresh(collectionView)
    }

    /// Navigate to home via breadcrumb
    func navigateToHome() {
        let homeButton = breadcrumbView.buttons.element(boundBy: 0)
        if homeButton.exists {
            homeButton.tap()
        }
    }

    // MARK: - Search

    /// Search for a file
    func searchFor(_ query: String) {
        searchBar.tap()
        searchBar.typeText(query)
    }

    /// Clear search
    func clearSearch() {
        if searchBar.exists {
            let clearButton = searchBar.buttons["Clear text"]
            if clearButton.exists {
                clearButton.tap()
            }
        }
    }

    // MARK: - Context Menu

    /// Open context menu for item
    func openContextMenu(for itemName: String) {
        longPressItem(named: itemName)
    }

    /// Share item from context menu
    func shareItem(named name: String) {
        openContextMenu(for: name)
        let shareButton = app.buttons["Share"]
        _ = shareButton.waitForExistence(timeout: UITestConfig.shortTimeout)
        shareButton.tap()
    }

    /// Delete item from context menu
    func deleteItem(named name: String) {
        openContextMenu(for: name)
        let deleteButton = app.buttons["Delete"]
        _ = deleteButton.waitForExistence(timeout: UITestConfig.shortTimeout)
        deleteButton.tap()
    }

    /// Confirm deletion
    func confirmDelete() {
        let deleteButton = app.alerts.buttons["Delete"]
        _ = deleteButton.waitForExistence(timeout: UITestConfig.shortTimeout)
        deleteButton.tap()
    }

    // MARK: - State Checks

    /// Check if empty state is visible
    var isEmptyStateVisible: Bool {
        emptyStateView.exists
    }

    /// Check if breadcrumb is visible (in subfolder)
    var isBreadcrumbVisible: Bool {
        breadcrumbView.exists && breadcrumbView.isHittable
    }
}
