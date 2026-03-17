package my.ssdid.drive.presentation.settings

import app.cash.turbine.test
import my.ssdid.drive.domain.model.Tenant
import my.ssdid.drive.domain.model.TenantContext
import my.ssdid.drive.domain.model.UserRole
import my.ssdid.drive.domain.repository.TenantRepository
import my.ssdid.drive.util.AppException
import my.ssdid.drive.util.Result
import io.mockk.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

/**
 * Unit tests for TenantSwitcherViewModel.
 *
 * Tests cover:
 * - switchTenant to same tenant (no-op)
 * - leaveTenant when only one tenant (error)
 * - leaveTenant on current tenant (error)
 * - Successful switch
 * - clearError / clearSwitchSuccess
 * - refreshTenants success/error
 */
@OptIn(ExperimentalCoroutinesApi::class)
class TenantSwitcherViewModelTest {

    private lateinit var tenantRepository: TenantRepository
    private lateinit var viewModel: TenantSwitcherViewModel
    private val testDispatcher = StandardTestDispatcher()

    private val tenantA = Tenant(
        id = "tenant-a",
        name = "Org A",
        slug = "org-a",
        role = UserRole.ADMIN,
        joinedAt = "2026-01-01T00:00:00Z"
    )

    private val tenantB = Tenant(
        id = "tenant-b",
        name = "Org B",
        slug = "org-b",
        role = UserRole.USER,
        joinedAt = "2026-02-01T00:00:00Z"
    )

    private val contextWithTwoTenants = TenantContext(
        currentTenantId = "tenant-a",
        currentRole = UserRole.ADMIN,
        availableTenants = listOf(tenantA, tenantB)
    )

    private val contextWithOneTenant = TenantContext(
        currentTenantId = "tenant-a",
        currentRole = UserRole.ADMIN,
        availableTenants = listOf(tenantA)
    )

    private val tenantContextFlow = MutableStateFlow<TenantContext?>(null)

    @Before
    fun setup() {
        Dispatchers.setMain(testDispatcher)
        tenantRepository = mockk()

        // Default stubs for init
        coEvery { tenantRepository.getCurrentTenantContext() } returns contextWithTwoTenants
        every { tenantRepository.observeTenantContext() } returns tenantContextFlow
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
        unmockkAll()
    }

    private fun createViewModel(): TenantSwitcherViewModel {
        return TenantSwitcherViewModel(tenantRepository)
    }

    // ==================== switchTenant Tests ====================

    @Test
    fun `switchTenant to same tenant is a no-op`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        // Current tenant is tenant-a
        viewModel.switchTenant("tenant-a")
        advanceUntilIdle()

