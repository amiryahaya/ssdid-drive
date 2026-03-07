package my.ssdid.drive.ui

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.test.hasProgressBarRangeInfo
import my.ssdid.drive.domain.model.User
import my.ssdid.drive.domain.repository.AuthRepository
import my.ssdid.drive.presentation.auth.LoginScreen
import my.ssdid.drive.presentation.auth.LoginViewModel
import my.ssdid.drive.presentation.common.theme.SsdidDriveTheme
import my.ssdid.drive.util.AppException
import my.ssdid.drive.util.Result
import kotlinx.coroutines.delay
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * UI tests for LoginScreen.
 *
 * Tests cover:
 * - Initial screen rendering
 * - Form input
 * - Loading state
 * - Error display
 * - Navigation to register
 */
@RunWith(AndroidJUnit4::class)
class LoginScreenTest {

    @get:Rule
    val composeTestRule = createComposeRule()

    private class FakeAuthRepository : AuthRepository {
        var loginCalls = 0
        var delayMillis = 0L
        var nextResult: Result<User> = Result.success(
            User(id = "user-1", email = "test@example.com")
        )

        override suspend fun isAuthenticated(): Boolean = false

        override suspend fun login(
            email: String,
            password: CharArray,
            tenantSlug: String?
        ): Result<User> {
            loginCalls += 1
            if (delayMillis > 0) {
                delay(delayMillis)
            }
            return nextResult
        }

        override suspend fun register(email: String, password: CharArray, tenantSlug: String): Result<User> {
            return Result.error(AppException.Unknown("not implemented"))
        }

        override suspend fun logout(): Result<Unit> = Result.success(Unit)

        override suspend fun getCurrentUser(): Result<User> =
            Result.error(AppException.Unauthorized())

        override suspend fun updateProfile(displayName: String?): Result<User> =
            Result.error(AppException.Unknown("not implemented"))

        override suspend fun refreshToken(): Result<Unit> =
            Result.error(AppException.Unauthorized())

        override suspend fun unlockKeys(password: CharArray): Result<Unit> =
            Result.error(AppException.Unauthorized())

        override suspend fun areKeysUnlocked(): Boolean = false

        override suspend fun changePassword(currentPassword: CharArray, newPassword: CharArray): Result<Unit> =
            Result.error(AppException.Unknown("not implemented"))

        override suspend fun enableBiometricUnlock(password: CharArray): Result<Unit> =
            Result.error(AppException.Unknown("not implemented"))

        override suspend fun disableBiometricUnlock(): Result<Unit> =
            Result.error(AppException.Unknown("not implemented"))

        override suspend fun unlockWithBiometric(): Result<Unit> =
            Result.error(AppException.Unknown("not implemented"))

        override suspend fun isBiometricUnlockEnabled(): Boolean = false

        override suspend fun lockKeys() {}
    }

    // ==================== Initial State Tests ====================

    @Test
    fun loginScreen_displaysAllFields() {
        val viewModel = LoginViewModel(FakeAuthRepository())

        composeTestRule.setContent {
            SsdidDriveTheme {
                LoginScreen(
                    onNavigateToRegister = {},
                    onLoginSuccess = {},
                    viewModel = viewModel
                )
            }
        }

        // Verify all input fields are displayed
        composeTestRule.onNodeWithText("Email").assertIsDisplayed()
        composeTestRule.onNodeWithText("Password").assertIsDisplayed()
        composeTestRule.onNodeWithText("Organization (optional)").assertIsDisplayed()

        // Verify login button is displayed
        composeTestRule.onNodeWithTag("login_button").assertIsDisplayed()

        // Verify register link is displayed
        composeTestRule.onNodeWithText("Don't have an account? Register").assertIsDisplayed()
    }

    // ==================== Input Tests ====================

    @Test
    fun loginScreen_emailInput_updatesState() {
        val viewModel = LoginViewModel(FakeAuthRepository())

        composeTestRule.setContent {
            SsdidDriveTheme {
                LoginScreen(
                    onNavigateToRegister = {},
                    onLoginSuccess = {},
                    viewModel = viewModel
                )
            }
        }

        composeTestRule.onNodeWithText("Email")
            .performTextInput("test@example.com")

        composeTestRule.runOnIdle {
            assert(viewModel.uiState.value.email == "test@example.com")
        }
    }

    @Test
    fun loginScreen_passwordInput_updatesState() {
        val viewModel = LoginViewModel(FakeAuthRepository())

        composeTestRule.setContent {
            SsdidDriveTheme {
                LoginScreen(
                    onNavigateToRegister = {},
                    onLoginSuccess = {},
                    viewModel = viewModel
                )
            }
        }

        composeTestRule.onNodeWithText("Password")
            .performTextInput("password123")

        composeTestRule.runOnIdle {
            assert(viewModel.uiState.value.password == "password123")
        }
    }

