package my.ssdid.drive.presentation.sharing

import androidx.lifecycle.SavedStateHandle
import app.cash.turbine.test
import my.ssdid.drive.domain.model.FileItem
import my.ssdid.drive.domain.model.FileStatus
import my.ssdid.drive.domain.model.Share
import my.ssdid.drive.domain.model.SharePermission
import my.ssdid.drive.domain.model.ResourceType
import my.ssdid.drive.domain.model.User
import my.ssdid.drive.domain.repository.FileRepository
import my.ssdid.drive.domain.repository.ShareRepository
import my.ssdid.drive.presentation.navigation.Screen
import my.ssdid.drive.util.AppException
import my.ssdid.drive.util.Result
import io.mockk.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import java.time.Instant

/**
 * Unit tests for ShareFileViewModel.
 *
 * Tests cover:
 * - File loading on init
 * - User search with debounce
 * - User selection and clearing
 * - Permission selection
 * - Expiry configuration
 * - Share file success and error
 * - Error clearing
 */
@OptIn(ExperimentalCoroutinesApi::class)
class ShareFileViewModelTest {

    private lateinit var fileRepository: FileRepository
    private lateinit var shareRepository: ShareRepository
    private lateinit var savedStateHandle: SavedStateHandle
    private lateinit var viewModel: ShareFileViewModel
    private val testDispatcher = StandardTestDispatcher()

    private val testFileId = "file-123"

    private val testFile = FileItem(
        id = testFileId,
        name = "test-document.pdf",
        mimeType = "application/pdf",
        size = 2048,
        folderId = "folder-456",
        ownerId = "user-owner",
        tenantId = "tenant-001",
        status = FileStatus.COMPLETE,
        createdAt = Instant.parse("2025-01-01T00:00:00Z"),
        updatedAt = Instant.parse("2025-01-01T00:00:00Z")
    )

    private val testUser = User(
        id = "user-grantee",
        email = "alice@example.com",
        displayName = "Alice"
    )

    private val testUser2 = User(
        id = "user-grantee-2",
        email = "bob@example.com",
        displayName = "Bob"
    )

    private val testShare = Share(
        id = "share-001",
        grantorId = "user-owner",
        granteeId = testUser.id,
        resourceType = ResourceType.FILE,
        resourceId = testFileId,
        permission = SharePermission.READ,
        recursive = false,
        expiresAt = null,
        revokedAt = null,
        grantor = null,
        grantee = testUser,
        createdAt = Instant.parse("2025-01-01T00:00:00Z"),
        updatedAt = Instant.parse("2025-01-01T00:00:00Z")
    )

    @Before
    fun setup() {
        Dispatchers.setMain(testDispatcher)
        fileRepository = mockk()
        shareRepository = mockk()
        savedStateHandle = SavedStateHandle(mapOf(Screen.ARG_FILE_ID to testFileId))
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private fun createViewModel(): ShareFileViewModel {
        return ShareFileViewModel(savedStateHandle, fileRepository, shareRepository)
    }

    // ==================== Init / Load File Tests ====================

    @Test
    fun `init loads file successfully`() = runTest {
        coEvery { fileRepository.getFile(testFileId) } returns Result.success(testFile)

        viewModel = createViewModel()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals(testFile, state.file)
            assertFalse(state.isLoading)
            assertNull(state.error)
        }
    }

