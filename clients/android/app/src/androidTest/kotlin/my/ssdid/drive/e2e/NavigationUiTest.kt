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
 * UI tests for basic navigation flows that do not require auth.
 *
 * These tests verify that the app starts on LoginScreen and that navigation between
 * publicly accessible screens works correctly (login → join tenant, login → tenant
 * request, back-stack behaviour).
 *
 * Run with: ./gradlew connectedDevDebugAndroidTest
 */
@HiltAndroidTest
@RunWith(AndroidJUnit4::class)
class NavigationUiTest {

    @get:Rule(order = 0)
    val hiltRule = HiltAndroidRule(this)

    @get:Rule(order = 1)
    val composeTestRule = createAndroidComposeRule<MainActivity>()

    @Before
    fun setUp() {
        hiltRule.inject()
    }

    // ==================== Initial destination ====================

    @Test
    fun appLaunches_withoutCrash() {
        composeTestRule.onNodeWithText("SSDID Drive").assertIsDisplayed()
    }

    @Test
    fun appLaunches_showsLoginScreen() {
        composeTestRule.onNodeWithText("Post-Quantum Secure File Sharing").assertIsDisplayed()
        composeTestRule.onNodeWithTag("email_input").assertIsDisplayed()
    }

    // ==================== LoginScreen destinations ====================

    @Test
    fun loginScreen_hasInviteCodeEntry() {
        composeTestRule.onNodeWithText("Have an invite code?").assertIsDisplayed()
    }

    @Test
    fun loginScreen_hasNeedOrganizationButton() {
        composeTestRule.onNodeWithText("Need an organization? Request one").assertIsDisplayed()
    }

    @Test
    fun loginScreen_hasRecoveryButton() {
        composeTestRule.onNodeWithText("Lost your authenticator? Recover access").assertIsDisplayed()
    }

    // ==================== Login → JoinTenant navigation ====================

    @Test
    fun navigation_loginToJoinTenant_showsJoinScreen() {
        composeTestRule.onNodeWithText("Have an invite code?").performClick()
        composeTestRule.waitForIdle()
        composeTestRule.onNodeWithText("Join Organization").assertIsDisplayed()
    }

    @Test
    fun navigation_joinTenantBack_returnsToLogin() {
        composeTestRule.onNodeWithText("Have an invite code?").performClick()
        composeTestRule.waitForIdle()
        composeTestRule.onNodeWithContentDescription("Navigate back").performClick()
        composeTestRule.waitForIdle()
        composeTestRule.onNodeWithText("SSDID Drive").assertIsDisplayed()
    }

    // ==================== Login → TenantRequest navigation ====================

    @Test
    fun navigation_loginToTenantRequest_showsRequestScreen() {
        composeTestRule.onNodeWithText("Need an organization? Request one").performClick()
        composeTestRule.waitForIdle()
        composeTestRule.onNodeWithText("Request Organization").assertIsDisplayed()
    }

    @Test
    fun navigation_tenantRequestBack_returnsToLogin() {
        composeTestRule.onNodeWithText("Need an organization? Request one").performClick()
        composeTestRule.waitForIdle()
        composeTestRule.onNodeWithContentDescription("Navigate back").performClick()
        composeTestRule.waitForIdle()
        composeTestRule.onNodeWithText("SSDID Drive").assertIsDisplayed()
    }

    // ==================== Deep link start ====================

    @Test
    fun navigation_deepLinkScreensDoNotCrashOnBack() {
        // Verify JoinTenant → back → TenantRequest → back: no crash or blank screen.
        composeTestRule.onNodeWithText("Have an invite code?").performClick()
        composeTestRule.waitForIdle()
        composeTestRule.onNodeWithContentDescription("Navigate back").performClick()
        composeTestRule.waitForIdle()

        composeTestRule.onNodeWithText("Need an organization? Request one").performClick()
        composeTestRule.waitForIdle()
        composeTestRule.onNodeWithContentDescription("Navigate back").performClick()
        composeTestRule.waitForIdle()

        composeTestRule.onNodeWithText("SSDID Drive").assertIsDisplayed()
    }
}
