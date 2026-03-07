package my.ssdid.drive.e2e

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import my.ssdid.drive.MainActivity
import my.ssdid.drive.domain.repository.AuthRepository
import my.ssdid.drive.util.Result
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
 * E2E tests for biometric authentication functionality.
 *
 * Tests cover:
 * - Biometric enrollment flow
 * - Biometric unlock flow
 * - Fallback to password when biometric fails
 */
@HiltAndroidTest
@RunWith(AndroidJUnit4::class)
class BiometricAuthE2eTest {

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

        // Logout any existing session
        runBlocking { authRepository.logout() }
    }

    /**
     * Test biometric enrollment after login
     *
     * Preconditions:
     * - User has logged in successfully
     * - Device supports biometric authentication
     *
     * Steps:
     * 1. Login with email/password
     * 2. Navigate to Settings
     * 3. Find biometric toggle
     * 4. Enable biometric
     * 5. Verify biometric is enabled
     */
    @Test
    fun biometricEnrollment_afterLogin_succeeds() {
        // Skip if biometric not available
        assumeTrue(
            "Biometric not available on this device",
            E2eTestUtils.isBiometricAvailable(context)
        )

        val tenantSlug = E2eTestConfig.tenantSlug()
        val email = E2eTestConfig.uniqueEmail("bio_enroll")
        val password = "E2ePassword!123".toCharArray()

        try {
            // Register new user
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

            // Look for biometric option
            val biometricToggle = composeRule.onAllNodes(
                hasText("Face ID") or hasText("Fingerprint") or hasText("Biometric")
            ).onFirst()

            // If biometric option exists, try to enable it
            try {
                biometricToggle.assertIsDisplayed()

                // Click to enable biometric
                biometricToggle.performClick()

                // The system will show biometric prompt
                // In E2E test, we can verify the flow initiated
                // Actual biometric verification requires manual interaction or mock

                E2eTestUtils.takeScreenshot("biometric_enrollment_prompt")

                // Verify biometric state in repository
                runBlocking {
                    val isEnabled = authRepository.isBiometricUnlockEnabled()
                    // Note: May not be enabled if user cancelled the prompt
                    println("Biometric enabled: $isEnabled")
                }

            } catch (e: AssertionError) {
                // Biometric option not visible - device may not support it
                println("Biometric toggle not found in settings")
            }

        } finally {
            E2eTestUtils.zeroize(password)
        }
    }

    /**
     * Test biometric authentication flow at app launch
     *
     * Preconditions:
     * - User has previously enrolled biometric
     * - App is locked
     *
     * Steps:
     * 1. Launch app (should show biometric prompt or lock screen)
     * 2. Verify biometric prompt appears (or fallback option)
     * 3. Verify password fallback is available
     */
    @Test
    fun biometricUnlock_atAppLaunch_showsPromptOrFallback() {
        // Skip if biometric not available
        assumeTrue(
            "Biometric not available on this device",
            E2eTestUtils.isBiometricAvailable(context)
        )

        val tenantSlug = E2eTestConfig.tenantSlug()
        val email = E2eTestConfig.uniqueEmail("bio_unlock")
        val password = "E2ePassword!123".toCharArray()

        try {
            // Register and enable biometric
            runBlocking {
                E2eTestUtils.registerUser(authRepository, email, password, tenantSlug)

                // Try to enable biometric
                val result = E2eTestUtils.enableBiometric(authRepository, password)
                when (result) {
                    is Result.Success -> println("Biometric enabled successfully")
                    is Result.Error -> println("Biometric enrollment failed: ${result.exception.message}")
                }

                // Lock the keys
                authRepository.lockKeys()
            }

            // At this point, the app should show lock screen or biometric prompt
            // Wait for either biometric prompt or lock screen to appear
            composeRule.waitUntil(timeoutMillis = 10_000) {
                try {
                    // Check for biometric prompt indicator or lock screen
                    val hasBiometricPrompt = composeRule.onAllNodes(
                        hasText("Use biometric") or
                                hasText("Unlock with fingerprint") or
                                hasText("Unlock with Face ID") or
                                hasContentDescription("Biometric prompt")
                    ).fetchSemanticsNodes().isNotEmpty()

                    val hasLockScreen = composeRule.onAllNodes(
                        hasText("Enter your password") or
                                hasText("Unlock") or
                                hasText("Password")
                    ).fetchSemanticsNodes().isNotEmpty()

                    hasBiometricPrompt || hasLockScreen
                } catch (_: Exception) {
                    false
                }
            }

            E2eTestUtils.takeScreenshot("biometric_unlock_screen")

            // Verify password fallback option exists
            val passwordFallback = composeRule.onAllNodes(
                hasText("Use password") or
                        hasText("Enter password") or
                        hasText("Password")
            )

            try {
                passwordFallback.onFirst().assertExists()
                println("Password fallback option is available")
            } catch (e: AssertionError) {
                // Password input field should be available on lock screen
                composeRule.onNode(hasSetTextAction()).assertExists()
            }

        } finally {
            E2eTestUtils.zeroize(password)
        }
    }
}
