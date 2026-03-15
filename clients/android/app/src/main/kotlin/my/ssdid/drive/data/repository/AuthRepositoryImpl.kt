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
import my.ssdid.drive.data.remote.dto.*
import my.ssdid.drive.domain.model.LinkedLogin
import my.ssdid.drive.domain.model.PublicKeys
import my.ssdid.drive.domain.model.TokenInvitation
import my.ssdid.drive.domain.model.TokenInvitationError
import my.ssdid.drive.domain.model.TotpSetupInfo
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
import uniffi.ssdid_sdk_ffi.buildLoginRequest
import uniffi.ssdid_sdk_ffi.FfiRequestedClaim
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

        val serverUrl = qr.serviceUrl.ifEmpty { BuildConfig.API_BASE_URL.removeSuffix("/api/").removeSuffix("/api") }

        // Convert backend requested_claims to SDK format
        val requestedClaims = mutableListOf<FfiRequestedClaim>()
        qr.requestedClaims?.required?.forEach { name ->
            requestedClaims.add(FfiRequestedClaim(name = name, required = true))
        }
        qr.requestedClaims?.optional?.forEach { name ->
            requestedClaims.add(FfiRequestedClaim(name = name, required = false))
        }
        if (requestedClaims.isEmpty()) {
            // Default claims when backend doesn't specify any
            requestedClaims.add(FfiRequestedClaim(name = "name", required = true))
            requestedClaims.add(FfiRequestedClaim(name = "email", required = false))
        }

        // Build same-device deep link via ssdid-sdk
        val walletUrl = buildLoginRequest(
            serverUrl = serverUrl,
            serviceName = qr.serviceName,
            challengeId = qr.challengeId,
            callbackScheme = "ssdiddrive",
            requestedClaims = requestedClaims,
            challenge = qr.challenge,
            serverDid = qr.serverDid,
            serverKeyId = qr.serverKeyId,
            serverSignature = qr.serverSignature,
            registryUrl = qr.registryUrl
        )

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

    override suspend fun saveSession(accessToken: String, refreshToken: String) {
        secureStorage.saveString("session_token", accessToken)
        secureStorage.saveString("refresh_token", refreshToken)
    }

    override suspend fun getSession(): String? {
        return secureStorage.getString("session_token")
    }

    // ==================== Email + TOTP Auth ====================

    override suspend fun emailLogin(email: String): Result<Boolean> {
        return try {
            val response = apiService.emailLogin(EmailLoginRequest(email = email))
            if (response.isSuccessful) {
                val body = response.body()
                    ?: return Result.error(AppException.Unknown("Empty response"))
                Result.success(body.requiresTotp)
            } else {
                when (response.code()) {
                    404 -> Result.error(AppException.NotFound("Account not found"))
                    429 -> Result.error(AppException.ValidationError("Too many attempts. Please try again later."))
                    else -> Result.error(AppException.Unknown("Login failed: ${response.code()}"))
                }
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to login", e))
        }
    }

    override suspend fun emailRegister(email: String, invitationToken: String): Result<Unit> {
        return try {
            val response = apiService.emailRegister(
                EmailRegisterRequest(email = email, invitationToken = invitationToken)
            )
            if (response.isSuccessful) {
                Result.success(Unit)
            } else {
                when (response.code()) {
                    409 -> Result.error(AppException.ValidationError("Email already registered"))
                    422 -> Result.error(AppException.ValidationError("Invalid invitation"))
                    429 -> Result.error(AppException.ValidationError("Too many attempts"))
                    else -> Result.error(AppException.Unknown("Registration failed: ${response.code()}"))
                }
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to register", e))
        }
    }

    override suspend fun emailRegisterVerify(
        email: String,
        code: String,
        invitationToken: String
    ): Result<User> {
        return try {
            val response = apiService.emailRegisterVerify(
                EmailRegisterVerifyRequest(
                    email = email,
                    code = code,
                    invitationToken = invitationToken
                )
            )
            handleAuthResponse(response)
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to verify registration", e))
        }
    }

    override suspend fun totpVerify(email: String, code: String): Result<User> {
        return try {
            val response = apiService.totpVerify(
                TotpVerifyRequest(email = email, code = code)
            )
            handleAuthResponse(response)
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to verify TOTP", e))
        }
    }

    override suspend fun totpSetup(): Result<TotpSetupInfo> {
        return try {
            val response = apiService.totpSetup()
            if (response.isSuccessful) {
                val body = response.body()
                    ?: return Result.error(AppException.Unknown("Empty response"))
                Result.success(
                    TotpSetupInfo(
                        secret = body.secret,
                        otpauthUri = body.otpauthUri,
                        qrCode = body.qrCode
                    )
                )
            } else {
                Result.error(AppException.Unknown("TOTP setup failed: ${response.code()}"))
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to setup TOTP", e))
        }
    }

    override suspend fun totpSetupConfirm(code: String): Result<List<String>> {
        return try {
            val response = apiService.totpSetupConfirm(
                TotpSetupConfirmRequest(code = code)
            )
            if (response.isSuccessful) {
                val body = response.body()
                    ?: return Result.error(AppException.Unknown("Empty response"))
                Result.success(body.backupCodes)
            } else {
                when (response.code()) {
                    400 -> Result.error(AppException.ValidationError("Invalid TOTP code"))
                    else -> Result.error(AppException.Unknown("TOTP confirm failed: ${response.code()}"))
                }
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to confirm TOTP", e))
        }
    }

    override suspend fun totpRecovery(email: String): Result<Unit> {
        return try {
            val response = apiService.totpRecovery(TotpRecoveryRequest(email = email))
            if (response.isSuccessful) {
                Result.success(Unit)
            } else {
                Result.error(AppException.Unknown("TOTP recovery failed: ${response.code()}"))
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to initiate TOTP recovery", e))
        }
    }

    override suspend fun totpRecoveryVerify(email: String, code: String): Result<User> {
        return try {
            val response = apiService.totpRecoveryVerify(
                TotpRecoveryVerifyRequest(email = email, code = code)
            )
            handleAuthResponse(response)
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to verify TOTP recovery", e))
        }
    }

    // ==================== OIDC Auth ====================

    override suspend fun oidcVerify(
        provider: String,
        idToken: String,
        invitationToken: String?
    ): Result<User> {
        return try {
            val response = apiService.oidcVerify(
                OidcVerifyRequest(
                    provider = provider,
                    idToken = idToken,
                    invitationToken = invitationToken
                )
            )
            handleAuthResponse(response)
        } catch (e: Exception) {
            Result.error(AppException.Network("OIDC verification failed", e))
        }
    }

    // ==================== Account Logins (Linking) ====================

    override suspend fun getLinkedLogins(): Result<List<LinkedLogin>> {
        return try {
            val response = apiService.getLinkedLogins()
            if (response.isSuccessful) {
                val body = response.body()
                    ?: return Result.error(AppException.Unknown("Empty response"))
                val logins = body.data.map { it.toDomain() }
                Result.success(logins)
            } else {
                Result.error(AppException.Unknown("Failed to get logins: ${response.code()}"))
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to get linked logins", e))
        }
    }

    override suspend fun linkEmail(email: String): Result<Unit> {
        return try {
            val response = apiService.linkEmail(LinkEmailRequest(email = email))
            if (response.isSuccessful) {
                Result.success(Unit)
            } else {
                when (response.code()) {
                    409 -> Result.error(AppException.ValidationError("Email already linked to another account"))
                    else -> Result.error(AppException.Unknown("Failed to link email: ${response.code()}"))
                }
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to link email", e))
        }
    }

    override suspend fun linkEmailVerify(email: String, code: String): Result<LinkedLogin> {
        return try {
            val response = apiService.linkEmailVerify(
                LinkEmailVerifyRequest(email = email, code = code)
            )
            if (response.isSuccessful) {
                val body = response.body()
                    ?: return Result.error(AppException.Unknown("Empty response"))
                Result.success(body.toDomain())
            } else {
                Result.error(AppException.Unknown("Failed to verify email link: ${response.code()}"))
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to verify email link", e))
        }
    }

    override suspend fun linkOidc(provider: String, idToken: String): Result<LinkedLogin> {
        return try {
            val response = apiService.linkOidc(
                LinkOidcRequest(provider = provider, idToken = idToken)
            )
            if (response.isSuccessful) {
                val body = response.body()
                    ?: return Result.error(AppException.Unknown("Empty response"))
                Result.success(body.toDomain())
            } else {
                when (response.code()) {
                    409 -> Result.error(AppException.ValidationError("This login is already linked to another account"))
                    else -> Result.error(AppException.Unknown("Failed to link OIDC: ${response.code()}"))
                }
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to link OIDC login", e))
        }
    }

    override suspend fun unlinkLogin(loginId: String): Result<Unit> {
        return try {
            val response = apiService.unlinkLogin(loginId)
            if (response.isSuccessful) {
                Result.success(Unit)
            } else {
                when (response.code()) {
                    400 -> Result.error(AppException.ValidationError("Cannot remove last login method"))
                    else -> Result.error(AppException.Unknown("Failed to unlink login: ${response.code()}"))
                }
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to unlink login", e))
        }
    }

    /**
     * Handle a standard auth response (access_token + refresh_token + user).
     */
    private suspend fun handleAuthResponse(
        response: retrofit2.Response<AuthResponse>
    ): Result<User> {
        if (response.isSuccessful) {
            val body = response.body()
                ?: return Result.error(AppException.Unknown("Empty auth response"))
            val data = body.data
            saveSession(data.accessToken, data.refreshToken)
            fetchAndApplyTenantConfig()
            analyticsManager.trackLogin("standard")
            pushNotificationManager.requestPermission()
            return Result.success(data.user.toDomain())
        } else {
            return when (response.code()) {
                401 -> Result.error(AppException.Unauthorized())
                422 -> Result.error(AppException.ValidationError("Invalid credentials"))
                429 -> Result.error(AppException.ValidationError("Too many attempts"))
                else -> Result.error(AppException.Unknown("Auth failed: ${response.code()}"))
            }
        }
    }

    private fun LinkedLoginDto.toDomain(): LinkedLogin {
        return LinkedLogin(
            id = id,
            provider = provider,
            providerSubject = providerSubject,
            email = email,
            linkedAt = linkedAt
        )
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
