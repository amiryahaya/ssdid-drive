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
 * UI tests for the JoinTenant screen (invite code entry flow).
 *
 * Navigation to JoinTenantScreen is triggered from LoginScreen by clicking the
 * "Have an invite code?" card. These tests navigate to that screen and verify its
 * UI elements without submitting a real code to the backend.
 *
 * Run with: ./gradlew connectedDevDebugAndroidTest
 */
@HiltAndroidTest
@RunWith(AndroidJUnit4::class)
class JoinTenantUiTest {

    @get:Rule(order = 0)
    val hiltRule = HiltAndroidRule(this)

    @get:Rule(order = 1)
    val composeTestRule = createAndroidComposeRule<MainActivity>()

    @Before
    fun setUp() {
        hiltRule.inject()
        // Navigate to JoinTenant screen via the invite code card on LoginScreen.
        composeTestRule.onNodeWithText("Have an invite code?").performClick()
        composeTestRule.waitForIdle()
    }

    // ==================== Screen structure ====================

    @Test
    fun joinTenant_displaysTopBarTitle() {
        composeTestRule.onNodeWithText("Join Organization").assertIsDisplayed()
    }

    @Test
    fun joinTenant_displaysBackButton() {
        composeTestRule.onNodeWithContentDescription("Navigate back").assertIsDisplayed()
    }

    @Test
    fun joinTenant_displaysScreenHeading() {
        composeTestRule.onNodeWithText("Enter Invite Code").assertIsDisplayed()
    }

    @Test
    fun joinTenant_displaysInstructionText() {
        composeTestRule.onNodeWithText(
            "Enter the code you received to join an organization.",
            substring = true
        ).assertIsDisplayed()
    }

    @Test
    fun joinTenant_displaysInviteCodeField() {
        composeTestRule.onNodeWithText("Invite Code").assertIsDisplayed()
    }

    @Test
    fun joinTenant_displaysPlaceholderHint() {
        composeTestRule.onNodeWithText("e.g. ACME-7K9X").assertIsDisplayed()
    }

    @Test
    fun joinTenant_displaysLookUpButton() {
        composeTestRule.onNodeWithText("Look Up").assertIsDisplayed()
    }

    // ==================== Button enabled state ====================

    @Test
    fun joinTenant_lookUpDisabledWhenCodeEmpty() {
        composeTestRule.onNodeWithText("Look Up").assertIsNotEnabled()
    }

    @Test
    fun joinTenant_lookUpEnabledAfterCodeEntry() {
        composeTestRule.onNodeWithText("Invite Code")
            .performTextInput("ACME-7K9X")
        composeTestRule.onNodeWithText("Look Up").assertIsEnabled()
    }

    // ==================== Navigation ====================

    @Test
    fun joinTenant_backButtonReturnsToLoginScreen() {
        composeTestRule.onNodeWithContentDescription("Navigate back").performClick()
        composeTestRule.waitForIdle()
        composeTestRule.onNodeWithText("SSDID Drive").assertIsDisplayed()
    }

    // ==================== Code input ====================

    @Test
    fun joinTenant_inviteCodeFieldAcceptsInput() {
        val testCode = "TEST-1234"
        composeTestRule.onNodeWithText("Invite Code").performTextInput(testCode)
        composeTestRule.onNodeWithText("Invite Code")
            .assertTextContains(testCode, substring = true)
    }
}
