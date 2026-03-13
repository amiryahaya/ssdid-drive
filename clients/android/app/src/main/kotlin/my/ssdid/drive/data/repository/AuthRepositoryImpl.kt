package my.ssdid.drive.data.repository

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Base64
import com.google.gson.Gson
import com.google.gson.annotations.SerializedName
import my.ssdid.drive.BuildConfig
import my.ssdid.drive.crypto.CryptoConfig
import my.ssdid.drive.crypto.CryptoManager
import my.ssdid.drive.crypto.FolderKeyManager
import my.ssdid.drive.crypto.KeyManager
import my.ssdid.drive.crypto.PqcAlgorithm
import my.ssdid.drive.crypto.SecureMemory
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.suspendCancellableCoroutine
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
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.sse.EventSource
import okhttp3.sse.EventSourceListener
import okhttp3.sse.EventSources
import java.net.URLEncoder
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

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
        val response = apiService.loginInitiate()
        val qr = response.qrPayload

        // Build same-device deep link per ssdid-drive-deeplink-protocol.md
        val serverUrl = qr.serviceUrl.ifEmpty { BuildConfig.API_BASE_URL.removeSuffix("/api/").removeSuffix("/api") }
        val walletUrl = "ssdid://authenticate" +
            "?server_url=${URLEncoder.encode(serverUrl, "UTF-8")}" +
            "&callback_url=${URLEncoder.encode("ssdiddrive://auth/callback", "UTF-8")}"

        return ChallengeInfo(
            challengeId = response.challengeId,
            subscriberSecret = response.subscriberSecret,
            walletDeepLink = walletUrl
        )
    }

    override suspend fun launchWalletAuth(challenge: ChallengeInfo) {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(challenge.walletDeepLink)).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
    }

    override suspend fun listenForSession(challenge: ChallengeInfo): String {
        val sseUrl = BuildConfig.API_BASE_URL.removeSuffix("/api/").removeSuffix("/api") +
            "/api/auth/ssdid/events" +
            "?challenge_id=${URLEncoder.encode(challenge.challengeId, "UTF-8")}" +
            "&subscriber_secret=${URLEncoder.encode(challenge.subscriberSecret, "UTF-8")}"

        return suspendCancellableCoroutine { continuation ->
            val client = OkHttpClient.Builder()
                .readTimeout(6, java.util.concurrent.TimeUnit.MINUTES)
                .build()

            val request = Request.Builder().url(sseUrl).build()

            val eventSource = EventSources.createFactory(client)
                .newEventSource(request, object : EventSourceListener() {
                    override fun onEvent(
                        eventSource: EventSource,
                        id: String?,
                        type: String?,
                        data: String
                    ) {
                        if (type == "authenticated") {
                            try {
                                val parsed = Gson().fromJson(data, SseAuthEvent::class.java)
                                if (continuation.isActive) {
                                    continuation.resume(parsed.sessionToken)
                                }
                            } catch (e: Exception) {
                                if (continuation.isActive) {
                                    continuation.resumeWithException(
                                        AppException.Unknown("Failed to parse session token", e)
                                    )
                                }
                            }
                            eventSource.cancel()
                        } else if (type == "timeout") {
                            if (continuation.isActive) {
                                continuation.resumeWithException(
                                    AppException.Unknown("Authentication timed out")
                                )
                            }
                            eventSource.cancel()
                        }
                    }

                    override fun onFailure(
                        eventSource: EventSource,
                        t: Throwable?,
                        response: Response?
                    ) {
                        if (continuation.isActive) {
                            continuation.resumeWithException(
                                AppException.Network(
                                    "SSE connection failed: ${t?.message ?: "unknown"}",
                                    t
                                )
                            )
                        }
                    }
                })

            continuation.invokeOnCancellation { eventSource.cancel() }
        }
    }

    private data class SseAuthEvent(
        @SerializedName("session_token") val sessionToken: String
    )

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

    override suspend fun launchWalletInvite(token: String) {
        val serverUrl = BuildConfig.API_BASE_URL.removeSuffix("/api/").removeSuffix("/api")
        val walletUrl = "ssdid://invite" +
            "?server_url=${URLEncoder.encode(serverUrl, "UTF-8")}" +
            "&token=${URLEncoder.encode(token, "UTF-8")}" +
            "&callback_url=${URLEncoder.encode("ssdiddrive://invite/callback", "UTF-8")}"

        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(walletUrl)).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
    }

    override suspend fun getInvitationInfo(token: String): Result<TokenInvitation> {
        return try {
            val response = apiService.getInviteInfo(token)

            if (response.isSuccessful) {
                val body = response.body()
                    ?: return Result.error(AppException.Unknown("Empty response from server"))

                val dto = body.data
                val invitation = TokenInvitation(
                    email = dto.email,
                    role = UserRole.fromString(dto.role),
                    tenantName = dto.tenantName,
                    inviterName = dto.inviterName,
                    message = dto.message,
                    expiresAt = dto.expiresAt,
                    valid = dto.status == "pending",
                    errorReason = when (dto.status) {
                        "pending" -> null
                        "accepted" -> TokenInvitationError.ALREADY_USED
                        "expired" -> TokenInvitationError.EXPIRED
                        "revoked" -> TokenInvitationError.REVOKED
                        else -> TokenInvitationError.NOT_FOUND
                    }
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
