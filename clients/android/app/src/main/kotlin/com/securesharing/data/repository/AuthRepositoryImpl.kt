package com.securesharing.data.repository

import android.content.Context
import android.util.Base64
import com.securesharing.crypto.CryptoConfig
import com.securesharing.crypto.CryptoManager
import com.securesharing.crypto.DeviceManager
import com.securesharing.crypto.FolderKeyManager
import com.securesharing.crypto.KdfProfile
import com.securesharing.crypto.KeyManager
import com.securesharing.crypto.PqcAlgorithm
import com.securesharing.crypto.SecureMemory
import dagger.hilt.android.qualifiers.ApplicationContext
import com.securesharing.data.local.BiometricKeyInvalidatedException
import com.securesharing.data.local.SecureStorage
import com.securesharing.data.remote.ApiService
import com.securesharing.data.remote.dto.AcceptInviteRequest
import com.securesharing.data.remote.dto.LoginRequest
import com.securesharing.data.remote.dto.PublicKeysDto
import com.securesharing.data.remote.dto.RegisterRequest
import com.securesharing.data.remote.dto.UpdateKeyMaterialRequest
import com.securesharing.data.remote.dto.UpdateProfileRequest
import com.securesharing.domain.model.PublicKeys
import com.securesharing.domain.model.TokenInvitation
import com.securesharing.domain.model.TokenInvitationError
import com.securesharing.domain.model.User
import com.securesharing.domain.model.UserRole
import com.securesharing.domain.repository.AuthRepository
import com.securesharing.util.AnalyticsManager
import com.securesharing.util.AppException
import com.securesharing.util.CacheManager
import com.securesharing.util.Logger
import com.securesharing.util.PushNotificationManager
import com.securesharing.util.Result
import java.nio.ByteBuffer
import java.nio.CharBuffer
import java.nio.charset.StandardCharsets
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class AuthRepositoryImpl @Inject constructor(
    @ApplicationContext private val context: Context,
    private val apiService: ApiService,
    private val secureStorage: SecureStorage,
    private val cryptoManager: CryptoManager,
    private val keyManager: KeyManager,
    private val cryptoConfig: CryptoConfig,
    private val folderKeyManager: FolderKeyManager,
    private val deviceManager: DeviceManager,
    private val cacheManager: CacheManager,
    private val pushNotificationManager: PushNotificationManager,
    private val analyticsManager: AnalyticsManager
) : AuthRepository {

    override suspend fun isAuthenticated(): Boolean {
        return secureStorage.hasValidTokens()
    }

    override suspend fun login(
        email: String,
        password: CharArray,
        tenantSlug: String?
    ): Result<User> {
        // Convert password to String for API call (unavoidable for JSON serialization)
        // The String will be garbage collected, but we minimize its lifetime
        val passwordString = String(password)

        return try {
            val response = apiService.login(LoginRequest(email, passwordString, tenantSlug))

            if (response.isSuccessful) {
                val authResponse = response.body()
                    ?: run {
                        // SECURITY: Zeroize password before returning
                        password.fill('\u0000')
                        return Result.error(AppException.Unknown("Empty login response from server"))
                    }

                val responseData = authResponse.data
                val userDto = responseData.user

                // Save tokens
                secureStorage.saveTokens(responseData.accessToken, responseData.refreshToken)

                // Save user info
                secureStorage.saveUserId(userDto.id)

                // Save tenant context (multi-tenant support)
                val effectiveTenantId = userDto.getEffectiveTenantId()
                val effectiveRole = userDto.getEffectiveRole()

                if (effectiveTenantId != null) {
                    secureStorage.saveTenantId(effectiveTenantId)
                }
                if (effectiveRole != null) {
                    secureStorage.saveCurrentRole(effectiveRole)
                }

                // Save user's tenants list for tenant switching
                userDto.tenants?.let { tenants ->
                    val tenantsJson = com.google.gson.Gson().toJson(tenants)
                    secureStorage.saveUserTenants(tenantsJson)
                }

                // Save encrypted key material for later unlock
                userDto.encryptedMasterKey?.let {
                    secureStorage.saveEncryptedMasterKey(Base64.decode(it, Base64.NO_WRAP))
                }
                userDto.encryptedPrivateKeys?.let {
                    secureStorage.saveEncryptedPrivateKeys(Base64.decode(it, Base64.NO_WRAP))
                }
                userDto.keyDerivationSalt?.let {
                    secureStorage.saveKeyDerivationSalt(Base64.decode(it, Base64.NO_WRAP))
                }

                // Fetch tenant config to get PQC algorithm
                fetchAndApplyTenantConfig()

                // Unlock keys with password (password CharArray is still valid here)
                unlockKeys(password)

                // SECURITY: Zeroize password after successful login
                password.fill('\u0000')

                analyticsManager.setUser(userDto.id)
                analyticsManager.trackLogin("password")

                Result.success(userDto.toDomain())
            } else {
                // SECURITY: Zeroize password before returning error
                password.fill('\u0000')
                when (response.code()) {
                    401 -> Result.error(AppException.Unauthorized("Invalid credentials"))
                    404 -> Result.error(AppException.NotFound("User not found"))
                    else -> Result.error(AppException.Unknown("Login failed: ${response.code()}"))
                }
            }
        } catch (e: Exception) {
            // SECURITY: Zeroize password on exception
            password.fill('\u0000')
            Result.error(AppException.Network("Login failed", e))
        }
    }

    override suspend fun register(
        email: String,
        password: CharArray,
        tenantSlug: String
    ): Result<User> {
        // Convert password to bytes for key derivation
        val passwordBytes = charArrayToBytes(password)

        return try {
            // Generate all key pairs
            val keyBundle = keyManager.generateKeyBundle()

            // Derive password key using tiered KDF (profile selected by device RAM)
            val salt = KdfProfile.createSaltWithProfile(KdfProfile.selectForDevice(context))
            val passwordKey = cryptoManager.deriveKeyWithProfile(passwordBytes, salt)

            // SECURITY: Zeroize password bytes immediately after use
            SecureMemory.zeroize(passwordBytes)

            // Encrypt master key with password-derived key
            val encryptedMasterKey = cryptoManager.encryptAesGcm(keyBundle.masterKey, passwordKey)

            // SECURITY: Zeroize password key after use
            SecureMemory.zeroize(passwordKey)

            // Encrypt private keys with master key
            val privateKeysBundle = keyManager.serializePrivateKeys(keyBundle)
            val encryptedPrivateKeys = cryptoManager.encryptAesGcm(privateKeysBundle, keyBundle.masterKey)

            // SECURITY: Zeroize serialized private keys after encryption
            SecureMemory.zeroize(privateKeysBundle)

            // Prepare public keys
            val publicKeysDto = PublicKeysDto(
                kem = Base64.encodeToString(keyBundle.kazKemPublicKey, Base64.NO_WRAP),
                sign = Base64.encodeToString(keyBundle.kazSignPublicKey, Base64.NO_WRAP),
                mlKem = keyBundle.mlKemPublicKey.takeIf { it.isNotEmpty() }?.let { Base64.encodeToString(it, Base64.NO_WRAP) },
                mlDsa = keyBundle.mlDsaPublicKey.takeIf { it.isNotEmpty() }?.let { Base64.encodeToString(it, Base64.NO_WRAP) }
            )

            // Convert password to String for API call (unavoidable for JSON serialization)
            val passwordString = String(password)

            val request = RegisterRequest(
                email = email,
                password = passwordString,
                tenantSlug = tenantSlug,
                publicKeys = publicKeysDto,
                encryptedMasterKey = Base64.encodeToString(encryptedMasterKey, Base64.NO_WRAP),
                encryptedPrivateKeys = Base64.encodeToString(encryptedPrivateKeys, Base64.NO_WRAP),
                keyDerivationSalt = Base64.encodeToString(salt, Base64.NO_WRAP)
            )

            val response = apiService.register(request)

            if (response.isSuccessful) {
                val authResponse = response.body()
                    ?: return Result.error(AppException.Unknown("Empty registration response from server"))

                val responseData = authResponse.data
                val userDto = responseData.user

                // Save tokens
                secureStorage.saveTokens(responseData.accessToken, responseData.refreshToken)

                // Save key material
                secureStorage.saveEncryptedMasterKey(encryptedMasterKey)
                secureStorage.saveEncryptedPrivateKeys(encryptedPrivateKeys)
                secureStorage.saveKeyDerivationSalt(salt)

                // Unlock keys
                keyManager.setUnlockedKeys(keyBundle)

                // Save user info
                secureStorage.saveUserId(userDto.id)

                // Save tenant context (multi-tenant support)
                val effectiveTenantId = userDto.getEffectiveTenantId()
                val effectiveRole = userDto.getEffectiveRole()

                if (effectiveTenantId != null) {
                    secureStorage.saveTenantId(effectiveTenantId)
                }
                if (effectiveRole != null) {
                    secureStorage.saveCurrentRole(effectiveRole)
                }

                // Save user's tenants list for tenant switching
                userDto.tenants?.let { tenants ->
                    val tenantsJson = com.google.gson.Gson().toJson(tenants)
                    secureStorage.saveUserTenants(tenantsJson)
                }

                // Fetch tenant config to get PQC algorithm
                fetchAndApplyTenantConfig()

                Result.success(userDto.toDomain())
            } else {
                when (response.code()) {
                    409 -> Result.error(AppException.ValidationError("Email already registered"))
                    422 -> Result.error(AppException.ValidationError("Invalid registration data"))
                    else -> Result.error(AppException.Unknown("Registration failed: ${response.code()}"))
                }
            }
        } catch (e: Exception) {
            // Ensure password bytes are zeroized even on exception
            SecureMemory.zeroize(passwordBytes)
            Result.error(AppException.Network("Registration failed", e))
        }
    }

    override suspend fun logout(): Result<Unit> {
        return try {
            // Unregister push notifications first (while we still have enrollment ID)
            try {
                val enrollmentId = secureStorage.getDeviceEnrollmentId()
                pushNotificationManager.logout(enrollmentId)
            } catch (e: Exception) {
                Logger.w(TAG, "Push notification logout failed, continuing with cleanup", e)
            }

            // Call logout API - log errors but don't fail logout
            try {
                apiService.logout()
            } catch (e: Exception) {
                // Log the error but continue with local cleanup
                // Logout should succeed even if server is unreachable
                Logger.w(TAG, "Logout API call failed, continuing with local cleanup", e)
            }

            analyticsManager.clearUser()

            // Clear all local data and crypto caches
            secureStorage.clearAll()
            keyManager.clearUnlockedKeys()
            folderKeyManager.clearCache()

            // SECURITY: Clear device signing key from memory
            // Prevents stale keys from persisting across user sessions
            deviceManager.clearDeviceKey()

            // Clear file caches (decrypted files)
            cacheManager.clearAllCaches()

            Result.success(Unit)
        } catch (e: Exception) {
            Result.error(AppException.Unknown("Logout failed", e))
        }
    }

    override suspend fun getCurrentUser(): Result<User> {
        return try {
            val response = apiService.getCurrentUser()

            if (response.isSuccessful) {
                val body = response.body()
                    ?: return Result.error(AppException.Unknown("Empty user response from server"))
                val user = body.data.toDomain()
                Result.success(user)
            } else {
                when (response.code()) {
                    401 -> Result.error(AppException.Unauthorized())
                    else -> Result.error(AppException.Unknown("Failed to get user"))
                }
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to get user", e))
        }
    }

    override suspend fun refreshToken(): Result<Unit> {
        // Token refresh is handled automatically by TokenRefreshAuthenticator
        return Result.success(Unit)
    }

    override suspend fun updateProfile(displayName: String?): Result<User> {
        return try {
            val request = UpdateProfileRequest(displayName = displayName)
            val response = apiService.updateProfile(request)

            if (response.isSuccessful) {
                val body = response.body()
                    ?: return Result.error(AppException.Unknown("Empty response from server"))
                val user = body.data.toDomain()
                Result.success(user)
            } else {
                when (response.code()) {
                    401 -> Result.error(AppException.Unauthorized())
                    422 -> Result.error(AppException.ValidationError("Invalid display name"))
                    else -> Result.error(AppException.Unknown("Failed to update profile"))
                }
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to update profile", e))
        }
    }

    override suspend fun unlockKeys(password: CharArray): Result<Unit> {
        // Convert password to bytes for key derivation
        val passwordBytes = charArrayToBytes(password)

        return try {
            val encryptedMasterKey = secureStorage.getEncryptedMasterKey()
                ?: return Result.error(AppException.CryptoError("No encrypted master key found"))
            val encryptedPrivateKeys = secureStorage.getEncryptedPrivateKeys()
                ?: return Result.error(AppException.CryptoError("No encrypted private keys found"))
            val salt = secureStorage.getKeyDerivationSalt()
                ?: return Result.error(AppException.CryptoError("No key derivation salt found"))

            // Derive password key using tiered KDF (auto-detects profile from salt)
            val passwordKey = cryptoManager.deriveKeyWithProfile(passwordBytes, salt)

            // Decrypt master key (fallback to legacy HKDF-only derivation)
            val masterKey = try {
                cryptoManager.decryptAesGcm(encryptedMasterKey, passwordKey)
            } catch (e: Exception) {
                SecureMemory.zeroize(passwordKey)
                val legacyKey = cryptoManager.deriveKeyLegacy(passwordBytes, salt)
                try {
                    cryptoManager.decryptAesGcm(encryptedMasterKey, legacyKey)
                } finally {
                    SecureMemory.zeroize(legacyKey)
                }
            }

            // Best-effort KDF profile upgrade (before zeroizing password bytes)
            upgradeKdfProfileIfNeeded(passwordBytes, masterKey, salt)

            // SECURITY: Zeroize password bytes and key after use
            SecureMemory.zeroize(passwordBytes)
            SecureMemory.zeroize(passwordKey)

            // Decrypt private keys
            val privateKeysBundle = cryptoManager.decryptAesGcm(encryptedPrivateKeys, masterKey)

            // Parse and store unlocked keys
            val keyBundle = keyManager.deserializePrivateKeys(privateKeysBundle, masterKey)
            keyManager.setUnlockedKeys(keyBundle)

            // SECURITY: Zeroize decrypted private keys bundle after parsing
            SecureMemory.zeroize(privateKeysBundle)

            Result.success(Unit)
        } catch (e: Exception) {
            // Ensure password bytes are zeroized even on exception
            SecureMemory.zeroize(passwordBytes)
            Result.error(AppException.CryptoError("Failed to unlock keys", e))
        }
    }

    override suspend fun areKeysUnlocked(): Boolean {
        return keyManager.hasUnlockedKeys()
    }

    override suspend fun changePassword(currentPassword: CharArray, newPassword: CharArray): Result<Unit> {
        // Convert passwords to bytes for key derivation
        val currentPasswordBytes = charArrayToBytes(currentPassword)
        val newPasswordBytes = charArrayToBytes(newPassword)

        return try {
            // First verify current password by unlocking keys
            val encryptedMasterKey = secureStorage.getEncryptedMasterKey()
                ?: return Result.error(AppException.CryptoError("No encrypted master key found"))
            val encryptedPrivateKeys = secureStorage.getEncryptedPrivateKeys()
                ?: return Result.error(AppException.CryptoError("No encrypted private keys found"))
            val currentSalt = secureStorage.getKeyDerivationSalt()
                ?: return Result.error(AppException.CryptoError("No key derivation salt found"))

            // Verify current password using tiered KDF (auto-detects profile from salt)
            val currentPasswordKey = cryptoManager.deriveKeyWithProfile(currentPasswordBytes, currentSalt)

            val masterKey = try {
                cryptoManager.decryptAesGcm(encryptedMasterKey, currentPasswordKey)
            } catch (e: Exception) {
                SecureMemory.zeroize(currentPasswordKey)
                val legacyKey = cryptoManager.deriveKeyLegacy(currentPasswordBytes, currentSalt)
                try {
                    cryptoManager.decryptAesGcm(encryptedMasterKey, legacyKey)
                } catch (legacyError: Exception) {
                    SecureMemory.zeroize(legacyKey)
                    SecureMemory.zeroize(currentPasswordBytes)
                    SecureMemory.zeroize(newPasswordBytes)
                    return Result.error(AppException.Unauthorized("Current password is incorrect"))
                } finally {
                    SecureMemory.zeroize(legacyKey)
                }
            }

            // SECURITY: Zeroize current password bytes and key after use
            SecureMemory.zeroize(currentPasswordBytes)
            SecureMemory.zeroize(currentPasswordKey)

            // Generate new salt with tiered KDF profile for new password
            val newSalt = KdfProfile.createSaltWithProfile(KdfProfile.selectForDevice(context))
            val newPasswordKey = cryptoManager.deriveKeyWithProfile(newPasswordBytes, newSalt)

            // SECURITY: Zeroize new password bytes after key derivation
            SecureMemory.zeroize(newPasswordBytes)

            // Re-encrypt master key with new password-derived key
            val newEncryptedMasterKey = cryptoManager.encryptAesGcm(masterKey, newPasswordKey)

            // SECURITY: Zeroize new password key and master key after use
            SecureMemory.zeroize(newPasswordKey)
            SecureMemory.zeroize(masterKey)

            // Private keys remain encrypted with master key (unchanged)
            // Just need to update the password-encrypted master key and salt

            // Sync with server first - if this fails, don't update locally
            val request = UpdateKeyMaterialRequest(
                encryptedMasterKey = Base64.encodeToString(newEncryptedMasterKey, Base64.NO_WRAP),
                keyDerivationSalt = Base64.encodeToString(newSalt, Base64.NO_WRAP)
            )

            val response = try {
                apiService.updateKeyMaterial(request)
            } catch (e: Exception) {
                Logger.e(TAG, "Failed to sync password change with server", e)
                return Result.error(AppException.Network("Failed to sync password change with server", e))
            }

            if (!response.isSuccessful) {
                Logger.e(TAG, "Server rejected password change: ${response.code()}")
                return Result.error(AppException.Unknown("Failed to update password on server: ${response.code()}"))
            }

            // Server update successful - now save locally
            secureStorage.saveEncryptedMasterKey(newEncryptedMasterKey)
            secureStorage.saveKeyDerivationSalt(newSalt)

            // If biometric unlock was enabled, we need to update the biometric-protected key
            // with the new master key (since we just changed how it's encrypted)
            if (isBiometricUnlockEnabled()) {
                // We already have the decrypted master key in scope, use it to update biometric
                // Wait - we zeroized it above. We need to re-think this flow.
                // Actually, the master key itself hasn't changed, just how it's encrypted.
                // So biometric unlock should still work since it stores the raw master key.
                Logger.d(TAG, "Biometric unlock still valid - master key unchanged, only password-encryption updated")
            }

            Logger.i(TAG, "Password changed successfully")
            Result.success(Unit)
        } catch (e: Exception) {
            // Ensure password bytes are zeroized even on exception
            SecureMemory.zeroize(currentPasswordBytes)
            SecureMemory.zeroize(newPasswordBytes)
            Result.error(AppException.CryptoError("Failed to change password", e))
        }
    }

    /**
     * Fetch tenant configuration from the server and apply the PQC algorithm setting.
     * This should be called after successful login/registration.
     */
    private suspend fun fetchAndApplyTenantConfig() {
        try {
            val response = apiService.getTenantConfig()
            if (response.isSuccessful) {
                response.body()?.data?.let { config ->
                    val algorithm = PqcAlgorithm.fromString(config.pqcAlgorithm)
                    cryptoConfig.setAlgorithm(algorithm)
                }
            }
        } catch (e: Exception) {
            // Log error but don't fail login - default to KAZ algorithm
            // In production, consider logging this appropriately
        }
    }

    // Extension function to convert DTO to domain model
    private fun com.securesharing.data.remote.dto.UserDto.toDomain(): User {
        return User(
            id = id,
            email = email,
            displayName = displayName,
            status = status,
            recoverySetupComplete = recoverySetupComplete,
            // Multi-tenant fields
            tenants = tenants?.map { tenantDto ->
                com.securesharing.domain.model.Tenant(
                    id = tenantDto.id,
                    name = tenantDto.name,
                    slug = tenantDto.slug,
                    role = UserRole.fromString(tenantDto.role),
                    joinedAt = tenantDto.joinedAt
                )
            },
            currentTenantId = currentTenantId,
            // Legacy single-tenant fields
            tenantId = tenantId,
            role = role?.let { UserRole.fromString(it) },
            // Crypto fields
            publicKeys = publicKeys?.let {
                PublicKeys(
                    kem = Base64.decode(it.kem, Base64.NO_WRAP),
                    sign = Base64.decode(it.sign, Base64.NO_WRAP),
                    mlKem = it.mlKem?.let { pk -> Base64.decode(pk, Base64.NO_WRAP) },
                    mlDsa = it.mlDsa?.let { pk -> Base64.decode(pk, Base64.NO_WRAP) }
                )
            },
            storageQuota = storageQuota,
            storageUsed = storageUsed
        )
    }

    // ==================== Biometric Unlock ====================

    override suspend fun enableBiometricUnlock(password: CharArray): Result<Unit> {
        val passwordBytes = charArrayToBytes(password)

        return try {
            // Get encrypted master key material
            val encryptedMasterKey = secureStorage.getEncryptedMasterKey()
                ?: return Result.error(AppException.CryptoError("No encrypted master key found"))
            val salt = secureStorage.getKeyDerivationSalt()
                ?: return Result.error(AppException.CryptoError("No key derivation salt found"))

            // Derive password key using tiered KDF (auto-detects profile from salt)
            val passwordKey = cryptoManager.deriveKeyWithProfile(passwordBytes, salt)

            // SECURITY: Zeroize password bytes after key derivation
            SecureMemory.zeroize(passwordBytes)

            val masterKey = try {
                cryptoManager.decryptAesGcm(encryptedMasterKey, passwordKey)
            } catch (e: Exception) {
                SecureMemory.zeroize(passwordKey)
                return Result.error(AppException.Unauthorized("Incorrect password"))
            }

            // SECURITY: Zeroize password key after use
            SecureMemory.zeroize(passwordKey)

            // Store master key in biometric-protected storage
            secureStorage.saveBiometricProtectedMasterKey(masterKey)

            // SECURITY: Zeroize master key after storing
            SecureMemory.zeroize(masterKey)

            // Set biometric preference
            secureStorage.setBiometricUnlockPreference(true)

            Logger.i(TAG, "Biometric unlock enabled")
            Result.success(Unit)
        } catch (e: Exception) {
            SecureMemory.zeroize(passwordBytes)
            Logger.e(TAG, "Failed to enable biometric unlock", e)
            Result.error(AppException.CryptoError("Failed to enable biometric unlock", e))
        }
    }

    override suspend fun disableBiometricUnlock(): Result<Unit> {
        return try {
            // Clear biometric-protected master key
            secureStorage.disableBiometricUnlock()

            // Clear preference
            secureStorage.setBiometricUnlockPreference(false)

            Logger.i(TAG, "Biometric unlock disabled")
            Result.success(Unit)
        } catch (e: Exception) {
            Logger.e(TAG, "Failed to disable biometric unlock", e)
            Result.error(AppException.CryptoError("Failed to disable biometric unlock", e))
        }
    }

    override suspend fun unlockWithBiometric(): Result<Unit> {
        return try {
            // Get master key from biometric-protected storage
            val masterKey = secureStorage.getBiometricProtectedMasterKey()
                ?: return Result.error(AppException.CryptoError("No biometric master key found. Please re-enable biometric unlock."))

            // Get encrypted private keys
            val encryptedPrivateKeys = secureStorage.getEncryptedPrivateKeys()
                ?: return Result.error(AppException.CryptoError("No encrypted private keys found"))

            // Decrypt private keys with master key
            val privateKeysBundle = cryptoManager.decryptAesGcm(encryptedPrivateKeys, masterKey)

            // Parse and store unlocked keys
            val keyBundle = keyManager.deserializePrivateKeys(privateKeysBundle, masterKey.copyOf())

            // SECURITY: Zeroize decrypted private keys bundle
            SecureMemory.zeroize(privateKeysBundle)

            // SECURITY: Zeroize the master key copy we retrieved
            SecureMemory.zeroize(masterKey)

            keyManager.setUnlockedKeys(keyBundle)

            analyticsManager.trackLogin("biometric")

            Logger.i(TAG, "Keys unlocked with biometric")
            Result.success(Unit)
        } catch (e: BiometricKeyInvalidatedException) {
            // Biometric key was invalidated (e.g., new fingerprint enrolled)
            // Clear the biometric preference so user has to set it up again
            secureStorage.disableBiometricUnlock()
            secureStorage.setBiometricUnlockPreference(false)
            Logger.w(TAG, "Biometric key invalidated, disabled biometric unlock", e)
            Result.error(AppException.CryptoError("Biometric credentials changed. Please use your password and re-enable biometric unlock."))
        } catch (e: Exception) {
            Logger.e(TAG, "Failed to unlock with biometric", e)
            Result.error(AppException.CryptoError("Failed to unlock with biometric", e))
        }
    }

    override suspend fun isBiometricUnlockEnabled(): Boolean {
        return try {
            secureStorage.isBiometricUnlockEnabled() && secureStorage.getBiometricUnlockPreference()
        } catch (e: Exception) {
            false
        }
    }

    override suspend fun lockKeys() {
        keyManager.clearUnlockedKeys()
        folderKeyManager.clearCache()
        Logger.i(TAG, "Keys locked")
    }

    /**
     * Convert a CharArray to ByteArray using UTF-8 encoding.
     *
     * SECURITY: This creates a byte array that can be explicitly zeroized.
     * The returned ByteArray MUST be zeroized after use.
     *
     * @param chars The CharArray to convert
     * @return ByteArray representation of the chars
     */
    private fun charArrayToBytes(chars: CharArray): ByteArray {
        val charBuffer = CharBuffer.wrap(chars)
        val byteBuffer = StandardCharsets.UTF_8.encode(charBuffer)
        val bytes = ByteArray(byteBuffer.remaining())
        byteBuffer.get(bytes)

        // Clear the intermediate ByteBuffer
        byteBuffer.array().fill(0)

        return bytes
    }

    // ==================== Invitation Token (Public - for new users) ====================

    override suspend fun getInvitationInfo(token: String): Result<TokenInvitation> {
        return try {
            val response = apiService.getInviteInfo(token)

            if (response.isSuccessful) {
                val body = response.body()
                    ?: return Result.error(AppException.Unknown("Empty response from server"))

                val dto = body.data
                val invitation = TokenInvitation(
                    id = dto.id,
                    email = dto.email,
                    role = UserRole.fromString(dto.role),
                    tenantName = dto.tenantName,
                    inviterName = dto.inviterName,
                    message = dto.message,
                    expiresAt = dto.expiresAt,
                    valid = dto.valid,
                    errorReason = TokenInvitationError.fromString(dto.errorReason)
                )
                Result.success(invitation)
            } else {
                when (response.code()) {
                    404 -> Result.error(AppException.NotFound("Invitation not found"))
                    410 -> Result.error(AppException.ValidationError("Invitation expired"))
                    else -> Result.error(AppException.Unknown("Failed to get invitation: ${response.code()}"))
                }
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to get invitation info", e))
        }
    }

    override suspend fun acceptInvitation(
        token: String,
        displayName: String,
        password: CharArray
    ): Result<User> {
        // Convert password to bytes for key derivation
        val passwordBytes = charArrayToBytes(password)

        return try {
            // Generate all key pairs (same as regular registration)
            val keyBundle = keyManager.generateKeyBundle()

            // Derive password key using tiered KDF (profile selected by device RAM)
            val salt = KdfProfile.createSaltWithProfile(KdfProfile.selectForDevice(context))
            val passwordKey = cryptoManager.deriveKeyWithProfile(passwordBytes, salt)

            // SECURITY: Zeroize password bytes immediately after use
            SecureMemory.zeroize(passwordBytes)

            // Encrypt master key with password-derived key
            val encryptedMasterKey = cryptoManager.encryptAesGcm(keyBundle.masterKey, passwordKey)

            // SECURITY: Zeroize password key after use
            SecureMemory.zeroize(passwordKey)

            // Encrypt private keys with master key
            val privateKeysBundle = keyManager.serializePrivateKeys(keyBundle)
            val encryptedPrivateKeys = cryptoManager.encryptAesGcm(privateKeysBundle, keyBundle.masterKey)

            // SECURITY: Zeroize serialized private keys after encryption
            SecureMemory.zeroize(privateKeysBundle)

            // Prepare public keys
            val publicKeysDto = PublicKeysDto(
                kem = Base64.encodeToString(keyBundle.kazKemPublicKey, Base64.NO_WRAP),
                sign = Base64.encodeToString(keyBundle.kazSignPublicKey, Base64.NO_WRAP),
                mlKem = keyBundle.mlKemPublicKey.takeIf { it.isNotEmpty() }?.let { Base64.encodeToString(it, Base64.NO_WRAP) },
                mlDsa = keyBundle.mlDsaPublicKey.takeIf { it.isNotEmpty() }?.let { Base64.encodeToString(it, Base64.NO_WRAP) }
            )

            // Convert password to String for API call (unavoidable for JSON serialization)
            val passwordString = String(password)

            val request = AcceptInviteRequest(
                displayName = displayName,
                password = passwordString,
                publicKeys = publicKeysDto,
                encryptedMasterKey = Base64.encodeToString(encryptedMasterKey, Base64.NO_WRAP),
                encryptedPrivateKeys = Base64.encodeToString(encryptedPrivateKeys, Base64.NO_WRAP),
                keyDerivationSalt = Base64.encodeToString(salt, Base64.NO_WRAP)
            )

            val response = apiService.acceptInvite(token, request)

            if (response.isSuccessful) {
                val acceptResponse = response.body()
                    ?: return Result.error(AppException.Unknown("Empty response from server"))

                val responseData = acceptResponse.data
                val userDto = responseData.user

                // Save tokens
                secureStorage.saveTokens(responseData.accessToken, responseData.refreshToken)

                // Save key material
                secureStorage.saveEncryptedMasterKey(encryptedMasterKey)
                secureStorage.saveEncryptedPrivateKeys(encryptedPrivateKeys)
                secureStorage.saveKeyDerivationSalt(salt)

                // Unlock keys
                keyManager.setUnlockedKeys(keyBundle)

                // Save user info
                secureStorage.saveUserId(userDto.id)

                // Save tenant context (multi-tenant support)
                val effectiveTenantId = userDto.getEffectiveTenantId()
                val effectiveRole = userDto.getEffectiveRole()

                if (effectiveTenantId != null) {
                    secureStorage.saveTenantId(effectiveTenantId)
                }
                if (effectiveRole != null) {
                    secureStorage.saveCurrentRole(effectiveRole)
                }

                // Save user's tenants list for tenant switching
                userDto.tenants?.let { tenants ->
                    val tenantsJson = com.google.gson.Gson().toJson(tenants)
                    secureStorage.saveUserTenants(tenantsJson)
                }

                // Fetch tenant config to get PQC algorithm
                fetchAndApplyTenantConfig()

                Logger.i(TAG, "Invitation accepted successfully for user: ${userDto.email}")
                Result.success(userDto.toDomain())
            } else {
                when (response.code()) {
                    400 -> Result.error(AppException.ValidationError("Invalid invitation data"))
                    404 -> Result.error(AppException.NotFound("Invitation not found"))
                    409 -> Result.error(AppException.ValidationError("Email already registered"))
                    410 -> Result.error(AppException.ValidationError("Invitation expired"))
                    422 -> Result.error(AppException.ValidationError("Invalid registration data"))
                    else -> Result.error(AppException.Unknown("Failed to accept invitation: ${response.code()}"))
                }
            }
        } catch (e: Exception) {
            // Ensure password bytes are zeroized even on exception
            SecureMemory.zeroize(passwordBytes)
            Logger.e(TAG, "Failed to accept invitation", e)
            Result.error(AppException.Network("Failed to accept invitation", e))
        }
    }

    /**
     * Silently upgrade the KDF profile if the device supports a stronger one.
     * This re-encrypts the master key with a stronger password-derived key,
     * updates the server, and saves locally. Best-effort: failures are logged
     * and do not affect the login flow.
     */
    private suspend fun upgradeKdfProfileIfNeeded(
        passwordBytes: ByteArray,
        masterKey: ByteArray,
        currentSalt: ByteArray
    ) {
        try {
            val deviceProfile = KdfProfile.selectForDevice(context)

            val needsUpgrade = if (KdfProfile.isTieredSalt(currentSalt)) {
                val currentProfile = KdfProfile.fromByte(currentSalt[0])
                currentProfile.profileByte > deviceProfile.profileByte
            } else {
                true // Legacy salt always needs upgrade
            }

            if (!needsUpgrade) return

            // Generate new salt + derive new key with stronger profile
            val newSalt = KdfProfile.createSaltWithProfile(deviceProfile)
            val newKey = cryptoManager.deriveKeyWithProfile(passwordBytes, newSalt)

            // Re-encrypt master key with the stronger key
            val newEncryptedMasterKey = cryptoManager.encryptAesGcm(masterKey, newKey)
            SecureMemory.zeroize(newKey)

            // Update server
            val request = UpdateKeyMaterialRequest(
                encryptedMasterKey = Base64.encodeToString(newEncryptedMasterKey, Base64.NO_WRAP),
                keyDerivationSalt = Base64.encodeToString(newSalt, Base64.NO_WRAP)
            )
            val response = apiService.updateKeyMaterial(request)
            if (!response.isSuccessful) return

            // Update local storage
            secureStorage.saveEncryptedMasterKey(newEncryptedMasterKey)
            secureStorage.saveKeyDerivationSalt(newSalt)

            Logger.i(TAG, "Upgraded KDF profile to ${deviceProfile.name}")
        } catch (e: Exception) {
            Logger.w(TAG, "KDF profile upgrade failed (non-fatal)", e)
        }
    }

    companion object {
        private const val TAG = "AuthRepository"
    }
}
