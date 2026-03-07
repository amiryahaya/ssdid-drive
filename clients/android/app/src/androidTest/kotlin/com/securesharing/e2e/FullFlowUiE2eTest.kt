package com.securesharing.e2e

import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.securesharing.MainActivity
import com.securesharing.domain.repository.AuthRepository
import dagger.hilt.android.testing.HiltAndroidRule
import dagger.hilt.android.testing.HiltAndroidTest
import kotlinx.coroutines.runBlocking
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import javax.inject.Inject

@HiltAndroidTest
@RunWith(AndroidJUnit4::class)
class FullFlowUiE2eTest {

    @get:Rule
    val hiltRule = HiltAndroidRule(this)

    @get:Rule
    val composeRule = createAndroidComposeRule<MainActivity>()

    @Inject
    lateinit var authRepository: AuthRepository

    @Before
    fun setUp() {
        hiltRule.inject()
        assumeTrue(E2eTestConfig.isE2eEnabled())
        assumeTrue(E2eTestConfig.isLocalBackend())
        assumeTrue(E2eTestConfig.tenantSlug().isNotBlank())

        runBlocking { authRepository.logout() }
    }

    @Test
    fun registrationLoginLogout_uiFlow() {
        val tenantSlug = E2eTestConfig.tenantSlug()
        val email = E2eTestConfig.uniqueEmail("ui_e2e")
        val password = "E2ePassword!123".toCharArray()

        try {
            composeRule.onNodeWithText("Don't have an account? Register").assertIsDisplayed()
            composeRule.onNodeWithText("Don't have an account? Register").performClick()

            fillTextField("Organization", tenantSlug)
            fillTextField("Email", email)
            fillTextField("Password", String(password))
            fillTextField("Confirm Password", String(password))

            composeRule.onNode(hasText("Register") and hasClickAction()).performClick()

            waitForNodeWithContentDescription("Open settings")

            composeRule.onNodeWithContentDescription("Open settings").performClick()
            waitForNode(hasText("Settings"))

            composeRule.onNodeWithText("Logout").performClick()
            composeRule.onAllNodesWithText("Logout").onLast().performClick()

            fillTextField("Email", email)
            fillTextField("Password", String(password))

            composeRule.onNodeWithTag("login_button").performClick()
            waitForNodeWithContentDescription("Open settings")
        } finally {
            E2eTestUtils.zeroize(password)
        }
    }

    private fun fillTextField(label: String, text: String) {
        composeRule
            .onNode(hasText(label) and hasSetTextAction(), useUnmergedTree = true)
            .performTextInput(text)
    }

    private fun waitForNode(matcher: SemanticsMatcher) {
        composeRule.waitUntil(timeoutMillis = 15_000) {
            try {
                composeRule.onNode(matcher).assertIsDisplayed()
                true
            } catch (_: AssertionError) {
                false
            }
        }
    }

    private fun waitForNodeWithContentDescription(description: String) {
        waitForNode(hasContentDescription(description))
    }
}
