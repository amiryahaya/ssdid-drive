package my.ssdid.drive.presentation.sharing

import androidx.lifecycle.SavedStateHandle
import app.cash.turbine.test
import my.ssdid.drive.domain.model.Folder
import my.ssdid.drive.domain.model.Share
import my.ssdid.drive.domain.model.SharePermission
import my.ssdid.drive.domain.model.ResourceType
import my.ssdid.drive.domain.model.User
import my.ssdid.drive.domain.repository.FolderRepository
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
 * Unit tests for ShareFolderViewModel.
 *
 * Tests cover:
 * - Folder loading on init
 * - User search with debounce
 * - User selection and clearing
 * - Permission selection
 * - Recursive toggle
 * - Expiry configuration
 * - Share folder success and error
 * - Error clearing
 */
@OptIn(ExperimentalCoroutinesApi::class)
class ShareFolderViewModelTest {

    private lateinit var folderRepository: FolderRepository
    private lateinit var shareRepository: ShareRepository
    private lateinit var savedStateHandle: SavedStateHandle
    private lateinit var viewModel: ShareFolderViewModel
    private val testDispatcher = StandardTestDispatcher()

    private val testFolderId = "folder-789"

    private val testFolder = Folder(
        id = testFolderId,
        name = "Shared Documents",
        parentId = "folder-root",
        ownerId = "user-owner",
        tenantId = "tenant-001",
        isRoot = false,
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
        id = "share-002",
        grantorId = "user-owner",
        granteeId = testUser.id,
        resourceType = ResourceType.FOLDER,
        resourceId = testFolderId,
        permission = SharePermission.READ,
        recursive = true,
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
        folderRepository = mockk()
        shareRepository = mockk()
        savedStateHandle = SavedStateHandle(mapOf(Screen.ARG_FOLDER_ID to testFolderId))
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private fun createViewModel(): ShareFolderViewModel {
        return ShareFolderViewModel(savedStateHandle, folderRepository, shareRepository)
    }

    // ==================== Init / Load Folder Tests ====================

    @Test
    fun `init loads folder successfully`() = runTest {
        coEvery { folderRepository.getFolder(testFolderId) } returns Result.success(testFolder)

        viewModel = createViewModel()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals(testFolder, state.folder)
            assertFalse(state.isLoading)
            assertNull(state.error)
        }
    }

