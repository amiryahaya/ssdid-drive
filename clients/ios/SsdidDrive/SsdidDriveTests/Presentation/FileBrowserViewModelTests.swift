import XCTest
import Combine
@testable import SsdidDrive

/// Unit tests for FileBrowserViewModel — file loading, deletion, folder creation,
/// sorting, navigation, and empty state handling.
@MainActor
final class FileBrowserViewModelTests: XCTestCase {

    // MARK: - Properties

    var viewModel: FileBrowserViewModel!
    var mockFileRepository: MockFileRepository!
    var cancellables: Set<AnyCancellable>!

    // MARK: - Test Data

    private let now = Date()

    private lazy var testFiles: [FileItem] = [
        FileItem(id: "file-1", name: "Document.pdf", mimeType: "application/pdf", size: 1024000,
                 folderId: nil, ownerId: "user-1", encryptedKey: nil, createdAt: now, updatedAt: now),
        FileItem(id: "file-2", name: "Photo.jpg", mimeType: "image/jpeg", size: 3000000,
                 folderId: nil, ownerId: "user-1", encryptedKey: nil, createdAt: now, updatedAt: now),
        FileItem(id: "file-3", name: "Notes.txt", mimeType: "text/plain", size: 2048,
                 folderId: nil, ownerId: "user-1", encryptedKey: nil, createdAt: now, updatedAt: now),
    ]

    private lazy var testFolders: [Folder] = [
        Folder(id: "folder-1", name: "Archives", parentId: nil, ownerId: "user-1",
               encryptedFolderKey: nil, kemAlgorithm: nil, createdAt: now, updatedAt: now),
    ]

    // MARK: - Setup

