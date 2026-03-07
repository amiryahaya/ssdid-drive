package com.securesharing.presentation.files

import app.cash.turbine.test
import com.securesharing.data.sync.SyncManager
import com.securesharing.data.sync.SyncState
import com.securesharing.data.sync.SyncStatus
import com.securesharing.domain.model.FileItem
import com.securesharing.domain.model.FileStatus
import com.securesharing.domain.model.Folder
import com.securesharing.domain.repository.FileRepository
import com.securesharing.domain.repository.FolderRepository
import com.securesharing.util.AppException
import com.securesharing.util.FavoritesManager
import com.securesharing.util.Result
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
}
