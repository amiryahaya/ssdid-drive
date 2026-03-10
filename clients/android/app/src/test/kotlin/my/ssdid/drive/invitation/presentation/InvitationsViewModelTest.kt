package my.ssdid.drive.invitation.presentation

import app.cash.turbine.test
import my.ssdid.drive.domain.model.InvitationAccepted
import my.ssdid.drive.domain.model.UserRole
import my.ssdid.drive.domain.repository.TenantRepository
import my.ssdid.drive.invitation.fixtures.InvitationTestFixtures
import my.ssdid.drive.presentation.settings.InvitationsViewModel
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

/**
 * Unit tests for InvitationsViewModel.
 *
 * Tests cover:
 * - Loading pending invitations
 * - Accepting invitations
 * - Declining invitations
 * - Error handling
 * - Message clearing
 */
@OptIn(ExperimentalCoroutinesApi::class)
class InvitationsViewModelTest {

    private lateinit var tenantRepository: TenantRepository
    private lateinit var viewModel: InvitationsViewModel
    private val testDispatcher = StandardTestDispatcher()

    @Before
    fun setup() {
        Dispatchers.setMain(testDispatcher)
        tenantRepository = mockk()
        // Default mock to prevent unmocked init-block coroutines leaking between tests
        coEvery { tenantRepository.getPendingInvitations() } returns Result.Success(emptyList())
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
        unmockkAll()
    }

    private fun createViewModel(): InvitationsViewModel {
        return InvitationsViewModel(tenantRepository)
    }

    // ==================== Initialization Tests ====================

    @Test
    fun `init loads pending invitations`() = runTest {
        val invitations = listOf(InvitationTestFixtures.DomainModels.validPendingInvitation)
        coEvery { tenantRepository.getPendingInvitations() } returns Result.Success(invitations)

        viewModel = createViewModel()
        advanceUntilIdle()

        coVerify { tenantRepository.getPendingInvitations() }
    }

    @Test
    fun `initial state transitions to loading when loadInvitations is called`() = runTest {
        coEvery { tenantRepository.getPendingInvitations() } coAnswers {
            // Delay to allow capturing loading state
            kotlinx.coroutines.delay(100)
            Result.Success(emptyList())
        }

        viewModel = createViewModel()

        viewModel.uiState.test {
            // First state might be default (isLoading = false) or loading
            val initialState = awaitItem()

            // Advance past the coroutine launch
            testScheduler.advanceTimeBy(50)

            // Check the loading state
            val loadingState = awaitItem()
            assertTrue(loadingState.isLoading)

            cancelAndIgnoreRemainingEvents()
        }
    }

    // ==================== Load Invitations Tests ====================