    @Test
    fun `init shows error when folder load fails`() = runTest {
        coEvery { folderRepository.getFolder(testFolderId) } returns Result.error(
            AppException.NotFound("Folder not found")
        )

        viewModel = createViewModel()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertNull(state.folder)
            assertFalse(state.isLoading)
            assertEquals("Folder not found", state.error)
        }
    }

    @Test
    fun `init shows default error on unknown failure`() = runTest {
        coEvery { folderRepository.getFolder(testFolderId) } returns Result.error(
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
        coEvery { folderRepository.getFolder(testFolderId) } returns Result.success(testFolder)
        // "bo" has length >= 2, so a debounced search will be triggered
        coEvery { shareRepository.searchUsers("bo") } returns Result.success(emptyList())

        viewModel = createViewModel()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.onSearchQueryChanged("bo")

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals("bo", state.searchQuery)
        }
    }

    @Test
    fun `onSearchQueryChanged with short query clears results`() = runTest {
        coEvery { folderRepository.getFolder(testFolderId) } returns Result.success(testFolder)

        viewModel = createViewModel()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.onSearchQueryChanged("a")

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals("a", state.searchQuery)
            assertTrue(state.searchResults.isEmpty())
            assertFalse(state.isSearching)
        }
    }

    @Test
    fun `onSearchQueryChanged debounces and searches users`() = runTest {
        coEvery { folderRepository.getFolder(testFolderId) } returns Result.success(testFolder)
        coEvery { shareRepository.searchUsers("bob") } returns Result.success(listOf(testUser2))

        viewModel = createViewModel()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.onSearchQueryChanged("bob")
        testDispatcher.scheduler.advanceTimeBy(301)
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals(1, state.searchResults.size)
            assertEquals(testUser2, state.searchResults.first())
            assertFalse(state.isSearching)
        }
    }

    @Test
    fun `onSearchQueryChanged cancels previous search on new query`() = runTest {
        coEvery { folderRepository.getFolder(testFolderId) } returns Result.success(testFolder)
        coEvery { shareRepository.searchUsers("alice") } returns Result.success(listOf(testUser))

        viewModel = createViewModel()
        testDispatcher.scheduler.advanceUntilIdle()

        // Start first search then override
        viewModel.onSearchQueryChanged("bob")
        testDispatcher.scheduler.advanceTimeBy(100)
        viewModel.onSearchQueryChanged("alice")
        testDispatcher.scheduler.advanceTimeBy(301)
        testDispatcher.scheduler.advanceUntilIdle()

        coVerify(exactly = 0) { shareRepository.searchUsers("bob") }
        coVerify(exactly = 1) { shareRepository.searchUsers("alice") }
    }

    @Test
    fun `onSearchQueryChanged handles search failure gracefully`() = runTest {
        coEvery { folderRepository.getFolder(testFolderId) } returns Result.success(testFolder)
        coEvery { shareRepository.searchUsers("bob") } returns Result.error(
            AppException.Network("Timeout")
        )

        viewModel = createViewModel()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.onSearchQueryChanged("bob")
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
        coEvery { folderRepository.getFolder(testFolderId) } returns Result.success(testFolder)

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
        coEvery { folderRepository.getFolder(testFolderId) } returns Result.success(testFolder)

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
        coEvery { folderRepository.getFolder(testFolderId) } returns Result.success(testFolder)

        viewModel = createViewModel()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals(SharePermission.READ, state.selectedPermission)
        }
    }

    @Test
    fun `onPermissionSelected updates permission`() = runTest {
        coEvery { folderRepository.getFolder(testFolderId) } returns Result.success(testFolder)

        viewModel = createViewModel()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.onPermissionSelected(SharePermission.ADMIN)

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals(SharePermission.ADMIN, state.selectedPermission)
        }
    }

    // ==================== Recursive Tests ====================

    @Test
    fun `initial recursive is true`() = runTest {
        coEvery { folderRepository.getFolder(testFolderId) } returns Result.success(testFolder)

        viewModel = createViewModel()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertTrue(state.recursive)
        }
    }

    @Test
    fun `onRecursiveChanged sets recursive to false`() = runTest {
        coEvery { folderRepository.getFolder(testFolderId) } returns Result.success(testFolder)

        viewModel = createViewModel()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.onRecursiveChanged(false)

        viewModel.uiState.test {
            val state = awaitItem()
            assertFalse(state.recursive)
        }
    }

    @Test
    fun `onRecursiveChanged toggles back to true`() = runTest {
        coEvery { folderRepository.getFolder(testFolderId) } returns Result.success(testFolder)

        viewModel = createViewModel()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.onRecursiveChanged(false)
        viewModel.onRecursiveChanged(true)

        viewModel.uiState.test {
            val state = awaitItem()
            assertTrue(state.recursive)
        }
    }

    // ==================== Expiry Tests ====================

    @Test
    fun `initial expiry is null`() = runTest {
        coEvery { folderRepository.getFolder(testFolderId) } returns Result.success(testFolder)

        viewModel = createViewModel()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertNull(state.expiryDays)
        }
    }

    @Test
    fun `onExpiryChanged sets expiry days`() = runTest {
        coEvery { folderRepository.getFolder(testFolderId) } returns Result.success(testFolder)

        viewModel = createViewModel()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.onExpiryChanged(14)

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals(14, state.expiryDays)
        }
    }

    @Test
    fun `onExpiryChanged with null clears expiry`() = runTest {
        coEvery { folderRepository.getFolder(testFolderId) } returns Result.success(testFolder)

        viewModel = createViewModel()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.onExpiryChanged(30)
        viewModel.onExpiryChanged(null)

        viewModel.uiState.test {
            val state = awaitItem()
            assertNull(state.expiryDays)
        }
    }

    // ==================== Share Folder Tests ====================

    @Test
    fun `shareFolder success updates state`() = runTest {
        coEvery { folderRepository.getFolder(testFolderId) } returns Result.success(testFolder)
        coEvery {
            shareRepository.shareFolder(
                folderId = testFolderId,
                grantee = testUser,
                permission = SharePermission.READ,
                recursive = true,
                expiresAt = any()
            )
        } returns Result.success(testShare)

        viewModel = createViewModel()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.onUserSelected(testUser)
        viewModel.shareFolder()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertTrue(state.shareSuccess)
            assertFalse(state.isSharing)
            assertNull(state.error)
        }
    }

    @Test
    fun `shareFolder passes correct permission and recursive params`() = runTest {
        coEvery { folderRepository.getFolder(testFolderId) } returns Result.success(testFolder)
        coEvery {
            shareRepository.shareFolder(
                folderId = testFolderId,
                grantee = testUser,
                permission = SharePermission.WRITE,
                recursive = false,
                expiresAt = any()
            )
        } returns Result.success(testShare.copy(permission = SharePermission.WRITE, recursive = false))

        viewModel = createViewModel()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.onUserSelected(testUser)
        viewModel.onPermissionSelected(SharePermission.WRITE)
        viewModel.onRecursiveChanged(false)
        viewModel.onExpiryChanged(7)
        viewModel.shareFolder()
        testDispatcher.scheduler.advanceUntilIdle()

        coVerify {
            shareRepository.shareFolder(
                folderId = testFolderId,
                grantee = testUser,
                permission = SharePermission.WRITE,
                recursive = false,
                expiresAt = any()
            )
        }
    }

    @Test
    fun `shareFolder without expiry passes null expiresAt`() = runTest {
        coEvery { folderRepository.getFolder(testFolderId) } returns Result.success(testFolder)
        coEvery {
            shareRepository.shareFolder(
                folderId = testFolderId,
                grantee = testUser,
                permission = SharePermission.READ,
                recursive = true,
                expiresAt = null
            )
        } returns Result.success(testShare)

        viewModel = createViewModel()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.onUserSelected(testUser)
        viewModel.shareFolder()
        testDispatcher.scheduler.advanceUntilIdle()

        coVerify {
            shareRepository.shareFolder(
                folderId = testFolderId,
                grantee = testUser,
                permission = SharePermission.READ,
                recursive = true,
                expiresAt = null
            )
        }
    }

    @Test
    fun `shareFolder error updates state with error message`() = runTest {
        coEvery { folderRepository.getFolder(testFolderId) } returns Result.success(testFolder)
        coEvery {
            shareRepository.shareFolder(
                folderId = testFolderId,
                grantee = testUser,
                permission = SharePermission.READ,
                recursive = true,
                expiresAt = any()
            )
        } returns Result.error(AppException.Forbidden("No permission to share"))

        viewModel = createViewModel()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.onUserSelected(testUser)
        viewModel.shareFolder()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertFalse(state.shareSuccess)
            assertFalse(state.isSharing)
            assertEquals("No permission to share", state.error)
        }
    }

    @Test
    fun `shareFolder without selected user does nothing`() = runTest {
        coEvery { folderRepository.getFolder(testFolderId) } returns Result.success(testFolder)

        viewModel = createViewModel()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.shareFolder()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertFalse(state.isSharing)
            assertFalse(state.shareSuccess)
        }

        coVerify(exactly = 0) {
            shareRepository.shareFolder(
                folderId = any(),
                grantee = any(),
                permission = any(),
                recursive = any(),
                expiresAt = any()
            )
        }
    }

    @Test
    fun `shareFolder sets isSharing while in progress`() = runTest {
        coEvery { folderRepository.getFolder(testFolderId) } returns Result.success(testFolder)
        coEvery {
            shareRepository.shareFolder(
                folderId = testFolderId,
                grantee = testUser,
                permission = SharePermission.READ,
                recursive = true,
                expiresAt = any()
            )
        } returns Result.success(testShare)

        viewModel = createViewModel()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.onUserSelected(testUser)

        viewModel.uiState.test {
            skipItems(1)

            viewModel.shareFolder()

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
        coEvery { folderRepository.getFolder(testFolderId) } returns Result.error(
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
