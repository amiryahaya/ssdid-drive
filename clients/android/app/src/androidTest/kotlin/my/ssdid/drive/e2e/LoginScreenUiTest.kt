package my.ssdid.drive.e2e

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import dagger.hilt.android.testing.HiltAndroidRule
import dagger.hilt.android.testing.HiltAndroidTest
import my.ssdid.drive.MainActivity
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * UI tests for the LoginScreen that do not require a running backend or auth session.
 *
 * These tests verify that the login screen renders its UI elements correctly and that
 * basic interactions work as expected. The app must be in a logged-out state (default
 * on a fresh install / test run without a pre-seeded session).
 *
 * Run with: ./gradlew connectedDevDebugAndroidTest
 */
@HiltAndroidTest
@RunWith(AndroidJUnit4::class)
class LoginScreenUiTest {

    @get:Rule(order = 0)
    val hiltRule = HiltAndroidRule(this)

    @get:Rule(order = 1)
    val composeTestRule = createAndroidComposeRule<MainActivity>()

    @Before
    fun setUp() {
        hiltRule.inject()
    }

    // ==================== Static content ====================

    @Test
    fun loginScreen_displaysAppTitle() {
        composeTestRule.onNodeWithText("SSDID Drive").assertIsDisplayed()
    }

    @Test
    fun loginScreen_displaysTagline() {
        composeTestRule.onNodeWithText("Post-Quantum Secure File Sharing").assertIsDisplayed()
    }

    @Test
    fun loginScreen_displaysEmailField() {
        composeTestRule.onNodeWithTag("email_input").assertIsDisplayed()
    }

    @Test
    fun loginScreen_displaysEmailFieldLabel() {
        composeTestRule.onNodeWithText("Email").assertIsDisplayed()
    }

    @Test
    fun loginScreen_displaysContinueButton() {
        composeTestRule.onNodeWithTag("login_button").assertIsDisplayed()
    }

    @Test
    fun loginScreen_displaysContinueButtonText() {
        composeTestRule.onNodeWithText("Continue with Email").assertIsDisplayed()
    }

    @Test
    fun loginScreen_displaysGoogleButton() {
        composeTestRule.onNodeWithTag("google_button").assertIsDisplayed()
    }

    @Test
    fun loginScreen_displaysGoogleButtonText() {
        composeTestRule.onNodeWithText("Sign in with Google").assertIsDisplayed()
    }

    @Test
    fun loginScreen_displaysMicrosoftButton() {
        composeTestRule.onNodeWithTag("microsoft_button").assertIsDisplayed()
    }

    @Test
    fun loginScreen_displaysMicrosoftButtonText() {
        composeTestRule.onNodeWithText("Sign in with Microsoft").assertIsDisplayed()
    }

    @Test
    fun loginScreen_displaysInviteCodeCard() {
        composeTestRule.onNodeWithText("Have an invite code?").assertIsDisplayed()
    }

    @Test
    fun loginScreen_displaysInviteCodeSubtext() {
        composeTestRule.onNodeWithText("Enter your code to join an organization").assertIsDisplayed()
    }

    @Test
    fun loginScreen_displaysNeedOrganizationButton() {
        composeTestRule.onNodeWithText("Need an organization? Request one").assertIsDisplayed()
    }

    @Test
    fun loginScreen_displaysRecoveryButton() {
        composeTestRule.onNodeWithText("Lost your authenticator? Recover access").assertIsDisplayed()
    }

    // ==================== Button enabled state ====================

    @Test
    fun loginScreen_continueDisabledWhenEmailEmpty() {
        composeTestRule.onNodeWithTag("login_button").assertIsNotEnabled()
    }

    @Test
    fun loginScreen_continueEnabledAfterEmailEntry() {
        composeTestRule.onNodeWithTag("email_input").performTextInput("test@example.com")
        composeTestRule.onNodeWithTag("login_button").assertIsEnabled()
    }

    @Test
    fun loginScreen_continueDisabledAfterClearingEmail() {
        composeTestRule.onNodeWithTag("email_input").performTextInput("test@example.com")
        composeTestRule.onNodeWithTag("login_button").assertIsEnabled()
        composeTestRule.onNodeWithTag("email_input").performTextClearance()
        composeTestRule.onNodeWithTag("login_button").assertIsNotEnabled()
    }

    @Test
    fun loginScreen_googleButtonEnabledInitially() {
        composeTestRule.onNodeWithTag("google_button").assertIsEnabled()
    }

    @Test
    fun loginScreen_microsoftButtonEnabledInitially() {
        composeTestRule.onNodeWithTag("microsoft_button").assertIsEnabled()
    }

    // ==================== Interaction sanity ====================

    @Test
    fun loginScreen_emailFieldAcceptsInput() {
        val testEmail = "user@example.com"
        composeTestRule.onNodeWithTag("email_input").performTextInput(testEmail)
        composeTestRule.onNodeWithTag("email_input").assertTextContains(testEmail)
    }

    @Test
    fun loginScreen_clickingInviteCodeCardDoesNotCrash() {
        // Clicking navigates away to JoinTenant; we just verify the click is handled.
        composeTestRule.onNodeWithText("Have an invite code?").performClick()
        composeTestRule.waitForIdle()
        // No assertion — simply verifying no crash occurs.
    }

    @Test
    fun loginScreen_clickingNeedOrganizationDoesNotCrash() {
        composeTestRule.onNodeWithText("Need an organization? Request one").performClick()
        composeTestRule.waitForIdle()
        // No assertion — simply verifying no crash occurs.
    }
}