    @Test
    fun `loadInvitations success updates state with invitations`() = runTest {
        val invitations = listOf(
            InvitationTestFixtures.DomainModels.validPendingInvitation,
            InvitationTestFixtures.DomainModels.pendingInvitationAsAdmin
        )
        coEvery { tenantRepository.getPendingInvitations() } returns Result.Success(invitations)

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals(2, state.invitations.size)
            assertFalse(state.isLoading)
            assertNull(state.error)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `loadInvitations with empty list updates state correctly`() = runTest {
        coEvery { tenantRepository.getPendingInvitations() } returns Result.Success(emptyList())

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertTrue(state.invitations.isEmpty())
            assertFalse(state.isLoading)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `loadInvitations failure shows error`() = runTest {
        coEvery { tenantRepository.getPendingInvitations() } returns
            Result.Error(AppException.Network("Network error"))

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertFalse(state.isLoading)
            assertEquals("Network error", state.error)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `loadInvitations clears previous error`() = runTest {
        coEvery { tenantRepository.getPendingInvitations() } returns
            Result.Error(AppException.Network("Error")) andThen
            Result.Success(emptyList())

        viewModel = createViewModel()
        advanceUntilIdle()

        // First load fails
        viewModel.uiState.test {
            var state = awaitItem()
            assertNotNull(state.error)

            // Reload
            viewModel.loadInvitations()
            advanceUntilIdle()

            state = awaitItem()
            assertNull(state.error)
            cancelAndIgnoreRemainingEvents()
        }
    }

    // ==================== Accept Invitation Tests ====================

    @Test
    fun `acceptInvitation success shows success message`() = runTest {
        val accepted = InvitationAccepted(
            id = "inv-123",
            tenantId = "tenant-456",
            role = UserRole.USER,
            joinedAt = "2025-01-15T12:00:00Z"
        )
        coEvery { tenantRepository.getPendingInvitations() } returns Result.Success(emptyList())
        coEvery { tenantRepository.acceptInvitation(any()) } returns Result.Success(accepted)

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.acceptInvitation("inv-123")
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertFalse(state.isProcessing)
            assertNotNull(state.successMessage)
            assertTrue(state.successMessage!!.contains("accepted"))
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `acceptInvitation reloads invitations after success`() = runTest {
        val accepted = InvitationAccepted(
            id = "inv-123",
            tenantId = "tenant-456",
            role = UserRole.USER,
            joinedAt = "2025-01-15T12:00:00Z"
        )
        coEvery { tenantRepository.getPendingInvitations() } returns Result.Success(emptyList())
        coEvery { tenantRepository.acceptInvitation(any()) } returns Result.Success(accepted)

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.acceptInvitation("inv-123")
        advanceUntilIdle()

        // Should be called once on init and once after accept
        coVerify(atLeast = 2) { tenantRepository.getPendingInvitations() }
    }

    @Test
    fun `acceptInvitation sets isProcessing during call`() = runTest {
        coEvery { tenantRepository.getPendingInvitations() } returns Result.Success(emptyList())
        coEvery { tenantRepository.acceptInvitation(any()) } coAnswers {
            Result.Success(
                InvitationAccepted(
                    id = "inv-123",
                    tenantId = "tenant-456",
                    role = UserRole.USER,
                    joinedAt = null
                )
            )
        }

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.uiState.test {
            skipItems(1)

            viewModel.acceptInvitation("inv-123")

            val processingState = awaitItem()
            assertTrue(processingState.isProcessing)

            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `acceptInvitation failure shows error`() = runTest {
        coEvery { tenantRepository.getPendingInvitations() } returns Result.Success(emptyList())
        coEvery { tenantRepository.acceptInvitation(any()) } returns
            Result.Error(AppException.NotFound("Invitation not found"))

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.acceptInvitation("inv-123")
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertFalse(state.isProcessing)
            assertEquals("Invitation not found", state.error)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `acceptInvitation with conflict error`() = runTest {
        coEvery { tenantRepository.getPendingInvitations() } returns Result.Success(emptyList())
        coEvery { tenantRepository.acceptInvitation(any()) } returns
            Result.Error(AppException.Conflict("Already processed"))

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.acceptInvitation("inv-123")
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals("Already processed", state.error)
            cancelAndIgnoreRemainingEvents()
        }
    }

    // ==================== Decline Invitation Tests ====================

    @Test
    fun `declineInvitation success shows success message`() = runTest {
        coEvery { tenantRepository.getPendingInvitations() } returns Result.Success(emptyList())
        coEvery { tenantRepository.declineInvitation(any()) } returns Result.Success(Unit)

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.declineInvitation("inv-123")
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertFalse(state.isProcessing)
            assertEquals("Invitation declined", state.successMessage)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `declineInvitation reloads invitations after success`() = runTest {
        coEvery { tenantRepository.getPendingInvitations() } returns Result.Success(emptyList())
        coEvery { tenantRepository.declineInvitation(any()) } returns Result.Success(Unit)

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.declineInvitation("inv-123")
        advanceUntilIdle()

        coVerify(atLeast = 2) { tenantRepository.getPendingInvitations() }
    }

    @Test
    fun `declineInvitation sets isProcessing during call`() = runTest {
        coEvery { tenantRepository.getPendingInvitations() } returns Result.Success(emptyList())
        coEvery { tenantRepository.declineInvitation(any()) } coAnswers {
            Result.Success(Unit)
        }

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.uiState.test {
            skipItems(1)

            viewModel.declineInvitation("inv-123")

            val processingState = awaitItem()
            assertTrue(processingState.isProcessing)

            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `declineInvitation failure shows error`() = runTest {
        coEvery { tenantRepository.getPendingInvitations() } returns Result.Success(emptyList())
        coEvery { tenantRepository.declineInvitation(any()) } returns
            Result.Error(AppException.Network("Network error"))

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.declineInvitation("inv-123")
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertFalse(state.isProcessing)
            assertEquals("Network error", state.error)
            cancelAndIgnoreRemainingEvents()
        }
    }

    // ==================== Message Clearing Tests ====================

    @Test
    fun `clearError clears error message`() = runTest {
        coEvery { tenantRepository.getPendingInvitations() } returns
            Result.Error(AppException.Network("Error"))

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.uiState.test {
            var state = awaitItem()
            assertNotNull(state.error)

            viewModel.clearError()

            state = awaitItem()
            assertNull(state.error)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `clearSuccessMessage clears success message`() = runTest {
        coEvery { tenantRepository.getPendingInvitations() } returns Result.Success(emptyList())
        coEvery { tenantRepository.declineInvitation(any()) } returns Result.Success(Unit)

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.declineInvitation("inv-123")
        advanceUntilIdle()

        viewModel.uiState.test {
            var state = awaitItem()
            assertNotNull(state.successMessage)

            viewModel.clearSuccessMessage()

            state = awaitItem()
            assertNull(state.successMessage)
            cancelAndIgnoreRemainingEvents()
        }
    }

    // ==================== Edge Cases ====================

    @Test
    fun `multiple invitations loaded correctly`() = runTest {
        val invitations = listOf(
            InvitationTestFixtures.DomainModels.validPendingInvitation,
            InvitationTestFixtures.DomainModels.validPendingInvitation.copy(id = "inv-2"),
            InvitationTestFixtures.DomainModels.validPendingInvitation.copy(id = "inv-3"),
            InvitationTestFixtures.DomainModels.pendingInvitationAsAdmin,
            InvitationTestFixtures.DomainModels.pendingInvitationWithNullInviter
        )
        coEvery { tenantRepository.getPendingInvitations() } returns Result.Success(invitations)

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals(5, state.invitations.size)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `accept followed by decline on different invitations`() = runTest {
        val accepted = InvitationAccepted(
            id = "inv-1",
            tenantId = "tenant-1",
            role = UserRole.USER,
            joinedAt = null
        )
        coEvery { tenantRepository.getPendingInvitations() } returns Result.Success(emptyList())
        coEvery { tenantRepository.acceptInvitation("inv-1") } returns Result.Success(accepted)
        coEvery { tenantRepository.declineInvitation("inv-2") } returns Result.Success(Unit)

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.acceptInvitation("inv-1")
        advanceUntilIdle()

        viewModel.clearSuccessMessage()

        viewModel.declineInvitation("inv-2")
        advanceUntilIdle()

        coVerify { tenantRepository.acceptInvitation("inv-1") }
        coVerify { tenantRepository.declineInvitation("inv-2") }
    }
}
