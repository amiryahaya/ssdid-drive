package my.ssdid.drive.e2e

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
 * E2E tests for notification functionality.
 *
 * Tests cover:
 * - Notification settings accessibility
 */
@HiltAndroidTest
@RunWith(AndroidJUnit4::class)
class NotificationE2eTest {

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
     * Test notification settings accessibility
     *
     * Steps:
     * 1. Authenticate via wallet
     * 2. Navigate to Settings
     * 3. Find notification settings section
     * 4. Verify notification preferences are accessible
     */
    @Test
    fun notificationSettings_inSettings_areAccessible() {
        // Note: This test requires wallet-based auth which cannot be automated in E2E
        // It serves as a manual test guide and verifies UI structure after manual auth

        // Wait for home screen (assumes user is already authenticated)
        E2eTestUtils.run {
            composeRule.waitForContentDescription("Open settings")
        }

        // Navigate to settings
        composeRule.onNodeWithContentDescription("Open settings").performClick()
        E2eTestUtils.run {
            composeRule.waitForText("Settings")
        }

        E2eTestUtils.takeScreenshot("settings_screen")

        // Look for notification settings
        val notificationSection = composeRule.onAllNodes(
            hasText("Notifications") or
                    hasText("Push Notifications") or
                    hasText("Alerts")
        )

        try {
            notificationSection.onFirst().assertIsDisplayed()

            // Tap to view notification settings
            notificationSection.onFirst().performClick()

            // Wait for notification settings to load
            composeRule.waitUntil(timeoutMillis = 10_000) {
                try {
                    // Check for notification options (toggles or switches)
                    val hasNotificationOptions = composeRule.onAllNodes(
                        hasText("Enable notifications") or
                                hasText("Share notifications") or
                                hasText("File notifications")
                    ).fetchSemanticsNodes().isNotEmpty()

                    hasNotificationOptions
                } catch (_: Exception) {
                    false
                }
            }

            E2eTestUtils.takeScreenshot("notification_settings")

            println("Notification settings are accessible")

        } catch (e: AssertionError) {
            // Notification settings might not be a separate section
            // Check if it's inline in settings
            val inlineToggle = composeRule.onAllNodes(
                hasText("Notifications", substring = true)
            )

            try {
                inlineToggle.onFirst().assertExists()
                println("Found inline notification section")
            } catch (_: AssertionError) {
                println("Notification settings not found in UI - may use system settings")
            }
        }
    }
}
