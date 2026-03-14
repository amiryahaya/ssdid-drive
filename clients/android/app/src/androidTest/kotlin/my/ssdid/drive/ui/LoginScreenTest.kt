package my.ssdid.drive.ui

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import my.ssdid.drive.domain.model.LinkedLogin
import my.ssdid.drive.domain.model.TokenInvitation
import my.ssdid.drive.domain.model.TotpSetupInfo
import my.ssdid.drive.domain.model.User
import my.ssdid.drive.domain.repository.AuthRepository
import my.ssdid.drive.domain.repository.ChallengeInfo
import my.ssdid.drive.presentation.auth.LoginScreen
import my.ssdid.drive.presentation.auth.LoginViewModel
import my.ssdid.drive.presentation.common.theme.SsdidDriveTheme
import my.ssdid.drive.util.AppException
import my.ssdid.drive.util.PushNotificationManager
import my.ssdid.drive.util.Result
import io.mockk.mockk
import kotlinx.coroutines.delay
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class LoginScreenTest {

    @get:Rule
    val composeTestRule = createComposeRule()

    private val mockPushManager: PushNotificationManager = mockk(relaxed = true)

    private class FakeAuthRepository : AuthRepository {
        var emailLoginCalls = 0
        var delayMillis = 0L
        var shouldFail = false

        override suspend fun isAuthenticated(): Boolean = false
        override suspend fun getSession(): String? = null
        override suspend fun saveSession(accessToken: String, refreshToken: String) {}
        override suspend fun logout(): Result<Unit> = Result.success(Unit)
        override suspend fun getCurrentUser(): Result<User> = Result.error(AppException.Unauthorized())
        override suspend fun updateProfile(displayName: String?): Result<User> = Result.error(AppException.Unknown("not implemented"))
        override suspend fun areKeysUnlocked(): Boolean = false

        override suspend fun emailLogin(email: String): Result<Boolean> {
            emailLoginCalls += 1
            if (delayMillis > 0) delay(delayMillis)
            if (shouldFail) return Result.error(AppException.NotFound("Account not found"))
            return Result.success(true)
        }

        override suspend fun emailRegister(email: String, invitationToken: String): Result<Unit> = Result.success(Unit)
        override suspend fun emailRegisterVerify(email: String, code: String, invitationToken: String): Result<User> = Result.error(AppException.Unknown("not implemented"))
        override suspend fun totpVerify(email: String, code: String): Result<User> = Result.error(AppException.Unknown("not implemented"))
        override suspend fun totpSetup(): Result<TotpSetupInfo> = Result.error(AppException.Unknown("not implemented"))
        override suspend fun totpSetupConfirm(code: String): Result<List<String>> = Result.error(AppException.Unknown("not implemented"))
        override suspend fun totpRecovery(email: String): Result<Unit> = Result.success(Unit)
        override suspend fun totpRecoveryVerify(email: String, code: String): Result<User> = Result.error(AppException.Unknown("not implemented"))
        override suspend fun oidcVerify(provider: String, idToken: String, invitationToken: String?): Result<User> = Result.error(AppException.Unknown("not implemented"))
        override suspend fun getLinkedLogins(): Result<List<LinkedLogin>> = Result.success(emptyList())
        override suspend fun linkEmail(email: String): Result<Unit> = Result.success(Unit)
        override suspend fun linkEmailVerify(email: String, code: String): Result<LinkedLogin> = Result.error(AppException.Unknown("not implemented"))
        override suspend fun linkOidc(provider: String, idToken: String): Result<LinkedLogin> = Result.error(AppException.Unknown("not implemented"))
        override suspend fun unlinkLogin(loginId: String): Result<Unit> = Result.success(Unit)
        override suspend fun enableBiometricUnlock(): Result<Unit> = Result.error(AppException.Unknown("not implemented"))
        override suspend fun disableBiometricUnlock(): Result<Unit> = Result.error(AppException.Unknown("not implemented"))
        override suspend fun unlockWithBiometric(): Result<Unit> = Result.error(AppException.Unknown("not implemented"))
        override suspend fun isBiometricUnlockEnabled(): Boolean = false
        override suspend fun lockKeys() {}
        override suspend fun getInvitationInfo(token: String): Result<TokenInvitation> = Result.error(AppException.Unknown("not implemented"))
        override suspend fun createChallenge(action: String): ChallengeInfo = ChallengeInfo("c", "s", "w")
        override suspend fun launchWalletAuth(challenge: ChallengeInfo) {}
        override suspend fun listenForSession(challenge: ChallengeInfo): String = "token"
        override suspend fun launchWalletInvite(token: String) {}
    }

    @Test
    fun loginScreen_displaysAllFields() {
        val viewModel = LoginViewModel(FakeAuthRepository(), mockPushManager)

        composeTestRule.setContent {
            SsdidDriveTheme {
                LoginScreen(onLoginSuccess = {}, viewModel = viewModel)
            }
        }

        composeTestRule.onNodeWithText("SSDID Drive").assertIsDisplayed()
        composeTestRule.onNodeWithText("Post-Quantum Secure File Sharing").assertIsDisplayed()
        composeTestRule.onNodeWithTag("email_input").assertIsDisplayed()
        composeTestRule.onNodeWithTag("login_button").assertIsDisplayed()
        composeTestRule.onNodeWithText("Continue with Email").assertIsDisplayed()
        composeTestRule.onNodeWithText("Sign in with Google").assertIsDisplayed()
        composeTestRule.onNodeWithText("Sign in with Microsoft").assertIsDisplayed()
    }

    @Test
    fun loginScreen_emailSubmit_triggersEmailLogin() {
        val fakeRepo = FakeAuthRepository()
        val viewModel = LoginViewModel(fakeRepo, mockPushManager)

        composeTestRule.setContent {
            SsdidDriveTheme {
                LoginScreen(onLoginSuccess = {}, viewModel = viewModel)
            }
        }

        composeTestRule.onNodeWithTag("email_input").performTextInput("test@example.com")
        composeTestRule.onNodeWithTag("login_button").performClick()

        composeTestRule.waitUntil(3_000) { fakeRepo.emailLoginCalls > 0 }
    }

    @Test
    fun loginScreen_errorState_displaysError() {
        val fakeRepo = FakeAuthRepository().apply { shouldFail = true }
        val viewModel = LoginViewModel(fakeRepo, mockPushManager)

        composeTestRule.setContent {
            SsdidDriveTheme {
                LoginScreen(onLoginSuccess = {}, viewModel = viewModel)
            }
        }

        composeTestRule.onNodeWithTag("email_input").performTextInput("bad@example.com")
        composeTestRule.onNodeWithTag("login_button").performClick()

        composeTestRule.waitUntil(3_000) {
            try {
                composeTestRule.onNodeWithText("Account not found").assertIsDisplayed()
                true
            } catch (_: AssertionError) {
                false
            }
        }
    }
}
