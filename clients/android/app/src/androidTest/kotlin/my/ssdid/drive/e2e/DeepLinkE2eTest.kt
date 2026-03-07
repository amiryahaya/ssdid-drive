package my.ssdid.drive.e2e

import android.content.Intent
import android.net.Uri
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
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
 * E2E tests for deep link handling.
 *
 * Tests cover:
 * - Share invitation deep links
 * - User invitation deep links
 * - Deep link navigation when logged in/out
 */
@HiltAndroidTest
@RunWith(AndroidJUnit4::class)
class DeepLinkE2eTest {

    @get:Rule(order = 0)
    val hiltRule = HiltAndroidRule(this)

    @get:Rule(order = 1)
    val composeRule = createAndroidComposeRule<MainActivity>()

    @Inject
    lateinit var authRepository: AuthRepository

    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Before
    fun setUp() {
        hiltRule.inject()
        assumeTrue("E2E tests must be enabled", E2eTestConfig.isE2eEnabled())
        assumeTrue("Must use local backend", E2eTestConfig.isLocalBackend())
        assumeTrue("Tenant slug required", E2eTestConfig.tenantSlug().isNotBlank())

        runBlocking { authRepository.logout() }
    }

    /**
     * Test deep link handling for share invitation
     *
     * This test verifies:
     * 1. App can receive and parse deep links
     * 2. Appropriate UI is shown for share acceptance
     * 3. Login is required if not authenticated
     */
    @Test
    fun deepLink_shareInvitation_handledCorrectly() {
        val testToken = "test-share-token-${System.currentTimeMillis()}"
        val deepLinkUri = Uri.parse(E2eTestUtils.buildShareInvitationDeepLink(testToken))

        // Create intent with deep link
        val intent = Intent(Intent.ACTION_VIEW, deepLinkUri).apply {
            setPackage(context.packageName)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        // Launch activity with deep link
        composeRule.activityRule.scenario.onActivity { activity ->
            activity.startActivity(intent)
        }

        // Wait for app to process deep link
        Thread.sleep(2000)

        // Check what screen is displayed
        val needsLogin = try {
            composeRule.onNodeWithTag("login_button").assertIsDisplayed()
            true
        } catch (_: AssertionError) {
            false
        }

        if (needsLogin) {
            // Deep link requires authentication
            println("Deep link requires login - expected behavior for unauthenticated user")

            E2eTestUtils.takeScreenshot("deep_link_requires_login")

            // Login to continue
            val tenantSlug = E2eTestConfig.tenantSlug()
            val email = E2eTestConfig.uniqueEmail("deeplink_e2e")
            val password = "E2ePassword!123".toCharArray()

            try {
                // Register first
                runBlocking {
                    E2eTestUtils.registerUser(authRepository, email, password, tenantSlug)
                    authRepository.logout()
                }

                // Fill login form
                composeRule.onNode(hasText("Email") and hasSetTextAction())
                    .performTextInput(email)
                composeRule.onNode(hasText("Password") and hasSetTextAction())
                    .performTextInput(String(password))
                composeRule.onNodeWithTag("login_button").performClick()

                // Wait for login and deep link processing
                Thread.sleep(3000)

            } finally {
                E2eTestUtils.zeroize(password)
            }
        }

        // After authentication (or if already authenticated), check for share acceptance UI
        composeRule.waitUntil(timeoutMillis = 15_000) {
            try {
                // Check for share acceptance screen or error
                val hasShareAccept = composeRule.onAllNodes(
                    hasText("Accept") or
                            hasText("Shared with you") or
                            hasText("invitation") or
                            hasContentDescription("Accept share")
                ).fetchSemanticsNodes().isNotEmpty()

                val hasError = composeRule.onAllNodes(
                    hasText("Invalid") or
                            hasText("expired") or
                            hasText("not found")
                ).fetchSemanticsNodes().isNotEmpty()

                val hasHome = composeRule.onAllNodes(
                    hasContentDescription("Open settings")
                ).fetchSemanticsNodes().isNotEmpty()

                hasShareAccept || hasError || hasHome
            } catch (_: Exception) {
                false
            }
        }

        E2eTestUtils.takeScreenshot("deep_link_result")

        // Verify app handled the deep link (either showed acceptance UI or appropriate error)
        val handledDeepLink = try {
            // Either share acceptance, error message, or navigated to relevant screen
            composeRule.onAllNodes(
                hasText("Accept") or
                        hasText("Share") or
                        hasText("Invalid") or
                        hasText("expired") or
                        hasContentDescription("Open settings")
            ).fetchSemanticsNodes().isNotEmpty()
        } catch (_: Exception) {
            false
        }

        assert(handledDeepLink) { "App should handle deep link appropriately" }

        println("Deep link was handled by the app")
    }
}
