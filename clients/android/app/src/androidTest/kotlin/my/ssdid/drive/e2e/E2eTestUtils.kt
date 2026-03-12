package my.ssdid.drive.e2e

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.util.Base64
import androidx.biometric.BiometricManager
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.AndroidComposeTestRule
import androidx.test.ext.junit.rules.ActivityScenarioRule
import my.ssdid.drive.MainActivity
import my.ssdid.drive.data.remote.dto.PublicKeysDto
import my.ssdid.drive.domain.model.PublicKeys
import my.ssdid.drive.domain.model.User
import my.ssdid.drive.domain.repository.AuthRepository
import my.ssdid.drive.domain.repository.TenantRepository
import my.ssdid.drive.util.Result

object E2eTestUtils {
    fun toPublicKeys(dto: PublicKeysDto): PublicKeys {
        return PublicKeys(
            kem = Base64.decode(dto.kem, Base64.NO_WRAP),
            sign = Base64.decode(dto.sign, Base64.NO_WRAP),
            mlKem = dto.mlKem?.let { Base64.decode(it, Base64.NO_WRAP) },
            mlDsa = dto.mlDsa?.let { Base64.decode(it, Base64.NO_WRAP) }
        )
    }

    /**
     * Register a user via the API.
     *
     * Note: Auth is now wallet-based (SSDID). This method is a stub for E2E tests
     * that were written for the old email/password auth system.
     * These tests should be migrated to use wallet-based auth via deep links.
     */
    @Suppress("UNUSED_PARAMETER")
    suspend fun registerUser(
        authRepository: AuthRepository,
        email: String,
        password: CharArray,
        tenantSlug: String
    ): User {
        throw UnsupportedOperationException(
            "Email/password registration is no longer supported. " +
            "Auth is now wallet-based (SSDID). Migrate this E2E test to use wallet deep links."
        )
    }

    /**
     * Login and unlock keys.
     *
     * Note: Auth is now wallet-based (SSDID). This method is a stub for E2E tests
     * that were written for the old email/password auth system.
     */
    @Suppress("UNUSED_PARAMETER")
    suspend fun loginAndUnlock(
        authRepository: AuthRepository,
        email: String,
        password: CharArray,
        tenantSlug: String
    ): User {
        throw UnsupportedOperationException(
            "Email/password login is no longer supported. " +
            "Auth is now wallet-based (SSDID). Migrate this E2E test to use wallet deep links."
        )
    }

    fun zeroize(chars: CharArray) {
        for (index in chars.indices) {
            chars[index] = '\u0000'
        }
    }

    // ==================== Biometric Helpers ====================

    /**
     * Check if biometric authentication is available on the device
     */
    fun isBiometricAvailable(context: Context): Boolean {
        val biometricManager = BiometricManager.from(context)
        return when (biometricManager.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG)) {
            BiometricManager.BIOMETRIC_SUCCESS -> true
            else -> false
        }
    }

    /**
     * Enable biometric unlock for the current user
     */
    suspend fun enableBiometric(
        authRepository: AuthRepository
    ): Result<Unit> {
        return authRepository.enableBiometricUnlock()
    }

    /**
     * Disable biometric unlock
     */
    suspend fun disableBiometric(authRepository: AuthRepository): Result<Unit> {
        return authRepository.disableBiometricUnlock()
    }

    // ==================== Network Helpers ====================

    /**
     * Check if device has network connectivity
     */
    fun isNetworkAvailable(context: Context): Boolean {
        val connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val network = connectivityManager.activeNetwork ?: return false
        val capabilities = connectivityManager.getNetworkCapabilities(network) ?: return false
        return capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
    }

    /**
     * Simulate offline mode by disabling network (requires system permissions in real tests)
     * For E2E tests, this primarily verifies offline UI behavior
     */
    fun simulateOfflineMode(): Boolean {
        // Note: Actually disabling network requires system permissions
        // In E2E tests, we verify the app handles lack of connectivity gracefully
        return true
    }

    // ==================== Tenant Helpers ====================

    /**
     * Switch to a different tenant
     */
    suspend fun switchTenant(
        tenantRepository: TenantRepository,
        tenantId: String
    ) = tenantRepository.switchTenant(tenantId)

    /**
     * Get list of available tenants for current user
     */
    suspend fun listTenants(tenantRepository: TenantRepository) = tenantRepository.getUserTenants()

    // ==================== Compose Test Helpers ====================

    /**
     * Wait for a node matching the given semantic matcher to appear
     */
    fun AndroidComposeTestRule<ActivityScenarioRule<MainActivity>, MainActivity>.waitForNode(
        matcher: SemanticsMatcher,
        timeoutMillis: Long = 15_000
    ) {
        waitUntil(timeoutMillis = timeoutMillis) {
            try {
                onNode(matcher).assertIsDisplayed()
                true
            } catch (_: AssertionError) {
                false
            }
        }
    }

    /**
     * Wait for a node with specific text to appear
     */
    fun AndroidComposeTestRule<ActivityScenarioRule<MainActivity>, MainActivity>.waitForText(
        text: String,
        timeoutMillis: Long = 15_000
    ) {
        waitForNode(hasText(text), timeoutMillis)
    }

    /**
     * Wait for a node with specific content description to appear
     */
    fun AndroidComposeTestRule<ActivityScenarioRule<MainActivity>, MainActivity>.waitForContentDescription(
        description: String,
        timeoutMillis: Long = 15_000
    ) {
        waitForNode(hasContentDescription(description), timeoutMillis)
    }

    /**
     * Wait for loading state to complete (no loading indicator visible)
     */
    fun AndroidComposeTestRule<ActivityScenarioRule<MainActivity>, MainActivity>.waitForLoadingComplete(
        timeoutMillis: Long = 30_000
    ) {
        // Wait until loading indicator disappears
        waitUntil(timeoutMillis = timeoutMillis) {
            onAllNodes(hasContentDescription("Loading"))
                .fetchSemanticsNodes().isEmpty()
        }
    }

    // ==================== Deep Link Helpers ====================

    /**
     * Build a deep link URI for share invitation
     */
    fun buildShareInvitationDeepLink(token: String): String {
        return "ssdiddrive://share/accept?token=$token"
    }

    /**
     * Build a deep link URI for user invitation
     */
    fun buildUserInvitationDeepLink(token: String, email: String): String {
        return "ssdiddrive://invite/accept?token=$token&email=$email"
    }

    // ==================== Screenshot Helper ====================

    /**
     * Take a screenshot for test documentation (requires additional setup)
     */
    fun takeScreenshot(name: String) {
        // Screenshot capture would require additional libraries like Shot or Falcon
        // This is a placeholder for potential future implementation
        println("Screenshot requested: $name")
    }
}
