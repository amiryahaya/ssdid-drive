package my.ssdid.drive.domain.repository

import my.ssdid.drive.domain.model.TokenInvitation
import my.ssdid.drive.domain.model.User
import my.ssdid.drive.util.Result

/**
 * Repository interface for authentication operations.
 *
 * SECURITY: Password parameters use CharArray instead of String.
 * CharArray can be explicitly zeroized after use, while String is immutable
 * and remains in memory until garbage collected.
 *
 * Callers MUST zeroize password CharArrays after calling these methods.
 */
interface AuthRepository {

    /**
     * Check if user is authenticated (has valid tokens).
     */
    suspend fun isAuthenticated(): Boolean

    /**
     * Login with email and password.
     * Returns the authenticated user on success.
     *
     * With multi-tenant support, the tenant_slug is optional. If not provided,
     * the user will be logged into their first available tenant. The response
     * includes all tenants the user belongs to.
     *
     * SECURITY: Caller must zeroize the password CharArray after this call.
     *
     * @param email User's email address
     * @param password User's password as CharArray (will be used then should be zeroized by caller)
     * @param tenantSlug Optional tenant slug to login to a specific tenant
     * @return Result containing the authenticated User or an error
     */
    suspend fun login(
        email: String,
        password: CharArray,
        tenantSlug: String? = null
    ): Result<User>

    /**
     * Register a new user.
     * Generates key pairs and encrypts them with the password.
     *
     * SECURITY: Caller must zeroize the password CharArray after this call.
     *
     * @param email User's email address
     * @param password User's password as CharArray (will be used then should be zeroized by caller)
     * @param tenantSlug Tenant slug to register under
     * @return Result containing the new User or an error
     */
    suspend fun register(
        email: String,
        password: CharArray,
        tenantSlug: String
    ): Result<User>

    /**
     * Logout the current user.
     * Clears all tokens and key material.
     */
    suspend fun logout(): Result<Unit>

    /**
     * Get the current authenticated user.
     */
    suspend fun getCurrentUser(): Result<User>

    /**
     * Update the current user's profile.
     *
     * @param displayName New display name (optional, pass null to keep current)
     * @return Result containing the updated User or an error
     */
    suspend fun updateProfile(displayName: String?): Result<User>

    /**
     * Refresh the access token using the refresh token.
     */
    suspend fun refreshToken(): Result<Unit>

    /**
     * Unlock the user's keys with their password.
     * Must be called after login to access encrypted content.
     *
     * SECURITY: Caller must zeroize the password CharArray after this call.
     *
     * @param password User's password as CharArray
     * @return Result indicating success or failure
     */
    suspend fun unlockKeys(password: CharArray): Result<Unit>

    /**
     * Check if keys are unlocked.
     */
    suspend fun areKeysUnlocked(): Boolean

    /**
     * Change the user's password.
     * Re-encrypts the master key and private keys with the new password.
     *
     * SECURITY: Caller must zeroize both password CharArrays after this call.
     *
     * @param currentPassword Current password as CharArray
     * @param newPassword New password as CharArray
     * @return Result indicating success or failure
     */
    suspend fun changePassword(currentPassword: CharArray, newPassword: CharArray): Result<Unit>

    // ==================== Biometric Unlock ====================

    /**
     * Enable biometric unlock by storing the master key in biometric-protected storage.
     * Requires password verification before enabling.
     *
     * SECURITY: Caller must zeroize the password CharArray after this call.
     *
     * @param password User's password to verify and decrypt master key
     * @return Result indicating success or failure
     */
    suspend fun enableBiometricUnlock(password: CharArray): Result<Unit>

    /**
     * Disable biometric unlock by clearing the biometric-protected master key.
     *
     * @return Result indicating success or failure
     */
    suspend fun disableBiometricUnlock(): Result<Unit>

    /**
     * Unlock the user's keys using biometric authentication.
     * Retrieves the master key from biometric-protected storage and decrypts private keys.
     *
     * @return Result indicating success or failure
     */
    suspend fun unlockWithBiometric(): Result<Unit>

    /**
     * Check if biometric unlock is enabled and available.
     *
     * @return true if biometric unlock is set up and can be used
     */
    suspend fun isBiometricUnlockEnabled(): Boolean

    /**
     * Lock the keys by clearing them from memory.
     * Called when app is locked due to timeout or manual lock.
     */
    suspend fun lockKeys()

    // ==================== Invitation Token (Public - for new users) ====================

    /**
     * Get public invitation info by token.
     * This is for new users who received an invitation link.
     * No authentication required.
     *
     * @param token The invitation token from the deep link
     * @return Result containing TokenInvitation or an error
     */
    suspend fun getInvitationInfo(token: String): Result<TokenInvitation>

    /**
     * Accept an invitation and register a new account.
     * Generates key pairs and encrypts them with the password.
     * No authentication required - this creates the account.
     *
     * SECURITY: Caller must zeroize the password CharArray after this call.
     *
     * @param token The invitation token
     * @param displayName User's display name
     * @param password User's password as CharArray
     * @return Result containing the new User or an error
     */
    suspend fun acceptInvitation(
        token: String,
        displayName: String,
        password: CharArray
    ): Result<User>
}
