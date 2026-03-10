package my.ssdid.drive.presentation.files

import app.cash.turbine.test
import my.ssdid.drive.data.sync.SyncManager
import my.ssdid.drive.data.sync.SyncState
import my.ssdid.drive.data.sync.SyncStatus
import my.ssdid.drive.domain.model.FileItem
import my.ssdid.drive.domain.model.FileStatus
import my.ssdid.drive.domain.model.Folder
import my.ssdid.drive.domain.repository.FileRepository
import my.ssdid.drive.domain.repository.FolderRepository
import my.ssdid.drive.util.AppException
import my.ssdid.drive.util.FavoritesManager
import my.ssdid.drive.util.Result
import io.mockk.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import java.time.Instant

/**
 * Unit tests for FileBrowserViewModel.
 *
 * Tests cover:
 * - Folder loading and navigation
 * - File and folder operations
 * - Error handling with null-safe messages
 * - Sync status observation
 */
@OptIn(ExperimentalCoroutinesApi::class)
class FileBrowserViewModelTest {

    private lateinit var folderRepository: FolderRepository
    private lateinit var fileRepository: FileRepository
    private lateinit var syncManager: SyncManager
    private lateinit var favoritesManager: FavoritesManager
    private lateinit var viewModel: FileBrowserViewModel
    private val testDispatcher = StandardTestDispatcher()

    private val syncStatusFlow = MutableStateFlow(SyncStatus(SyncState.IDLE, 0, false))

    private val testFolder = Folder(
        id = "folder-123",
        name = "Test Folder",
        parentId = null,
        ownerId = "user-123",
        tenantId = "tenant-123",
        isRoot = true,
        createdAt = Instant.now(),
        updatedAt = Instant.now()
    )

    private val childFolder = Folder(
        id = "child-folder-456",
        name = "Child Folder",
        parentId = "folder-123",
        ownerId = "user-123",
        tenantId = "tenant-123",
        isRoot = false,
        createdAt = Instant.now(),
        updatedAt = Instant.now()
    )

    private val testFile = FileItem(
        id = "file-789",
        name = "test-file.txt",
        mimeType = "text/plain",
        size = 1024,
        folderId = "folder-123",
        ownerId = "user-123",
        tenantId = "tenant-123",
        status = FileStatus.COMPLETE,
        createdAt = Instant.now(),
        updatedAt = Instant.now()
    )

    @Before
    fun setup() {
        Dispatchers.setMain(testDispatcher)
        folderRepository = mockk()
        fileRepository = mockk()
        syncManager = mockk(relaxed = true)
        favoritesManager = mockk(relaxed = true)

        every { syncManager.observeSyncStatus() } returns syncStatusFlow
        every { syncManager.schedulePeriodicSync() } just Runs
        every { favoritesManager.favoriteFolderIds } returns flowOf(emptySet())
        every { favoritesManager.favoriteFileIds } returns flowOf(emptySet())

        viewModel = FileBrowserViewModel(folderRepository, fileRepository, syncManager, favoritesManager)
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    // ==================== Initial State Tests ====================

    @Test
    fun `initial state is empty`() = runTest {
        viewModel.uiState.test {
            val state = awaitItem()
            assertNull(state.currentFolder)
            assertTrue(state.folders.isEmpty())
            assertTrue(state.files.isEmpty())
            assertFalse(state.isLoading)
            assertNull(state.error)
        }
    }

    // ==================== Folder Loading Tests ====================

    @Test
    fun `loadFolder with null loads root folder`() = runTest {
        coEvery { folderRepository.getRootFolder() } returns Result.success(testFolder)
        coEvery { folderRepository.getChildFolders(testFolder.id) } returns Result.success(listOf(childFolder))
        coEvery { fileRepository.getFiles(testFolder.id) } returns Result.success(listOf(testFile))

        viewModel.uiState.test {
            skipItems(1) // Initial state

            viewModel.loadFolder(null)

            // Loading state
            val loadingState = awaitItem()
            assertTrue(loadingState.isLoading)

            testDispatcher.scheduler.advanceUntilIdle()

            // Current folder set
            val folderState = awaitItem()
            assertEquals(testFolder, folderState.currentFolder)

            // Contents loaded
            val contentState = awaitItem()
            assertFalse(contentState.isLoading)
            assertEquals(1, contentState.folders.size)
            assertEquals(1, contentState.files.size)
        }
    }

    @Test
    fun `loadFolder with id loads specific folder`() = runTest {
        coEvery { folderRepository.getFolder(testFolder.id) } returns Result.success(testFolder)
        coEvery { folderRepository.getChildFolders(testFolder.id) } returns Result.success(emptyList())
        coEvery { fileRepository.getFiles(testFolder.id) } returns Result.success(emptyList())

        viewModel.loadFolder(testFolder.id)
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals(testFolder, state.currentFolder)
            assertFalse(state.isLoading)
        }
    }

