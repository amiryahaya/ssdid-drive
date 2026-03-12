package my.ssdid.drive.domain.repository

import my.ssdid.drive.domain.model.TokenInvitation
import my.ssdid.drive.domain.model.User
import my.ssdid.drive.util.Result

/**
 * Repository interface for authentication operations.
 *
 * Authentication is handled via SSDID Wallet deep links.
 * The flow is:
 * 1. App requests server info (challenge)
 * 2. App launches SSDID Wallet via deep link with challenge
 * 3. Wallet authenticates user and calls back with session token
 * 4. App saves session token for API access
 */
interface AuthRepository {

    /**
     * Check if user is authenticated (has valid session token).
     */
    suspend fun isAuthenticated(): Boolean

    /**
     * Create a challenge for SSDID Wallet authentication.
     *
     * @param action The action type ("authenticate" or "register")
     * @return ChallengeInfo containing the deep link URL for the wallet
     */
    suspend fun createChallenge(action: String): ChallengeInfo

    /**
     * Launch the SSDID Wallet app via deep link for authentication.
     *
     * @param challenge The challenge info containing the wallet deep link URL
     */
    suspend fun launchWalletAuth(challenge: ChallengeInfo)

    /**
     * Listen for session token via SSE after launching wallet.
     * Blocks until the server sends the authenticated event or timeout.
     *
     * @param challenge The challenge info with SSE connection details
     * @return The session token
     */
    suspend fun listenForSession(challenge: ChallengeInfo): String

    /**
     * Save the session token received from the wallet callback.
     *
     * @param sessionToken The session token from the wallet
     */
    suspend fun saveSession(sessionToken: String)

    /**
     * Get the current session token.
     *
     * @return The session token, or null if not authenticated
     */
    suspend fun getSession(): String?

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
     * Check if keys are unlocked.
     */
    suspend fun areKeysUnlocked(): Boolean

    // ==================== Biometric Unlock ====================

    /**
     * Enable biometric unlock by storing the master key in biometric-protected storage.
     *
     * @return Result indicating success or failure
     */
    suspend fun enableBiometricUnlock(): Result<Unit>

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
}

/**
 * Information about a challenge for SSDID Wallet authentication.
 */
data class ChallengeInfo(
    val challengeId: String,
    val subscriberSecret: String,
    val walletDeepLink: String
)
