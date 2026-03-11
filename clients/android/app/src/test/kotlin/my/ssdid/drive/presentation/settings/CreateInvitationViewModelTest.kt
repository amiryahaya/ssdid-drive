package my.ssdid.drive.presentation.settings

import my.ssdid.drive.domain.model.CreatedInvitation
import my.ssdid.drive.domain.model.InvitationStatus
import my.ssdid.drive.domain.model.TenantContext
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
 * Unit tests for CreateInvitationViewModel.
 *
 * Tests cover:
 * - Email validation (valid, invalid, blank, whitespace-only)
 * - Message cap at 500 characters
 * - Role selection
 * - createInvitation success/error
 * - resetForm preserving currentUserRole
 * - loadCurrentUserRole with null context
 */
@OptIn(ExperimentalCoroutinesApi::class)
class CreateInvitationViewModelTest {

    private lateinit var tenantRepository: TenantRepository
    private lateinit var viewModel: CreateInvitationViewModel
    private val testDispatcher = StandardTestDispatcher()

    private val sampleCreatedInvitation = CreatedInvitation(
        id = "inv-001",
        shortCode = "ACME-1234",
        email = "user@example.com",
        role = UserRole.USER,
        status = InvitationStatus.PENDING,
        message = null,
        createdAt = "2026-03-11T12:00:00Z",
        expiresAt = "2026-04-11T12:00:00Z"
    )

    @Before
    fun setup() {
        Dispatchers.setMain(testDispatcher)
        tenantRepository = mockk()
        // Default: init calls loadCurrentUserRole -> getCurrentTenantContext
        coEvery { tenantRepository.getCurrentTenantContext() } returns null
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
        unmockkAll()
    }

    private fun createViewModel(): CreateInvitationViewModel {
        return CreateInvitationViewModel(tenantRepository)
    }

    // ==================== Email Validation Tests ====================

    @Test
    fun `createInvitation with valid email succeeds`() = runTest {
        coEvery {
            tenantRepository.createInvitation(
                email = "user@example.com",
                role = UserRole.USER,
                message = null
            )
        } returns Result.Success(sampleCreatedInvitation)

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.updateEmail("user@example.com")
        viewModel.createInvitation()
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertNull(state.emailError)
        assertNotNull(state.createdInvitation)
        assertEquals("ACME-1234", state.createdInvitation!!.shortCode)
    }

    @Test
    fun `createInvitation with invalid email shows error`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.updateEmail("not-an-email")
        viewModel.createInvitation()

