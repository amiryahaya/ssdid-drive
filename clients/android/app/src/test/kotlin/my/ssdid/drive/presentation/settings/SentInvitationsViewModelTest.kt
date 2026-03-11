package my.ssdid.drive.presentation.settings

import app.cash.turbine.test
import my.ssdid.drive.domain.model.InvitationStatus
import my.ssdid.drive.domain.model.SentInvitation
import my.ssdid.drive.domain.model.UserRole
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

/**
 * Unit tests for SentInvitationsViewModel.
 *
 * Tests cover:
 * - loadSentInvitations success/error
 * - revokeInvitation success/error
 * - showCopiedMessage
 * - Loading states
 * - clearError / clearSuccessMessage
 */
@OptIn(ExperimentalCoroutinesApi::class)
class SentInvitationsViewModelTest {

    private lateinit var tenantRepository: TenantRepository
    private lateinit var viewModel: SentInvitationsViewModel
    private val testDispatcher = StandardTestDispatcher()

    private val sampleInvitations = listOf(
        SentInvitation(
            id = "inv-1",
            shortCode = "ACME-1234",
            email = "user1@example.com",
            role = UserRole.USER,
            status = InvitationStatus.PENDING,
            message = null,
            createdAt = "2026-03-01T00:00:00Z",
            expiresAt = "2026-04-01T00:00:00Z"
        ),
        SentInvitation(
            id = "inv-2",
            shortCode = "ACME-5678",
            email = null,
            role = UserRole.ADMIN,
            status = InvitationStatus.ACCEPTED,
            message = "Welcome!",
            createdAt = "2026-03-05T00:00:00Z",
            expiresAt = "2026-04-05T00:00:00Z"
        )
    )

    @Before
    fun setup() {
        Dispatchers.setMain(testDispatcher)
        tenantRepository = mockk()
        // Default: init calls loadSentInvitations
        coEvery { tenantRepository.getSentInvitations(any(), any()) } returns Result.Success(emptyList())
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
        unmockkAll()
    }

    private fun createViewModel(): SentInvitationsViewModel {
        return SentInvitationsViewModel(tenantRepository)
    }

    // ==================== loadSentInvitations Tests ====================

    @Test
    fun `init loads sent invitations`() = runTest {
        coEvery { tenantRepository.getSentInvitations(any(), any()) } returns Result.Success(sampleInvitations)

        viewModel = createViewModel()
        advanceUntilIdle()

        coVerify { tenantRepository.getSentInvitations(any(), any()) }
    }

    @Test
    fun `loadSentInvitations success updates state with invitations`() = runTest {
        coEvery { tenantRepository.getSentInvitations(any(), any()) } returns Result.Success(sampleInvitations)

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
    fun `loadSentInvitations with empty list updates state correctly`() = runTest {
        coEvery { tenantRepository.getSentInvitations(any(), any()) } returns Result.Success(emptyList())

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
    fun `loadSentInvitations failure shows error`() = runTest {
        coEvery { tenantRepository.getSentInvitations(any(), any()) } returns
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
    fun `loadSentInvitations sets isLoading during call`() = runTest {
        coEvery { tenantRepository.getSentInvitations(any(), any()) } coAnswers {
            kotlinx.coroutines.delay(100)
            Result.Success(sampleInvitations)
        }

        viewModel = createViewModel()

        viewModel.uiState.test {
            awaitItem() // initial state

            testScheduler.advanceTimeBy(50)
            val loadingState = awaitItem()
            assertTrue(loadingState.isLoading)

            cancelAndIgnoreRemainingEvents()
        }
    }

    // ==================== revokeInvitation Tests ====================

    @Test
    fun `revokeInvitation success shows success message and reloads`() = runTest {
        coEvery { tenantRepository.getSentInvitations(any(), any()) } returns Result.Success(sampleInvitations)
        coEvery { tenantRepository.revokeInvitation("inv-1") } returns Result.Success(Unit)

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.revokeInvitation("inv-1")
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertFalse(state.isRevoking)
            assertEquals("Invitation revoked", state.successMessage)
            cancelAndIgnoreRemainingEvents()
        }

        // Verify it reloads invitations (init + after revoke)
        coVerify(atLeast = 2) { tenantRepository.getSentInvitations(any(), any()) }
    }

    @Test
    fun `revokeInvitation failure shows error`() = runTest {
        coEvery { tenantRepository.getSentInvitations(any(), any()) } returns Result.Success(emptyList())
        coEvery { tenantRepository.revokeInvitation("inv-1") } returns
            Result.Error(AppException.NotFound("Invitation not found"))

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.revokeInvitation("inv-1")
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertFalse(state.isRevoking)
            assertEquals("Invitation not found", state.error)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `revokeInvitation sets isRevoking during call`() = runTest {
        coEvery { tenantRepository.getSentInvitations(any(), any()) } returns Result.Success(emptyList())
        coEvery { tenantRepository.revokeInvitation(any()) } coAnswers {
            Result.Success(Unit)
        }

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.uiState.test {
            skipItems(1)

            viewModel.revokeInvitation("inv-1")

            val revokingState = awaitItem()
            assertTrue(revokingState.isRevoking)

            cancelAndIgnoreRemainingEvents()
        }
    }

    // ==================== showCopiedMessage Tests ====================

    @Test
    fun `showCopiedMessage sets success message`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.showCopiedMessage()

        assertEquals("Code copied to clipboard", viewModel.uiState.value.successMessage)
    }

    // ==================== clearError / clearSuccessMessage Tests ====================

    @Test
    fun `clearError clears error message`() = runTest {
        coEvery { tenantRepository.getSentInvitations(any(), any()) } returns
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
        coEvery { tenantRepository.getSentInvitations(any(), any()) } returns Result.Success(emptyList())
        coEvery { tenantRepository.revokeInvitation(any()) } returns Result.Success(Unit)

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.revokeInvitation("inv-1")
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
}
