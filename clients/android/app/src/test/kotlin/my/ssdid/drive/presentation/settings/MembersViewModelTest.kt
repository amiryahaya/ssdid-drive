package my.ssdid.drive.presentation.settings

import app.cash.turbine.test
import my.ssdid.drive.domain.model.MemberStatus
import my.ssdid.drive.domain.model.TenantContext
import my.ssdid.drive.domain.model.TenantMember
import my.ssdid.drive.domain.model.User
import my.ssdid.drive.domain.model.UserRole
import my.ssdid.drive.domain.repository.AuthRepository
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
 * Unit tests for MembersViewModel.
 *
 * Tests cover:
 * - loadMembers success/error/null-tenantId
 * - changeRole success/error
 * - removeMember success/error
 * - Dialog state management (showChangeRoleDialog, dismissChangeRoleDialog, showRemoveMemberDialog, dismissRemoveMemberDialog)
 * - clearError / clearSuccessMessage
 */
@OptIn(ExperimentalCoroutinesApi::class)
class MembersViewModelTest {

    private lateinit var tenantRepository: TenantRepository
    private lateinit var authRepository: AuthRepository
    private lateinit var viewModel: MembersViewModel
    private val testDispatcher = StandardTestDispatcher()

    private val testTenantId = "tenant-123"
    private val testUserId = "user-456"

    private val sampleMembers = listOf(
        TenantMember(
            id = "member-1",
            userId = "user-1",
            email = "admin@test.com",
            displayName = "Admin User",
            role = UserRole.ADMIN,
            status = MemberStatus.ACTIVE,
            joinedAt = "2026-01-01T00:00:00Z"
        ),
        TenantMember(
            id = "member-2",
            userId = "user-2",
            email = "member@test.com",
            displayName = "Regular Member",
            role = UserRole.USER,
            status = MemberStatus.ACTIVE,
            joinedAt = "2026-02-01T00:00:00Z"
        )
    )

    private val sampleContext = TenantContext(
        currentTenantId = testTenantId,
        currentRole = UserRole.ADMIN,
        availableTenants = emptyList()
    )

    @Before
    fun setup() {
        Dispatchers.setMain(testDispatcher)
        tenantRepository = mockk()
        authRepository = mockk()

        // Default stubs for init
        coEvery { authRepository.getCurrentUser() } returns Result.Success(
            User(id = testUserId, email = "me@test.com")
        )
        coEvery { tenantRepository.getCurrentTenantContext() } returns sampleContext
        coEvery { tenantRepository.getTenantMembers(testTenantId) } returns Result.Success(sampleMembers)
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
        unmockkAll()
    }

    private fun createViewModel(): MembersViewModel {
        return MembersViewModel(tenantRepository, authRepository)
    }

    // ==================== loadMembers Tests ====================