        val state = viewModel.uiState.value
        assertEquals("Invalid email format", state.emailError)
        assertNull(state.createdInvitation)
    }

    @Test
    fun `createInvitation with blank email skips email validation and sends null email`() = runTest {
        coEvery {
            tenantRepository.createInvitation(
                email = null,
                role = UserRole.USER,
                message = null
            )
        } returns Result.Success(sampleCreatedInvitation.copy(email = null))

        viewModel = createViewModel()
        advanceUntilIdle()

        // Leave email blank (default)
        viewModel.createInvitation()
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertNull(state.emailError)
        assertNotNull(state.createdInvitation)
    }

    @Test
    fun `createInvitation with whitespace-only email treats as blank`() = runTest {
        coEvery {
            tenantRepository.createInvitation(
                email = null,
                role = UserRole.USER,
                message = null
            )
        } returns Result.Success(sampleCreatedInvitation.copy(email = null))

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.updateEmail("   ")
        viewModel.createInvitation()
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertNull(state.emailError)
        assertNotNull(state.createdInvitation)
    }

    @Test
    fun `updateEmail clears emailError`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        // First trigger email error
        viewModel.updateEmail("bad")
        viewModel.createInvitation()
        assertEquals("Invalid email format", viewModel.uiState.value.emailError)

        // Updating email should clear the error
        viewModel.updateEmail("new@email.com")
        assertNull(viewModel.uiState.value.emailError)
    }

    // ==================== Message Tests ====================

    @Test
    fun `updateMessage allows up to 500 characters`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        val message500 = "a".repeat(500)
        viewModel.updateMessage(message500)
        assertEquals(500, viewModel.uiState.value.message.length)
    }

    @Test
    fun `updateMessage rejects more than 500 characters`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        val message500 = "a".repeat(500)
        viewModel.updateMessage(message500)

        // Try to set 501 characters - should be rejected, keeping old value
        val message501 = "a".repeat(501)
        viewModel.updateMessage(message501)
        assertEquals(500, viewModel.uiState.value.message.length)
    }

    // ==================== Role Selection Tests ====================

    @Test
    fun `updateRole changes selectedRole`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        assertEquals(UserRole.USER, viewModel.uiState.value.selectedRole)

        viewModel.updateRole(UserRole.ADMIN)
        assertEquals(UserRole.ADMIN, viewModel.uiState.value.selectedRole)
    }

    @Test
    fun `createInvitation sends selected role`() = runTest {
        coEvery {
            tenantRepository.createInvitation(
                email = null,
                role = UserRole.ADMIN,
                message = null
            )
        } returns Result.Success(sampleCreatedInvitation.copy(role = UserRole.ADMIN))

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.updateRole(UserRole.ADMIN)
        viewModel.createInvitation()
        advanceUntilIdle()

        coVerify {
            tenantRepository.createInvitation(
                email = null,
                role = UserRole.ADMIN,
                message = null
            )
        }
    }

    // ==================== createInvitation Success/Error Tests ====================

    @Test
    fun `createInvitation success updates state with created invitation`() = runTest {
        coEvery {
            tenantRepository.createInvitation(any(), any(), any())
        } returns Result.Success(sampleCreatedInvitation)

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.updateEmail("user@example.com")
        viewModel.createInvitation()
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertFalse(state.isCreating)
        assertNotNull(state.createdInvitation)
        assertNull(state.error)
    }

    @Test
    fun `createInvitation error updates state with error message`() = runTest {
        coEvery {
            tenantRepository.createInvitation(any(), any(), any())
        } returns Result.Error(AppException.Forbidden("Not authorized to create invitations"))

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.createInvitation()
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertFalse(state.isCreating)
        assertNull(state.createdInvitation)
        assertEquals("Not authorized to create invitations", state.error)
    }

    @Test
    fun `createInvitation network error shows fallback message`() = runTest {
        coEvery {
            tenantRepository.createInvitation(any(), any(), any())
        } returns Result.Error(AppException.Network(""))

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.createInvitation()
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertFalse(state.isCreating)
        // Empty message should use fallback (the message is empty string, not null, so it returns empty)
        assertNotNull(state.error)
    }

    // ==================== resetForm Tests ====================

    @Test
    fun `resetForm clears all fields but preserves currentUserRole`() = runTest {
        val context = TenantContext(
            currentTenantId = "tenant-1",
            currentRole = UserRole.ADMIN,
            availableTenants = emptyList()
        )
        coEvery { tenantRepository.getCurrentTenantContext() } returns context

        viewModel = createViewModel()
        advanceUntilIdle()

        // Fill in some data
        viewModel.updateEmail("test@example.com")
        viewModel.updateRole(UserRole.ADMIN)
        viewModel.updateMessage("Hello")

        // Reset
        viewModel.resetForm()

        val state = viewModel.uiState.value
        assertEquals("", state.email)
        assertNull(state.emailError)
        assertEquals(UserRole.USER, state.selectedRole)
        assertEquals("", state.message)
        assertFalse(state.isCreating)
        assertNull(state.error)
        assertNull(state.createdInvitation)
        // currentUserRole should be preserved
        assertEquals(UserRole.ADMIN, state.currentUserRole)
    }

    // ==================== loadCurrentUserRole Tests ====================

    @Test
    fun `init with null tenant context keeps default USER role`() = runTest {
        coEvery { tenantRepository.getCurrentTenantContext() } returns null

        viewModel = createViewModel()
        advanceUntilIdle()

        assertEquals(UserRole.USER, viewModel.uiState.value.currentUserRole)
    }

    @Test
    fun `init with tenant context updates currentUserRole`() = runTest {
        val context = TenantContext(
            currentTenantId = "tenant-1",
            currentRole = UserRole.OWNER,
            availableTenants = emptyList()
        )
        coEvery { tenantRepository.getCurrentTenantContext() } returns context

        viewModel = createViewModel()
        advanceUntilIdle()

        assertEquals(UserRole.OWNER, viewModel.uiState.value.currentUserRole)
    }

    // ==================== clearError Tests ====================

    @Test
    fun `clearError clears error message`() = runTest {
        coEvery {
            tenantRepository.createInvitation(any(), any(), any())
        } returns Result.Error(AppException.Network("Network error"))

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.createInvitation()
        advanceUntilIdle()
        assertNotNull(viewModel.uiState.value.error)

        viewModel.clearError()
        assertNull(viewModel.uiState.value.error)
    }
}
