package my.ssdid.drive.data.remote

import my.ssdid.drive.data.local.SecureStorage
import okhttp3.Interceptor
import okhttp3.Response
import javax.inject.Inject

/**
 * OkHttp Interceptor that adds the Authorization header to requests.
 *
 * Uses session token from SSDID Wallet authentication.
 * Skips unauthenticated endpoints (server-info, invite).
 */
class AuthInterceptor @Inject constructor(
    private val secureStorage: SecureStorage
) : Interceptor {

    override fun intercept(chain: Interceptor.Chain): Response {
        val originalRequest = chain.request()

        // Skip auth for unauthenticated endpoints
        if (isUnauthenticatedEndpoint(originalRequest.url.encodedPath)) {
            return chain.proceed(originalRequest)
        }

        // Get session token
        val sessionToken = secureStorage.getStringSync("session_token")

        // If no token, proceed without auth
        if (sessionToken.isNullOrEmpty()) {
            return chain.proceed(originalRequest)
        }

        // Add Authorization header and tenant context
        val tenantId = secureStorage.getTenantIdSync()

        val authenticatedRequest = originalRequest.newBuilder()
            .header("Authorization", "Bearer $sessionToken")
            .header("Content-Type", "application/json")
            .apply {
                if (!tenantId.isNullOrEmpty()) {
                    header("X-Tenant-ID", tenantId)
                }
            }
            .build()

        return chain.proceed(authenticatedRequest)
    }

    private fun isUnauthenticatedEndpoint(path: String): Boolean {
        return path.contains("auth/ssdid/server-info") ||
               path.contains("invite/")
    }
}
