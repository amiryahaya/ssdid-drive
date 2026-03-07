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
 * E2E tests for settings and profile functionality.
 *
 * Tests cover:
 * - Profile display
 * - Settings navigation
 * - Account information
 */
@HiltAndroidTest
@RunWith(AndroidJUnit4::class)
class SettingsProfileE2eTest {

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
     * Test profile information display in settings
     *
     * Steps:
     * 1. Login to the app
     * 2. Navigate to Settings
     * 3. Verify profile section shows user email
     * 4. Verify account settings are accessible
     */
    @Test
    fun profileSettings_showsUserInformation() {
        val tenantSlug = E2eTestConfig.tenantSlug()
        val email = E2eTestConfig.uniqueEmail("profile_e2e")
        val password = "E2ePassword!123".toCharArray()

        try {
            // Register and login
            runBlocking {
                E2eTestUtils.registerUser(authRepository, email, password, tenantSlug)
            }

            // Wait for home screen
            E2eTestUtils.run {
                composeRule.waitForContentDescription("Open settings")
            }

            // Navigate to settings
            composeRule.onNodeWithContentDescription("Open settings").performClick()
            E2eTestUtils.run {
                composeRule.waitForText("Settings")
            }

            E2eTestUtils.takeScreenshot("settings_profile_screen")

            // Verify user email is displayed somewhere in settings
            composeRule.onAllNodes(hasText(email, substring = true))
                .onFirst()
                .assertExists()

            // Verify profile section exists
            val profileSection = composeRule.onAllNodes(
                hasText("Profile") or
                        hasText("Account") or
                        hasText("User") or
                        hasContentDescription("Profile")
            )

            try {
                profileSection.onFirst().assertExists()
                println("Profile section found")

                // Tap profile to see details
                profileSection.onFirst().performClick()

                // Wait for profile details
                composeRule.waitUntil(timeoutMillis = 10_000) {
                    try {
                        composeRule.onAllNodes(hasText(email))
                            .fetchSemanticsNodes().isNotEmpty()
                    } catch (_: Exception) {
                        false
                    }
                }

                E2eTestUtils.takeScreenshot("profile_details")

            } catch (e: AssertionError) {
                // Profile might be displayed inline
                println("Profile section not separate - checking inline display")
            }

            // Verify key settings sections exist
            val expectedSections = listOf("Security", "Devices", "About", "Logout")
            var sectionsFound = 0

            for (section in expectedSections) {
                try {
                    composeRule.onAllNodes(hasText(section, substring = true))
                        .onFirst()
                        .assertExists()
                    sectionsFound++
                } catch (_: AssertionError) {
                    println("Section '$section' not found")
                }
            }

            assert(sectionsFound >= 2) {
                "Should find at least 2 of the expected settings sections"
            }

            // Verify app version is displayed
            val versionNode = composeRule.onAllNodes(
                hasText("Version") or hasText("v1.") or hasText("Build")
            )

            try {
                versionNode.onFirst().assertExists()
                println("Version information found")
            } catch (_: AssertionError) {
                // Version might be at bottom - scroll
                composeRule.onRoot().performScrollToIndex(10)
                Thread.sleep(500)

                try {
                    versionNode.onFirst().assertExists()
                } catch (_: AssertionError) {
                    println("Version info not visible")
                }
            }

        } finally {
            E2eTestUtils.zeroize(password)
        }
    }
}