    override func setUp() {
        super.setUp()
        mockFileRepository = MockFileRepository()
        cancellables = Set<AnyCancellable>()

        mockFileRepository.listFilesResult = .success(
            ListFilesResult(
                contents: FolderContents(folder: nil, files: testFiles, subfolders: testFolders, breadcrumbs: nil),
                isFromCache: false
            )
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

    private func waitForRunLoop(seconds: TimeInterval = 0.5) {
        let expectation = expectation(description: "RunLoop wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: seconds + 1.0)
    }

    // MARK: - Load Files Tests

    func testLoadFiles_success_setsItems() {
        // When
        viewModel.loadFiles()
        waitForRunLoop(seconds: 0.5)

        // Then — should have folders + files
        XCTAssertEqual(viewModel.files.count, 4) // 1 folder + 3 files
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertFalse(viewModel.isRefreshing)
    }

    func testLoadFiles_success_foldersAppearFirst() {
        // When
        viewModel.loadFiles()
        waitForRunLoop(seconds: 0.5)

        // Then — first item should be the folder
        let firstItem = viewModel.files.first
        XCTAssertTrue(firstItem?.isFolder == true, "Folders should appear before files")
        XCTAssertEqual(firstItem?.name, "Archives")
    }

    func testLoadFiles_failure_setsErrorMessage() {
        // Given
        mockFileRepository.listFilesResult = .failure(MockError.testError("Network error"))
        viewModel = FileBrowserViewModel(fileRepository: mockFileRepository)

        // When
        viewModel.loadFiles()
        waitForRunLoop(seconds: 0.5)

        // Then
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertContains(viewModel.errorMessage, "Network error")
        XCTAssertTrue(viewModel.isOffline)
    }

    func testLoadFiles_fromCache_setsIsOffline() {
        // Given
        mockFileRepository.listFilesResult = .success(
            ListFilesResult(
                contents: FolderContents(folder: nil, files: testFiles, subfolders: [], breadcrumbs: nil),
                isFromCache: true
            )
        )
        viewModel = FileBrowserViewModel(fileRepository: mockFileRepository)

        // When
        viewModel.loadFiles()
        waitForRunLoop(seconds: 0.5)

        // Then
        XCTAssertTrue(viewModel.isOffline)
    }

    func testLoadFiles_callsRepository() {
        // When
        viewModel.loadFiles()
        waitForRunLoop(seconds: 0.5)

        // Then
        XCTAssertEqual(mockFileRepository.listFilesCallCount, 1)
        XCTAssertNil(mockFileRepository.lastListFilesFolderId, "Root folder should pass nil folderId")
    }

    // MARK: - Search Filtering Tests

    func testSearchFiltering_filtersByName() {
        // Given
        viewModel.loadFiles()
        waitForRunLoop(seconds: 0.3)

        viewModel.activateSearch()
        waitForRunLoop(seconds: 0.3)

        // When
        viewModel.updateSearchQuery("Document")
        waitForRunLoop(seconds: 0.5)

        // Then
        XCTAssertEqual(viewModel.searchResults.count, 1)
        XCTAssertEqual(viewModel.searchResults.first?.name, "Document.pdf")
    }

    func testSearchFiltering_caseInsensitive() {
        // Given
        viewModel.loadFiles()
        waitForRunLoop(seconds: 0.3)

        viewModel.activateSearch()
        waitForRunLoop(seconds: 0.3)

        // When
        viewModel.updateSearchQuery("photo")
        waitForRunLoop(seconds: 0.5)

        // Then
        XCTAssertEqual(viewModel.searchResults.count, 1)
        XCTAssertEqual(viewModel.searchResults.first?.name, "Photo.jpg")
    }

    func testSearchFiltering_noMatch_emptyResults() {
        // Given
        viewModel.loadFiles()
        waitForRunLoop(seconds: 0.3)

        viewModel.activateSearch()
        waitForRunLoop(seconds: 0.3)

        // When
        viewModel.updateSearchQuery("zzz_nonexistent")
        waitForRunLoop(seconds: 0.5)

        // Then
        XCTAssertTrue(viewModel.searchResults.isEmpty)
    }

    // MARK: - Delete File Tests

    func testDeleteFile_success_removesFromList() {
        // Given
        viewModel.loadFiles()
        waitForRunLoop(seconds: 0.5)

        let fileToDelete = viewModel.files.first { $0.id == "file-1" }!
        let initialCount = viewModel.files.count

        // When
        viewModel.deleteFile(fileToDelete)
        waitForRunLoop(seconds: 0.5)

        // Then
        XCTAssertEqual(viewModel.files.count, initialCount - 1)
        XCTAssertFalse(viewModel.files.contains { $0.id == "file-1" })
        XCTAssertEqual(mockFileRepository.deleteFileCallCount, 1)
        XCTAssertEqual(mockFileRepository.lastDeleteFileId, "file-1")
    }

    func testDeleteFile_failure_setsErrorMessage() {
        // Given
        mockFileRepository.deleteFileResult = .failure(MockError.testError("Delete failed"))
        viewModel.loadFiles()
        waitForRunLoop(seconds: 0.5)

        let fileToDelete = viewModel.files.first { $0.id == "file-1" }!

        // When
        viewModel.deleteFile(fileToDelete)
        waitForRunLoop(seconds: 0.5)

        // Then
        XCTAssertNotNil(viewModel.errorMessage)
    }

    // MARK: - Create Folder Tests

    func testCreateFolder_success_addsToList() {
        // Given
        let newFolder = Folder(
            id: "folder-new", name: "New Folder", parentId: nil, ownerId: "user-1",
            encryptedFolderKey: nil, kemAlgorithm: nil, createdAt: now, updatedAt: now
        )
        mockFileRepository.createFolderResult = .success(newFolder)

        viewModel.loadFiles()
        waitForRunLoop(seconds: 0.5)
        let initialCount = viewModel.files.count

        // When
        viewModel.createFolder(name: "New Folder")
        waitForRunLoop(seconds: 0.5)

        // Then
        XCTAssertEqual(viewModel.files.count, initialCount + 1)
        XCTAssertTrue(viewModel.files.contains { $0.id == "folder-new" })
        XCTAssertEqual(mockFileRepository.createFolderCallCount, 1)
        XCTAssertEqual(mockFileRepository.lastCreateFolderName, "New Folder")
        XCTAssertNil(mockFileRepository.lastCreateFolderParentId)
    }

    func testCreateFolder_failure_setsErrorMessage() {
        // Given
        mockFileRepository.createFolderResult = .failure(MockError.testError("Create failed"))

        // When
        viewModel.createFolder(name: "Bad Folder")
        waitForRunLoop(seconds: 0.5)

        // Then
        XCTAssertNotNil(viewModel.errorMessage)
    }

    // MARK: - Pull to Refresh Tests

    func testRefreshFiles_setsIsRefreshing() {
        // When
        viewModel.refreshFiles()

        // Then — isRefreshing should be set immediately
        XCTAssertTrue(viewModel.isRefreshing)
    }

    func testRefreshFiles_reloadsData() {
        // When
        viewModel.refreshFiles()
        waitForRunLoop(seconds: 0.5)

        // Then
        XCTAssertEqual(mockFileRepository.listFilesCallCount, 1)
        XCTAssertFalse(viewModel.isRefreshing)
    }

    // MARK: - Empty State Tests

    func testEmptyState_noFiles_isTrue() {
        // Given
        mockFileRepository.listFilesResult = .success(
            ListFilesResult(
                contents: FolderContents(folder: nil, files: [], subfolders: [], breadcrumbs: nil),
                isFromCache: false
            )
        )
        viewModel = FileBrowserViewModel(fileRepository: mockFileRepository)

        // When
        viewModel.loadFiles()
        waitForRunLoop(seconds: 0.5)

        // Then
        XCTAssertTrue(viewModel.isEmpty)
        XCTAssertTrue(viewModel.files.isEmpty)
    }

    func testEmptyState_hasFiles_isFalse() {
        // When
        viewModel.loadFiles()
        waitForRunLoop(seconds: 0.5)

        // Then
        XCTAssertFalse(viewModel.isEmpty)
    }

    func testEmptyState_whileLoading_isFalse() {
        // isEmpty should be false while loading even if files array is empty
        viewModel.isLoading = true
        XCTAssertFalse(viewModel.isEmpty, "Should not show empty state while loading")
    }

    // MARK: - Navigation Tests

    func testNavigationTitle_rootFolder_returnsMyFiles() {
        XCTAssertEqual(viewModel.navigationTitle, "My Files")
    }

    func testNavigationTitle_subfolder_returnsFolderName() {
        // Given
        let folder = FileItem(
            id: "folder-1", name: "Projects", mimeType: "folder", size: 0,
            folderId: nil, ownerId: "user-1", encryptedKey: nil,
            createdAt: now, updatedAt: now, isFolder: true
        )
        viewModel = FileBrowserViewModel(fileRepository: mockFileRepository, folder: folder)

        // Then
        XCTAssertEqual(viewModel.navigationTitle, "Projects")
    }

    func testNavigateToFolder_updatesFolderPath() {
        // Given
        let folder = FileItem(
            id: "folder-1", name: "Archives", mimeType: "folder", size: 0,
            folderId: nil, ownerId: "user-1", encryptedKey: nil,
            createdAt: now, updatedAt: now, isFolder: true
        )

        // When
        viewModel.navigateToFolder(folder)

        // Then
        XCTAssertEqual(viewModel.currentFolder?.id, "folder-1")
        XCTAssertEqual(viewModel.folderPath.count, 1)
        XCTAssertEqual(viewModel.navigationTitle, "Archives")
    }

    func testNavigateUp_removesFromFolderPath() {
        // Given — navigate into a folder first
        let folder = FileItem(
            id: "folder-1", name: "Archives", mimeType: "folder", size: 0,
            folderId: nil, ownerId: "user-1", encryptedKey: nil,
            createdAt: now, updatedAt: now, isFolder: true
        )
        viewModel.navigateToFolder(folder)
        XCTAssertEqual(viewModel.folderPath.count, 1)

        // When
        viewModel.navigateUp()

        // Then
        XCTAssertTrue(viewModel.folderPath.isEmpty)
        XCTAssertNil(viewModel.currentFolder)
        XCTAssertEqual(viewModel.navigationTitle, "My Files")
    }

    func testNavigateUp_atRoot_doesNothing() {
        // Given — already at root
        XCTAssertTrue(viewModel.folderPath.isEmpty)

        // When
        viewModel.navigateUp()

        // Then — should not crash
        XCTAssertTrue(viewModel.folderPath.isEmpty)
        XCTAssertNil(viewModel.currentFolder)
    }

    // MARK: - Sort Tests

    func testSetSortOption_resortFiles() {
        // Given
        viewModel.loadFiles()
        waitForRunLoop(seconds: 0.5)

        // When
        viewModel.setSortOption(.nameDesc)

        // Then
        XCTAssertEqual(viewModel.sortOption, .nameDesc)
        // Folders still come first, but files should be reverse-sorted
        let fileItems = viewModel.files.filter { !$0.isFolder }
        if fileItems.count >= 2 {
            XCTAssertTrue(
                fileItems[0].name.localizedCaseInsensitiveCompare(fileItems[1].name) == .orderedDescending,
                "Files should be sorted in descending name order"
            )
        }
    }

    // MARK: - View Mode Tests

    func testToggleViewMode_switchesBetweenGridAndList() {
        // Given
        XCTAssertTrue(viewModel.isGridView) // default

        // When
        viewModel.toggleViewMode()

        // Then
        XCTAssertFalse(viewModel.isGridView)

        // When — toggle back
        viewModel.toggleViewMode()

        // Then
        XCTAssertTrue(viewModel.isGridView)
    }

    // MARK: - Subfolder File Loading Tests

    func testLoadFiles_inSubfolder_passesCorrectFolderId() {
        // Given
        let folder = FileItem(
            id: "folder-sub", name: "Subfolder", mimeType: "folder", size: 0,
            folderId: nil, ownerId: "user-1", encryptedKey: nil,
            createdAt: now, updatedAt: now, isFolder: true
        )
        viewModel = FileBrowserViewModel(fileRepository: mockFileRepository, folder: folder)

        // When
        viewModel.loadFiles()
        waitForRunLoop(seconds: 0.5)

        // Then
        XCTAssertEqual(mockFileRepository.lastListFilesFolderId, "folder-sub")
    }
}
