package my.ssdid.drive.presentation.tenant

import my.ssdid.drive.domain.model.TenantRequestResult
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
 * Unit tests for TenantRequestViewModel.
 *
 * Tests cover:
 * - Initial state has empty fields
 * - Submit with blank name shows error
 * - Submit calls repository and sets submitted on success
 * - Submit shows error on conflict (409)
 */
@OptIn(ExperimentalCoroutinesApi::class)
class TenantRequestViewModelTest {

    private lateinit var tenantRepository: TenantRepository
    private lateinit var viewModel: TenantRequestViewModel
    private val testDispatcher = StandardTestDispatcher()

    @Before
    fun setup() {
        Dispatchers.setMain(testDispatcher)
        tenantRepository = mockk()
        viewModel = TenantRequestViewModel(tenantRepository)
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    @Test
    fun `initial state has empty fields and no error`() = runTest {
        val state = viewModel.uiState.value
        assertEquals("", state.organizationName)
        assertEquals("", state.reason)
        assertFalse(state.isLoading)
        assertFalse(state.isSubmitted)
        assertNull(state.error)
    }

    @Test
    fun `updateOrganizationName updates state and clears error`() = runTest {
        // First trigger an error
        viewModel.submitRequest()
        assertNotNull(viewModel.uiState.value.error)

        // Update name should clear error
        viewModel.updateOrganizationName("Acme Corp")
        assertEquals("Acme Corp", viewModel.uiState.value.organizationName)
        assertNull(viewModel.uiState.value.error)
    }

    @Test
    fun `updateReason updates state`() = runTest {
        viewModel.updateReason("We need a team workspace")
        assertEquals("We need a team workspace", viewModel.uiState.value.reason)
    }

    @Test
    fun `submitRequest with blank name shows error`() = runTest {
        viewModel.submitRequest()

        assertEquals("Organization name is required", viewModel.uiState.value.error)
        assertFalse(viewModel.uiState.value.isSubmitted)
    }

    @Test
    fun `submitRequest with whitespace-only name shows error`() = runTest {
        viewModel.updateOrganizationName("   ")
        viewModel.submitRequest()

        assertEquals("Organization name is required", viewModel.uiState.value.error)
        assertFalse(viewModel.uiState.value.isSubmitted)
    }

    @Test
    fun `submitRequest success sets isSubmitted`() = runTest {
        coEvery { tenantRepository.submitTenantRequest("Acme Corp", null) } returns
            Result.success(
                TenantRequestResult(
                    id = "req-123",
                    organizationName = "Acme Corp",
                    status = "pending"
                )
            )

        viewModel.updateOrganizationName("Acme Corp")
        viewModel.submitRequest()
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertFalse(state.isLoading)
        assertTrue(state.isSubmitted)
        assertNull(state.error)

        coVerify { tenantRepository.submitTenantRequest("Acme Corp", null) }
    }

    @Test
    fun `submitRequest with reason passes reason to repository`() = runTest {
        coEvery { tenantRepository.submitTenantRequest("Acme Corp", "We need collaboration") } returns
            Result.success(
                TenantRequestResult(
                    id = "req-456",
                    organizationName = "Acme Corp",
                    status = "pending"
                )
            )

        viewModel.updateOrganizationName("Acme Corp")
        viewModel.updateReason("We need collaboration")
        viewModel.submitRequest()
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertTrue(state.isSubmitted)

        coVerify { tenantRepository.submitTenantRequest("Acme Corp", "We need collaboration") }
    }

    @Test
    fun `submitRequest with blank reason passes null to repository`() = runTest {
        coEvery { tenantRepository.submitTenantRequest("Acme Corp", null) } returns
            Result.success(
                TenantRequestResult(
                    id = "req-789",
                    organizationName = "Acme Corp",
                    status = "pending"
                )
            )

        viewModel.updateOrganizationName("Acme Corp")
        viewModel.updateReason("   ")
        viewModel.submitRequest()
        advanceUntilIdle()

        coVerify { tenantRepository.submitTenantRequest("Acme Corp", null) }
    }

    @Test
    fun `submitRequest shows error on conflict`() = runTest {
        coEvery { tenantRepository.submitTenantRequest("Acme Corp", null) } returns
            Result.error(AppException.Conflict("Organization name already taken"))

        viewModel.updateOrganizationName("Acme Corp")
        viewModel.submitRequest()
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertFalse(state.isLoading)
        assertFalse(state.isSubmitted)
        assertEquals("Organization name already taken", state.error)
    }

    @Test
    fun `submitRequest shows error on network failure`() = runTest {
        coEvery { tenantRepository.submitTenantRequest("Acme Corp", null) } returns
            Result.error(AppException.Network("No internet connection"))

        viewModel.updateOrganizationName("Acme Corp")
        viewModel.submitRequest()
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertFalse(state.isLoading)
        assertFalse(state.isSubmitted)
        assertEquals("No internet connection", state.error)
    }
}