        // Should not call switchTenant on repository
        coVerify(exactly = 0) { tenantRepository.switchTenant(any()) }
        assertFalse(viewModel.uiState.value.isSwitching)
    }

    @Test
    fun `switchTenant success updates state`() = runTest {
        val newContext = TenantContext(
            currentTenantId = "tenant-b",
            currentRole = UserRole.USER,
            availableTenants = listOf(tenantA, tenantB)
        )
        coEvery { tenantRepository.switchTenant("tenant-b") } returns Result.Success(newContext)

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.switchTenant("tenant-b")
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertFalse(state.isSwitching)
        assertTrue(state.switchSuccess)
        assertEquals("tenant-b", state.currentTenant?.id)
        assertNull(state.error)
    }

    @Test
    fun `switchTenant failure shows error`() = runTest {
        coEvery { tenantRepository.switchTenant("tenant-b") } returns
            Result.Error(AppException.Forbidden("Not authorized"))

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.switchTenant("tenant-b")
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertFalse(state.isSwitching)
        assertFalse(state.switchSuccess)
        assertEquals("Not authorized", state.error)
    }

    @Test
    fun `switchTenant blocked when upload in progress`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.setUploadInProgress(true)
        viewModel.switchTenant("tenant-b")
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertFalse(state.isSwitching)
        assertFalse(state.switchSuccess)
        assertEquals(
            "Cannot switch organization while an upload is in progress",
            state.error
        )
        coVerify(exactly = 0) { tenantRepository.switchTenant(any()) }
    }

    @Test
    fun `switchTenant allowed after upload completes`() = runTest {
        val newContext = TenantContext(
            currentTenantId = "tenant-b",
            currentRole = UserRole.USER,
            availableTenants = listOf(tenantA, tenantB)
        )
        coEvery { tenantRepository.switchTenant("tenant-b") } returns Result.Success(newContext)

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.setUploadInProgress(true)
        viewModel.setUploadInProgress(false)
        viewModel.switchTenant("tenant-b")
        advanceUntilIdle()

        assertTrue(viewModel.uiState.value.switchSuccess)
        coVerify { tenantRepository.switchTenant("tenant-b") }
    }

    // ==================== leaveTenant Tests ====================

    @Test
    fun `leaveTenant when only one tenant shows error`() = runTest {
        coEvery { tenantRepository.getCurrentTenantContext() } returns contextWithOneTenant

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.leaveTenant("tenant-a")

        assertEquals("Cannot leave your only organization", viewModel.uiState.value.error)
        coVerify(exactly = 0) { tenantRepository.leaveTenant(any()) }
    }

    @Test
    fun `leaveTenant on current tenant shows error`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        // Current tenant is tenant-a, try to leave it
        viewModel.leaveTenant("tenant-a")

        assertEquals(
            "Switch to another organization before leaving this one",
            viewModel.uiState.value.error
        )
        coVerify(exactly = 0) { tenantRepository.leaveTenant(any()) }
    }

    @Test
    fun `leaveTenant success refreshes tenants`() = runTest {
        coEvery { tenantRepository.leaveTenant("tenant-b") } returns Result.Success(Unit)
        coEvery { tenantRepository.refreshTenants() } returns Result.Success(listOf(tenantA))

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.leaveTenant("tenant-b")
        advanceUntilIdle()

        coVerify { tenantRepository.leaveTenant("tenant-b") }
        coVerify { tenantRepository.refreshTenants() }
    }

    @Test
    fun `leaveTenant failure shows error`() = runTest {
        coEvery { tenantRepository.leaveTenant("tenant-b") } returns
            Result.Error(AppException.Conflict("Cannot leave as only owner"))

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.leaveTenant("tenant-b")
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertFalse(state.isLoading)
        assertEquals("Cannot leave as only owner", state.error)
    }

    // ==================== clearError / clearSwitchSuccess Tests ====================

    @Test
    fun `clearError clears error`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        // Trigger error
        viewModel.leaveTenant("tenant-a")
        assertNotNull(viewModel.uiState.value.error)

        viewModel.clearError()
        assertNull(viewModel.uiState.value.error)
    }

    @Test
    fun `clearSwitchSuccess resets switchSuccess flag`() = runTest {
        val newContext = TenantContext(
            currentTenantId = "tenant-b",
            currentRole = UserRole.USER,
            availableTenants = listOf(tenantA, tenantB)
        )
        coEvery { tenantRepository.switchTenant("tenant-b") } returns Result.Success(newContext)

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.switchTenant("tenant-b")
        advanceUntilIdle()
        assertTrue(viewModel.uiState.value.switchSuccess)

        viewModel.clearSwitchSuccess()
        assertFalse(viewModel.uiState.value.switchSuccess)
    }

    // ==================== refreshTenants Tests ====================

    @Test
    fun `refreshTenants success updates available tenants`() = runTest {
        coEvery { tenantRepository.refreshTenants() } returns Result.Success(listOf(tenantA, tenantB))

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.refreshTenants()
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertFalse(state.isLoading)
        assertEquals(2, state.availableTenants.size)
        assertNull(state.error)
    }

    @Test
    fun `refreshTenants failure shows error`() = runTest {
        coEvery { tenantRepository.refreshTenants() } returns
            Result.Error(AppException.Network("Network error"))

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.refreshTenants()
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertFalse(state.isLoading)
        assertEquals("Network error", state.error)
    }

    // ==================== Init Tests ====================

    @Test
    fun `init with null context calls refreshTenants`() = runTest {
        coEvery { tenantRepository.getCurrentTenantContext() } returns null
        coEvery { tenantRepository.refreshTenants() } returns Result.Success(listOf(tenantA))

        viewModel = createViewModel()
        advanceUntilIdle()

        coVerify { tenantRepository.refreshTenants() }
    }

    @Test
    fun `init with valid context populates state`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertFalse(state.isLoading)
        assertEquals(tenantA, state.currentTenant)
        assertEquals(2, state.availableTenants.size)
    }

    @Test
    fun `observeTenantContext updates state on emission`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        // Emit a new context through the flow
        val newContext = TenantContext(
            currentTenantId = "tenant-b",
            currentRole = UserRole.USER,
            availableTenants = listOf(tenantA, tenantB)
        )
        tenantContextFlow.value = newContext
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertEquals("tenant-b", state.currentTenant?.id)
    }
}