    @Test
    fun `loadFolder error shows error message`() = runTest {
        coEvery { folderRepository.getRootFolder() } returns Result.error(AppException.Unknown())

        viewModel.uiState.test {
            skipItems(1)

            viewModel.loadFolder(null)
            skipItems(1) // Loading

            testDispatcher.scheduler.advanceUntilIdle()

            val errorState = awaitItem()
            assertFalse(errorState.isLoading)
            assertNotNull(errorState.error)
            assertEquals("Unknown error", errorState.error)
        }
    }

    @Test
    fun `loadFolder error shows exception message when available`() = runTest {
        val errorMessage = "Folder not found"
        coEvery { folderRepository.getRootFolder() } returns Result.error(
            AppException.NotFound(errorMessage)
        )

        viewModel.uiState.test {
            skipItems(1)

            viewModel.loadFolder(null)
            skipItems(1) // Loading

            testDispatcher.scheduler.advanceUntilIdle()

            val errorState = awaitItem()
            assertEquals(errorMessage, errorState.error)
        }
    }

    // ==================== Create Folder Tests ====================

    @Test
    fun `showCreateFolderDialog updates state`() = runTest {
        viewModel.uiState.test {
            skipItems(1)

            viewModel.showCreateFolderDialog()
            val state = awaitItem()

            assertTrue(state.showCreateFolderDialog)
        }
    }

    @Test
    fun `hideCreateFolderDialog updates state`() = runTest {
        viewModel.showCreateFolderDialog()

        viewModel.uiState.test {
            val initialState = awaitItem()
            assertTrue(initialState.showCreateFolderDialog)

            viewModel.hideCreateFolderDialog()
            val state = awaitItem()

            assertFalse(state.showCreateFolderDialog)
        }
    }

