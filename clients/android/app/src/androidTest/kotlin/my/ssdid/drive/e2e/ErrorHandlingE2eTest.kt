package my.ssdid.drive.e2e

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import my.ssdid.drive.MainActivity
import my.ssdid.drive.domain.repository.AuthRepository
import dagger.hilt.android.testing.HiltAndroidRule
import dagger.hilt.android.testing.HiltAndroidTest
import kotlinx.coroutines.runBlocking
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import javax.inject.Inject

/**
 * E2E tests for error handling and recovery.
 *
 * Tests cover:
 * - Invalid input error display
 * - Network error handling
 * - Recovery from error states
 */
@HiltAndroidTest
@RunWith(AndroidJUnit4::class)
class ErrorHandlingE2eTest {

    @get:Rule(order = 0)
    val hiltRule = HiltAndroidRule(this)

    @get:Rule(order = 1)
    val composeRule = createAndroidComposeRule<MainActivity>()

    @Inject
    lateinit var authRepository: AuthRepository

    @Before
    fun setUp() {
        hiltRule.inject()
        assumeTrue("E2E tests must be enabled", E2eTestConfig.isE2eEnabled())
        assumeTrue("Must use local backend", E2eTestConfig.isLocalBackend())
        assumeTrue("Tenant slug required", E2eTestConfig.tenantSlug().isNotBlank())

        runBlocking { authRepository.logout() }
    }

    /**
     * Test error handling for invalid login credentials
     *
     * Steps:
     * 1. Navigate to login screen
     * 2. Enter invalid credentials
     * 3. Attempt login
     * 4. Verify error message is displayed
     * 5. Verify user can recover by entering correct credentials
     */
    @Test
    fun errorHandling_invalidCredentials_showsErrorAndAllowsRetry() {
        val tenantSlug = E2eTestConfig.tenantSlug()
        val validEmail = E2eTestConfig.uniqueEmail("error_test")
        val validPassword = "E2ePassword!123".toCharArray()
        val invalidPassword = "wrongpassword".toCharArray()

        try {
            // First register a user
            runBlocking {
                E2eTestUtils.registerUser(authRepository, validEmail, validPassword, tenantSlug)
                authRepository.logout()
            }

            // Wait for login screen
            composeRule.waitUntil(timeoutMillis = 10_000) {
                try {
                    composeRule.onNodeWithTag("login_button").assertIsDisplayed()
                    true
                } catch (_: AssertionError) {
                    false
                }
            }

            // Enter valid email but invalid password
            composeRule.onNode(hasText("Email") and hasSetTextAction())
                .performTextInput(validEmail)

            composeRule.onNode(hasText("Password") and hasSetTextAction())
                .performTextInput(String(invalidPassword))

            // Attempt login
            composeRule.onNodeWithTag("login_button").performClick()

            // Wait for error response
            composeRule.waitUntil(timeoutMillis = 15_000) {
                try {
                    // Check for error message
                    val hasError = composeRule.onAllNodes(
                        hasText("Invalid") or
                                hasText("incorrect") or
                                hasText("failed") or
                                hasText("Error") or
                                hasText("Wrong password")
                    ).fetchSemanticsNodes().isNotEmpty()

                    hasError
                } catch (_: Exception) {
                    false
                }
            }

            E2eTestUtils.takeScreenshot("error_displayed")

            // Verify we're still on login screen (can retry)
            composeRule.onNodeWithTag("login_button").assertExists()

            // Clear and enter correct password
            composeRule.onNode(hasText("Password") and hasSetTextAction())
                .performTextClearance()
            composeRule.onNode(hasText("Password") and hasSetTextAction())
                .performTextInput(String(validPassword))

            // Retry login
            composeRule.onNodeWithTag("login_button").performClick()

            // Wait for successful login
            E2eTestUtils.run {
                composeRule.waitForContentDescription("Open settings", timeoutMillis = 15_000)
            }

            E2eTestUtils.takeScreenshot("error_recovery_success")

            println("Successfully recovered from error state")

        } finally {
            E2eTestUtils.zeroize(validPassword)
            E2eTestUtils.zeroize(invalidPassword)
        }
    }
}
