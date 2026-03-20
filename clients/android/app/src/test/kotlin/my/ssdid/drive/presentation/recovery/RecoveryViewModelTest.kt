package my.ssdid.drive.presentation.recovery

import app.cash.turbine.test
import my.ssdid.drive.data.remote.dto.ApproveRequestResponse
import my.ssdid.drive.data.remote.dto.CompleteRecoveryResponse
import my.ssdid.drive.data.remote.dto.ListTrusteesResponse
import my.ssdid.drive.data.remote.dto.MyRecoveryRequestData
import my.ssdid.drive.data.remote.dto.MyRecoveryRequestResponse
import my.ssdid.drive.data.remote.dto.PendingRecoveryRequestDto
import my.ssdid.drive.data.remote.dto.PendingRequestsResponse
import my.ssdid.drive.data.remote.dto.RecoveryRequestResponse
import my.ssdid.drive.data.remote.dto.RecoveryStatusResponse
import my.ssdid.drive.data.remote.dto.RejectRequestResponse
import my.ssdid.drive.data.remote.dto.ReleasedShareDto
import my.ssdid.drive.data.remote.dto.ReleasedSharesResponse
import my.ssdid.drive.data.remote.dto.ServerShareResponse
import my.ssdid.drive.data.remote.dto.SetupTrusteesRequest
import my.ssdid.drive.data.remote.dto.SetupTrusteesResponse
import my.ssdid.drive.data.remote.dto.TrusteeDto
import my.ssdid.drive.data.remote.dto.TrusteeShareEntry
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

    // ==================== TrusteeSetupViewModel Tests ====================

    @Test
    fun `TrusteeSetupViewModel init loads trustees`() = runTest {
        val trustee = TrusteeDto("t-1", "user-1", "Alice", "alice@example.com", 1, "2024-01-01T00:00:00Z")
        coEvery { recoveryRepository.getTrustees() } returns Result.success(
            ListTrusteesResponse(listOf(trustee), 2)
        )

        val viewModel = TrusteeSetupViewModel(recoveryRepository)
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals(1, state.trustees.size)
            assertEquals(2, state.threshold)
            assertFalse(state.isLoading)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `TrusteeSetupViewModel setupTrustees success sets isSetupComplete`() = runTest {
        coEvery { recoveryRepository.getTrustees() } returns Result.success(
            ListTrusteesResponse(emptyList(), 0)
        )
        coEvery { recoveryRepository.setupTrustees(any()) } returns Result.success(
            SetupTrusteesResponse(2, 2)
        )

        val viewModel = TrusteeSetupViewModel(recoveryRepository)
        advanceUntilIdle()

        val shares = listOf(TrusteeShareEntry("user-1", "enc1", 1), TrusteeShareEntry("user-2", "enc2", 2))
        viewModel.setupTrustees(2, shares)
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertTrue(state.isSetupComplete)
            assertFalse(state.isLoading)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `TrusteeSetupViewModel setupTrustees failure sets error`() = runTest {
        coEvery { recoveryRepository.getTrustees() } returns Result.success(
            ListTrusteesResponse(emptyList(), 0)
        )
        coEvery { recoveryRepository.setupTrustees(any()) } returns Result.failure(
            Exception("Trustee setup failed: 400")
        )

        val viewModel = TrusteeSetupViewModel(recoveryRepository)
        advanceUntilIdle()

        viewModel.setupTrustees(2, emptyList())
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals("Trustee setup failed: 400", state.error)
            assertFalse(state.isSetupComplete)
            cancelAndIgnoreRemainingEvents()
        }
    }

    // ==================== InitiateRecoveryViewModel Tests ====================

    @Test
    fun `InitiateRecoveryViewModel init checks status — no active request`() = runTest {
        coEvery { recoveryRepository.getMyRecoveryRequest() } returns Result.success(
            MyRecoveryRequestResponse(null)
        )

        val viewModel = InitiateRecoveryViewModel(recoveryRepository)
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertNull(state.activeRequest)
            assertFalse(state.isInitiated)
            assertFalse(state.isLoading)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `InitiateRecoveryViewModel initiateRecovery success sets isInitiated`() = runTest {
        coEvery { recoveryRepository.getMyRecoveryRequest() } returns Result.success(
            MyRecoveryRequestResponse(null)
        ) andThen Result.success(
            MyRecoveryRequestResponse(
                MyRecoveryRequestData("req-1", "pending", 0, 2, "2024-01-03T00:00:00Z", "2024-01-01T00:00:00Z")
            )
        )
        coEvery { recoveryRepository.initiateRecoveryRequest() } returns Result.success(
            RecoveryRequestResponse("req-1", "pending", 2, "2024-01-03T00:00:00Z")
        )

        val viewModel = InitiateRecoveryViewModel(recoveryRepository)
        advanceUntilIdle()

        viewModel.initiateRecovery()
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertTrue(state.isInitiated)
            assertFalse(state.isLoading)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `InitiateRecoveryViewModel initiateRecovery failure sets error`() = runTest {
        coEvery { recoveryRepository.getMyRecoveryRequest() } returns Result.success(
            MyRecoveryRequestResponse(null)
        )
        coEvery { recoveryRepository.initiateRecoveryRequest() } returns Result.failure(
            Exception("Initiate recovery failed: 404")
        )

        val viewModel = InitiateRecoveryViewModel(recoveryRepository)
        advanceUntilIdle()

        viewModel.initiateRecovery()
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals("Initiate recovery failed: 404", state.error)
            cancelAndIgnoreRemainingEvents()
        }
    }

    // ==================== PendingRecoveryRequestsViewModel Tests ====================

    @Test
    fun `PendingRecoveryRequestsViewModel loads pending requests on init`() = runTest {
        val request = PendingRecoveryRequestDto(
            "req-1", "Bob", "bob@example.com", "pending", 0, 2,
            "2024-01-03T00:00:00Z", "2024-01-01T00:00:00Z"
        )
        coEvery { recoveryRepository.getPendingRecoveryRequests() } returns Result.success(
            PendingRequestsResponse(listOf(request))
        )

        val viewModel = PendingRecoveryRequestsViewModel(recoveryRepository)
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals(1, state.requests.size)
            assertEquals("Bob", state.requests[0].requesterName)
            assertFalse(state.isLoading)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `PendingRecoveryRequestsViewModel approveRequest removes from list`() = runTest {
        val request = PendingRecoveryRequestDto(
            "req-1", "Bob", "bob@example.com", "pending", 0, 2,
            "2024-01-03T00:00:00Z", "2024-01-01T00:00:00Z"
        )
        coEvery { recoveryRepository.getPendingRecoveryRequests() } returns Result.success(
            PendingRequestsResponse(listOf(request))
        )
        coEvery { recoveryRepository.approveRecoveryRequest("req-1") } returns Result.success(
            ApproveRequestResponse("req-1", "pending", 1, 2)
        )

        val viewModel = PendingRecoveryRequestsViewModel(recoveryRepository)
        advanceUntilIdle()

        viewModel.approveRequest("req-1")
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertTrue(state.requests.isEmpty())
            assertNull(state.processingId)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `PendingRecoveryRequestsViewModel rejectRequest removes from list`() = runTest {
        val request = PendingRecoveryRequestDto(
            "req-1", "Carol", "carol@example.com", "pending", 0, 2,
            "2024-01-03T00:00:00Z", "2024-01-01T00:00:00Z"
        )
        coEvery { recoveryRepository.getPendingRecoveryRequests() } returns Result.success(
            PendingRequestsResponse(listOf(request))
        )
        coEvery { recoveryRepository.rejectRecoveryRequest("req-1") } returns Result.success(
            RejectRequestResponse("req-1", "pending", "rejected")
        )

        val viewModel = PendingRecoveryRequestsViewModel(recoveryRepository)
        advanceUntilIdle()

        viewModel.rejectRequest("req-1")
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertTrue(state.requests.isEmpty())
            assertNull(state.processingId)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `PendingRecoveryRequestsViewModel approve failure sets error`() = runTest {
        val request = PendingRecoveryRequestDto(
            "req-1", "Dave", "dave@example.com", "pending", 0, 2,
            "2024-01-03T00:00:00Z", "2024-01-01T00:00:00Z"
        )
        coEvery { recoveryRepository.getPendingRecoveryRequests() } returns Result.success(
            PendingRequestsResponse(listOf(request))
        )
        coEvery { recoveryRepository.approveRecoveryRequest("req-1") } returns Result.failure(
            Exception("Approve request failed: 403")
        )

        val viewModel = PendingRecoveryRequestsViewModel(recoveryRepository)
        advanceUntilIdle()

        viewModel.approveRequest("req-1")
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals("Approve request failed: 403", state.error)
            assertNull(state.processingId)
            // Request still in list since approve failed
            assertEquals(1, state.requests.size)
            cancelAndIgnoreRemainingEvents()
        }
    }
}
