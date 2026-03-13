package my.ssdid.drive.presentation.recovery

import app.cash.turbine.test
import my.ssdid.drive.data.remote.dto.CompleteRecoveryResponse
import my.ssdid.drive.data.remote.dto.RecoveryStatusResponse
import my.ssdid.drive.data.remote.dto.ServerShareResponse
import my.ssdid.drive.domain.repository.RecoveryRepository
import io.mockk.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

/**
 * Unit tests for Recovery ViewModels:
 * - RecoverySetupViewModel
 * - RecoveryShareViewModel
 * - CompleteRecoveryViewModel
 *
 * Tests cover:
 * - Status loading and setup/delete operations
 * - Server share fetching
 * - Recovery completion flow
 * - Error handling
 */
@OptIn(ExperimentalCoroutinesApi::class)
class RecoveryViewModelTest {

    private lateinit var recoveryRepository: RecoveryRepository
    private val testDispatcher = StandardTestDispatcher()

    @Before
    fun setup() {
        Dispatchers.setMain(testDispatcher)
        recoveryRepository = mockk(relaxed = true)
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
        unmockkAll()
    }

    // ==================== RecoverySetupViewModel Tests ====================

    @Test
    fun `RecoverySetupViewModel loadStatus sets active status`() = runTest {
        val status = RecoveryStatusResponse(isActive = true, createdAt = "2024-01-01T00:00:00Z")
        coEvery { recoveryRepository.getStatus() } returns Result.success(status)

        val viewModel = RecoverySetupViewModel(recoveryRepository)
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals(status, state.status)
            assertTrue(state.isSetupComplete)
            assertFalse(state.isLoading)
            assertNull(state.error)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `RecoverySetupViewModel loadStatus sets inactive status`() = runTest {
        val status = RecoveryStatusResponse(isActive = false, createdAt = null)
        coEvery { recoveryRepository.getStatus() } returns Result.success(status)

        val viewModel = RecoverySetupViewModel(recoveryRepository)
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals(status, state.status)
            assertFalse(state.isSetupComplete)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `RecoverySetupViewModel loadStatus failure sets error`() = runTest {
        coEvery { recoveryRepository.getStatus() } returns Result.failure(Exception("Network error"))

        val viewModel = RecoverySetupViewModel(recoveryRepository)
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals("Network error", state.error)
            assertFalse(state.isLoading)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `RecoverySetupViewModel setupRecovery success sets isSetupComplete`() = runTest {
        coEvery { recoveryRepository.getStatus() } returns Result.success(
            RecoveryStatusResponse(isActive = false, createdAt = null)
        )
        coEvery { recoveryRepository.setupRecovery(any(), any()) } returns Result.success(Unit)

        val viewModel = RecoverySetupViewModel(recoveryRepository)
        advanceUntilIdle()

        viewModel.setupRecovery("server_share", "key_proof")
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertTrue(state.isSetupComplete)
            assertFalse(state.isLoading)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `RecoverySetupViewModel setupRecovery failure sets error`() = runTest {
        coEvery { recoveryRepository.getStatus() } returns Result.success(
            RecoveryStatusResponse(isActive = false, createdAt = null)
        )
        coEvery { recoveryRepository.setupRecovery(any(), any()) } returns Result.failure(
            Exception("Setup failed: 422")
        )

        val viewModel = RecoverySetupViewModel(recoveryRepository)
        advanceUntilIdle()

        viewModel.setupRecovery("share", "proof")
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals("Setup failed: 422", state.error)
            assertFalse(state.isSetupComplete)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `RecoverySetupViewModel deleteSetup success clears status`() = runTest {
        coEvery { recoveryRepository.getStatus() } returns Result.success(
            RecoveryStatusResponse(isActive = true, createdAt = "2024-01-01T00:00:00Z")
        )
        coEvery { recoveryRepository.deleteSetup() } returns Result.success(Unit)

        val viewModel = RecoverySetupViewModel(recoveryRepository)
        advanceUntilIdle()

        viewModel.deleteSetup()
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertNull(state.status)
            assertFalse(state.isSetupComplete)
            assertFalse(state.isLoading)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `RecoverySetupViewModel deleteSetup failure sets error`() = runTest {
        coEvery { recoveryRepository.getStatus() } returns Result.success(
            RecoveryStatusResponse(isActive = true, createdAt = "2024-01-01T00:00:00Z")
        )
        coEvery { recoveryRepository.deleteSetup() } returns Result.failure(
            Exception("Delete failed: 404")
        )

        val viewModel = RecoverySetupViewModel(recoveryRepository)
        advanceUntilIdle()

        viewModel.deleteSetup()
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals("Delete failed: 404", state.error)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `RecoverySetupViewModel clearError clears error`() = runTest {
        coEvery { recoveryRepository.getStatus() } returns Result.failure(Exception("Error"))

        val viewModel = RecoverySetupViewModel(recoveryRepository)
        advanceUntilIdle()

        viewModel.clearError()

        viewModel.uiState.test {
            val state = awaitItem()
            assertNull(state.error)
            cancelAndIgnoreRemainingEvents()
        }
    }

    // ==================== RecoveryShareViewModel Tests ====================

    @Test
    fun `RecoveryShareViewModel fetchServerShare returns share on success`() = runTest {
        val share = ServerShareResponse(serverShare = "share_data", shareIndex = 1)
        coEvery { recoveryRepository.getServerShare("did:example:123") } returns Result.success(share)

        val viewModel = RecoveryShareViewModel(recoveryRepository)
        viewModel.fetchServerShare("did:example:123")
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals(share, state.serverShare)
            assertFalse(state.isLoading)
            assertNull(state.error)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `RecoveryShareViewModel fetchServerShare failure sets error`() = runTest {
        coEvery { recoveryRepository.getServerShare(any()) } returns Result.failure(
            Exception("Share retrieval failed: 404")
        )

        val viewModel = RecoveryShareViewModel(recoveryRepository)
        viewModel.fetchServerShare("did:example:missing")
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertNull(state.serverShare)
            assertEquals("Share retrieval failed: 404", state.error)
            assertFalse(state.isLoading)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `RecoveryShareViewModel clearError clears error`() = runTest {
        coEvery { recoveryRepository.getServerShare(any()) } returns Result.failure(
            Exception("Error")
        )

        val viewModel = RecoveryShareViewModel(recoveryRepository)
        viewModel.fetchServerShare("did:x")
        advanceUntilIdle()

        viewModel.clearError()

        viewModel.uiState.test {
            val state = awaitItem()
            assertNull(state.error)
            cancelAndIgnoreRemainingEvents()
        }
    }

    // ==================== CompleteRecoveryViewModel Tests ====================

    @Test
    fun `CompleteRecoveryViewModel completeRecovery success sets result and isComplete`() = runTest {
        val response = CompleteRecoveryResponse(token = "new_token", userId = "user-123")
        coEvery { recoveryRepository.completeRecovery(any(), any(), any(), any()) } returns Result.success(response)

        val viewModel = CompleteRecoveryViewModel(recoveryRepository)
        viewModel.completeRecovery("old_did", "new_did", "key_proof", "kem_pk")
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals(response, state.result)
            assertTrue(state.isComplete)
            assertFalse(state.isLoading)
            assertNull(state.error)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `CompleteRecoveryViewModel completeRecovery failure sets error`() = runTest {
        coEvery { recoveryRepository.completeRecovery(any(), any(), any(), any()) } returns Result.failure(
            Exception("Recovery failed: 422")
        )

        val viewModel = CompleteRecoveryViewModel(recoveryRepository)
        viewModel.completeRecovery("old", "new", "proof", "kemkey")
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertNull(state.result)
            assertFalse(state.isComplete)
            assertEquals("Recovery failed: 422", state.error)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `CompleteRecoveryViewModel clearError clears error`() = runTest {
        coEvery { recoveryRepository.completeRecovery(any(), any(), any(), any()) } returns Result.failure(
            Exception("Error")
        )

        val viewModel = CompleteRecoveryViewModel(recoveryRepository)
        viewModel.completeRecovery("o", "n", "p", "k")
        advanceUntilIdle()

        viewModel.clearError()

        viewModel.uiState.test {
            val state = awaitItem()
            assertNull(state.error)
            cancelAndIgnoreRemainingEvents()
        }
    }
}
