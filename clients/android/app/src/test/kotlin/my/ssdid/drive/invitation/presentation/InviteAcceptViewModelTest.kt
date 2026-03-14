package my.ssdid.drive.invitation.presentation

import androidx.lifecycle.SavedStateHandle
import app.cash.turbine.test
import my.ssdid.drive.domain.repository.AuthRepository
import my.ssdid.drive.invitation.fixtures.InvitationTestFixtures
import my.ssdid.drive.presentation.auth.InviteAcceptViewModel
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

@OptIn(ExperimentalCoroutinesApi::class)
class InviteAcceptViewModelTest {

    private lateinit var authRepository: AuthRepository
    private lateinit var viewModel: InviteAcceptViewModel
    private val testDispatcher = StandardTestDispatcher()

    @Before
    fun setup() {
        Dispatchers.setMain(testDispatcher)
        authRepository = mockk()
        coEvery { authRepository.getInvitationInfo(any()) } returns
            Result.Success(InvitationTestFixtures.DomainModels.validTokenInvitation)
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
        unmockkAll()
    }

    private fun createViewModel(token: String = "test-token-123"): InviteAcceptViewModel {
        val savedStateHandle = SavedStateHandle(mapOf("token" to token))
        return InviteAcceptViewModel(authRepository, savedStateHandle)
    }

    // ==================== Initialization Tests ====================

    @Test
    fun `initial state with valid token loads invitation info`() = runTest {
        coEvery { authRepository.getInvitationInfo(any()) } returns
            Result.Success(InvitationTestFixtures.DomainModels.validTokenInvitation)

        viewModel = createViewModel("test-token")
        advanceUntilIdle()

        assertEquals("test-token", viewModel.uiState.value.token)
        coVerify { authRepository.getInvitationInfo("test-token") }
    }

