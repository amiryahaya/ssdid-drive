package my.ssdid.drive.data.repository

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Base64
import my.ssdid.drive.crypto.CryptoConfig
import my.ssdid.drive.crypto.CryptoManager
import my.ssdid.drive.crypto.FolderKeyManager
import my.ssdid.drive.crypto.KeyManager
import my.ssdid.drive.crypto.PqcAlgorithm
import my.ssdid.drive.crypto.SecureMemory
import dagger.hilt.android.qualifiers.ApplicationContext
import my.ssdid.drive.data.local.BiometricKeyInvalidatedException
import my.ssdid.drive.data.local.SecureStorage
import my.ssdid.drive.data.remote.ApiService
import my.ssdid.drive.data.remote.dto.UpdateProfileRequest
import my.ssdid.drive.domain.model.PublicKeys
import my.ssdid.drive.domain.model.TokenInvitation
import my.ssdid.drive.domain.model.TokenInvitationError
import my.ssdid.drive.domain.model.User
import my.ssdid.drive.domain.model.UserRole
import my.ssdid.drive.domain.repository.AuthRepository
import my.ssdid.drive.domain.repository.ChallengeInfo
import my.ssdid.drive.util.AnalyticsManager
import my.ssdid.drive.util.AppException
import my.ssdid.drive.util.CacheManager
import my.ssdid.drive.util.Logger
import my.ssdid.drive.util.PushNotificationManager
import my.ssdid.drive.util.Result
import java.net.URLEncoder
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
    private val cacheManager: CacheManager,
    private val pushNotificationManager: PushNotificationManager,
    private val analyticsManager: AnalyticsManager
) : AuthRepository {

    override suspend fun isAuthenticated(): Boolean {
        return getSession() != null
    }

    override suspend fun createChallenge(action: String): ChallengeInfo {
        val serverInfo = apiService.getServerInfo()

        // Build deep link URL for wallet
        val walletUrl = "ssdid://$action" +
            "?server_url=${URLEncoder.encode(serverInfo.serverUrl, "UTF-8")}" +
            "&server_did=${URLEncoder.encode(serverInfo.serverDid, "UTF-8")}" +
            "&challenge_id=${serverInfo.challengeId}" +
            "&callback=${URLEncoder.encode("ssdiddrive://auth/callback", "UTF-8")}"

        return ChallengeInfo(
            serverUrl = serverInfo.serverUrl,
            serverDid = serverInfo.serverDid,
            challengeId = serverInfo.challengeId,
            walletDeepLink = walletUrl
        )
    }

    override suspend fun launchWalletAuth(challenge: ChallengeInfo) {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(challenge.walletDeepLink)).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
    }

    override suspend fun saveSession(sessionToken: String) {
        secureStorage.saveString("session_token", sessionToken)
    }

    override suspend fun getSession(): String? {
        return secureStorage.getString("session_token")
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
                Logger.w(TAG, "Logout API call failed, continuing with local cleanup", e)
            }

            analyticsManager.clearUser()

            // Clear all local data and crypto caches
            secureStorage.clearAll()
            keyManager.clearUnlockedKeys()
            folderKeyManager.clearCache()

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

    override suspend fun areKeysUnlocked(): Boolean {
        return keyManager.hasUnlockedKeys()
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
            // Log error but don't fail - default to KAZ algorithm
            Logger.w(TAG, "Failed to fetch tenant config", e)
        }
    }

    // Extension function to convert DTO to domain model
    private fun my.ssdid.drive.data.remote.dto.UserDto.toDomain(): User {
        return User(
            id = id,
            email = email,
            displayName = displayName,
            status = status,
            recoverySetupComplete = recoverySetupComplete,
            // Multi-tenant fields
            tenants = tenants?.map { tenantDto ->
                my.ssdid.drive.domain.model.Tenant(
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

    override suspend fun enableBiometricUnlock(): Result<Unit> {
        return try {
            // Get master key from unlocked key manager
            if (!keyManager.hasUnlockedKeys()) {
                return Result.error(AppException.CryptoError("Keys are not unlocked"))
            }
            val masterKey = keyManager.getUnlockedKeys().masterKey

            // Store master key in biometric-protected storage
            secureStorage.saveBiometricProtectedMasterKey(masterKey)

            // Set biometric preference
            secureStorage.setBiometricUnlockPreference(true)

            Logger.i(TAG, "Biometric unlock enabled")
            Result.success(Unit)
        } catch (e: Exception) {
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
            // With SSDID Wallet architecture, biometric unlock re-requests
            // keys from the wallet rather than decrypting locally stored keys.
            // For now, check if keys are already available from a prior wallet callback.
            if (keyManager.hasUnlockedKeys()) {
                analyticsManager.trackLogin("biometric")
                Logger.i(TAG, "Keys already unlocked")
                return Result.success(Unit)
            }

            // Keys need to be obtained from the wallet via deep link
            Result.error(AppException.CryptoError("Please authenticate via SSDID Wallet"))
        } catch (e: BiometricKeyInvalidatedException) {
            secureStorage.disableBiometricUnlock()
            secureStorage.setBiometricUnlockPreference(false)
            Logger.w(TAG, "Biometric key invalidated, disabled biometric unlock", e)
            Result.error(AppException.CryptoError("Biometric credentials changed. Please re-enable biometric unlock."))
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

    companion object {
        private const val TAG = "AuthRepository"
    }
}