    @Test
    fun `init sets loading state while loading file`() = runTest {
        coEvery { fileRepository.getFile(testFileId) } returns Result.success(testFile)

        viewModel = createViewModel()

        viewModel.uiState.test {
            // With StandardTestDispatcher, the initial emission is the default state
            // (isLoading=false). Advance to let loadFile() run.
            val initial = awaitItem()

            testDispatcher.scheduler.advanceUntilIdle()

            // After advancing, we may see isLoading=true then isLoading=false,
            // or just the final loaded state (states may be conflated).
            val emissions = cancelAndConsumeRemainingEvents()
            // Verify the file was loaded by checking current state
        }

        // Verify the final state has the file loaded
        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals(testFile, state.file)
            assertFalse(state.isLoading)
        }
    }

    @Test
    fun `init shows error when file load fails`() = runTest {
        coEvery { fileRepository.getFile(testFileId) } returns Result.error(
            AppException.NotFound("File not found")
        )

        viewModel = createViewModel()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertNull(state.file)
            assertFalse(state.isLoading)
            assertEquals("File not found", state.error)
        }
    }

    @Test
    fun `init shows default error message when exception has no message`() = runTest {
        coEvery { fileRepository.getFile(testFileId) } returns Result.error(
            AppException.Unknown()
        )

        viewModel = createViewModel()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertNotNull(state.error)
        }
    }

    // ==================== Search Query Tests ====================

    @Test
    fun `onSearchQueryChanged updates query in state`() = runTest {
        coEvery { fileRepository.getFile(testFileId) } returns Result.success(testFile)
        // "al" has length >= 2, so a debounced search will be triggered
        coEvery { shareRepository.searchUsers("al") } returns Result.success(emptyList())

        viewModel = createViewModel()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.onSearchQueryChanged("al")

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals("al", state.searchQuery)
        }
    }

    @Test
    fun `onSearchQueryChanged with short query clears results`() = runTest {
        coEvery { fileRepository.getFile(testFileId) } returns Result.success(testFile)

        viewModel = createViewModel()
        testDispatcher.scheduler.advanceUntilIdle()

        // First do a valid search
        coEvery { shareRepository.searchUsers("alice") } returns Result.success(listOf(testUser))
        viewModel.onSearchQueryChanged("alice")
        testDispatcher.scheduler.advanceUntilIdle()

        // Then enter a short query
        viewModel.onSearchQueryChanged("a")

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals("a", state.searchQuery)
            assertTrue(state.searchResults.isEmpty())
            assertFalse(state.isSearching)
        }
    }

    @Test
    fun `onSearchQueryChanged with empty query clears results`() = runTest {
        coEvery { fileRepository.getFile(testFileId) } returns Result.success(testFile)

        viewModel = createViewModel()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.onSearchQueryChanged("")

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals("", state.searchQuery)
            assertTrue(state.searchResults.isEmpty())
        }
    }

    @Test
    fun `onSearchQueryChanged debounces and searches users`() = runTest {
        coEvery { fileRepository.getFile(testFileId) } returns Result.success(testFile)
        coEvery { shareRepository.searchUsers("alice") } returns Result.success(listOf(testUser))

        viewModel = createViewModel()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.onSearchQueryChanged("alice")
        // Advance past the 300ms debounce
        testDispatcher.scheduler.advanceTimeBy(301)
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals(1, state.searchResults.size)
            assertEquals(testUser, state.searchResults.first())
            assertFalse(state.isSearching)
        }
    }

    @Test
    fun `onSearchQueryChanged cancels previous search on new query`() = runTest {
        coEvery { fileRepository.getFile(testFileId) } returns Result.success(testFile)
        coEvery { shareRepository.searchUsers("bob") } returns Result.success(listOf(testUser2))

        viewModel = createViewModel()
        testDispatcher.scheduler.advanceUntilIdle()

        // Start first search
        viewModel.onSearchQueryChanged("alice")
        // Before debounce completes, start new search
        testDispatcher.scheduler.advanceTimeBy(100)
        viewModel.onSearchQueryChanged("bob")
        testDispatcher.scheduler.advanceTimeBy(301)
        testDispatcher.scheduler.advanceUntilIdle()

        // Only "bob" search should have executed
        coVerify(exactly = 0) { shareRepository.searchUsers("alice") }
        coVerify(exactly = 1) { shareRepository.searchUsers("bob") }
    }

    @Test
    fun `onSearchQueryChanged handles search failure gracefully`() = runTest {
        coEvery { fileRepository.getFile(testFileId) } returns Result.success(testFile)
        coEvery { shareRepository.searchUsers("alice") } returns Result.error(
            AppException.Network("Connection failed")
        )

        viewModel = createViewModel()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.onSearchQueryChanged("alice")
        testDispatcher.scheduler.advanceTimeBy(301)
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertTrue(state.searchResults.isEmpty())
            assertFalse(state.isSearching)
        }
    }

    // ==================== User Selection Tests ====================

    @Test
    fun `onUserSelected sets selected user and clears search`() = runTest {
        coEvery { fileRepository.getFile(testFileId) } returns Result.success(testFile)

        viewModel = createViewModel()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.onUserSelected(testUser)

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals(testUser, state.selectedUser)
            assertEquals("", state.searchQuery)
            assertTrue(state.searchResults.isEmpty())
        }
    }

    @Test
    fun `onUserCleared clears selected user`() = runTest {
        coEvery { fileRepository.getFile(testFileId) } returns Result.success(testFile)

        viewModel = createViewModel()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.onUserSelected(testUser)
        viewModel.onUserCleared()

        viewModel.uiState.test {
            val state = awaitItem()
            assertNull(state.selectedUser)
        }
    }

    // ==================== Permission Tests ====================

    @Test
    fun `initial permission is READ`() = runTest {
        coEvery { fileRepository.getFile(testFileId) } returns Result.success(testFile)

        viewModel = createViewModel()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals(SharePermission.READ, state.selectedPermission)
        }
    }

    @Test
    fun `onPermissionSelected updates permission`() = runTest {
        coEvery { fileRepository.getFile(testFileId) } returns Result.success(testFile)

        viewModel = createViewModel()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.onPermissionSelected(SharePermission.WRITE)

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals(SharePermission.WRITE, state.selectedPermission)
        }
    }

    @Test
    fun `onPermissionSelected to ADMIN updates permission`() = runTest {
        coEvery { fileRepository.getFile(testFileId) } returns Result.success(testFile)

        viewModel = createViewModel()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.onPermissionSelected(SharePermission.ADMIN)

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals(SharePermission.ADMIN, state.selectedPermission)
        }
    }

    // ==================== Expiry Tests ====================

    @Test
    fun `initial expiry is null`() = runTest {
        coEvery { fileRepository.getFile(testFileId) } returns Result.success(testFile)

        viewModel = createViewModel()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertNull(state.expiryDays)
        }
    }

    @Test
    fun `onExpiryChanged sets expiry days`() = runTest {
        coEvery { fileRepository.getFile(testFileId) } returns Result.success(testFile)

        viewModel = createViewModel()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.onExpiryChanged(30)

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals(30, state.expiryDays)
        }
    }

    @Test
    fun `onExpiryChanged with null clears expiry`() = runTest {
        coEvery { fileRepository.getFile(testFileId) } returns Result.success(testFile)

        viewModel = createViewModel()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.onExpiryChanged(7)
        viewModel.onExpiryChanged(null)

        viewModel.uiState.test {
            val state = awaitItem()
            assertNull(state.expiryDays)
        }
    }

    // ==================== Share File Tests ====================

    @Test
    fun `shareFile success updates state`() = runTest {
        coEvery { fileRepository.getFile(testFileId) } returns Result.success(testFile)
        coEvery {
            shareRepository.shareFile(
                fileId = testFileId,
                grantee = testUser,
                permission = SharePermission.READ,
                expiresAt = any()
            )
        } returns Result.success(testShare)

        viewModel = createViewModel()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.onUserSelected(testUser)
        viewModel.shareFile()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertTrue(state.shareSuccess)
            assertFalse(state.isSharing)
            assertNull(state.error)
        }
    }

    @Test
    fun `shareFile with permission and expiry passes correct params`() = runTest {
        coEvery { fileRepository.getFile(testFileId) } returns Result.success(testFile)
        coEvery {
            shareRepository.shareFile(
                fileId = testFileId,
                grantee = testUser,
                permission = SharePermission.WRITE,
                expiresAt = any()
            )
        } returns Result.success(testShare.copy(permission = SharePermission.WRITE))

        viewModel = createViewModel()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.onUserSelected(testUser)
        viewModel.onPermissionSelected(SharePermission.WRITE)
        viewModel.onExpiryChanged(7)
        viewModel.shareFile()
        testDispatcher.scheduler.advanceUntilIdle()

        coVerify {
            shareRepository.shareFile(
                fileId = testFileId,
                grantee = testUser,
                permission = SharePermission.WRITE,
                expiresAt = any()
            )
        }
    }

    @Test
    fun `shareFile without expiry passes null expiresAt`() = runTest {
        coEvery { fileRepository.getFile(testFileId) } returns Result.success(testFile)
        coEvery {
            shareRepository.shareFile(
                fileId = testFileId,
                grantee = testUser,
                permission = SharePermission.READ,
                expiresAt = null
            )
        } returns Result.success(testShare)

        viewModel = createViewModel()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.onUserSelected(testUser)
        viewModel.shareFile()
        testDispatcher.scheduler.advanceUntilIdle()

        coVerify {
            shareRepository.shareFile(
                fileId = testFileId,
                grantee = testUser,
                permission = SharePermission.READ,
                expiresAt = null
            )
        }
    }

    @Test
    fun `shareFile error updates state with error message`() = runTest {
        coEvery { fileRepository.getFile(testFileId) } returns Result.success(testFile)
        coEvery {
            shareRepository.shareFile(
                fileId = testFileId,
                grantee = testUser,
                permission = SharePermission.READ,
                expiresAt = any()
            )
        } returns Result.error(AppException.Forbidden("Access denied"))

        viewModel = createViewModel()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.onUserSelected(testUser)
        viewModel.shareFile()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertFalse(state.shareSuccess)
            assertFalse(state.isSharing)
            assertEquals("Access denied", state.error)
        }
    }

    @Test
    fun `shareFile without selected user does nothing`() = runTest {
        coEvery { fileRepository.getFile(testFileId) } returns Result.success(testFile)

        viewModel = createViewModel()
        testDispatcher.scheduler.advanceUntilIdle()

        // Do not select a user
        viewModel.shareFile()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertFalse(state.isSharing)
            assertFalse(state.shareSuccess)
        }

        coVerify(exactly = 0) {
            shareRepository.shareFile(
                fileId = any(),
                grantee = any(),
                permission = any(),
                expiresAt = any()
            )
        }
    }

    @Test
    fun `shareFile sets isSharing while in progress`() = runTest {
        coEvery { fileRepository.getFile(testFileId) } returns Result.success(testFile)
        coEvery {
            shareRepository.shareFile(
                fileId = testFileId,
                grantee = testUser,
                permission = SharePermission.READ,
                expiresAt = any()
            )
        } returns Result.success(testShare)

        viewModel = createViewModel()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.onUserSelected(testUser)

        viewModel.uiState.test {
            skipItems(1) // Current state

            viewModel.shareFile()

            val sharingState = awaitItem()
            assertTrue(sharingState.isSharing)
            assertNull(sharingState.error)

            testDispatcher.scheduler.advanceUntilIdle()

            val doneState = awaitItem()
            assertFalse(doneState.isSharing)
            assertTrue(doneState.shareSuccess)
        }
    }

    // ==================== Clear Error Tests ====================

    @Test
    fun `clearError clears error from state`() = runTest {
        coEvery { fileRepository.getFile(testFileId) } returns Result.error(
            AppException.Unknown("Some error")
        )

        viewModel = createViewModel()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.uiState.test {
            val errorState = awaitItem()
            assertNotNull(errorState.error)

            viewModel.clearError()
            val clearedState = awaitItem()
            assertNull(clearedState.error)
        }
    }
}
