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
 * Accessibility UI tests for publicly accessible screens.
 *
 * These tests verify that interactive elements have content descriptions or are
 * otherwise accessible to users relying on assistive technologies such as TalkBack.
 * No backend connection is required.
 *
 * Run with: ./gradlew connectedDevDebugAndroidTest
 */
@HiltAndroidTest
@RunWith(AndroidJUnit4::class)
class AccessibilityUiTest {

    @get:Rule(order = 0)
    val hiltRule = HiltAndroidRule(this)

    @get:Rule(order = 1)
    val composeTestRule = createAndroidComposeRule<MainActivity>()

    @Before
    fun setUp() {
        hiltRule.inject()
    }

    // ==================== LoginScreen accessibility ====================

    @Test
    fun loginScreen_appLogoHasContentDescription() {
        // The Image composable has contentDescription = "SSDID Drive"
        composeTestRule.onNodeWithContentDescription("SSDID Drive").assertExists()
    }

    @Test
    fun loginScreen_inviteCodeIconHasContentDescription() {
        // The GroupAdd icon inside the invite card has contentDescription = "Enter invite code"
        composeTestRule.onNodeWithContentDescription("Enter invite code").assertExists()
    }

    @Test
    fun loginScreen_emailFieldIsAccessible() {
        // OutlinedTextField with testTag has the "email_input" tag and a visible label
        composeTestRule.onNodeWithTag("email_input").assertIsDisplayed()
        composeTestRule.onNodeWithText("Email").assertExists()
    }

    @Test
    fun loginScreen_continueButtonIsAccessible() {
        // Button is labelled with visible text — no separate content description needed
        composeTestRule.onNodeWithTag("login_button")
            .assertIsDisplayed()
            .assertHasClickAction()
    }

    @Test
    fun loginScreen_googleButtonIsAccessible() {
        composeTestRule.onNodeWithTag("google_button")
            .assertIsDisplayed()
            .assertHasClickAction()
    }

    @Test
    fun loginScreen_microsoftButtonIsAccessible() {
        composeTestRule.onNodeWithTag("microsoft_button")
            .assertIsDisplayed()
            .assertHasClickAction()
    }

    @Test
    fun loginScreen_recoveryButtonIsAccessible() {
        composeTestRule.onNodeWithText("Lost your authenticator? Recover access")
            .assertIsDisplayed()
            .assertHasClickAction()
    }

    @Test
    fun loginScreen_needOrganizationButtonIsAccessible() {
        composeTestRule.onNodeWithText("Need an organization? Request one")
            .assertIsDisplayed()
            .assertHasClickAction()
    }

    // ==================== JoinTenantScreen accessibility ====================

    @Test
    fun joinTenantScreen_backButtonHasContentDescription() {
        composeTestRule.onNodeWithText("Have an invite code?").performClick()
        composeTestRule.waitForIdle()
        composeTestRule.onNodeWithContentDescription("Navigate back")
            .assertIsDisplayed()
            .assertHasClickAction()
    }

    @Test
    fun joinTenantScreen_joinOrganizationIconHasContentDescription() {
        composeTestRule.onNodeWithText("Have an invite code?").performClick()
        composeTestRule.waitForIdle()
        // Header icon contentDescription = "Join organization"
        composeTestRule.onNodeWithContentDescription("Join organization").assertExists()
    }

    @Test
    fun joinTenantScreen_inviteCodeFieldIsAccessible() {
        composeTestRule.onNodeWithText("Have an invite code?").performClick()
        composeTestRule.waitForIdle()
        composeTestRule.onNodeWithText("Invite Code").assertIsDisplayed()
    }

    @Test
    fun joinTenantScreen_lookUpButtonIsAccessible() {
        composeTestRule.onNodeWithText("Have an invite code?").performClick()
        composeTestRule.waitForIdle()
        composeTestRule.onNodeWithText("Look Up")
            .assertIsDisplayed()
            .assertHasClickAction()
    }

    // ==================== TenantRequestScreen accessibility ====================

    @Test
    fun tenantRequestScreen_backButtonHasContentDescription() {
        composeTestRule.onNodeWithText("Need an organization? Request one").performClick()
        composeTestRule.waitForIdle()
        composeTestRule.onNodeWithContentDescription("Navigate back")
            .assertIsDisplayed()
            .assertHasClickAction()
    }

    @Test
    fun tenantRequestScreen_organizationIconHasContentDescription() {
        composeTestRule.onNodeWithText("Need an organization? Request one").performClick()
        composeTestRule.waitForIdle()
        // Header icon contentDescription = "Organization"
        composeTestRule.onNodeWithContentDescription("Organization").assertExists()
    }

    @Test
    fun tenantRequestScreen_submitButtonIsAccessible() {
        composeTestRule.onNodeWithText("Need an organization? Request one").performClick()
        composeTestRule.waitForIdle()
        composeTestRule.onNodeWithText("Submit Request")
            .assertIsDisplayed()
            .assertHasClickAction()
    }
}