    @Test
    fun `createFolder success reloads contents`() = runTest {
        // Setup initial folder
        coEvery { folderRepository.getRootFolder() } returns Result.success(testFolder)
        coEvery { folderRepository.getChildFolders(testFolder.id) } returns Result.success(emptyList())
        coEvery { fileRepository.getFiles(testFolder.id) } returns Result.success(emptyList())
        coEvery { folderRepository.createFolder(testFolder.id, "New Folder") } returns Result.success(childFolder)

        viewModel.loadFolder(null)
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.createFolder("New Folder")
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            // Dialog should be hidden
            assertFalse(state.showCreateFolderDialog)

            // Contents should reload
            coVerify { folderRepository.getChildFolders(testFolder.id) }
        }
    }

    @Test
    fun `createFolder failure shows error`() = runTest {
        coEvery { folderRepository.getRootFolder() } returns Result.success(testFolder)
        coEvery { folderRepository.getChildFolders(testFolder.id) } returns Result.success(emptyList())
        coEvery { fileRepository.getFiles(testFolder.id) } returns Result.success(emptyList())
        coEvery { folderRepository.createFolder(testFolder.id, "New Folder") } returns Result.error(
            AppException.ValidationError("Folder name already exists")
        )

        viewModel.loadFolder(null)
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.uiState.test {
            skipItems(1)

            viewModel.createFolder("New Folder")
            testDispatcher.scheduler.advanceUntilIdle()

            val errorState = awaitItem()
            assertNotNull(errorState.error)
        }
    }

    // ==================== Delete Tests ====================

    @Test
    fun `deleteFolder success reloads contents`() = runTest {
        coEvery { folderRepository.getRootFolder() } returns Result.success(testFolder)
        coEvery { folderRepository.getChildFolders(testFolder.id) } returns Result.success(listOf(childFolder))
        coEvery { fileRepository.getFiles(testFolder.id) } returns Result.success(emptyList())
        coEvery { folderRepository.deleteFolder(childFolder.id) } returns Result.success(Unit)

        viewModel.loadFolder(null)
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.deleteFolder(childFolder.id)
        testDispatcher.scheduler.advanceUntilIdle()

        coVerify { folderRepository.deleteFolder(childFolder.id) }
        coVerify(atLeast = 2) { folderRepository.getChildFolders(testFolder.id) }
    }

    @Test
    fun `deleteFolder failure shows error message`() = runTest {
        coEvery { folderRepository.getRootFolder() } returns Result.success(testFolder)
        coEvery { folderRepository.getChildFolders(testFolder.id) } returns Result.success(listOf(childFolder))
        coEvery { fileRepository.getFiles(testFolder.id) } returns Result.success(emptyList())
        coEvery { folderRepository.deleteFolder(childFolder.id) } returns Result.error(
            AppException.Unknown()
        )

        viewModel.loadFolder(null)
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.uiState.test {
            skipItems(1)

            viewModel.deleteFolder(childFolder.id)
            testDispatcher.scheduler.advanceUntilIdle()

            val errorState = awaitItem()
            assertNotNull(errorState.error)
            assertEquals("Unknown error", errorState.error)
        }
    }

    @Test
    fun `deleteFile success reloads contents`() = runTest {
        coEvery { folderRepository.getRootFolder() } returns Result.success(testFolder)
        coEvery { folderRepository.getChildFolders(testFolder.id) } returns Result.success(emptyList())
        coEvery { fileRepository.getFiles(testFolder.id) } returns Result.success(listOf(testFile))
        coEvery { fileRepository.deleteFile(testFile.id) } returns Result.success(Unit)

        viewModel.loadFolder(null)
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.deleteFile(testFile.id)
        testDispatcher.scheduler.advanceUntilIdle()

        coVerify { fileRepository.deleteFile(testFile.id) }
        coVerify(atLeast = 2) { fileRepository.getFiles(testFolder.id) }
    }

    @Test
    fun `deleteFile failure shows error message`() = runTest {
        coEvery { folderRepository.getRootFolder() } returns Result.success(testFolder)
        coEvery { folderRepository.getChildFolders(testFolder.id) } returns Result.success(emptyList())
        coEvery { fileRepository.getFiles(testFolder.id) } returns Result.success(listOf(testFile))
        coEvery { fileRepository.deleteFile(testFile.id) } returns Result.error(
            AppException.Unknown()
        )

        viewModel.loadFolder(null)
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.uiState.test {
            skipItems(1)

            viewModel.deleteFile(testFile.id)
            testDispatcher.scheduler.advanceUntilIdle()

            val errorState = awaitItem()
            assertNotNull(errorState.error)
            assertEquals("Unknown error", errorState.error)
        }
    }

    // ==================== Sync Tests ====================

    @Test
    fun `triggerSync calls syncManager`() {
        viewModel.triggerSync()
        verify { syncManager.triggerSync() }
    }

    @Test
    fun `retryFailedSync calls syncManager`() = runTest {
        coEvery { syncManager.retryAllFailed() } just Runs

        viewModel.retryFailedSync()
        testDispatcher.scheduler.advanceUntilIdle()

        coVerify { syncManager.retryAllFailed() }
    }

    @Test
    fun `syncStatus reflects syncManager state`() = runTest {
        val newStatus = SyncStatus(SyncState.SYNCING, 5, false)

        viewModel.syncStatus.test {
            val initial = awaitItem()
            assertEquals(SyncState.IDLE, initial.state)

            syncStatusFlow.value = newStatus
            val updated = awaitItem()
            assertEquals(SyncState.SYNCING, updated.state)
            assertEquals(5, updated.pendingCount)
        }
    }

    // ==================== Multi-Select Tests ====================

    @Test
    fun `enterSelectionMode sets isSelectionMode`() = runTest {
        viewModel.uiState.test {
            skipItems(1)

            viewModel.enterSelectionMode()
            val state = awaitItem()
            assertTrue(state.isSelectionMode)
        }
    }

    @Test
    fun `exitSelectionMode clears selection and mode`() = runTest {
        viewModel.enterSelectionMode()
        viewModel.toggleFolderSelection("folder-1")
        viewModel.toggleFileSelection("file-1")

        viewModel.uiState.test {
            skipItems(1)

            viewModel.exitSelectionMode()
            val state = awaitItem()
            assertFalse(state.isSelectionMode)
            assertTrue(state.selectedFolderIds.isEmpty())
            assertTrue(state.selectedFileIds.isEmpty())
        }
    }

    @Test
    fun `toggleFolderSelection adds folder to selection`() = runTest {
        viewModel.uiState.test {
            skipItems(1)

            viewModel.toggleFolderSelection("folder-1")
            val state = awaitItem()
            assertTrue(state.selectedFolderIds.contains("folder-1"))
            assertTrue(state.isSelectionMode)
        }
    }

    @Test
    fun `toggleFolderSelection removes folder from selection when already selected`() = runTest {
        viewModel.toggleFolderSelection("folder-1")

        viewModel.uiState.test {
            skipItems(1)

            viewModel.toggleFolderSelection("folder-1")
            val state = awaitItem()
            assertFalse(state.selectedFolderIds.contains("folder-1"))
        }
    }

    @Test
    fun `toggleFolderSelection exits selection mode when last item deselected`() = runTest {
        viewModel.toggleFolderSelection("folder-1")

        viewModel.uiState.test {
            skipItems(1)

            viewModel.toggleFolderSelection("folder-1")
            val state = awaitItem()
            assertFalse(state.isSelectionMode)
        }
    }

    @Test
    fun `toggleFileSelection adds file to selection`() = runTest {
        viewModel.uiState.test {
            skipItems(1)

            viewModel.toggleFileSelection("file-1")
            val state = awaitItem()
            assertTrue(state.selectedFileIds.contains("file-1"))
            assertTrue(state.isSelectionMode)
        }
    }

    @Test
    fun `toggleFileSelection removes file from selection when already selected`() = runTest {
        viewModel.toggleFileSelection("file-1")

        viewModel.uiState.test {
            skipItems(1)

            viewModel.toggleFileSelection("file-1")
            val state = awaitItem()
            assertFalse(state.selectedFileIds.contains("file-1"))
        }
    }

    @Test
    fun `toggleFileSelection stays in selection mode if folders still selected`() = runTest {
        viewModel.toggleFolderSelection("folder-1")
        viewModel.toggleFileSelection("file-1")

        viewModel.uiState.test {
            skipItems(1)

            viewModel.toggleFileSelection("file-1")
            val state = awaitItem()
            assertTrue(state.isSelectionMode)
            assertTrue(state.selectedFolderIds.contains("folder-1"))
        }
    }

    @Test
    fun `selectAll selects all folders and files`() = runTest {
        coEvery { folderRepository.getRootFolder() } returns Result.success(testFolder)
        coEvery { folderRepository.getChildFolders(testFolder.id) } returns Result.success(listOf(childFolder))
        coEvery { fileRepository.getFiles(testFolder.id) } returns Result.success(listOf(testFile))

        viewModel.loadFolder(null)
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.uiState.test {
            skipItems(1)

            viewModel.selectAll()
            val state = awaitItem()
            assertTrue(state.isSelectionMode)
            assertTrue(state.selectedFolderIds.contains(childFolder.id))
            assertTrue(state.selectedFileIds.contains(testFile.id))
            assertEquals(2, state.selectedCount)
        }
    }

    @Test
    fun `clearSelection clears all selections`() = runTest {
        viewModel.toggleFolderSelection("folder-1")
        viewModel.toggleFileSelection("file-1")

        viewModel.uiState.test {
            skipItems(1)

            viewModel.clearSelection()
            val state = awaitItem()
            assertTrue(state.selectedFolderIds.isEmpty())
            assertTrue(state.selectedFileIds.isEmpty())
        }
    }

    // ==================== Bulk Operations Tests ====================

    @Test
    fun `deleteSelected deletes all selected items and reloads`() = runTest {
        coEvery { folderRepository.getRootFolder() } returns Result.success(testFolder)
        coEvery { folderRepository.getChildFolders(testFolder.id) } returns Result.success(listOf(childFolder))
        coEvery { fileRepository.getFiles(testFolder.id) } returns Result.success(listOf(testFile))
        coEvery { folderRepository.deleteFolder(childFolder.id) } returns Result.success(Unit)
        coEvery { fileRepository.deleteFile(testFile.id) } returns Result.success(Unit)

        viewModel.loadFolder(null)
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.toggleFolderSelection(childFolder.id)
        viewModel.toggleFileSelection(testFile.id)

        viewModel.deleteSelected()
        testDispatcher.scheduler.advanceUntilIdle()

        coVerify { folderRepository.deleteFolder(childFolder.id) }
        coVerify { fileRepository.deleteFile(testFile.id) }

        viewModel.uiState.test {
            val state = awaitItem()
            assertFalse(state.isSelectionMode)
            assertTrue(state.selectedFolderIds.isEmpty())
            assertTrue(state.selectedFileIds.isEmpty())
        }
    }

    @Test
    fun `deleteSelected shows error when some items fail`() = runTest {
        coEvery { folderRepository.getRootFolder() } returns Result.success(testFolder)
        coEvery { folderRepository.getChildFolders(testFolder.id) } returns Result.success(listOf(childFolder))
        coEvery { fileRepository.getFiles(testFolder.id) } returns Result.success(listOf(testFile))
        coEvery { folderRepository.deleteFolder(childFolder.id) } returns Result.error(
            AppException.Forbidden("Cannot delete")
        )
        coEvery { fileRepository.deleteFile(testFile.id) } returns Result.success(Unit)

        viewModel.loadFolder(null)
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.toggleFolderSelection(childFolder.id)
        viewModel.toggleFileSelection(testFile.id)

        viewModel.deleteSelected()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals("Some items could not be deleted", state.error)
        }
    }

    @Test
    fun `moveSelected moves items to destination folder`() = runTest {
        coEvery { folderRepository.getRootFolder() } returns Result.success(testFolder)
        coEvery { folderRepository.getChildFolders(testFolder.id) } returns Result.success(listOf(childFolder))
        coEvery { fileRepository.getFiles(testFolder.id) } returns Result.success(listOf(testFile))
        coEvery { folderRepository.moveFolder(childFolder.id, "dest-folder") } returns Result.success(childFolder)
        coEvery { fileRepository.moveFile(testFile.id, "dest-folder") } returns Result.success(testFile)

        viewModel.loadFolder(null)
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.toggleFolderSelection(childFolder.id)
        viewModel.toggleFileSelection(testFile.id)

        viewModel.moveSelected("dest-folder")
        testDispatcher.scheduler.advanceUntilIdle()

        coVerify { folderRepository.moveFolder(childFolder.id, "dest-folder") }
        coVerify { fileRepository.moveFile(testFile.id, "dest-folder") }

        viewModel.uiState.test {
            val state = awaitItem()
            assertFalse(state.isSelectionMode)
            assertFalse(state.isBulkOperationInProgress)
        }
    }

    @Test
    fun `moveSelected shows error when some items fail`() = runTest {
        coEvery { folderRepository.getRootFolder() } returns Result.success(testFolder)
        coEvery { folderRepository.getChildFolders(testFolder.id) } returns Result.success(emptyList())
        coEvery { fileRepository.getFiles(testFolder.id) } returns Result.success(listOf(testFile))
        coEvery { fileRepository.moveFile(testFile.id, "dest-folder") } returns Result.error(
            AppException.Forbidden("Cannot move")
        )

        viewModel.loadFolder(null)
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.toggleFileSelection(testFile.id)

        viewModel.moveSelected("dest-folder")
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertNotNull(state.error)
            assertTrue(state.error!!.contains("failed"))
        }
    }

    @Test
    fun `showMoveDialog loads available folders`() = runTest {
        val otherFolder = Folder(
            id = "other-folder",
            name = "Other Folder",
            parentId = null,
            ownerId = "user-123",
            tenantId = "tenant-123",
            isRoot = false,
            createdAt = Instant.now(),
            updatedAt = Instant.now()
        )
        coEvery { folderRepository.getRootFolder() } returns Result.success(testFolder)
        coEvery { folderRepository.getChildFolders(testFolder.id) } returns Result.success(emptyList())
        coEvery { fileRepository.getFiles(testFolder.id) } returns Result.success(emptyList())
        coEvery { folderRepository.getAllFolders() } returns Result.success(listOf(testFolder, otherFolder))

        viewModel.loadFolder(null)
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.showMoveDialog()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertTrue(state.showMoveDialog)
            // Current folder should be filtered out
            assertTrue(state.availableFoldersForMove.none { it.id == testFolder.id })
        }
    }

    @Test
    fun `hideMoveDialog clears move dialog state`() = runTest {
        viewModel.hideMoveDialog()

        viewModel.uiState.test {
            val state = awaitItem()
            assertFalse(state.showMoveDialog)
            assertTrue(state.availableFoldersForMove.isEmpty())
        }
    }

    @Test
    fun `getSelectedFileIdsForShare returns file ids when selected`() {
        viewModel.toggleFileSelection("file-1")
        viewModel.toggleFileSelection("file-2")

        val ids = viewModel.getSelectedFileIdsForShare()
        assertNotNull(ids)
        assertEquals(2, ids!!.size)
    }

    @Test
    fun `getSelectedFileIdsForShare returns null when no files selected`() {
        val ids = viewModel.getSelectedFileIdsForShare()
        assertNull(ids)
    }

    @Test
    fun `getSelectedFolderIdsForShare returns folder ids when selected`() {
        viewModel.toggleFolderSelection("folder-1")

        val ids = viewModel.getSelectedFolderIdsForShare()
        assertNotNull(ids)
        assertEquals(1, ids!!.size)
    }

    @Test
    fun `getSelectedFolderIdsForShare returns null when no folders selected`() {
        val ids = viewModel.getSelectedFolderIdsForShare()
        assertNull(ids)
    }

    // ==================== Search Tests ====================

    @Test
    fun `enterSearchMode sets search mode`() = runTest {
        viewModel.uiState.test {
            skipItems(1)

            viewModel.enterSearchMode()
            val state = awaitItem()
            assertTrue(state.isSearchMode)
            assertEquals("", state.searchQuery)
        }
    }

    @Test
    fun `exitSearchMode clears search state`() = runTest {
        viewModel.enterSearchMode()

        viewModel.uiState.test {
            skipItems(1)

            viewModel.exitSearchMode()
            val state = awaitItem()
            assertFalse(state.isSearchMode)
            assertEquals("", state.searchQuery)
            assertTrue(state.searchResults.isEmpty())
        }
    }

    @Test
    fun `updateSearchQuery sets query and triggers search for long queries`() = runTest {
        val searchResults = listOf(testFile.copy(id = "search-result-1", name = "searched-file.txt"))
        coEvery { fileRepository.searchFiles("te") } returns Result.success(searchResults)

        viewModel.updateSearchQuery("te")
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals("te", state.searchQuery)
            assertEquals(1, state.searchResults.size)
        }
    }

    @Test
    fun `updateSearchQuery with short query clears search results`() = runTest {
        viewModel.uiState.test {
            skipItems(1)

            viewModel.updateSearchQuery("t")
            val state = awaitItem()
            assertEquals("t", state.searchQuery)
            assertTrue(state.searchResults.isEmpty())
        }
    }

    @Test
    fun `searchFiles error falls back to local filtering`() = runTest {
        coEvery { fileRepository.searchFiles("query") } returns Result.error(
            AppException.Network("Failed")
        )

        viewModel.updateSearchQuery("query")
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertFalse(state.isSearching)
            // No error set - graceful fallback
        }
    }

    // ==================== Sort and View Mode Tests ====================

    @Test
    fun `setSortOption updates sort option`() = runTest {
        viewModel.uiState.test {
            skipItems(1)

            viewModel.setSortOption(SortOption.DATE_NEW)
            val state = awaitItem()
            assertEquals(SortOption.DATE_NEW, state.sortOption)
        }
    }

    @Test
    fun `setViewMode updates view mode`() = runTest {
        viewModel.uiState.test {
            skipItems(1)

            viewModel.setViewMode(ViewMode.GRID)
            val state = awaitItem()
            assertEquals(ViewMode.GRID, state.viewMode)
        }
    }

    @Test
    fun `toggleViewMode switches between list and grid`() = runTest {
        viewModel.uiState.test {
            skipItems(1)

            viewModel.toggleViewMode()
            val gridState = awaitItem()
            assertEquals(ViewMode.GRID, gridState.viewMode)

            viewModel.toggleViewMode()
            val listState = awaitItem()
            assertEquals(ViewMode.LIST, listState.viewMode)
        }
    }

    @Test
    fun `displayFiles sorts by name ascending by default`() = runTest {
        val fileA = testFile.copy(id = "a", name = "alpha.txt")
        val fileC = testFile.copy(id = "c", name = "charlie.txt")
        val fileB = testFile.copy(id = "b", name = "bravo.txt")

        coEvery { folderRepository.getRootFolder() } returns Result.success(testFolder)
        coEvery { folderRepository.getChildFolders(testFolder.id) } returns Result.success(emptyList())
        coEvery { fileRepository.getFiles(testFolder.id) } returns Result.success(listOf(fileC, fileA, fileB))

        viewModel.loadFolder(null)
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals("alpha.txt", state.displayFiles[0].name)
            assertEquals("bravo.txt", state.displayFiles[1].name)
            assertEquals("charlie.txt", state.displayFiles[2].name)
        }
    }

    @Test
    fun `displayFiles sorts by name descending`() = runTest {
        val fileA = testFile.copy(id = "a", name = "alpha.txt")
        val fileB = testFile.copy(id = "b", name = "bravo.txt")

        coEvery { folderRepository.getRootFolder() } returns Result.success(testFolder)
        coEvery { folderRepository.getChildFolders(testFolder.id) } returns Result.success(emptyList())
        coEvery { fileRepository.getFiles(testFolder.id) } returns Result.success(listOf(fileA, fileB))

        viewModel.loadFolder(null)
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.setSortOption(SortOption.NAME_DESC)

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals("bravo.txt", state.displayFiles[0].name)
            assertEquals("alpha.txt", state.displayFiles[1].name)
        }
    }

    @Test
    fun `displayFiles sorts by size largest first`() = runTest {
        val smallFile = testFile.copy(id = "s", name = "small.txt", size = 100)
        val largeFile = testFile.copy(id = "l", name = "large.txt", size = 10000)

        coEvery { folderRepository.getRootFolder() } returns Result.success(testFolder)
        coEvery { folderRepository.getChildFolders(testFolder.id) } returns Result.success(emptyList())
        coEvery { fileRepository.getFiles(testFolder.id) } returns Result.success(listOf(smallFile, largeFile))

        viewModel.loadFolder(null)
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.setSortOption(SortOption.SIZE_LARGE)

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals("large.txt", state.displayFiles[0].name)
            assertEquals("small.txt", state.displayFiles[1].name)
        }
    }

    // ==================== Favorites Tests ====================

    @Test
    fun `toggleFolderFavorite calls favoritesManager`() = runTest {
        viewModel.toggleFolderFavorite("folder-1")
        testDispatcher.scheduler.advanceUntilIdle()

        coVerify { favoritesManager.toggleFolderFavorite("folder-1") }
    }

    @Test
    fun `toggleFileFavorite calls favoritesManager`() = runTest {
        viewModel.toggleFileFavorite("file-1")
        testDispatcher.scheduler.advanceUntilIdle()

        coVerify { favoritesManager.toggleFileFavorite("file-1") }
    }

    @Test
    fun `toggleShowFavoritesOnly toggles the flag`() = runTest {
        viewModel.uiState.test {
            skipItems(1)

            viewModel.toggleShowFavoritesOnly()
            val enabledState = awaitItem()
            assertTrue(enabledState.showFavoritesOnly)

            viewModel.toggleShowFavoritesOnly()
            val disabledState = awaitItem()
            assertFalse(disabledState.showFavoritesOnly)
        }
    }

    @Test
    fun `setShowFavoritesOnly sets the flag`() = runTest {
        viewModel.uiState.test {
            skipItems(1)

            viewModel.setShowFavoritesOnly(true)
            val state = awaitItem()
            assertTrue(state.showFavoritesOnly)
        }
    }

    @Test
    fun `displayFiles filters by favorites when showFavoritesOnly is true`() = runTest {
        val favFile = testFile.copy(id = "fav-file", name = "fav.txt")
        val normalFile = testFile.copy(id = "normal-file", name = "normal.txt")

        coEvery { folderRepository.getRootFolder() } returns Result.success(testFolder)
        coEvery { folderRepository.getChildFolders(testFolder.id) } returns Result.success(emptyList())
        coEvery { fileRepository.getFiles(testFolder.id) } returns Result.success(listOf(favFile, normalFile))

        // Set up favorites flow to include favFile
        every { favoritesManager.favoriteFileIds } returns flowOf(setOf("fav-file"))

        // Recreate viewModel with updated favorites
        viewModel = FileBrowserViewModel(folderRepository, fileRepository, syncManager, favoritesManager)

        viewModel.loadFolder(null)
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.setShowFavoritesOnly(true)

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals(1, state.displayFiles.size)
            assertEquals("fav.txt", state.displayFiles[0].name)
        }
    }

    @Test
    fun `displayFolders filters by favorites when showFavoritesOnly is true`() = runTest {
        val favFolder = childFolder.copy(id = "fav-folder", name = "Favorite Folder")
        val normalFolder = childFolder.copy(id = "normal-folder", name = "Normal Folder")

        coEvery { folderRepository.getRootFolder() } returns Result.success(testFolder)
        coEvery { folderRepository.getChildFolders(testFolder.id) } returns Result.success(listOf(favFolder, normalFolder))
        coEvery { fileRepository.getFiles(testFolder.id) } returns Result.success(emptyList())

        every { favoritesManager.favoriteFolderIds } returns flowOf(setOf("fav-folder"))

        viewModel = FileBrowserViewModel(folderRepository, fileRepository, syncManager, favoritesManager)

        viewModel.loadFolder(null)
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.setShowFavoritesOnly(true)

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals(1, state.displayFolders.size)
            assertEquals("Favorite Folder", state.displayFolders[0].name)
        }
    }

    @Test
    fun `isFolderFavorite checks favorite set`() = runTest {
        every { favoritesManager.favoriteFolderIds } returns flowOf(setOf("fav-folder"))

        viewModel = FileBrowserViewModel(folderRepository, fileRepository, syncManager, favoritesManager)
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertTrue(state.isFolderFavorite("fav-folder"))
            assertFalse(state.isFolderFavorite("not-fav"))
        }
    }

    @Test
    fun `isFileFavorite checks favorite set`() = runTest {
        every { favoritesManager.favoriteFileIds } returns flowOf(setOf("fav-file"))

        viewModel = FileBrowserViewModel(folderRepository, fileRepository, syncManager, favoritesManager)
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertTrue(state.isFileFavorite("fav-file"))
            assertFalse(state.isFileFavorite("not-fav"))
        }
    }

    // ==================== Utility Method Tests ====================

    @Test
    fun `clearBulkOperationMessage clears message`() = runTest {
        // bulkOperationMessage is null by default, so clearing it won't emit a new state.
        // Verify it stays null after calling clearBulkOperationMessage.
        viewModel.clearBulkOperationMessage()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertNull(state.bulkOperationMessage)
        }
    }

    @Test
    fun `isFolderSelected checks selection state`() {
        viewModel.toggleFolderSelection("folder-1")
        assertTrue(viewModel.isFolderSelected("folder-1"))
        assertFalse(viewModel.isFolderSelected("folder-2"))
    }

    @Test
    fun `isFileSelected checks selection state`() {
        viewModel.toggleFileSelection("file-1")
        assertTrue(viewModel.isFileSelected("file-1"))
        assertFalse(viewModel.isFileSelected("file-2"))
    }
}