    @Test
    fun `initial state with empty token shows error`() = runTest {
        viewModel = createViewModel("")

        viewModel.uiState.test {
            val state = awaitItem()
            assertFalse(state.isLoadingInvitation)
            assertEquals("Invalid invitation link", state.invitationError)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `initial state with blank token tries to load`() = runTest {
        viewModel = createViewModel("   ")

        viewModel.uiState.test {
            awaitItem()
            cancelAndIgnoreRemainingEvents()
        }
    }

    // ==================== Load Invitation Tests ====================

    @Test
    fun `loadInvitationInfo success updates state with invitation`() = runTest {
        val invitation = InvitationTestFixtures.DomainModels.validTokenInvitation
        coEvery { authRepository.getInvitationInfo(any()) } returns Result.Success(invitation)

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertFalse(state.isLoadingInvitation)
            assertEquals(invitation, state.invitation)
            assertNull(state.invitationError)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `loadInvitationInfo with expired invitation shows error`() = runTest {
        val invitation = InvitationTestFixtures.DomainModels.expiredTokenInvitation
        coEvery { authRepository.getInvitationInfo(any()) } returns Result.Success(invitation)

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertFalse(state.isLoadingInvitation)
            assertEquals("This invitation has expired", state.invitationError)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `loadInvitationInfo with revoked invitation shows error`() = runTest {
        val invitation = InvitationTestFixtures.DomainModels.revokedTokenInvitation
        coEvery { authRepository.getInvitationInfo(any()) } returns Result.Success(invitation)

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals("This invitation has been revoked", state.invitationError)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `loadInvitationInfo with already used invitation shows error`() = runTest {
        val invitation = InvitationTestFixtures.DomainModels.alreadyUsedTokenInvitation
        coEvery { authRepository.getInvitationInfo(any()) } returns Result.Success(invitation)

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals("This invitation has already been used", state.invitationError)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `loadInvitationInfo with not found invitation shows error`() = runTest {
        val invitation = InvitationTestFixtures.DomainModels.notFoundTokenInvitation
        coEvery { authRepository.getInvitationInfo(any()) } returns Result.Success(invitation)

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals("Invitation not found", state.invitationError)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `loadInvitationInfo with generic invalid invitation shows error`() = runTest {
        val invitation = InvitationTestFixtures.DomainModels.validTokenInvitation.copy(
            valid = false,
            errorReason = null
        )
        coEvery { authRepository.getInvitationInfo(any()) } returns Result.Success(invitation)

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals("This invitation is no longer valid", state.invitationError)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `loadInvitationInfo failure shows error message`() = runTest {
        coEvery { authRepository.getInvitationInfo(any()) } returns
            Result.Error(AppException.Network("Network error"))

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertFalse(state.isLoadingInvitation)
            assertEquals("Network error", state.invitationError)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `retryLoadInvitation calls repository again`() = runTest {
        coEvery { authRepository.getInvitationInfo(any()) } returns
            Result.Error(AppException.Network("Error")) andThen
            Result.Success(InvitationTestFixtures.DomainModels.validTokenInvitation)

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.retryLoadInvitation()
        advanceUntilIdle()

        coVerify(exactly = 2) { authRepository.getInvitationInfo(any()) }
    }

    // ==================== Accept With Wallet Tests ====================

    @Test
    fun `acceptWithWallet launches wallet invite deep link`() = runTest {
        coEvery { authRepository.getInvitationInfo(any()) } returns
            Result.Success(InvitationTestFixtures.DomainModels.validTokenInvitation)
        coEvery { authRepository.launchWalletInvite(any()) } just Runs

        viewModel = createViewModel("test-token-123")
        advanceUntilIdle()

        viewModel.acceptWithWallet()
        advanceUntilIdle()

        coVerify { authRepository.launchWalletInvite("test-token-123") }
    }

    @Test
    fun `acceptWithWallet sets isWaitingForWallet on success`() = runTest {
        coEvery { authRepository.getInvitationInfo(any()) } returns
            Result.Success(InvitationTestFixtures.DomainModels.validTokenInvitation)
        coEvery { authRepository.launchWalletInvite(any()) } just Runs

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.acceptWithWallet()
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertTrue(state.isWaitingForWallet)
            assertFalse(state.isLoading)
            assertNull(state.registrationError)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `acceptWithWallet failure shows registration error`() = runTest {
        coEvery { authRepository.getInvitationInfo(any()) } returns
            Result.Success(InvitationTestFixtures.DomainModels.validTokenInvitation)
        coEvery { authRepository.launchWalletInvite(any()) } throws
            RuntimeException("Wallet not installed")

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.acceptWithWallet()
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertFalse(state.isLoading)
            assertFalse(state.isWaitingForWallet)
            assertEquals("Wallet not installed", state.registrationError)
            cancelAndIgnoreRemainingEvents()
        }
    }

    // ==================== Wallet Callback Tests ====================

    @Test
    fun `handleWalletCallback saves session and sets isRegistered`() = runTest {
        coEvery { authRepository.getInvitationInfo(any()) } returns
            Result.Success(InvitationTestFixtures.DomainModels.validTokenInvitation)
        coEvery { authRepository.launchWalletInvite(any()) } just Runs
        coEvery { authRepository.saveSession("session-token-abc", "") } just Runs

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.acceptWithWallet()
        advanceUntilIdle()

        viewModel.handleWalletCallback("session-token-abc")
        advanceUntilIdle()

        coVerify { authRepository.saveSession("session-token-abc", "") }
        viewModel.uiState.test {
            val state = awaitItem()
            assertTrue(state.isRegistered)
            assertFalse(state.isWaitingForWallet)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `handleWalletCallback failure shows registration error`() = runTest {
        coEvery { authRepository.getInvitationInfo(any()) } returns
            Result.Success(InvitationTestFixtures.DomainModels.validTokenInvitation)
        coEvery { authRepository.saveSession(any(), any()) } throws
            RuntimeException("Invalid session token")

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.handleWalletCallback("bad-token")
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertFalse(state.isRegistered)
            assertFalse(state.isWaitingForWallet)
            assertEquals("Invalid session token", state.registrationError)
            cancelAndIgnoreRemainingEvents()
        }
    }
}
