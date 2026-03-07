package com.securesharing.data.local

import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import android.util.Base64
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Secure storage for sensitive data like tokens and encrypted keys.
 * Uses Android's EncryptedSharedPreferences with AES-256 encryption.
 *
 * SECURITY: Supports biometric-protected storage for sensitive key material.
 * When biometric protection is enabled, the encryption key requires user
 * authentication before it can be used.
 */
@Singleton
class SecureStorage @Inject constructor(
    @ApplicationContext private val context: Context
) {
    /**
     * Standard MasterKey for general secure storage (tokens, preferences).
     */
    private val masterKey: MasterKey by lazy {
        MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
    }

    /**
     * Biometric-protected MasterKey for highly sensitive data.
     * Requires user authentication (biometric or device credential) to access.
     *
     * SECURITY: This key is invalidated if new biometrics are enrolled,
     * providing protection against unauthorized biometric additions.
     */
    private val biometricMasterKey: MasterKey by lazy {
        val builder = MasterKey.Builder(context, BIOMETRIC_KEY_ALIAS)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // Android 11+: Use stronger authentication requirements
            builder.setUserAuthenticationRequired(
                true,
                AUTHENTICATION_VALIDITY_SECONDS
            )
        } else {
            // Android 7-10: Basic authentication requirement
            @Suppress("DEPRECATION")
            builder.setUserAuthenticationRequired(true)
        }

        builder.build()
    }

    /**
     * Biometric-protected SharedPreferences for sensitive key material.
     * Access to this storage requires user authentication.
     */
    private val biometricPrefs: SharedPreferences by lazy {
        EncryptedSharedPreferences.create(
            context,
            BIOMETRIC_PREFS_FILENAME,
            biometricMasterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )
    }

    private val encryptedPrefs: SharedPreferences by lazy {
        EncryptedSharedPreferences.create(
            context,
            PREFS_FILENAME,
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )
    }

    // ==================== Token Management ====================

    suspend fun saveTokens(accessToken: String, refreshToken: String) {
        withContext(Dispatchers.IO) {
            encryptedPrefs.edit()
                .putString(KEY_ACCESS_TOKEN, accessToken)
                .putString(KEY_REFRESH_TOKEN, refreshToken)
                .putLong(KEY_TOKEN_TIMESTAMP, System.currentTimeMillis())
                .apply()
        }
    }

    suspend fun getAccessToken(): String? = withContext(Dispatchers.IO) {
        encryptedPrefs.getString(KEY_ACCESS_TOKEN, null)
    }

    suspend fun getRefreshToken(): String? = withContext(Dispatchers.IO) {
        encryptedPrefs.getString(KEY_REFRESH_TOKEN, null)
    }

    suspend fun clearTokens() {
        withContext(Dispatchers.IO) {
            encryptedPrefs.edit()
                .remove(KEY_ACCESS_TOKEN)
                .remove(KEY_REFRESH_TOKEN)
                .remove(KEY_TOKEN_TIMESTAMP)
                .apply()
        }
    }

    suspend fun hasValidTokens(): Boolean = withContext(Dispatchers.IO) {
        !getAccessToken().isNullOrEmpty() && !getRefreshToken().isNullOrEmpty()
    }

    // ==================== User Data ====================

    suspend fun saveUserId(userId: String) {
        withContext(Dispatchers.IO) {
            encryptedPrefs.edit()
                .putString(KEY_USER_ID, userId)
                .apply()
        }
    }

    suspend fun getUserId(): String? = withContext(Dispatchers.IO) {
        encryptedPrefs.getString(KEY_USER_ID, null)
    }

    suspend fun saveTenantId(tenantId: String) {
        withContext(Dispatchers.IO) {
            encryptedPrefs.edit()
                .putString(KEY_TENANT_ID, tenantId)
                .apply()
        }
    }

    suspend fun getTenantId(): String? = withContext(Dispatchers.IO) {
        encryptedPrefs.getString(KEY_TENANT_ID, null)
    }

    // ==================== Multi-Tenant Support ====================

    /**
     * Save the current tenant's role.
     */
    suspend fun saveCurrentRole(role: String) {
        withContext(Dispatchers.IO) {
            encryptedPrefs.edit()
                .putString(KEY_CURRENT_ROLE, role)
                .apply()
        }
    }

    suspend fun getCurrentRole(): String? = withContext(Dispatchers.IO) {
        encryptedPrefs.getString(KEY_CURRENT_ROLE, null)
    }

    /**
     * Save the list of tenants the user belongs to as JSON.
     */
    suspend fun saveUserTenants(tenantsJson: String) {
        withContext(Dispatchers.IO) {
            encryptedPrefs.edit()
                .putString(KEY_USER_TENANTS, tenantsJson)
                .apply()
        }
    }

    suspend fun getUserTenants(): String? = withContext(Dispatchers.IO) {
        encryptedPrefs.getString(KEY_USER_TENANTS, null)
    }

    /**
     * Synchronous version of getTenantId for use in interceptors.
     */
    fun getTenantIdSync(): String? = kotlinx.coroutines.runBlocking(kotlinx.coroutines.Dispatchers.IO) {
        encryptedPrefs.getString(KEY_TENANT_ID, null)
    }

    /**
     * Synchronous version of getCurrentRole for use in interceptors.
     */
    fun getCurrentRoleSync(): String? = kotlinx.coroutines.runBlocking(kotlinx.coroutines.Dispatchers.IO) {
        encryptedPrefs.getString(KEY_CURRENT_ROLE, null)
    }

    /**
     * Save tokens and update tenant context atomically when switching tenants.
     */
    suspend fun saveTokensWithTenantContext(
        accessToken: String,
        refreshToken: String,
        tenantId: String,
        role: String
    ) {
        withContext(Dispatchers.IO) {
            encryptedPrefs.edit()
                .putString(KEY_ACCESS_TOKEN, accessToken)
                .putString(KEY_REFRESH_TOKEN, refreshToken)
                .putLong(KEY_TOKEN_TIMESTAMP, System.currentTimeMillis())
                .putString(KEY_TENANT_ID, tenantId)
                .putString(KEY_CURRENT_ROLE, role)
                .apply()
        }
    }

    /**
     * Synchronous version of getUserId for use in services.
     *
     * SECURITY: Uses runBlocking on IO dispatcher to prevent blocking main thread.
     * EncryptedSharedPreferences operations can be slow due to crypto operations.
     *
     * Note: Only use this in contexts where suspend functions are not available
     * (e.g., FirebaseMessagingService callbacks).
     */
    fun getUserIdSync(): String? = kotlinx.coroutines.runBlocking(kotlinx.coroutines.Dispatchers.IO) {
        encryptedPrefs.getString(KEY_USER_ID, null)
    }

    /**
     * Synchronous version of getAccessToken for use in services.
     *
     * SECURITY: Uses runBlocking on IO dispatcher to prevent blocking main thread.
     * EncryptedSharedPreferences operations can be slow due to crypto operations.
     *
     * Note: Only use this in contexts where suspend functions are not available
     * (e.g., OkHttp Authenticator callbacks).
     */
    fun getAccessTokenSync(): String? = kotlinx.coroutines.runBlocking(kotlinx.coroutines.Dispatchers.IO) {
        encryptedPrefs.getString(KEY_ACCESS_TOKEN, null)
    }

    /**
     * Synchronous version of getRefreshToken for use in TokenRefreshAuthenticator.
     *
     * SECURITY: Uses runBlocking on IO dispatcher to prevent blocking main thread.
     */
    fun getRefreshTokenSync(): String? = kotlinx.coroutines.runBlocking(kotlinx.coroutines.Dispatchers.IO) {
        encryptedPrefs.getString(KEY_REFRESH_TOKEN, null)
    }

    // ==================== FCM Token ====================

    fun setFcmToken(token: String) {
        encryptedPrefs.edit()
            .putString(KEY_FCM_TOKEN, token)
            .apply()
    }

    fun getFcmToken(): String? = encryptedPrefs.getString(KEY_FCM_TOKEN, null)

    fun clearFcmToken() {
        encryptedPrefs.edit()
            .remove(KEY_FCM_TOKEN)
            .apply()
    }

    // ==================== Device Enrollment ====================

    /**
     * Save device enrollment ID after successful enrollment.
     */
    suspend fun saveDeviceEnrollmentId(enrollmentId: String) {
        withContext(Dispatchers.IO) {
            encryptedPrefs.edit()
                .putString(KEY_DEVICE_ENROLLMENT_ID, enrollmentId)
                .apply()
        }
    }

    suspend fun getDeviceEnrollmentId(): String? = withContext(Dispatchers.IO) {
        encryptedPrefs.getString(KEY_DEVICE_ENROLLMENT_ID, null)
    }

    /**
     * Synchronous version for use in interceptors.
     */
    fun getDeviceEnrollmentIdSync(): String? = kotlinx.coroutines.runBlocking(kotlinx.coroutines.Dispatchers.IO) {
        encryptedPrefs.getString(KEY_DEVICE_ENROLLMENT_ID, null)
    }

    /**
     * Save device ID (physical device identifier).
     */
    suspend fun saveDeviceId(deviceId: String) {
        withContext(Dispatchers.IO) {
            encryptedPrefs.edit()
                .putString(KEY_DEVICE_ID, deviceId)
                .apply()
        }
    }

    suspend fun getDeviceId(): String? = withContext(Dispatchers.IO) {
        encryptedPrefs.getString(KEY_DEVICE_ID, null)
    }

    /**
     * Save encrypted device signing private key.
     * Encrypted with the user's master key.
     */
    suspend fun saveEncryptedDeviceSigningKey(encryptedKey: ByteArray) {
        withContext(Dispatchers.IO) {
            val encoded = Base64.encodeToString(encryptedKey, Base64.NO_WRAP)
            encryptedPrefs.edit()
                .putString(KEY_ENCRYPTED_DEVICE_SIGNING_KEY, encoded)
                .apply()
        }
    }

    suspend fun getEncryptedDeviceSigningKey(): ByteArray? = withContext(Dispatchers.IO) {
        encryptedPrefs.getString(KEY_ENCRYPTED_DEVICE_SIGNING_KEY, null)?.let {
            Base64.decode(it, Base64.NO_WRAP)
        }
    }

    /**
     * Save device signing public key (for verification).
     */
    suspend fun saveDeviceSigningPublicKey(publicKey: ByteArray) {
        withContext(Dispatchers.IO) {
            val encoded = Base64.encodeToString(publicKey, Base64.NO_WRAP)
            encryptedPrefs.edit()
                .putString(KEY_DEVICE_SIGNING_PUBLIC_KEY, encoded)
                .apply()
        }
    }

    suspend fun getDeviceSigningPublicKey(): ByteArray? = withContext(Dispatchers.IO) {
        encryptedPrefs.getString(KEY_DEVICE_SIGNING_PUBLIC_KEY, null)?.let {
            Base64.decode(it, Base64.NO_WRAP)
        }
    }

    /**
     * Save device key algorithm.
     */
    suspend fun saveDeviceKeyAlgorithm(algorithm: String) {
        withContext(Dispatchers.IO) {
            encryptedPrefs.edit()
                .putString(KEY_DEVICE_KEY_ALGORITHM, algorithm)
                .apply()
        }
    }

    suspend fun getDeviceKeyAlgorithm(): String? = withContext(Dispatchers.IO) {
        encryptedPrefs.getString(KEY_DEVICE_KEY_ALGORITHM, null)
    }

    /**
     * Clear all device enrollment data.
     */
    suspend fun clearDeviceEnrollment() {
        withContext(Dispatchers.IO) {
            encryptedPrefs.edit()
                .remove(KEY_DEVICE_ENROLLMENT_ID)
                .remove(KEY_DEVICE_ID)
                .remove(KEY_ENCRYPTED_DEVICE_SIGNING_KEY)
                .remove(KEY_DEVICE_SIGNING_PUBLIC_KEY)
                .remove(KEY_DEVICE_KEY_ALGORITHM)
                .apply()
        }
    }

    /**
     * Check if device is enrolled.
     */
    suspend fun isDeviceEnrolled(): Boolean = withContext(Dispatchers.IO) {
        !getDeviceEnrollmentId().isNullOrEmpty() && getEncryptedDeviceSigningKey() != null
    }

    // ==================== Key Material ====================

    /**
     * Save encrypted master key.
     * This is already encrypted with password-derived key.
     */
    suspend fun saveEncryptedMasterKey(encryptedKey: ByteArray) {
        withContext(Dispatchers.IO) {
            val encoded = Base64.encodeToString(encryptedKey, Base64.NO_WRAP)
            encryptedPrefs.edit()
                .putString(KEY_ENCRYPTED_MASTER_KEY, encoded)
                .apply()
        }
    }

    suspend fun getEncryptedMasterKey(): ByteArray? = withContext(Dispatchers.IO) {
        encryptedPrefs.getString(KEY_ENCRYPTED_MASTER_KEY, null)?.let {
            Base64.decode(it, Base64.NO_WRAP)
        }
    }

    /**
     * Save encrypted private keys bundle.
     */
    suspend fun saveEncryptedPrivateKeys(encryptedKeys: ByteArray) {
        withContext(Dispatchers.IO) {
            val encoded = Base64.encodeToString(encryptedKeys, Base64.NO_WRAP)
            encryptedPrefs.edit()
                .putString(KEY_ENCRYPTED_PRIVATE_KEYS, encoded)
                .apply()
        }
    }

    suspend fun getEncryptedPrivateKeys(): ByteArray? = withContext(Dispatchers.IO) {
        encryptedPrefs.getString(KEY_ENCRYPTED_PRIVATE_KEYS, null)?.let {
            Base64.decode(it, Base64.NO_WRAP)
        }
    }

    /**
     * Save key derivation salt used for password-based key derivation.
     */
    suspend fun saveKeyDerivationSalt(salt: ByteArray) {
        withContext(Dispatchers.IO) {
            val encoded = Base64.encodeToString(salt, Base64.NO_WRAP)
            encryptedPrefs.edit()
                .putString(KEY_DERIVATION_SALT, encoded)
                .apply()
        }
    }

    suspend fun getKeyDerivationSalt(): ByteArray? = withContext(Dispatchers.IO) {
        encryptedPrefs.getString(KEY_DERIVATION_SALT, null)?.let {
            Base64.decode(it, Base64.NO_WRAP)
        }
    }

    // ==================== Biometric-Protected Storage ====================

    /**
     * Save the decrypted master key in biometric-protected storage.
     *
     * SECURITY: This allows quick unlock via biometrics without requiring
     * the user to re-enter their password. The key is protected by the
     * Android Keystore and requires user authentication to access.
     *
     * @param masterKey The decrypted master key to store
     */
    suspend fun saveBiometricProtectedMasterKey(masterKey: ByteArray) {
        withContext(Dispatchers.IO) {
            try {
                val encoded = Base64.encodeToString(masterKey, Base64.NO_WRAP)
                biometricPrefs.edit()
                    .putString(KEY_BIOMETRIC_MASTER_KEY, encoded)
                    .apply()
            } catch (e: Exception) {
                // Biometric key may be invalidated - that's OK, user will need password
                throw BiometricKeyInvalidatedException("Biometric key invalidated", e)
            }
        }
    }

    /**
     * Get the master key from biometric-protected storage.
     *
     * SECURITY: This will only succeed after the user has authenticated
     * via biometrics or device credential. The key is automatically
     * invalidated if new biometrics are enrolled on the device.
     *
     * @return The decrypted master key, or null if not stored or invalidated
     * @throws BiometricKeyInvalidatedException if the biometric key was invalidated
     */
    suspend fun getBiometricProtectedMasterKey(): ByteArray? = withContext(Dispatchers.IO) {
        try {
            biometricPrefs.getString(KEY_BIOMETRIC_MASTER_KEY, null)?.let {
                Base64.decode(it, Base64.NO_WRAP)
            }
        } catch (e: Exception) {
            // Key may be invalidated due to new biometric enrollment
            throw BiometricKeyInvalidatedException("Biometric key invalidated", e)
        }
    }

    /**
     * Check if biometric unlock is enabled (master key stored in biometric storage).
     */
    suspend fun isBiometricUnlockEnabled(): Boolean = withContext(Dispatchers.IO) {
        try {
            biometricPrefs.contains(KEY_BIOMETRIC_MASTER_KEY)
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Disable biometric unlock by clearing the biometric-protected master key.
     */
    suspend fun disableBiometricUnlock() {
        withContext(Dispatchers.IO) {
            try {
                biometricPrefs.edit()
                    .remove(KEY_BIOMETRIC_MASTER_KEY)
                    .apply()
            } catch (e: Exception) {
                // Ignore - key may already be invalidated
            }
        }
    }

    /**
     * Enable or update biometric unlock preference.
     */
    suspend fun setBiometricUnlockPreference(enabled: Boolean) {
        withContext(Dispatchers.IO) {
            encryptedPrefs.edit()
                .putBoolean(KEY_BIOMETRIC_ENABLED, enabled)
                .apply()
        }
    }

    /**
     * Get biometric unlock preference.
     */
    suspend fun getBiometricUnlockPreference(): Boolean = withContext(Dispatchers.IO) {
        encryptedPrefs.getBoolean(KEY_BIOMETRIC_ENABLED, false)
    }

    // ==================== Session Management ====================

    /**
     * Clear all stored data (logout).
     */
    suspend fun clearAll() {
        withContext(Dispatchers.IO) {
            encryptedPrefs.edit().clear().apply()
            // Also clear biometric-protected storage
            try {
                biometricPrefs.edit().clear().apply()
            } catch (e: Exception) {
                // Ignore - biometric key may be invalidated
            }
        }
    }

    /**
     * Check if user is logged in (has tokens and key material).
     */
    suspend fun isLoggedIn(): Boolean = withContext(Dispatchers.IO) {
        hasValidTokens() && getEncryptedMasterKey() != null
    }

    companion object {
        private const val PREFS_FILENAME = "secure_sharing_encrypted_prefs"
        private const val BIOMETRIC_PREFS_FILENAME = "secure_sharing_biometric_prefs"
        private const val BIOMETRIC_KEY_ALIAS = "secure_sharing_biometric_key"

        /**
         * How long the user's authentication is valid after they authenticate.
         * Set to 1 for immediate re-authentication requirement (most secure).
         * Note: Android requires this to be >= 1.
         */
        private const val AUTHENTICATION_VALIDITY_SECONDS = 1

        // Token keys
        private const val KEY_ACCESS_TOKEN = "access_token"
        private const val KEY_REFRESH_TOKEN = "refresh_token"
        private const val KEY_TOKEN_TIMESTAMP = "token_timestamp"

        // User keys
        private const val KEY_USER_ID = "user_id"
        private const val KEY_TENANT_ID = "tenant_id"
        private const val KEY_CURRENT_ROLE = "current_role"
        private const val KEY_USER_TENANTS = "user_tenants"

        // Crypto keys
        private const val KEY_ENCRYPTED_MASTER_KEY = "encrypted_master_key"
        private const val KEY_ENCRYPTED_PRIVATE_KEYS = "encrypted_private_keys"
        private const val KEY_DERIVATION_SALT = "key_derivation_salt"

        // FCM keys
        private const val KEY_FCM_TOKEN = "fcm_token"

        // Biometric keys
        private const val KEY_BIOMETRIC_MASTER_KEY = "biometric_master_key"
        private const val KEY_BIOMETRIC_ENABLED = "biometric_enabled"

        // Device enrollment keys
        private const val KEY_DEVICE_ENROLLMENT_ID = "device_enrollment_id"
        private const val KEY_DEVICE_ID = "device_id"
        private const val KEY_ENCRYPTED_DEVICE_SIGNING_KEY = "encrypted_device_signing_key"
        private const val KEY_DEVICE_SIGNING_PUBLIC_KEY = "device_signing_public_key"
        private const val KEY_DEVICE_KEY_ALGORITHM = "device_key_algorithm"
    }
}

/**
 * Exception thrown when the biometric key has been invalidated.
 * This typically happens when new biometrics are enrolled on the device.
 */
class BiometricKeyInvalidatedException(
    message: String,
    cause: Throwable? = null
) : Exception(message, cause)
