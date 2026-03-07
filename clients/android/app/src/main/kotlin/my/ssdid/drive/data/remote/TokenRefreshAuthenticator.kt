package my.ssdid.drive.data.remote

import com.google.gson.Gson
import my.ssdid.drive.BuildConfig
import my.ssdid.drive.data.local.SecureStorage
import my.ssdid.drive.data.remote.dto.AuthResponse
import my.ssdid.drive.data.remote.dto.RefreshTokenRequest
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import okhttp3.Authenticator
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okhttp3.Route
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import javax.inject.Inject

/**
 * OkHttp Authenticator that handles 401 responses by refreshing the access token.
 *
 * SECURITY: Uses Mutex for coroutine-safe token refresh deduplication.
 * When multiple 401 responses occur simultaneously, only one refresh request
 * is made and all waiting requests use the same result.
 */
class TokenRefreshAuthenticator @Inject constructor(
    private val secureStorage: SecureStorage,
    private val gson: Gson
) : Authenticator {

    // Separate client to avoid recursion
    private val refreshClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(30, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .build()
    }

    // Mutex for synchronizing token refresh across coroutines
    private val refreshMutex = Mutex()

    // Track the token that was used for the last successful refresh
    // This helps deduplicate refresh requests when multiple 401s come in
    private val lastRefreshedToken = AtomicReference<String?>(null)

    override fun authenticate(route: Route?, response: Response): Request? {
        // Avoid infinite loops - don't retry if we've already tried
        if (response.request.header("X-Retry-Auth") != null) {
            return null
        }

        return runBlocking {
            refreshMutex.withLock {
                // Get current refresh token
                val refreshToken = secureStorage.getRefreshToken()
                    ?: return@runBlocking null

                // Check if another thread already refreshed with this token
                // If so, the current access token should be valid
                val currentAccessToken = secureStorage.getAccessToken()
                if (lastRefreshedToken.get() == refreshToken && currentAccessToken != null) {
                    // Token was already refreshed, just retry with current token
                    return@runBlocking response.request.newBuilder()
                        .header("Authorization", "Bearer $currentAccessToken")
                        .header("X-Retry-Auth", "true")
                        .build()
                }

                // Try to refresh the token
                val newTokens = refreshAccessToken(refreshToken)
                if (newTokens == null) {
                    // Refresh failed, clear tokens and require re-login
                    secureStorage.clearTokens()
                    lastRefreshedToken.set(null)
                    return@runBlocking null
                }

                // Save new tokens
                secureStorage.saveTokens(newTokens.data.accessToken, newTokens.data.refreshToken)

                // Mark this refresh token as processed
                lastRefreshedToken.set(refreshToken)

                // Retry the original request with new token
                response.request.newBuilder()
                    .header("Authorization", "Bearer ${newTokens.data.accessToken}")
                    .header("X-Retry-Auth", "true")
                    .build()
            }
        }
    }

    private fun refreshAccessToken(refreshToken: String): AuthResponse? {
        val requestBody = gson.toJson(RefreshTokenRequest(refreshToken))
            .toRequestBody("application/json".toMediaType())

        val request = Request.Builder()
            .url("${BuildConfig.API_BASE_URL}auth/refresh")
            .post(requestBody)
            .build()

        return try {
            val response = refreshClient.newCall(request).execute()
            if (response.isSuccessful) {
                response.body?.string()?.let { body ->
                    gson.fromJson(body, AuthResponse::class.java)
                }
            } else {
                null
            }
        } catch (e: Exception) {
            null
        }
    }

    /**
     * Clear the refresh state (e.g., on logout).
     */
    fun clearRefreshState() {
        lastRefreshedToken.set(null)
    }
}
