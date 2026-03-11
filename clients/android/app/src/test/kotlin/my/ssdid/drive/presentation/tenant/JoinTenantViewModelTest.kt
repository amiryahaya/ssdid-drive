package my.ssdid.drive.presentation.tenant

import app.cash.turbine.test
import my.ssdid.drive.domain.model.InvitationAccepted
import my.ssdid.drive.domain.model.InviteCodeInfo
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
 * Unit tests for JoinTenantViewModel.
 *
 * Tests cover:
 * - Code input handling (auto-uppercase, trim)
 * - Invite code lookup (success, error)
 * - Joining a tenant (success, error)
 * - Clearing preview state
 * - Validation of blank code
 */
@OptIn(ExperimentalCoroutinesApi::class)
class JoinTenantViewModelTest {

    private lateinit var tenantRepository: TenantRepository
    private lateinit var viewModel: JoinTenantViewModel
    private val testDispatcher = StandardTestDispatcher()

    private val sampleInviteInfo = InviteCodeInfo(
        id = "inv-123",
        tenantName = "Acme Corp",
        role = UserRole.USER,
        shortCode = "ACME-7K9X",
        expiresAt = "2026-04-01T00:00:00Z"
    )

    @Before
    fun setup() {
        Dispatchers.setMain(testDispatcher)
        tenantRepository = mockk()
        viewModel = JoinTenantViewModel(tenantRepository)
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    @Test
    fun `updateCode auto-uppercases and trims input`() = runTest {
        viewModel.updateCode("  acme-7k9x  ")

        assertEquals("ACME-7K9X", viewModel.uiState.value.code)
    }

    @Test
    fun `updateCode clears previous errors`() = runTest {
        // First trigger an error by looking up blank code
        viewModel.lookupCode()
        assertNotNull(viewModel.uiState.value.lookupError)

        // Now updating code should clear the error
        viewModel.updateCode("ACME")
        assertNull(viewModel.uiState.value.lookupError)
    }

    @Test
    fun `lookupCode with blank code shows error`() = runTest {
        viewModel.lookupCode()

        assertEquals("Please enter an invite code", viewModel.uiState.value.lookupError)
        assertNull(viewModel.uiState.value.inviteInfo)
    }

    @Test
    fun `lookupCode success populates inviteInfo`() = runTest {
        coEvery { tenantRepository.lookupInviteCode("ACME-7K9X") } returns Result.success(sampleInviteInfo)

        viewModel.updateCode("ACME-7K9X")
        viewModel.lookupCode()
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertFalse(state.isLookingUp)
        assertNotNull(state.inviteInfo)
        assertEquals("Acme Corp", state.inviteInfo!!.tenantName)
        assertEquals("ACME-7K9X", state.inviteInfo!!.shortCode)
        assertNull(state.lookupError)
    }

    @Test
    fun `lookupCode failure shows error`() = runTest {
        coEvery { tenantRepository.lookupInviteCode("BAD-CODE") } returns
            Result.error(AppException.NotFound("Invalid invite code"))

        viewModel.updateCode("BAD-CODE")
        viewModel.lookupCode()
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertFalse(state.isLookingUp)
        assertNull(state.inviteInfo)
        assertEquals("Invalid invite code", state.lookupError)
    }

    @Test
    fun `joinTenant does nothing when inviteInfo is null`() = runTest {
        viewModel.joinTenant()
        advanceUntilIdle()

        assertFalse(viewModel.uiState.value.isJoining)
        assertFalse(viewModel.uiState.value.isJoined)
    }

    @Test
    fun `joinTenant success sets isJoined`() = runTest {
        // First lookup
        coEvery { tenantRepository.lookupInviteCode("ACME-7K9X") } returns Result.success(sampleInviteInfo)
        coEvery { tenantRepository.acceptInvitationById("inv-123") } returns Result.success(
            InvitationAccepted(
                id = "inv-123",
                tenantId = "tenant-1",
                role = UserRole.USER,
                joinedAt = "2026-03-11T12:00:00Z"
            )
        )

        viewModel.updateCode("ACME-7K9X")
        viewModel.lookupCode()
        advanceUntilIdle()

        viewModel.joinTenant()
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertFalse(state.isJoining)
        assertTrue(state.isJoined)
        assertNull(state.joinError)
    }

    @Test
    fun `joinTenant failure shows error`() = runTest {
        coEvery { tenantRepository.lookupInviteCode("ACME-7K9X") } returns Result.success(sampleInviteInfo)
        coEvery { tenantRepository.acceptInvitationById("inv-123") } returns
            Result.error(AppException.Conflict("Already a member"))

        viewModel.updateCode("ACME-7K9X")
        viewModel.lookupCode()
        advanceUntilIdle()

        viewModel.joinTenant()
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertFalse(state.isJoining)
        assertFalse(state.isJoined)
        assertEquals("Already a member", state.joinError)
    }

    @Test
    fun `clearPreview resets inviteInfo and errors`() = runTest {
        coEvery { tenantRepository.lookupInviteCode("ACME-7K9X") } returns Result.success(sampleInviteInfo)

        viewModel.updateCode("ACME-7K9X")
        viewModel.lookupCode()
        advanceUntilIdle()
        assertNotNull(viewModel.uiState.value.inviteInfo)

        viewModel.clearPreview()

        val state = viewModel.uiState.value
        assertNull(state.inviteInfo)
        assertNull(state.lookupError)
        assertNull(state.joinError)
        // Code should still be there
        assertEquals("ACME-7K9X", state.code)
    }
}
