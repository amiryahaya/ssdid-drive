package my.ssdid.drive.data.remote

import my.ssdid.drive.data.local.SecureStorage
import my.ssdid.drive.util.Logger
import okhttp3.Authenticator
import okhttp3.Request
import okhttp3.Response
import okhttp3.Route
import java.util.concurrent.atomic.AtomicReference
import javax.inject.Inject

/**
 * OkHttp Authenticator that handles 401 responses by refreshing the session token.
 *
 * Uses AtomicReference-based deduplication so that multiple simultaneous 401s
 * share a single refresh request rather than triggering multiple refreshes.
 *
 * SECURITY: Limits retry attempts to prevent infinite loops.
 */
class TokenRefreshAuthenticator @Inject constructor(
    private val secureStorage: SecureStorage,
    private val tokenRefresher: TokenRefresher
) : Authenticator {

    /** Tracks the last successfully refreshed token to avoid duplicate refreshes. */
    private val lastRefreshedToken = AtomicReference<String?>(null)

    /** Maximum number of refresh attempts per request chain. */
    private val maxRetries = 1

    override fun authenticate(route: Route?, response: Response): Request? {
        val tag = "TokenRefreshAuthenticator"

        // Check retry count to prevent infinite loops
        val retryCount = responseCount(response)
        if (retryCount > maxRetries) {
            Logger.w(tag, "Max refresh retries exceeded ($retryCount)")
            return null
        }

        val currentToken = secureStorage.getAccessTokenSync()

        // If no token exists, we can't refresh
        if (currentToken.isNullOrEmpty()) {
            Logger.w(tag, "No access token available for refresh")
            return null
        }

        // Check if another thread already refreshed the token
        val lastRefreshed = lastRefreshedToken.get()
        if (lastRefreshed != null && lastRefreshed != currentToken) {
            // Another thread already refreshed - use the new token
            Logger.d(tag, "Using token refreshed by another thread")
            return response.request.newBuilder()
                .header("Authorization", "Bearer $lastRefreshed")
                .build()
        }

        // Attempt to refresh the token
        synchronized(this) {
            // Double-check after acquiring lock
            val doubleCheckToken = secureStorage.getAccessTokenSync()
            if (doubleCheckToken != currentToken && doubleCheckToken != null) {
                lastRefreshedToken.set(doubleCheckToken)
                return response.request.newBuilder()
                    .header("Authorization", "Bearer $doubleCheckToken")
                    .build()
            }

            // Perform the actual token refresh
            val newToken = try {
                tokenRefresher.refreshToken()
            } catch (e: Exception) {
                Logger.e(tag, "Token refresh failed", e)
                null
            }

            if (newToken == null) {
                Logger.w(tag, "Token refresh returned null")
                return null
            }

            lastRefreshedToken.set(newToken)

            return response.request.newBuilder()
                .header("Authorization", "Bearer $newToken")
                .build()
        }
    }

    /**
     * Clear the refresh state. Call this on logout.
     */
    fun clearRefreshState() {
        lastRefreshedToken.set(null)
    }

    /**
     * Count prior responses in the chain to detect retries.
     */
    private fun responseCount(response: Response): Int {
        var count = 1
        var prior = response.priorResponse
        while (prior != null) {
            count++
            prior = prior.priorResponse
        }
        return count
    }
}

/**
 * Interface for token refresh operations.
 * Extracted for testability - the implementation handles the actual API call.
 */
interface TokenRefresher {
    /**
     * Refresh the access token using the stored refresh token.
     * @return The new access token, or null if refresh fails.
     */
    fun refreshToken(): String?
}
