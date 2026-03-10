package my.ssdid.drive.presentation.sharing

import app.cash.turbine.test
import my.ssdid.drive.domain.model.ResourceType
import my.ssdid.drive.domain.model.Share
import my.ssdid.drive.domain.model.SharePermission
import my.ssdid.drive.domain.model.User
import my.ssdid.drive.domain.repository.ShareRepository
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
 * Unit tests for SharesViewModel.
 *
 * Tests cover:
 * - Loading received shares
 * - Loading created shares
 * - Revoking shares
 * - Error handling for all operations
 */
@OptIn(ExperimentalCoroutinesApi::class)
class SharesViewModelTest {

    private lateinit var shareRepository: ShareRepository
    private lateinit var viewModel: SharesViewModel
    private val testDispatcher = StandardTestDispatcher()

    private val testGrantor = User(
        id = "user-grantor",
        email = "owner@example.com",
        displayName = "Owner"
    )

    private val testGrantee = User(
        id = "user-grantee",
        email = "alice@example.com",
        displayName = "Alice"
    )

    private val receivedShare1 = Share(
        id = "share-r1",
        grantorId = testGrantor.id,
        granteeId = testGrantee.id,
        resourceType = ResourceType.FILE,
        resourceId = "file-001",
        permission = SharePermission.READ,
        recursive = false,
        expiresAt = null,
        revokedAt = null,
        grantor = testGrantor,
        grantee = testGrantee,
        createdAt = Instant.parse("2025-01-01T00:00:00Z"),
        updatedAt = Instant.parse("2025-01-01T00:00:00Z")
    )

    private val receivedShare2 = Share(
        id = "share-r2",
        grantorId = testGrantor.id,
        granteeId = testGrantee.id,
        resourceType = ResourceType.FOLDER,
        resourceId = "folder-001",
        permission = SharePermission.WRITE,
        recursive = true,
        expiresAt = Instant.parse("2025-12-31T23:59:59Z"),
        revokedAt = null,
        grantor = testGrantor,
        grantee = testGrantee,
        createdAt = Instant.parse("2025-01-01T00:00:00Z"),
        updatedAt = Instant.parse("2025-01-01T00:00:00Z")
    )

    private val createdShare1 = Share(
        id = "share-c1",
        grantorId = testGrantee.id,
        granteeId = testGrantor.id,
        resourceType = ResourceType.FILE,
        resourceId = "file-002",
        permission = SharePermission.READ,
        recursive = false,
        expiresAt = null,
        revokedAt = null,
        grantor = testGrantee,
        grantee = testGrantor,
        createdAt = Instant.parse("2025-02-01T00:00:00Z"),
        updatedAt = Instant.parse("2025-02-01T00:00:00Z")
    )

    private val createdShare2 = Share(
        id = "share-c2",
        grantorId = testGrantee.id,
        granteeId = testGrantor.id,
        resourceType = ResourceType.FOLDER,
        resourceId = "folder-002",
        permission = SharePermission.ADMIN,
        recursive = true,
        expiresAt = null,
        revokedAt = null,
        grantor = testGrantee,
        grantee = testGrantor,
        createdAt = Instant.parse("2025-02-01T00:00:00Z"),
        updatedAt = Instant.parse("2025-02-01T00:00:00Z")
    )

