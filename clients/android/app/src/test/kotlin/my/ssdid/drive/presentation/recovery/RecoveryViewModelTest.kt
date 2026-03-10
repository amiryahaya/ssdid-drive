package my.ssdid.drive.presentation.recovery

import app.cash.turbine.test
import my.ssdid.drive.domain.model.RecoveryApproval
import my.ssdid.drive.domain.model.RecoveryConfig
import my.ssdid.drive.domain.model.RecoveryConfigStatus
import my.ssdid.drive.domain.model.RecoveryProgress
import my.ssdid.drive.domain.model.RecoveryRequest
import my.ssdid.drive.domain.model.RecoveryRequestStatus
import my.ssdid.drive.domain.model.RecoveryShare
import my.ssdid.drive.domain.model.RecoveryShareStatus
import my.ssdid.drive.domain.model.User
import my.ssdid.drive.domain.repository.RecoveryRepository
import my.ssdid.drive.domain.repository.TenantRepository
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
 * Unit tests for Recovery ViewModels:
 * - RecoverySetupViewModel
 * - TrusteeSelectionViewModel
 * - TrusteeSharesViewModel
 * - RecoveryRequestViewModel
 *
 * Tests cover:
 * - Recovery config loading
 * - Setup and disable recovery
 * - Trustee selection and share distribution
 * - Accepting/rejecting shares
 * - Approving recovery requests
 * - Initiating and completing recovery
 * - Error handling
 */
@OptIn(ExperimentalCoroutinesApi::class)
class RecoveryViewModelTest {

    private lateinit var recoveryRepository: RecoveryRepository
    private lateinit var tenantRepository: TenantRepository
    private val testDispatcher = StandardTestDispatcher()

    private val now = Instant.now()

    private val testUser = User(
        id = "user-1",
        email = "user@example.com",
        displayName = "Test User"
    )

    private val trusteeUser = User(
        id = "trustee-1",
        email = "trustee@example.com",
        displayName = "Trustee User"
    )

    private val activeConfig = RecoveryConfig(
        id = "config-1",
        userId = "user-1",
        threshold = 2,
        totalShares = 3,
        status = RecoveryConfigStatus.ACTIVE,
        createdAt = now,
        updatedAt = now
    )

    private val pendingConfig = RecoveryConfig(
        id = "config-2",
        userId = "user-1",
        threshold = 2,
        totalShares = 3,
        status = RecoveryConfigStatus.PENDING,
        createdAt = now,
        updatedAt = now
    )

    private val pendingShare = RecoveryShare(
        id = "share-1",
        configId = "config-1",
        grantorId = "user-1",
        trusteeId = "trustee-1",
        shareIndex = 1,
        status = RecoveryShareStatus.PENDING,
        grantor = testUser,
        trustee = trusteeUser,
        createdAt = now,
        updatedAt = now
    )

    private val acceptedShare = RecoveryShare(
        id = "share-2",
        configId = "config-1",
        grantorId = "user-1",
        trusteeId = "trustee-1",
        shareIndex = 2,
        status = RecoveryShareStatus.ACCEPTED,
        grantor = testUser,
        trustee = trusteeUser,
        createdAt = now,
        updatedAt = now
    )

    private val pendingRequest = RecoveryRequest(
        id = "request-1",
        userId = "user-1",
        status = RecoveryRequestStatus.PENDING,
        reason = "Lost device",
        user = testUser,
        progress = RecoveryProgress(threshold = 2, approvals = 0, remaining = 2),
        createdAt = now,
        updatedAt = now
    )

    private val approvedRequest = RecoveryRequest(
        id = "request-2",
        userId = "user-1",
        status = RecoveryRequestStatus.APPROVED,
        reason = null,
        user = testUser,
        progress = RecoveryProgress(threshold = 2, approvals = 2, remaining = 0),
        createdAt = now,
        updatedAt = now
    )

