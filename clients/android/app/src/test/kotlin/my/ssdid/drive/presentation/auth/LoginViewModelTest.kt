package my.ssdid.drive.presentation.auth

import app.cash.turbine.test
import my.ssdid.drive.domain.repository.AuthRepository
import my.ssdid.drive.domain.repository.ChallengeInfo
import my.ssdid.drive.util.PushNotificationManager
import io.mockk.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

/**
 * Unit tests for LoginViewModel.
 *
 * Tests cover:
 * - Initial state
 * - Sign in with SSDID Wallet flow
 * - Wallet callback handling
 * - Error handling
 * - UI state transitions
 */
@OptIn(ExperimentalCoroutinesApi::class)
class LoginViewModelTest {

    private lateinit var authRepository: AuthRepository
    private lateinit var pushNotificationManager: PushNotificationManager
    private lateinit var viewModel: LoginViewModel
    private val testDispatcher = StandardTestDispatcher()

    private val testChallengeInfo = ChallengeInfo(
        challengeId = "challenge-456",
        subscriberSecret = "secret-456",
        walletDeepLink = "ssdid://login?challenge_id=challenge-456"
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

    // ==================== Initial State Tests ====================

    @Test
    fun `initial state is correct`() = runTest {
        viewModel.uiState.test {
            val state = awaitItem()
            assertFalse(state.isLoading)
            assertFalse(state.isWaitingForWallet)
            assertFalse(state.isAuthenticated)
            assertNull(state.error)
        }
    }

    // ==================== Sign In With Wallet Tests ====================

    @Test
    fun `signInWithWallet creates challenge and launches wallet`() = runTest {
        coEvery { authRepository.createChallenge("authenticate") } returns testChallengeInfo
        coEvery { authRepository.launchWalletAuth(testChallengeInfo) } just Runs

        viewModel.signInWithWallet()
        advanceUntilIdle()

        coVerify { authRepository.createChallenge("authenticate") }
        coVerify { authRepository.launchWalletAuth(testChallengeInfo) }
    }

    @Test
    fun `signInWithWallet sets isWaitingForWallet on success`() = runTest {
        coEvery { authRepository.createChallenge("authenticate") } returns testChallengeInfo
        coEvery { authRepository.launchWalletAuth(testChallengeInfo) } just Runs

        viewModel.signInWithWallet()
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertFalse(state.isLoading)
            assertTrue(state.isWaitingForWallet)
            assertNull(state.error)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `signInWithWallet shows loading state during challenge creation`() = runTest {
        coEvery { authRepository.createChallenge("authenticate") } returns testChallengeInfo
        coEvery { authRepository.launchWalletAuth(testChallengeInfo) } just Runs

        viewModel.uiState.test {
            skipItems(1) // Skip initial state

            viewModel.signInWithWallet()

            // Should show loading
            val loadingState = awaitItem()
            assertTrue(loadingState.isLoading)
            assertNull(loadingState.error)

            // Should transition to waiting for wallet
            testDispatcher.scheduler.advanceUntilIdle()
            val waitingState = awaitItem()
            assertFalse(waitingState.isLoading)
            assertTrue(waitingState.isWaitingForWallet)

            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `signInWithWallet failure shows error`() = runTest {
        coEvery { authRepository.createChallenge("authenticate") } throws
            RuntimeException("Wallet not installed")

        viewModel.signInWithWallet()
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertFalse(state.isLoading)
            assertFalse(state.isWaitingForWallet)
            assertEquals("Wallet not installed", state.error)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `signInWithWallet network error shows error`() = runTest {
        coEvery { authRepository.createChallenge("authenticate") } throws
            RuntimeException("Unable to connect")

        viewModel.signInWithWallet()
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertFalse(state.isLoading)
            assertNotNull(state.error)
            cancelAndIgnoreRemainingEvents()
        }
    }

    // ==================== Wallet Callback Tests ====================

    @Test
    fun `handleWalletCallback saves session and sets isAuthenticated`() = runTest {
        coEvery { authRepository.saveSession("session-token-abc") } just Runs

        viewModel.handleWalletCallback("session-token-abc")
        advanceUntilIdle()

        coVerify { authRepository.saveSession("session-token-abc") }
        viewModel.uiState.test {
            val state = awaitItem()
            assertTrue(state.isAuthenticated)
            assertFalse(state.isWaitingForWallet)
            assertNull(state.error)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `handleWalletCallback failure shows error`() = runTest {
        coEvery { authRepository.saveSession(any()) } throws
            RuntimeException("Invalid session token")

        viewModel.handleWalletCallback("bad-token")
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertFalse(state.isAuthenticated)
            assertFalse(state.isWaitingForWallet)
            assertEquals("Invalid session token", state.error)
            cancelAndIgnoreRemainingEvents()
        }
    }

    // ==================== Full Flow Test ====================

    @Test
    fun `full wallet auth flow from sign in to callback`() = runTest {
        coEvery { authRepository.createChallenge("authenticate") } returns testChallengeInfo
        coEvery { authRepository.launchWalletAuth(testChallengeInfo) } just Runs
        coEvery { authRepository.saveSession("session-token-xyz") } just Runs

        // Step 1: Initiate sign in
        viewModel.signInWithWallet()
        advanceUntilIdle()

        // Should be waiting for wallet
        assertTrue(viewModel.uiState.value.isWaitingForWallet)
        assertFalse(viewModel.uiState.value.isAuthenticated)

        // Step 2: Wallet calls back
        viewModel.handleWalletCallback("session-token-xyz")
        advanceUntilIdle()

        // Should be authenticated
        assertTrue(viewModel.uiState.value.isAuthenticated)
        assertFalse(viewModel.uiState.value.isWaitingForWallet)
    }
}