    @Before
    fun setup() {
        Dispatchers.setMain(testDispatcher)
        shareRepository = mockk()
        viewModel = SharesViewModel(shareRepository)
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
            assertTrue(state.receivedShares.isEmpty())
            assertTrue(state.createdShares.isEmpty())
            assertFalse(state.isLoading)
            assertNull(state.error)
        }
    }

    // ==================== Load Received Shares Tests ====================

    @Test
    fun `loadReceivedShares success updates state`() = runTest {
        val shares = listOf(receivedShare1, receivedShare2)
        coEvery { shareRepository.getReceivedShares() } returns Result.Success(shares)

        viewModel.uiState.test {
            skipItems(1) // Initial state

            viewModel.loadReceivedShares()

            val loadingState = awaitItem()
            assertTrue(loadingState.isLoading)
            assertNull(loadingState.error)

            testDispatcher.scheduler.advanceUntilIdle()

            val loadedState = awaitItem()
            assertFalse(loadedState.isLoading)
            assertEquals(2, loadedState.receivedShares.size)
            assertEquals(receivedShare1, loadedState.receivedShares[0])
            assertEquals(receivedShare2, loadedState.receivedShares[1])
        }
    }

    @Test
    fun `loadReceivedShares success with empty list`() = runTest {
        coEvery { shareRepository.getReceivedShares() } returns Result.Success(emptyList())

        viewModel.loadReceivedShares()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertTrue(state.receivedShares.isEmpty())
            assertFalse(state.isLoading)
            assertNull(state.error)
        }
    }

    @Test
    fun `loadReceivedShares error shows error message`() = runTest {
        coEvery { shareRepository.getReceivedShares() } returns Result.Error(
            AppException.Network("Connection failed")
        )

        viewModel.uiState.test {
            skipItems(1)

            viewModel.loadReceivedShares()

            val loadingState = awaitItem()
            assertTrue(loadingState.isLoading)

            testDispatcher.scheduler.advanceUntilIdle()

            val errorState = awaitItem()
            assertFalse(errorState.isLoading)
            assertEquals("Connection failed", errorState.error)
            assertTrue(errorState.receivedShares.isEmpty())
        }
    }

    @Test
    fun `loadReceivedShares error preserves existing created shares`() = runTest {
        val createdShares = listOf(createdShare1)
        coEvery { shareRepository.getCreatedShares() } returns Result.Success(createdShares)
        coEvery { shareRepository.getReceivedShares() } returns Result.Error(
            AppException.Network("Timeout")
        )

        // First load created shares
        viewModel.loadCreatedShares()
        testDispatcher.scheduler.advanceUntilIdle()

        // Then fail to load received shares
        viewModel.loadReceivedShares()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            // Created shares should still be there
            assertEquals(1, state.createdShares.size)
            assertEquals(createdShare1, state.createdShares.first())
        }
    }

    // ==================== Load Created Shares Tests ====================

    @Test
    fun `loadCreatedShares success updates state`() = runTest {
        val shares = listOf(createdShare1, createdShare2)
        coEvery { shareRepository.getCreatedShares() } returns Result.Success(shares)

        viewModel.uiState.test {
            skipItems(1)

            viewModel.loadCreatedShares()

            val loadingState = awaitItem()
            assertTrue(loadingState.isLoading)

            testDispatcher.scheduler.advanceUntilIdle()

            val loadedState = awaitItem()
            assertFalse(loadedState.isLoading)
            assertEquals(2, loadedState.createdShares.size)
            assertEquals(createdShare1, loadedState.createdShares[0])
            assertEquals(createdShare2, loadedState.createdShares[1])
        }
    }

    @Test
    fun `loadCreatedShares success with empty list`() = runTest {
        coEvery { shareRepository.getCreatedShares() } returns Result.Success(emptyList())

        viewModel.loadCreatedShares()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertTrue(state.createdShares.isEmpty())
            assertFalse(state.isLoading)
            assertNull(state.error)
        }
    }

    @Test
    fun `loadCreatedShares error shows error message`() = runTest {
        coEvery { shareRepository.getCreatedShares() } returns Result.Error(
            AppException.Unauthorized("Session expired")
        )

        viewModel.uiState.test {
            skipItems(1)

            viewModel.loadCreatedShares()

            val loadingState = awaitItem()
            assertTrue(loadingState.isLoading)

            testDispatcher.scheduler.advanceUntilIdle()

            val errorState = awaitItem()
            assertFalse(errorState.isLoading)
            assertEquals("Session expired", errorState.error)
        }
    }

    @Test
    fun `loadCreatedShares error preserves existing received shares`() = runTest {
        val receivedShares = listOf(receivedShare1)
        coEvery { shareRepository.getReceivedShares() } returns Result.Success(receivedShares)
        coEvery { shareRepository.getCreatedShares() } returns Result.Error(
            AppException.Unknown("Server error")
        )

        // First load received shares
        viewModel.loadReceivedShares()
        testDispatcher.scheduler.advanceUntilIdle()

        // Then fail to load created shares
        viewModel.loadCreatedShares()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals(1, state.receivedShares.size)
            assertEquals(receivedShare1, state.receivedShares.first())
        }
    }

    // ==================== Revoke Share Tests ====================

    @Test
    fun `revokeShare success removes share from created list`() = runTest {
        val shares = listOf(createdShare1, createdShare2)
        coEvery { shareRepository.getCreatedShares() } returns Result.Success(shares)
        coEvery { shareRepository.revokeShare(createdShare1.id) } returns Result.Success(Unit)

        // Load created shares first
        viewModel.loadCreatedShares()
        testDispatcher.scheduler.advanceUntilIdle()

        // Revoke one
        viewModel.revokeShare(createdShare1.id)
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals(1, state.createdShares.size)
            assertEquals(createdShare2, state.createdShares.first())
            assertNull(state.error)
        }
    }

    @Test
    fun `revokeShare success with last share results in empty list`() = runTest {
        coEvery { shareRepository.getCreatedShares() } returns Result.Success(listOf(createdShare1))
        coEvery { shareRepository.revokeShare(createdShare1.id) } returns Result.Success(Unit)

        viewModel.loadCreatedShares()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.revokeShare(createdShare1.id)
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertTrue(state.createdShares.isEmpty())
        }
    }

    @Test
    fun `revokeShare error shows error message`() = runTest {
        val shares = listOf(createdShare1, createdShare2)
        coEvery { shareRepository.getCreatedShares() } returns Result.Success(shares)
        coEvery { shareRepository.revokeShare(createdShare1.id) } returns Result.Error(
            AppException.Forbidden("Cannot revoke this share")
        )

        viewModel.loadCreatedShares()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.revokeShare(createdShare1.id)
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals("Cannot revoke this share", state.error)
            // Shares list should remain unchanged
            assertEquals(2, state.createdShares.size)
        }
    }

    @Test
    fun `revokeShare error does not remove share from list`() = runTest {
        coEvery { shareRepository.getCreatedShares() } returns Result.Success(listOf(createdShare1))
        coEvery { shareRepository.revokeShare(createdShare1.id) } returns Result.Error(
            AppException.Network("No connection")
        )

        viewModel.loadCreatedShares()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.revokeShare(createdShare1.id)
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals(1, state.createdShares.size)
            assertEquals(createdShare1, state.createdShares.first())
        }
    }

    @Test
    fun `revokeShare with nonexistent id does not modify list`() = runTest {
        coEvery { shareRepository.getCreatedShares() } returns Result.Success(listOf(createdShare1))
        coEvery { shareRepository.revokeShare("nonexistent") } returns Result.Success(Unit)

        viewModel.loadCreatedShares()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.revokeShare("nonexistent")
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            // Original share should still be present since filter didn't match
            assertEquals(1, state.createdShares.size)
        }
    }

    // ==================== Sequential Operations Tests ====================

    @Test
    fun `loading received then created shares maintains both`() = runTest {
        coEvery { shareRepository.getReceivedShares() } returns Result.Success(listOf(receivedShare1))
        coEvery { shareRepository.getCreatedShares() } returns Result.Success(listOf(createdShare1))

        viewModel.loadReceivedShares()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.loadCreatedShares()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals(1, state.receivedShares.size)
            assertEquals(1, state.createdShares.size)
            assertFalse(state.isLoading)
            assertNull(state.error)
        }
    }

    @Test
    fun `multiple loadReceivedShares calls replace previous data`() = runTest {
        coEvery { shareRepository.getReceivedShares() } returns Result.Success(listOf(receivedShare1))

        viewModel.loadReceivedShares()
        testDispatcher.scheduler.advanceUntilIdle()

        // Second load with different data
        coEvery { shareRepository.getReceivedShares() } returns Result.Success(
            listOf(receivedShare1, receivedShare2)
        )

        viewModel.loadReceivedShares()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals(2, state.receivedShares.size)
        }
    }

    @Test
    fun `error from one operation clears on successful next operation`() = runTest {
        // First call errors
        coEvery { shareRepository.getReceivedShares() } returns Result.Error(
            AppException.Network("Failed")
        )

        viewModel.loadReceivedShares()
        testDispatcher.scheduler.advanceUntilIdle()

        // Verify error
        viewModel.uiState.test {
            val errorState = awaitItem()
            assertNotNull(errorState.error)
        }

        // Second call succeeds and clears error
        coEvery { shareRepository.getCreatedShares() } returns Result.Success(listOf(createdShare1))

        viewModel.loadCreatedShares()
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            // error should be null because loadCreatedShares sets error = null at start
            assertNull(state.error)
            assertEquals(1, state.createdShares.size)
        }
    }
}