    @Before
    fun setup() {
        Dispatchers.setMain(testDispatcher)
        recoveryRepository = mockk(relaxed = true)
        tenantRepository = mockk(relaxed = true)
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    // ==================== RecoverySetupViewModel Tests ====================

    @Test
    fun `RecoverySetupViewModel loadConfig sets active config`() = runTest {
        coEvery { recoveryRepository.getRecoveryConfig() } returns Result.success(activeConfig)

        val viewModel = RecoverySetupViewModel(recoveryRepository)
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals(activeConfig, state.config)
            assertTrue(state.isSetupComplete)
            assertFalse(state.isLoading)
            assertNull(state.error)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `RecoverySetupViewModel loadConfig sets pending config`() = runTest {
        coEvery { recoveryRepository.getRecoveryConfig() } returns Result.success(pendingConfig)

        val viewModel = RecoverySetupViewModel(recoveryRepository)
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals(pendingConfig, state.config)
            assertFalse(state.isSetupComplete)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `RecoverySetupViewModel loadConfig sets null when no config`() = runTest {
        coEvery { recoveryRepository.getRecoveryConfig() } returns Result.success(null)

        val viewModel = RecoverySetupViewModel(recoveryRepository)
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertNull(state.config)
            assertFalse(state.isSetupComplete)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `RecoverySetupViewModel loadConfig error sets error message`() = runTest {
        coEvery { recoveryRepository.getRecoveryConfig() } returns Result.error(
            AppException.Network("Server error")
        )

        val viewModel = RecoverySetupViewModel(recoveryRepository)
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals("Server error", state.error)
            assertFalse(state.isLoading)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `RecoverySetupViewModel setThreshold updates state within bounds`() = runTest {
        coEvery { recoveryRepository.getRecoveryConfig() } returns Result.success(null)

        val viewModel = RecoverySetupViewModel(recoveryRepository)
        advanceUntilIdle()

        viewModel.setThreshold(3)

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals(3, state.threshold)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `RecoverySetupViewModel setThreshold coerces to totalShares maximum`() = runTest {
        coEvery { recoveryRepository.getRecoveryConfig() } returns Result.success(null)

        val viewModel = RecoverySetupViewModel(recoveryRepository)
        advanceUntilIdle()

        // Default totalShares is 3, so threshold of 5 should be coerced to 3
        viewModel.setThreshold(5)

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals(3, state.threshold)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `RecoverySetupViewModel setTotalShares updates state`() = runTest {
        coEvery { recoveryRepository.getRecoveryConfig() } returns Result.success(null)

        val viewModel = RecoverySetupViewModel(recoveryRepository)
        advanceUntilIdle()

        viewModel.setTotalShares(5)

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals(5, state.totalShares)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `RecoverySetupViewModel setupRecovery success sets config and isSetupComplete`() = runTest {
        coEvery { recoveryRepository.getRecoveryConfig() } returns Result.success(null)
        coEvery { recoveryRepository.setupRecovery(2, 3) } returns Result.success(activeConfig)

        val viewModel = RecoverySetupViewModel(recoveryRepository)
        advanceUntilIdle()

        viewModel.setupRecovery()
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals(activeConfig, state.config)
            assertTrue(state.isSetupComplete)
            assertFalse(state.isLoading)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `RecoverySetupViewModel setupRecovery failure sets error`() = runTest {
        coEvery { recoveryRepository.getRecoveryConfig() } returns Result.success(null)
        coEvery { recoveryRepository.setupRecovery(2, 3) } returns Result.error(
            AppException.ValidationError("Invalid threshold")
        )

        val viewModel = RecoverySetupViewModel(recoveryRepository)
        advanceUntilIdle()

        viewModel.setupRecovery()
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals("Invalid threshold", state.error)
            assertFalse(state.isSetupComplete)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `RecoverySetupViewModel disableRecovery success clears config`() = runTest {
        coEvery { recoveryRepository.getRecoveryConfig() } returns Result.success(activeConfig)
        coEvery { recoveryRepository.disableRecovery() } returns Result.success(Unit)

        val viewModel = RecoverySetupViewModel(recoveryRepository)
        advanceUntilIdle()

        viewModel.disableRecovery()
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertNull(state.config)
            assertFalse(state.isSetupComplete)
            assertFalse(state.isLoading)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `RecoverySetupViewModel disableRecovery failure sets error`() = runTest {
        coEvery { recoveryRepository.getRecoveryConfig() } returns Result.success(activeConfig)
        coEvery { recoveryRepository.disableRecovery() } returns Result.error(
            AppException.Forbidden("Cannot disable active recovery")
        )

        val viewModel = RecoverySetupViewModel(recoveryRepository)
        advanceUntilIdle()

        viewModel.disableRecovery()
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals("Cannot disable active recovery", state.error)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `RecoverySetupViewModel clearError clears error`() = runTest {
        coEvery { recoveryRepository.getRecoveryConfig() } returns Result.error(
            AppException.Unknown("Error")
        )

        val viewModel = RecoverySetupViewModel(recoveryRepository)
        advanceUntilIdle()

        viewModel.clearError()

        viewModel.uiState.test {
            val state = awaitItem()
            assertNull(state.error)
            cancelAndIgnoreRemainingEvents()
        }
    }

    // ==================== TrusteeSharesViewModel Tests ====================

    @Test
    fun `TrusteeSharesViewModel loadData separates pending and accepted shares`() = runTest {
        coEvery { recoveryRepository.getTrusteeShares() } returns
            Result.success(listOf(pendingShare, acceptedShare))
        coEvery { recoveryRepository.getPendingApprovalRequests() } returns
            Result.success(listOf(pendingRequest))

        val viewModel = TrusteeSharesViewModel(recoveryRepository)
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals(1, state.pendingShares.size)
            assertEquals("share-1", state.pendingShares[0].id)
            assertEquals(1, state.acceptedShares.size)
            assertEquals("share-2", state.acceptedShares[0].id)
            assertEquals(1, state.pendingApprovals.size)
            assertFalse(state.isLoading)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `TrusteeSharesViewModel loadData handles shares error`() = runTest {
        coEvery { recoveryRepository.getTrusteeShares() } returns Result.error(
            AppException.Network("Network error")
        )
        coEvery { recoveryRepository.getPendingApprovalRequests() } returns Result.success(emptyList())

        val viewModel = TrusteeSharesViewModel(recoveryRepository)
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertNotNull(state.error)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `TrusteeSharesViewModel acceptShare moves share from pending to accepted`() = runTest {
        coEvery { recoveryRepository.getTrusteeShares() } returns
            Result.success(listOf(pendingShare))
        coEvery { recoveryRepository.getPendingApprovalRequests() } returns
            Result.success(emptyList())
        coEvery { recoveryRepository.acceptShare("share-1") } returns
            Result.success(acceptedShare.copy(id = "share-1"))

        val viewModel = TrusteeSharesViewModel(recoveryRepository)
        advanceUntilIdle()

        viewModel.acceptShare("share-1")
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertTrue(state.pendingShares.isEmpty())
            assertEquals(1, state.acceptedShares.size)
            assertFalse(state.isLoading)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `TrusteeSharesViewModel acceptShare error sets error`() = runTest {
        coEvery { recoveryRepository.getTrusteeShares() } returns
            Result.success(listOf(pendingShare))
        coEvery { recoveryRepository.getPendingApprovalRequests() } returns
            Result.success(emptyList())
        coEvery { recoveryRepository.acceptShare("share-1") } returns Result.error(
            AppException.CryptoError("Decryption failed")
        )

        val viewModel = TrusteeSharesViewModel(recoveryRepository)
        advanceUntilIdle()

        viewModel.acceptShare("share-1")
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals("Decryption failed", state.error)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `TrusteeSharesViewModel rejectShare removes from pending`() = runTest {
        coEvery { recoveryRepository.getTrusteeShares() } returns
            Result.success(listOf(pendingShare))
        coEvery { recoveryRepository.getPendingApprovalRequests() } returns
            Result.success(emptyList())
        coEvery { recoveryRepository.rejectShare("share-1") } returns Result.success(Unit)

        val viewModel = TrusteeSharesViewModel(recoveryRepository)
        advanceUntilIdle()

        viewModel.rejectShare("share-1")
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertTrue(state.pendingShares.isEmpty())
            assertFalse(state.isLoading)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `TrusteeSharesViewModel rejectShare error sets error`() = runTest {
        coEvery { recoveryRepository.getTrusteeShares() } returns
            Result.success(listOf(pendingShare))
        coEvery { recoveryRepository.getPendingApprovalRequests() } returns
            Result.success(emptyList())
        coEvery { recoveryRepository.rejectShare("share-1") } returns Result.error(
            AppException.Unknown("Reject failed")
        )

        val viewModel = TrusteeSharesViewModel(recoveryRepository)
        advanceUntilIdle()

        viewModel.rejectShare("share-1")
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals("Reject failed", state.error)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `TrusteeSharesViewModel approveRecovery success reloads data`() = runTest {
        coEvery { recoveryRepository.getTrusteeShares() } returns Result.success(emptyList())
        coEvery { recoveryRepository.getPendingApprovalRequests() } returns
            Result.success(listOf(pendingRequest))
        coEvery { recoveryRepository.approveRecoveryRequest("request-1", "share-1") } returns
            Result.success(
                RecoveryApproval(
                    id = "approval-1",
                    requestId = "request-1",
                    shareId = "share-1",
                    approverId = "trustee-1",
                    createdAt = now
                )
            )

        val viewModel = TrusteeSharesViewModel(recoveryRepository)
        advanceUntilIdle()

        viewModel.approveRecovery("request-1", "share-1")
        advanceUntilIdle()

        // Should call loadData again (at least twice: init + after approve)
        coVerify(atLeast = 2) { recoveryRepository.getTrusteeShares() }
    }

    @Test
    fun `TrusteeSharesViewModel approveRecovery error sets error`() = runTest {
        coEvery { recoveryRepository.getTrusteeShares() } returns Result.success(emptyList())
        coEvery { recoveryRepository.getPendingApprovalRequests() } returns
            Result.success(listOf(pendingRequest))
        coEvery { recoveryRepository.approveRecoveryRequest("request-1", "share-1") } returns
            Result.error(AppException.CryptoError("Re-encryption failed"))

        val viewModel = TrusteeSharesViewModel(recoveryRepository)
        advanceUntilIdle()

        viewModel.approveRecovery("request-1", "share-1")
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals("Re-encryption failed", state.error)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `TrusteeSharesViewModel clearError clears error`() = runTest {
        coEvery { recoveryRepository.getTrusteeShares() } returns Result.error(
            AppException.Unknown("Error")
        )
        coEvery { recoveryRepository.getPendingApprovalRequests() } returns Result.success(emptyList())

        val viewModel = TrusteeSharesViewModel(recoveryRepository)
        advanceUntilIdle()

        viewModel.clearError()

        viewModel.uiState.test {
            val state = awaitItem()
            assertNull(state.error)
            cancelAndIgnoreRemainingEvents()
        }
    }

    // ==================== RecoveryRequestViewModel Tests ====================

    @Test
    fun `RecoveryRequestViewModel loadMyRequests sets requests`() = runTest {
        coEvery { recoveryRepository.getMyRecoveryRequests() } returns
            Result.success(listOf(pendingRequest, approvedRequest))

        val viewModel = RecoveryRequestViewModel(recoveryRepository)
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals(2, state.myRequests.size)
            // Current request should be the pending or approved one
            assertNotNull(state.currentRequest)
            assertFalse(state.isLoading)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `RecoveryRequestViewModel loadMyRequests error sets error`() = runTest {
        coEvery { recoveryRepository.getMyRecoveryRequests() } returns Result.error(
            AppException.Network("No connection")
        )

        val viewModel = RecoveryRequestViewModel(recoveryRepository)
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals("No connection", state.error)
            assertFalse(state.isLoading)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `RecoveryRequestViewModel initiateRecovery success sets request`() = runTest {
        coEvery { recoveryRepository.getMyRecoveryRequests() } returns Result.success(emptyList())
        coEvery { recoveryRepository.initiateRecovery("newpass", "Lost device") } returns
            Result.success(pendingRequest)

        val viewModel = RecoveryRequestViewModel(recoveryRepository)
        advanceUntilIdle()

        viewModel.initiateRecovery("newpass", "Lost device")
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals(pendingRequest, state.currentRequest)
            assertTrue(state.isRequestCreated)
            assertFalse(state.isLoading)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `RecoveryRequestViewModel initiateRecovery failure sets error`() = runTest {
        coEvery { recoveryRepository.getMyRecoveryRequests() } returns Result.success(emptyList())
        coEvery { recoveryRepository.initiateRecovery("pass", null) } returns Result.error(
            AppException.Conflict("Recovery already in progress")
        )

        val viewModel = RecoveryRequestViewModel(recoveryRepository)
        advanceUntilIdle()

        viewModel.initiateRecovery("pass", null)
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals("Recovery already in progress", state.error)
            assertFalse(state.isRequestCreated)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `RecoveryRequestViewModel checkRequestStatus updates current request`() = runTest {
        coEvery { recoveryRepository.getMyRecoveryRequests() } returns Result.success(emptyList())
        coEvery { recoveryRepository.getRecoveryRequest("request-1") } returns
            Result.success(approvedRequest)

        val viewModel = RecoveryRequestViewModel(recoveryRepository)
        advanceUntilIdle()

        viewModel.checkRequestStatus("request-1")
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals(approvedRequest, state.currentRequest)
            assertFalse(state.isLoading)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `RecoveryRequestViewModel checkRequestStatus error sets error`() = runTest {
        coEvery { recoveryRepository.getMyRecoveryRequests() } returns Result.success(emptyList())
        coEvery { recoveryRepository.getRecoveryRequest("request-1") } returns Result.error(
            AppException.NotFound("Request not found")
        )

        val viewModel = RecoveryRequestViewModel(recoveryRepository)
        advanceUntilIdle()

        viewModel.checkRequestStatus("request-1")
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals("Request not found", state.error)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `RecoveryRequestViewModel completeRecovery success sets isRecoveryComplete`() = runTest {
        coEvery { recoveryRepository.getMyRecoveryRequests() } returns Result.success(emptyList())
        coEvery { recoveryRepository.completeRecovery("request-2", "newpass") } returns
            Result.success(Unit)

        val viewModel = RecoveryRequestViewModel(recoveryRepository)
        advanceUntilIdle()

        viewModel.completeRecovery("request-2", "newpass")
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertTrue(state.isRecoveryComplete)
            assertFalse(state.isLoading)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `RecoveryRequestViewModel completeRecovery failure sets error`() = runTest {
        coEvery { recoveryRepository.getMyRecoveryRequests() } returns Result.success(emptyList())
        coEvery { recoveryRepository.completeRecovery("request-2", "pass") } returns Result.error(
            AppException.CryptoError("Insufficient shares")
        )

        val viewModel = RecoveryRequestViewModel(recoveryRepository)
        advanceUntilIdle()

        viewModel.completeRecovery("request-2", "pass")
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals("Insufficient shares", state.error)
            assertFalse(state.isRecoveryComplete)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `RecoveryRequestViewModel cancelRequest success clears current request`() = runTest {
        coEvery { recoveryRepository.getMyRecoveryRequests() } returns
            Result.success(listOf(pendingRequest))
        coEvery { recoveryRepository.cancelRecoveryRequest("request-1") } returns Result.success(Unit)

        val viewModel = RecoveryRequestViewModel(recoveryRepository)
        advanceUntilIdle()

        viewModel.cancelRequest("request-1")
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertNull(state.currentRequest)
            assertFalse(state.isRequestCreated)
            assertFalse(state.isLoading)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `RecoveryRequestViewModel cancelRequest failure sets error`() = runTest {
        coEvery { recoveryRepository.getMyRecoveryRequests() } returns
            Result.success(listOf(pendingRequest))
        coEvery { recoveryRepository.cancelRecoveryRequest("request-1") } returns Result.error(
            AppException.Forbidden("Cannot cancel approved request")
        )

        val viewModel = RecoveryRequestViewModel(recoveryRepository)
        advanceUntilIdle()

        viewModel.cancelRequest("request-1")
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals("Cannot cancel approved request", state.error)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `RecoveryRequestViewModel clearError clears error`() = runTest {
        coEvery { recoveryRepository.getMyRecoveryRequests() } returns Result.error(
            AppException.Unknown("Error")
        )

        val viewModel = RecoveryRequestViewModel(recoveryRepository)
        advanceUntilIdle()

        viewModel.clearError()

        viewModel.uiState.test {
            val state = awaitItem()
            assertNull(state.error)
            cancelAndIgnoreRemainingEvents()
        }
    }

    // ==================== TrusteeSelectionViewModel Tests ====================

    @Test
    fun `TrusteeSelectionViewModel initialize loads users and sets total shares`() = runTest {
        coEvery { tenantRepository.getTenantUsers() } returns
            Result.success(listOf(testUser, trusteeUser))

        val viewModel = TrusteeSelectionViewModel(recoveryRepository, tenantRepository)

        viewModel.initialize(3)
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals(3, state.totalShares)
            assertEquals(2, state.availableUsers.size)
            assertFalse(state.isLoading)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `TrusteeSelectionViewModel initialize error sets error`() = runTest {
        coEvery { tenantRepository.getTenantUsers() } returns Result.error(
            AppException.Network("No connection")
        )

        val viewModel = TrusteeSelectionViewModel(recoveryRepository, tenantRepository)

        viewModel.initialize(3)
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals("No connection", state.error)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `TrusteeSelectionViewModel selectTrustee adds user to selected`() = runTest {
        coEvery { tenantRepository.getTenantUsers() } returns
            Result.success(listOf(testUser, trusteeUser))

        val viewModel = TrusteeSelectionViewModel(recoveryRepository, tenantRepository)
        viewModel.initialize(3)
        advanceUntilIdle()

        viewModel.selectTrustee(trusteeUser)

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals(1, state.selectedTrustees.size)
            assertEquals(trusteeUser, state.selectedTrustees[0])
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `TrusteeSelectionViewModel selectTrustee does not add duplicate`() = runTest {
        coEvery { tenantRepository.getTenantUsers() } returns
            Result.success(listOf(testUser, trusteeUser))

        val viewModel = TrusteeSelectionViewModel(recoveryRepository, tenantRepository)
        viewModel.initialize(3)
        advanceUntilIdle()

        viewModel.selectTrustee(trusteeUser)
        viewModel.selectTrustee(trusteeUser)

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals(1, state.selectedTrustees.size)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `TrusteeSelectionViewModel deselectTrustee removes user from selected`() = runTest {
        coEvery { tenantRepository.getTenantUsers() } returns
            Result.success(listOf(testUser, trusteeUser))

        val viewModel = TrusteeSelectionViewModel(recoveryRepository, tenantRepository)
        viewModel.initialize(3)
        advanceUntilIdle()

        viewModel.selectTrustee(trusteeUser)
        viewModel.deselectTrustee(trusteeUser)

        viewModel.uiState.test {
            val state = awaitItem()
            assertTrue(state.selectedTrustees.isEmpty())
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `TrusteeSelectionViewModel distributeShare success increments index`() = runTest {
        coEvery { tenantRepository.getTenantUsers() } returns
            Result.success(listOf(testUser, trusteeUser))
        coEvery { recoveryRepository.createShare(trusteeUser, 1) } returns
            Result.success(pendingShare)

        val viewModel = TrusteeSelectionViewModel(recoveryRepository, tenantRepository)
        viewModel.initialize(3)
        advanceUntilIdle()

        viewModel.distributeShare(trusteeUser)
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals(1, state.distributedShares.size)
            assertEquals(2, state.currentShareIndex)
            assertFalse(state.isDistributionComplete)
            assertFalse(state.isLoading)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `TrusteeSelectionViewModel distributeShare completes when all shares distributed`() = runTest {
        coEvery { tenantRepository.getTenantUsers() } returns
            Result.success(listOf(testUser, trusteeUser))
        coEvery { recoveryRepository.createShare(any(), any()) } returns
            Result.success(pendingShare)

        val viewModel = TrusteeSelectionViewModel(recoveryRepository, tenantRepository)
        viewModel.initialize(1) // Only 1 share to distribute
        advanceUntilIdle()

        viewModel.distributeShare(trusteeUser)
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertTrue(state.isDistributionComplete)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `TrusteeSelectionViewModel distributeShare error sets error`() = runTest {
        coEvery { tenantRepository.getTenantUsers() } returns
            Result.success(listOf(testUser, trusteeUser))
        coEvery { recoveryRepository.createShare(trusteeUser, 1) } returns Result.error(
            AppException.CryptoError("Encryption failed")
        )

        val viewModel = TrusteeSelectionViewModel(recoveryRepository, tenantRepository)
        viewModel.initialize(3)
        advanceUntilIdle()

        viewModel.distributeShare(trusteeUser)
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals("Encryption failed", state.error)
            assertFalse(state.isLoading)
            cancelAndIgnoreRemainingEvents()
        }
    }
}
