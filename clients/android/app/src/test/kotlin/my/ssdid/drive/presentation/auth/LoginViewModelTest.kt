package my.ssdid.drive.presentation.auth

import app.cash.turbine.test
import my.ssdid.drive.domain.model.User
import my.ssdid.drive.domain.repository.AuthRepository
import my.ssdid.drive.util.AppException
import my.ssdid.drive.util.PushNotificationManager
import my.ssdid.drive.util.Result
import io.mockk.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class LoginViewModelTest {

    private lateinit var authRepository: AuthRepository
    private lateinit var pushNotificationManager: PushNotificationManager
    private lateinit var viewModel: LoginViewModel
    private val testDispatcher = StandardTestDispatcher()

    private val testUser = User(
        id = "user-1",
        email = "test@example.com",
        displayName = "Test User"
    )

    @Before
    fun setup() {
        Dispatchers.setMain(testDispatcher)
        authRepository = mockk()
        pushNotificationManager = mockk(relaxed = true)
        viewModel = LoginViewModel(authRepository, pushNotificationManager)
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    // ==================== Initial State ====================

    @Test
    fun `initial state is correct`() = runTest {
        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals("", state.email)
            assertFalse(state.isLoading)
            assertFalse(state.isAuthenticated)
            assertNull(state.navigateToTotp)
            assertNull(state.error)
        }
    }

    // ==================== Email Login ====================

    @Test
    fun `updateEmail updates state`() = runTest {
        viewModel.updateEmail("user@example.com")
        assertEquals("user@example.com", viewModel.uiState.value.email)
    }

    @Test
    fun `submitEmail with blank email shows error`() = runTest {
        viewModel.submitEmail()
        advanceUntilIdle()

        assertEquals("Email is required", viewModel.uiState.value.error)
    }

    @Test
    fun `submitEmail navigates to TOTP when required`() = runTest {
        coEvery { authRepository.emailLogin("test@example.com") } returns Result.success(true)

        viewModel.updateEmail("test@example.com")
        viewModel.submitEmail()
        advanceUntilIdle()

        assertEquals("test@example.com", viewModel.uiState.value.navigateToTotp)
        assertFalse(viewModel.uiState.value.isLoading)
    }

    @Test
    fun `submitEmail shows error when TOTP not set up`() = runTest {
        coEvery { authRepository.emailLogin("test@example.com") } returns Result.success(false)

        viewModel.updateEmail("test@example.com")
        viewModel.submitEmail()
        advanceUntilIdle()

        assertNotNull(viewModel.uiState.value.error)
        assertNull(viewModel.uiState.value.navigateToTotp)
    }

    @Test
    fun `submitEmail shows error on failure`() = runTest {
        coEvery { authRepository.emailLogin("bad@example.com") } returns
            Result.error(AppException.NotFound("Account not found"))

        viewModel.updateEmail("bad@example.com")
        viewModel.submitEmail()
        advanceUntilIdle()

        assertEquals("Account not found", viewModel.uiState.value.error)
    }

    @Test
    fun `submitEmail shows loading state`() = runTest {
        coEvery { authRepository.emailLogin(any()) } returns Result.success(true)

        viewModel.uiState.test {
            skipItems(1) // initial

            viewModel.updateEmail("test@example.com")
            awaitItem() // email update

            viewModel.submitEmail()

            val loading = awaitItem()
            assertTrue(loading.isLoading)

            testDispatcher.scheduler.advanceUntilIdle()
            val done = awaitItem()
            assertFalse(done.isLoading)

            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `onTotpNavigated clears navigateToTotp`() = runTest {
        coEvery { authRepository.emailLogin("test@example.com") } returns Result.success(true)

        viewModel.updateEmail("test@example.com")
        viewModel.submitEmail()
        advanceUntilIdle()

        assertNotNull(viewModel.uiState.value.navigateToTotp)

        viewModel.onTotpNavigated()
        assertNull(viewModel.uiState.value.navigateToTotp)
    }

    // ==================== OIDC Login ====================

    @Test
    fun `handleOidcResult sets authenticated on success`() = runTest {
        coEvery { authRepository.oidcVerify("google", "id-token-123", null) } returns
            Result.success(testUser)

        viewModel.handleOidcResult("google", "id-token-123")
        advanceUntilIdle()

        assertTrue(viewModel.uiState.value.isAuthenticated)
        assertFalse(viewModel.uiState.value.isLoading)
    }

    @Test
    fun `handleOidcResult shows error on failure`() = runTest {
        coEvery { authRepository.oidcVerify("microsoft", "bad-token", null) } returns
            Result.error(AppException.Unauthorized())

        viewModel.handleOidcResult("microsoft", "bad-token")
        advanceUntilIdle()

        assertFalse(viewModel.uiState.value.isAuthenticated)
        assertNotNull(viewModel.uiState.value.error)
    }
}
