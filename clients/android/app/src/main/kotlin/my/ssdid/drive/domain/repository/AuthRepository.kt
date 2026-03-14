package my.ssdid.drive.domain.repository

import my.ssdid.drive.domain.model.LinkedLogin
import my.ssdid.drive.domain.model.TokenInvitation
import my.ssdid.drive.domain.model.TotpSetupInfo
import my.ssdid.drive.domain.model.User
import my.ssdid.drive.util.Result

/**
 * Repository interface for authentication operations.
 *
 * Authentication methods:
 * - Email + TOTP: Email as identifier, TOTP as proof
 * - OIDC: Google and Microsoft sign-in via native SDKs
 * - Account linking: Multiple login methods per account
 */
interface AuthRepository {

    /**
     * Check if user is authenticated (has valid session token).
     */
    suspend fun isAuthenticated(): Boolean

    /**
     * Get the current session token.
     */
    suspend fun getSession(): String?

    /**
     * Save session tokens (access + refresh).
     */
    suspend fun saveSession(accessToken: String, refreshToken: String)

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
     */
    suspend fun updateProfile(displayName: String?): Result<User>

    /**
     * Check if keys are unlocked.
     */
    suspend fun areKeysUnlocked(): Boolean

    // ==================== Email + TOTP Auth ====================

    /**
     * Initiate email login.
     * @return true if TOTP verification is required
     */
    suspend fun emailLogin(email: String): Result<Boolean>

    /**
     * Register via email with invitation token. Sends OTP.
     */
    suspend fun emailRegister(email: String, invitationToken: String): Result<Unit>

    /**
     * Verify email registration OTP and create account.
     */
    suspend fun emailRegisterVerify(email: String, code: String, invitationToken: String): Result<User>

    /**
     * Verify TOTP code for login.
     */
    suspend fun totpVerify(email: String, code: String): Result<User>

    /**
     * Initiate TOTP setup. Returns setup info with otpauth URI.
     */
    suspend fun totpSetup(): Result<TotpSetupInfo>

    /**
     * Confirm TOTP setup with first code. Returns backup codes.
     */
    suspend fun totpSetupConfirm(code: String): Result<List<String>>

    /**
     * Initiate TOTP recovery (sends email OTP).
     */
    suspend fun totpRecovery(email: String): Result<Unit>

    /**
     * Verify TOTP recovery code.
     */
    suspend fun totpRecoveryVerify(email: String, code: String): Result<User>

    // ==================== OIDC Auth ====================

    /**
     * Verify an OIDC ID token for login or registration.
     * @param provider "google" or "microsoft"
     * @param idToken The ID token from the native SDK
     * @param invitationToken Optional invitation token for registration
     */
    suspend fun oidcVerify(provider: String, idToken: String, invitationToken: String? = null): Result<User>

    // ==================== Account Logins (Linking) ====================

    /**
     * List linked logins for the current account.
     */
    suspend fun getLinkedLogins(): Result<List<LinkedLogin>>

    /**
     * Initiate linking an email login (sends OTP).
     */
    suspend fun linkEmail(email: String): Result<Unit>

    /**
     * Verify email link OTP.
     */
    suspend fun linkEmailVerify(email: String, code: String): Result<LinkedLogin>

    /**
     * Link an OIDC login to the current account.
     */
    suspend fun linkOidc(provider: String, idToken: String): Result<LinkedLogin>

    /**
     * Unlink a login method. Must keep at least 1.
     */
    suspend fun unlinkLogin(loginId: String): Result<Unit>

    // ==================== Biometric Unlock ====================

    suspend fun enableBiometricUnlock(): Result<Unit>
    suspend fun disableBiometricUnlock(): Result<Unit>
    suspend fun unlockWithBiometric(): Result<Unit>
    suspend fun isBiometricUnlockEnabled(): Boolean
    suspend fun lockKeys()

    // ==================== Invitation Token (Public - for new users) ====================

    /**
     * Get public invitation info by token.
     */
    suspend fun getInvitationInfo(token: String): Result<TokenInvitation>

    // ==================== Legacy SSDID (kept during migration) ====================

    suspend fun createChallenge(action: String): ChallengeInfo
    suspend fun launchWalletAuth(challenge: ChallengeInfo)
    suspend fun listenForSession(challenge: ChallengeInfo): String
    suspend fun launchWalletInvite(token: String)
}

/**
 * Information about a challenge for SSDID Wallet authentication.
 */
data class ChallengeInfo(
    val challengeId: String,
    val subscriberSecret: String,
    val walletDeepLink: String
)