    @Test
    fun loginScreen_tenantInput_updatesState() {
        val viewModel = LoginViewModel(FakeAuthRepository())

        composeTestRule.setContent {
            SsdidDriveTheme {
                LoginScreen(
                    onNavigateToRegister = {},
                    onLoginSuccess = {},
                    viewModel = viewModel
                )
            }
        }

        composeTestRule.onNodeWithText("Organization (optional)")
            .performTextInput("my-org")

        composeTestRule.runOnIdle {
            assert(viewModel.uiState.value.tenantSlug == "my-org")
        }
    }

    // ==================== Button Tests ====================

    @Test
    fun loginScreen_loginButton_triggersCallback() {
        val fakeRepo = FakeAuthRepository()
        val viewModel = LoginViewModel(fakeRepo)

        composeTestRule.setContent {
            SsdidDriveTheme {
                LoginScreen(
                    onNavigateToRegister = {},
                    onLoginSuccess = {},
                    viewModel = viewModel
                )
            }
        }

        composeTestRule.runOnIdle {
            viewModel.updateEmail("test@example.com")
            viewModel.updatePassword("password")
            viewModel.updateTenantSlug("org")
        }

        composeTestRule.onNodeWithTag("login_button").performClick()

        composeTestRule.waitUntil(3_000) { fakeRepo.loginCalls > 0 }
    }

    @Test
    fun loginScreen_registerLink_triggersNavigation() {
        var navigateToRegisterCalled = false
        val viewModel = LoginViewModel(FakeAuthRepository())

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
        val fakeRepo = FakeAuthRepository().apply { delayMillis = 2_000 }
        val viewModel = LoginViewModel(fakeRepo)

        composeTestRule.setContent {
            SsdidDriveTheme {
                LoginScreen(
                    onNavigateToRegister = {},
                    onLoginSuccess = {},
                    viewModel = viewModel
                )
            }
        }

        composeTestRule.runOnIdle {
            viewModel.updateEmail("test@example.com")
            viewModel.updatePassword("password")
        }
        composeTestRule.onNodeWithTag("login_button").performClick()

        composeTestRule.waitUntil(3_000) {
            composeTestRule.onAllNodes(hasProgressBarRangeInfo(ProgressBarRangeInfo.Indeterminate))
                .fetchSemanticsNodes().isNotEmpty()
        }

        composeTestRule.onNodeWithTag("login_button").assertIsNotEnabled()
    }

    @Test
    fun loginScreen_loadingState_showsIndicator() {
        val fakeRepo = FakeAuthRepository().apply { delayMillis = 2_000 }
        val viewModel = LoginViewModel(fakeRepo)

        composeTestRule.setContent {
            SsdidDriveTheme {
                LoginScreen(
                    onNavigateToRegister = {},
                    onLoginSuccess = {},
                    viewModel = viewModel
                )
            }
        }

        composeTestRule.runOnIdle {
            viewModel.updateEmail("test@example.com")
            viewModel.updatePassword("password")
        }
        composeTestRule.onNodeWithTag("login_button").performClick()

        composeTestRule.waitUntil(3_000) {
            composeTestRule.onAllNodes(hasProgressBarRangeInfo(ProgressBarRangeInfo.Indeterminate))
                .fetchSemanticsNodes().isNotEmpty()
        }
    }

    // ==================== Error State Tests ====================

    @Test
    fun loginScreen_errorState_displaysError() {
        val viewModel = LoginViewModel(FakeAuthRepository())

        composeTestRule.setContent {
            SsdidDriveTheme {
                LoginScreen(
                    onNavigateToRegister = {},
                    onLoginSuccess = {},
                    viewModel = viewModel
                )
            }
        }

        composeTestRule.onNodeWithTag("login_button").performClick()

        composeTestRule.onNodeWithText("Email is required").assertIsDisplayed()
    }

    // ==================== Pre-filled State Tests ====================

    @Test
    fun loginScreen_prefilledState_showsValues() {
        val viewModel = LoginViewModel(FakeAuthRepository())

        composeTestRule.setContent {
            SsdidDriveTheme {
                LoginScreen(
                    onNavigateToRegister = {},
                    onLoginSuccess = {},
                    viewModel = viewModel
                )
            }
        }

        composeTestRule.runOnIdle {
            viewModel.updateEmail("prefilled@example.com")
            viewModel.updateTenantSlug("prefilled-org")
        }

        composeTestRule.onNodeWithText("prefilled@example.com").assertIsDisplayed()
        composeTestRule.onNodeWithText("prefilled-org").assertIsDisplayed()
    }
}
