package com.securesharing.e2e

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
import androidx.compose.ui.test.onNode
import androidx.test.ext.junit.rules.ActivityScenarioRule
import com.securesharing.MainActivity
import com.securesharing.data.remote.dto.PublicKeysDto
import com.securesharing.domain.model.PublicKeys
import com.securesharing.domain.model.User
import com.securesharing.domain.repository.AuthRepository
import com.securesharing.domain.repository.TenantRepository
import com.securesharing.util.Result

object E2eTestUtils {
    fun toPublicKeys(dto: PublicKeysDto): PublicKeys {
        return PublicKeys(
            kem = Base64.decode(dto.kem, Base64.NO_WRAP),
            sign = Base64.decode(dto.sign, Base64.NO_WRAP),
            mlKem = dto.mlKem?.let { Base64.decode(it, Base64.NO_WRAP) },
            mlDsa = dto.mlDsa?.let { Base64.decode(it, Base64.NO_WRAP) }
        )
    }

    suspend fun registerUser(
        authRepository: AuthRepository,
        email: String,
        password: CharArray,
        tenantSlug: String
    ): User {
        val result = authRepository.register(email, password, tenantSlug)
        return when (result) {
            is Result.Success -> result.data
            is Result.Error -> throw AssertionError("Registration failed: ${result.exception.message}")
        }
    }

    suspend fun loginAndUnlock(
        authRepository: AuthRepository,
        email: String,
        password: CharArray,
        tenantSlug: String
    ): User {
        val loginResult = authRepository.login(email, password, tenantSlug)
        val user = when (loginResult) {
            is Result.Success -> loginResult.data
            is Result.Error -> throw AssertionError("Login failed: ${loginResult.exception.message}")
        }

        val unlockResult = authRepository.unlockKeys(password)
        if (unlockResult is Result.Error) {
            throw AssertionError("Unlock keys failed: ${unlockResult.exception.message}")
        }

        return user
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
        authRepository: AuthRepository,
        password: CharArray
    ): Result<Unit> {
        return authRepository.enableBiometricUnlock(password)
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
    ): Result<Unit> {
        return tenantRepository.switchTenant(tenantId)
    }

    /**
     * Get list of available tenants for current user
     */
    suspend fun listTenants(tenantRepository: TenantRepository) = tenantRepository.getTenants()

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
            try {
                onNode(hasContentDescription("Loading")).assertDoesNotExist()
                true
            } catch (_: AssertionError) {
                false
            }
        }
    }

    // ==================== Deep Link Helpers ====================

    /**
     * Build a deep link URI for share invitation
     */
    fun buildShareInvitationDeepLink(token: String): String {
        return "securesharing://share/accept?token=$token"
    }

    /**
     * Build a deep link URI for user invitation
     */
    fun buildUserInvitationDeepLink(token: String, email: String): String {
        return "securesharing://invite/accept?token=$token&email=$email"
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
