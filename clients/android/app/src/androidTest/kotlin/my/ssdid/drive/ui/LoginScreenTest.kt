package my.ssdid.drive.ui

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import io.mockk.every
import io.mockk.mockk
import my.ssdid.drive.domain.model.TokenInvitation
import my.ssdid.drive.domain.model.User
import my.ssdid.drive.domain.repository.AuthRepository
import my.ssdid.drive.domain.repository.ChallengeInfo
import my.ssdid.drive.presentation.auth.LoginScreen
import my.ssdid.drive.presentation.auth.LoginViewModel
import my.ssdid.drive.presentation.common.theme.SsdidDriveTheme
import my.ssdid.drive.util.AppException
import my.ssdid.drive.util.PushNotificationManager
import my.ssdid.drive.util.Result
import kotlinx.coroutines.delay
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * UI tests for LoginScreen with SSDID Wallet authentication.
 *
 * Tests cover:
 * - Initial screen rendering
 * - Sign-in button behavior
 * - Loading state
 * - Error display
 * - Navigation to register
 */
@RunWith(AndroidJUnit4::class)
class LoginScreenTest {

    @get:Rule
    val composeTestRule = createComposeRule()

    private val mockPushManager: PushNotificationManager = mockk(relaxed = true)

    private class FakeAuthRepository : AuthRepository {
        var createChallengeCalls = 0
        var delayMillis = 0L
        var shouldFail = false

        override suspend fun isAuthenticated(): Boolean = false

        override suspend fun createChallenge(action: String): ChallengeInfo {
            createChallengeCalls += 1
            if (delayMillis > 0) {
                delay(delayMillis)
            }
            if (shouldFail) {
                throw Exception("Failed to create challenge")
            }
            return ChallengeInfo(
                challengeId = "challenge-1",
                subscriberSecret = "secret-1",
                walletDeepLink = "ssdid://login?challenge_id=challenge-1"
            )
        }

        override suspend fun launchWalletAuth(challenge: ChallengeInfo) {}

        override suspend fun listenForSession(challenge: ChallengeInfo): String = "test-token"

        override suspend fun saveSession(sessionToken: String) {}

        override suspend fun getSession(): String? = null

        override suspend fun logout(): Result<Unit> = Result.success(Unit)

        override suspend fun getCurrentUser(): Result<User> =
            Result.error(AppException.Unauthorized())

        override suspend fun updateProfile(displayName: String?): Result<User> =
            Result.error(AppException.Unknown("not implemented"))

        override suspend fun areKeysUnlocked(): Boolean = false

        override suspend fun enableBiometricUnlock(): Result<Unit> =
            Result.error(AppException.Unknown("not implemented"))

        override suspend fun disableBiometricUnlock(): Result<Unit> =
            Result.error(AppException.Unknown("not implemented"))

        override suspend fun unlockWithBiometric(): Result<Unit> =
            Result.error(AppException.Unknown("not implemented"))

        override suspend fun isBiometricUnlockEnabled(): Boolean = false

        override suspend fun lockKeys() {}

        override suspend fun getInvitationInfo(token: String): Result<TokenInvitation> =
            Result.error(AppException.Unknown("not implemented"))
    }

    // ==================== Initial State Tests ====================

    @Test
    fun loginScreen_displaysAllFields() {
        val viewModel = LoginViewModel(FakeAuthRepository(), mockPushManager)

        composeTestRule.setContent {
            SsdidDriveTheme {
                LoginScreen(
                    onLoginSuccess = {},
                    viewModel = viewModel
                )
            }
        }

        // Verify app title and subtitle
        composeTestRule.onNodeWithText("SSDID Drive").assertIsDisplayed()
        composeTestRule.onNodeWithText("Post-Quantum Secure File Sharing").assertIsDisplayed()

        // Verify sign-in button
        composeTestRule.onNodeWithTag("login_button").assertIsDisplayed()
        composeTestRule.onNodeWithText("Sign in with SSDID Wallet").assertIsDisplayed()

        // Verify register link
        composeTestRule.onNodeWithText("Don't have an account? Register").assertIsDisplayed()
    }

    // ==================== Button Tests ====================

    @Test
    fun loginScreen_signInButton_triggersWalletAuth() {
        val fakeRepo = FakeAuthRepository()
        val viewModel = LoginViewModel(fakeRepo, mockPushManager)

        composeTestRule.setContent {
            SsdidDriveTheme {
                LoginScreen(
                    onLoginSuccess = {},
                    viewModel = viewModel
                )
            }
        }

        composeTestRule.onNodeWithTag("login_button").performClick()

        composeTestRule.waitUntil(3_000) { fakeRepo.createChallengeCalls > 0 }
    }

    @Test
    fun loginScreen_registerLink_triggersNavigation() {
        var navigateToRegisterCalled = false
        val viewModel = LoginViewModel(FakeAuthRepository(), mockPushManager)

        composeTestRule.setContent {
            SsdidDriveTheme {
                LoginScreen(
                    onNavigateToRegister = { navigateToRegisterCalled = true },
                    onLoginSuccess = {},
                    viewModel = viewModel
                )
            }
        }

        composeTestRule.onNodeWithText("Don't have an account? Register").performClick()

        assert(navigateToRegisterCalled)
    }

    // ==================== Loading State Tests ====================

    @Test
    fun loginScreen_loadingState_disablesButton() {
        val fakeRepo = FakeAuthRepository().apply { delayMillis = 5_000 }
        val viewModel = LoginViewModel(fakeRepo, mockPushManager)

        composeTestRule.setContent {
            SsdidDriveTheme {
                LoginScreen(
                    onLoginSuccess = {},
                    viewModel = viewModel
                )
            }
        }

        composeTestRule.onNodeWithTag("login_button").performClick()

        composeTestRule.waitUntil(3_000) {
            try {
                composeTestRule.onNodeWithTag("login_button").assertIsNotEnabled()
                true
            } catch (_: AssertionError) {
                false
            }
        }
    }

    // ==================== Error State Tests ====================

    @Test
    fun loginScreen_errorState_displaysError() {
        val fakeRepo = FakeAuthRepository().apply { shouldFail = true }
        val viewModel = LoginViewModel(fakeRepo, mockPushManager)

        composeTestRule.setContent {
            SsdidDriveTheme {
                LoginScreen(
                    onLoginSuccess = {},
                    viewModel = viewModel
                )
            }
        }

        composeTestRule.onNodeWithTag("login_button").performClick()

        composeTestRule.waitUntil(3_000) {
            try {
                composeTestRule.onNodeWithText("Failed to create challenge").assertIsDisplayed()
                true
            } catch (_: AssertionError) {
                false
            }
        }
    }
}
