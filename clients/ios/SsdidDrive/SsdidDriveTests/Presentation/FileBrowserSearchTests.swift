import XCTest
import Combine
@testable import SsdidDrive

/// Unit tests for FileBrowserViewModel search functionality
@MainActor
final class FileBrowserSearchTests: XCTestCase {

    // MARK: - Properties

    var viewModel: FileBrowserViewModel!
    var mockFileRepository: MockFileRepository!
    var cancellables: Set<AnyCancellable>!

    // MARK: - Test Data

    private let now = Date()

    private lazy var testFiles: [FileItem] = [
        FileItem(id: "file-1", name: "Report Q4 2024.pdf", mimeType: "application/pdf", size: 1024000, folderId: nil, ownerId: "user-1", encryptedKey: nil, createdAt: now, updatedAt: now),
        FileItem(id: "file-2", name: "Budget 2025.xlsx", mimeType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", size: 512000, folderId: nil, ownerId: "user-1", encryptedKey: nil, createdAt: now, updatedAt: now),
        FileItem(id: "file-3", name: "Meeting Notes.txt", mimeType: "text/plain", size: 2048, folderId: nil, ownerId: "user-1", encryptedKey: nil, createdAt: now, updatedAt: now),
        FileItem(id: "file-4", name: "photo_vacation.jpg", mimeType: "image/jpeg", size: 3000000, folderId: nil, ownerId: "user-1", encryptedKey: nil, createdAt: now, updatedAt: now),
        FileItem(id: "file-5", name: "project_report_draft.pdf", mimeType: "application/pdf", size: 750000, folderId: nil, ownerId: "user-1", encryptedKey: nil, createdAt: now, updatedAt: now),
    ]

    private lazy var testFolders: [Folder] = [
        Folder(id: "folder-1", name: "Documents", parentId: nil, ownerId: "user-1", encryptedFolderKey: nil, kemAlgorithm: nil, createdAt: now, updatedAt: now),
        Folder(id: "folder-2", name: "Reports Archive", parentId: nil, ownerId: "user-1", encryptedFolderKey: nil, kemAlgorithm: nil, createdAt: now, updatedAt: now),
    ]

    // MARK: - Setup

    override func setUp() {
        super.setUp()
        mockFileRepository = MockFileRepository()
        cancellables = Set<AnyCancellable>()

        // Default: list files returns test data, search returns empty (global search cache)
        mockFileRepository.listFilesResult = .success(
            ListFilesResult(contents: FolderContents(folder: nil, files: testFiles, subfolders: testFolders, breadcrumbs: nil), isFromCache: false)
        )
        mockFileRepository.searchResult = .success(
            FolderContents(folder: nil, files: testFiles, subfolders: [], breadcrumbs: nil)
        )

        viewModel = FileBrowserViewModel(fileRepository: mockFileRepository)
    }

    override func tearDown() {
        viewModel = nil
        mockFileRepository = nil
        cancellables = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Wait for async operations by running the RunLoop. Unlike Task.sleep,
    /// this processes scheduled Timer events (needed for debounce timers).
    private func waitForRunLoop(seconds: TimeInterval = 0.5) {
        let expectation = expectation(description: "RunLoop wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: seconds + 1.0)
    }

    /// Wait for the searchResults publisher to emit a non-empty value
    private func waitForSearchResults(timeout: TimeInterval = 2.0) {
        let expectation = expectation(description: "Search results")
        viewModel.$searchResults
            .dropFirst()
            .first(where: { !$0.isEmpty })
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)
        wait(for: [expectation], timeout: timeout)
    }

    // MARK: - activateSearch Tests

    func testActivateSearch_setsIsSearchActiveToTrue() {
        // Given
        XCTAssertFalse(viewModel.isSearchActive)

        // When
        viewModel.activateSearch()

        // Then
        XCTAssertTrue(viewModel.isSearchActive)
    }

    func testActivateSearch_triggersAllFilesLoad() {
        // When
        viewModel.activateSearch()

        // Wait for async load
        waitForRunLoop(seconds: 0.3)

        // Then - should call search to load all accessible files
        XCTAssertEqual(mockFileRepository.searchCallCount, 1)
        XCTAssertEqual(mockFileRepository.lastSearchQuery, "")
    }

    func testActivateSearch_calledTwice_onlyLoadsOnce() {
        // When
        viewModel.activateSearch()
        waitForRunLoop(seconds: 0.3)

        // Load completes, files are cached
        viewModel.activateSearch()
        waitForRunLoop(seconds: 0.2)

        // Then - search should only be called once since files are already loaded
        XCTAssertEqual(mockFileRepository.searchCallCount, 1)
    }

    // MARK: - deactivateSearch Tests

    func testDeactivateSearch_clearsSearchState() {
        // Given
        viewModel.activateSearch()
        viewModel.updateSearchQuery("test")
        XCTAssertTrue(viewModel.isSearchActive)

        // When
        viewModel.deactivateSearch()

        // Then
        XCTAssertFalse(viewModel.isSearchActive)
        XCTAssertEqual(viewModel.searchQuery, "")
        XCTAssertTrue(viewModel.searchResults.isEmpty)
    }

    func testDeactivateSearch_fromInactiveState_remainsInactive() {
        // Given
        XCTAssertFalse(viewModel.isSearchActive)

        // When
        viewModel.deactivateSearch()

        // Then
        XCTAssertFalse(viewModel.isSearchActive)
        XCTAssertEqual(viewModel.searchQuery, "")
        XCTAssertTrue(viewModel.searchResults.isEmpty)
    }

    // MARK: - updateSearchQuery Tests

    func testUpdateSearchQuery_emptyQuery_clearsResults() {
        // Given
        viewModel.activateSearch()

        // When
        viewModel.updateSearchQuery("")

        // Then
        XCTAssertTrue(viewModel.searchResults.isEmpty)
        XCTAssertEqual(viewModel.searchQuery, "")
    }

    func testUpdateSearchQuery_whitespaceOnly_clearsResults() {
        // Given
        viewModel.activateSearch()

        // When
        viewModel.updateSearchQuery("   ")

        // Then
        XCTAssertTrue(viewModel.searchResults.isEmpty)
    }

    func testUpdateSearchQuery_setsQueryString() {
        // Given
        viewModel.activateSearch()

        // When
        viewModel.updateSearchQuery("report")

        // Then
        XCTAssertEqual(viewModel.searchQuery, "report")
    }

    // MARK: - Local Search Filtering Tests

    func testSearch_matchesByFileName() {
        // Given - load files first
        viewModel.loadFiles()
        waitForRunLoop(seconds: 0.3)

        viewModel.activateSearch()
        waitForRunLoop(seconds: 0.3)

        // When - search for "report"
        viewModel.updateSearchQuery("report")

        // Wait for debounce (300ms) + processing via RunLoop
        waitForRunLoop(seconds: 0.5)

        // Then - should match "Report Q4 2024.pdf", "project_report_draft.pdf", and "Reports Archive" folder
        XCTAssertEqual(viewModel.searchResults.count, 3)
        let resultNames = viewModel.searchResults.map { $0.name }
        XCTAssertTrue(resultNames.contains("Report Q4 2024.pdf"))
        XCTAssertTrue(resultNames.contains("project_report_draft.pdf"))
        XCTAssertTrue(resultNames.contains("Reports Archive"))
    }

    func testSearch_caseInsensitive() {
        // Given
        viewModel.loadFiles()
        waitForRunLoop(seconds: 0.3)

        viewModel.activateSearch()
        waitForRunLoop(seconds: 0.3)

        // When - search with different case
        viewModel.updateSearchQuery("BUDGET")

        // Wait for debounce
        waitForRunLoop(seconds: 0.5)

        // Then - should match "Budget 2025.xlsx"
        XCTAssertEqual(viewModel.searchResults.count, 1)
        XCTAssertEqual(viewModel.searchResults.first?.name, "Budget 2025.xlsx")
    }

    func testSearch_noMatches_returnsEmptyResults() {
        // Given
        viewModel.loadFiles()
        waitForRunLoop(seconds: 0.3)

        viewModel.activateSearch()
        waitForRunLoop(seconds: 0.3)

        // When - search for something that doesn't exist
        viewModel.updateSearchQuery("zzz_nonexistent_zzz")

        // Wait for debounce
        waitForRunLoop(seconds: 0.5)

        // Then
        XCTAssertTrue(viewModel.searchResults.isEmpty)
    }

    func testSearch_partialMatch() {
        // Given
        viewModel.loadFiles()
        waitForRunLoop(seconds: 0.3)

        viewModel.activateSearch()
        waitForRunLoop(seconds: 0.3)

        // When - search with partial name
        viewModel.updateSearchQuery("meet")

        // Wait for debounce
        waitForRunLoop(seconds: 0.5)

        // Then - should match "Meeting Notes.txt"
        XCTAssertEqual(viewModel.searchResults.count, 1)
        XCTAssertEqual(viewModel.searchResults.first?.name, "Meeting Notes.txt")
    }

    func testSearch_matchesFileExtension() {
        // Given
        viewModel.loadFiles()
        waitForRunLoop(seconds: 0.3)

        viewModel.activateSearch()
        waitForRunLoop(seconds: 0.3)

        // When - search by file extension
        viewModel.updateSearchQuery(".pdf")

        // Wait for debounce
        waitForRunLoop(seconds: 0.5)

        // Then - should match both PDF files
        XCTAssertEqual(viewModel.searchResults.count, 2)
        let resultNames = viewModel.searchResults.map { $0.name }
        XCTAssertTrue(resultNames.contains("Report Q4 2024.pdf"))
        XCTAssertTrue(resultNames.contains("project_report_draft.pdf"))
    }

    // MARK: - Search State Transitions

    func testSearchStateTransition_activateDeactivateActivate() {
        // Given
        viewModel.loadFiles()
        waitForRunLoop(seconds: 0.3)

        // When - activate, search, deactivate, activate again
        viewModel.activateSearch()
        waitForRunLoop(seconds: 0.3)

        viewModel.updateSearchQuery("report")
        waitForRunLoop(seconds: 0.5)

        XCTAssertFalse(viewModel.searchResults.isEmpty)

        viewModel.deactivateSearch()
        XCTAssertTrue(viewModel.searchResults.isEmpty)
        XCTAssertFalse(viewModel.isSearchActive)

        // Reactivate
        viewModel.activateSearch()
        XCTAssertTrue(viewModel.isSearchActive)
        XCTAssertTrue(viewModel.searchResults.isEmpty, "Results should be empty after reactivation until a new query is entered")
    }

    // MARK: - Navigation Properties

    func testNavigationTitle_rootFolder() {
        // When
        let title = viewModel.navigationTitle

        // Then
        XCTAssertEqual(title, "My Files")
    }

    func testIsEmpty_noFilesNotLoading() {
        // Given
        mockFileRepository.listFilesResult = .success(
            ListFilesResult(contents: FolderContents(folder: nil, files: [], subfolders: [], breadcrumbs: nil), isFromCache: false)
        )
        viewModel = FileBrowserViewModel(fileRepository: mockFileRepository)

        // When
        viewModel.loadFiles()
        waitForRunLoop(seconds: 0.3)

        // Then
        XCTAssertTrue(viewModel.isEmpty)
    }

    func testIsEmpty_hasFiles() {
        // When
        viewModel.loadFiles()
        waitForRunLoop(seconds: 0.3)

        // Then
        XCTAssertFalse(viewModel.isEmpty)
    }

    // MARK: - Search with Repository Error

    func testSearch_repositoryError_handledGracefully() {
        // Given
        mockFileRepository.searchResult = .failure(MockError.testError("Network error"))
        viewModel = FileBrowserViewModel(fileRepository: mockFileRepository)

        // When
        viewModel.activateSearch()
        waitForRunLoop(seconds: 0.3)

        // Then - should not crash, isSearching should be false
        XCTAssertFalse(viewModel.isSearching)
        XCTAssertTrue(viewModel.isSearchActive)
    }
}