    @Test
    fun `init loads current user context and members`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertEquals(testUserId, state.currentUserId)
        assertEquals(UserRole.ADMIN, state.currentUserRole)
        assertEquals(testTenantId, state.currentTenantId)
        assertEquals(2, state.members.size)
        assertFalse(state.isLoading)
    }

    @Test
    fun `loadMembers success updates state with members`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals(2, state.members.size)
            assertFalse(state.isLoading)
            assertNull(state.error)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `loadMembers failure shows error`() = runTest {
        coEvery { tenantRepository.getTenantMembers(testTenantId) } returns
            Result.Error(AppException.Forbidden("Access denied"))

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertFalse(state.isLoading)
            assertEquals("Access denied", state.error)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `loadMembers with null tenantId does nothing`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        // Reset member list
        clearMocks(tenantRepository, answers = false)
        coEvery { tenantRepository.getTenantMembers(any()) } returns Result.Success(emptyList())

        viewModel.loadMembers(null)
        advanceUntilIdle()

        // Should not have called getTenantMembers again with null
        coVerify(exactly = 0) { tenantRepository.getTenantMembers(isNull()) }
    }

    @Test
    fun `init with null tenant context does not load members`() = runTest {
        coEvery { tenantRepository.getCurrentTenantContext() } returns null

        viewModel = createViewModel()
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertNull(state.currentTenantId)
        assertTrue(state.members.isEmpty())
    }

    @Test
    fun `init with getCurrentUser error continues without userId`() = runTest {
        coEvery { authRepository.getCurrentUser() } returns
            Result.Error(AppException.Unauthorized())

        viewModel = createViewModel()
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertNull(state.currentUserId)
        // Members should still load
        assertEquals(2, state.members.size)
    }

    // ==================== changeRole Tests ====================

    @Test
    fun `changeRole success shows success message and reloads members`() = runTest {
        val updatedMember = sampleMembers[1].copy(role = UserRole.ADMIN)
        coEvery {
            tenantRepository.updateMemberRole(testTenantId, "user-2", UserRole.ADMIN)
        } returns Result.Success(updatedMember)

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.changeRole(sampleMembers[1], UserRole.ADMIN)
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertFalse(state.isUpdating)
            assertEquals("Role updated to admin", state.successMessage)
            assertNull(state.memberToChangeRole) // dialog dismissed
            cancelAndIgnoreRemainingEvents()
        }

        // Verify reloads members (init + after changeRole)
        coVerify(atLeast = 2) { tenantRepository.getTenantMembers(testTenantId) }
    }

    @Test
    fun `changeRole failure shows error`() = runTest {
        coEvery {
            tenantRepository.updateMemberRole(testTenantId, "user-2", UserRole.ADMIN)
        } returns Result.Error(AppException.Forbidden("Only owners can change roles"))

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.changeRole(sampleMembers[1], UserRole.ADMIN)
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertFalse(state.isUpdating)
            assertEquals("Only owners can change roles", state.error)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `changeRole with no currentTenantId does nothing`() = runTest {
        coEvery { tenantRepository.getCurrentTenantContext() } returns null

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.changeRole(sampleMembers[1], UserRole.ADMIN)
        advanceUntilIdle()

        coVerify(exactly = 0) { tenantRepository.updateMemberRole(any(), any(), any()) }
    }

    // ==================== removeMember Tests ====================

    @Test
    fun `removeMember success shows success message with displayName and reloads`() = runTest {
        coEvery {
            tenantRepository.removeMember(testTenantId, "user-2")
        } returns Result.Success(Unit)

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.removeMember(sampleMembers[1])
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertFalse(state.isUpdating)
            assertEquals("Regular Member removed", state.successMessage)
            assertNull(state.memberToRemove) // dialog dismissed
            cancelAndIgnoreRemainingEvents()
        }

        coVerify(atLeast = 2) { tenantRepository.getTenantMembers(testTenantId) }
    }

    @Test
    fun `removeMember with null displayName uses email in message`() = runTest {
        val memberNoName = TenantMember(
            id = "member-3",
            userId = "user-3",
            email = "noname@test.com",
            displayName = null,
            role = UserRole.USER,
            status = MemberStatus.ACTIVE,
            joinedAt = null
        )
        coEvery {
            tenantRepository.removeMember(testTenantId, "user-3")
        } returns Result.Success(Unit)

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.removeMember(memberNoName)
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals("noname@test.com removed", state.successMessage)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `removeMember with null displayName and email uses Member in message`() = runTest {
        val memberNoInfo = TenantMember(
            id = "member-4",
            userId = "user-4",
            email = null,
            displayName = null,
            role = UserRole.USER,
            status = MemberStatus.ACTIVE,
            joinedAt = null
        )
        coEvery {
            tenantRepository.removeMember(testTenantId, "user-4")
        } returns Result.Success(Unit)

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.removeMember(memberNoInfo)
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals("Member removed", state.successMessage)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `removeMember failure shows error`() = runTest {
        coEvery {
            tenantRepository.removeMember(testTenantId, "user-2")
        } returns Result.Error(AppException.Conflict("Cannot remove the only owner"))

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.removeMember(sampleMembers[1])
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertFalse(state.isUpdating)
            assertEquals("Cannot remove the only owner", state.error)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `removeMember with no currentTenantId does nothing`() = runTest {
        coEvery { tenantRepository.getCurrentTenantContext() } returns null

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.removeMember(sampleMembers[1])
        advanceUntilIdle()

        coVerify(exactly = 0) { tenantRepository.removeMember(any(), any()) }
    }

    // ==================== Dialog State Management Tests ====================

    @Test
    fun `showChangeRoleDialog sets memberToChangeRole`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.showChangeRoleDialog(sampleMembers[0])
        assertEquals(sampleMembers[0], viewModel.uiState.value.memberToChangeRole)
    }

    @Test
    fun `dismissChangeRoleDialog clears memberToChangeRole`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.showChangeRoleDialog(sampleMembers[0])
        assertNotNull(viewModel.uiState.value.memberToChangeRole)

        viewModel.dismissChangeRoleDialog()
        assertNull(viewModel.uiState.value.memberToChangeRole)
    }

    @Test
    fun `showRemoveMemberDialog sets memberToRemove`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.showRemoveMemberDialog(sampleMembers[1])
        assertEquals(sampleMembers[1], viewModel.uiState.value.memberToRemove)
    }

    @Test
    fun `dismissRemoveMemberDialog clears memberToRemove`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.showRemoveMemberDialog(sampleMembers[1])
        assertNotNull(viewModel.uiState.value.memberToRemove)

        viewModel.dismissRemoveMemberDialog()
        assertNull(viewModel.uiState.value.memberToRemove)
    }

    // ==================== clearError / clearSuccessMessage Tests ====================

    @Test
    fun `clearError clears error message`() = runTest {
        coEvery { tenantRepository.getTenantMembers(testTenantId) } returns
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
        coEvery {
            tenantRepository.removeMember(testTenantId, "user-2")
        } returns Result.Success(Unit)

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.removeMember(sampleMembers[1])
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
