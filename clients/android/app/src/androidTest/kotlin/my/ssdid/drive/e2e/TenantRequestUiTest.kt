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
 * UI tests for the TenantRequest screen (request a new organization).
 *
 * Navigation to TenantRequestScreen is triggered from LoginScreen by clicking the
 * "Need an organization? Request one" button. These tests verify the form UI without
 * submitting a real request to the backend.
 *
 * Run with: ./gradlew connectedDevDebugAndroidTest
 */
@HiltAndroidTest
@RunWith(AndroidJUnit4::class)
class TenantRequestUiTest {

    @get:Rule(order = 0)
    val hiltRule = HiltAndroidRule(this)

    @get:Rule(order = 1)
    val composeTestRule = createAndroidComposeRule<MainActivity>()

    @Before
    fun setUp() {
        hiltRule.inject()
        // Navigate to TenantRequest screen via the button on LoginScreen.
        composeTestRule.onNodeWithText("Need an organization? Request one").performClick()
        composeTestRule.waitForIdle()
    }

    // ==================== Screen structure ====================

    @Test
    fun tenantRequest_displaysTopBarTitle() {
        composeTestRule.onNodeWithText("Request Organization").assertIsDisplayed()
    }

    @Test
    fun tenantRequest_displaysBackButton() {
        composeTestRule.onNodeWithContentDescription("Navigate back").assertIsDisplayed()
    }

    @Test
    fun tenantRequest_displaysFormHeading() {
        composeTestRule.onNodeWithText("Create Your Organization").assertIsDisplayed()
    }

    @Test
    fun tenantRequest_displaysDescriptionText() {
        composeTestRule.onNodeWithText(
            "Submit a request to create a new organization",
            substring = true
        ).assertIsDisplayed()
    }

    @Test
    fun tenantRequest_displaysOrganizationNameField() {
        composeTestRule.onNodeWithText("Organization Name").assertIsDisplayed()
    }

    @Test
    fun tenantRequest_displaysOrganizationNamePlaceholder() {
        composeTestRule.onNodeWithText("e.g. Acme Corp").assertIsDisplayed()
    }

    @Test
    fun tenantRequest_displaysReasonField() {
        composeTestRule.onNodeWithText("Reason (optional)").assertIsDisplayed()
    }

    @Test
    fun tenantRequest_displaysSubmitButton() {
        composeTestRule.onNodeWithText("Submit Request").assertIsDisplayed()
    }

    // ==================== Button enabled state ====================

    @Test
    fun tenantRequest_submitDisabledWhenOrganizationNameEmpty() {
        composeTestRule.onNodeWithText("Submit Request").assertIsNotEnabled()
    }

    @Test
    fun tenantRequest_submitEnabledAfterOrganizationNameEntry() {
        composeTestRule.onNodeWithText("Organization Name")
            .performTextInput("Acme Corp")
        composeTestRule.onNodeWithText("Submit Request").assertIsEnabled()
    }

    @Test
    fun tenantRequest_submitDisabledAfterClearingOrganizationName() {
        composeTestRule.onNodeWithText("Organization Name")
            .performTextInput("Acme Corp")
        composeTestRule.onNodeWithText("Submit Request").assertIsEnabled()
        composeTestRule.onNodeWithText("Organization Name").performTextClearance()
        composeTestRule.onNodeWithText("Submit Request").assertIsNotEnabled()
    }

    // ==================== Field input ====================

    @Test
    fun tenantRequest_organizationNameFieldAcceptsInput() {
        val orgName = "My Test Org"
        composeTestRule.onNodeWithText("Organization Name").performTextInput(orgName)
        composeTestRule.onNodeWithText("Organization Name")
            .assertTextContains(orgName, substring = true)
    }

    @Test
    fun tenantRequest_reasonFieldAcceptsInput() {
        val reason = "We need secure file sharing for our team."
        composeTestRule.onNodeWithText("Reason (optional)").performTextInput(reason)
        composeTestRule.onNodeWithText("Reason (optional)")
            .assertTextContains(reason, substring = true)
    }

    // ==================== Navigation ====================

    @Test
    fun tenantRequest_canNavigateBack() {
        composeTestRule.onNodeWithContentDescription("Navigate back").performClick()
        composeTestRule.waitForIdle()
        composeTestRule.onNodeWithText("SSDID Drive").assertIsDisplayed()
    }

    @Test
    fun tenantRequest_navigateBackFromLoginScreenEntryPoint() {
        // Arrived from LoginScreen, back returns to LoginScreen.
        composeTestRule.onNodeWithContentDescription("Navigate back").performClick()
        composeTestRule.waitForIdle()
        composeTestRule.onNodeWithText("Post-Quantum Secure File Sharing").assertIsDisplayed()
    }
}
