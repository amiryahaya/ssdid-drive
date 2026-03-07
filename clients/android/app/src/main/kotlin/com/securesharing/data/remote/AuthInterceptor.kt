package com.securesharing.data.remote

import com.securesharing.data.local.SecureStorage
import okhttp3.Interceptor
import okhttp3.Response
import javax.inject.Inject

/**
 * OkHttp Interceptor that adds the Authorization header to requests.
 *
 * SECURITY: Uses synchronous storage access to avoid blocking OkHttp's
 * dispatcher threads with runBlocking. The sync methods internally use
 * runBlocking on IO dispatcher to prevent main thread blocking.
 */
class AuthInterceptor @Inject constructor(
    private val secureStorage: SecureStorage
) : Interceptor {

    override fun intercept(chain: Interceptor.Chain): Response {
        val originalRequest = chain.request()

        // Skip auth for login/register endpoints
        if (isAuthEndpoint(originalRequest.url.encodedPath)) {
            return chain.proceed(originalRequest)
        }

        // Get access token using sync method (avoids runBlocking on OkHttp thread)
        val accessToken = secureStorage.getAccessTokenSync()

        // If no token, proceed without auth
        if (accessToken.isNullOrEmpty()) {
            return chain.proceed(originalRequest)
        }

        // Add Authorization header and tenant context
        val tenantId = secureStorage.getTenantIdSync()

        val authenticatedRequest = originalRequest.newBuilder()
            .header("Authorization", "Bearer $accessToken")
            .header("Content-Type", "application/json")
            .apply {
                if (!tenantId.isNullOrEmpty()) {
                    header("X-Tenant-ID", tenantId)
                }
            }
            .build()

        return chain.proceed(authenticatedRequest)
    }

    private fun isAuthEndpoint(path: String): Boolean {
        return path.contains("auth/login") ||
               path.contains("auth/register") ||
               path.contains("auth/refresh") ||
               path.contains("auth/webauthn/register/") ||
               path.contains("auth/webauthn/login/") ||
               path.contains("auth/oidc/") ||
               path.contains("auth/providers")
    }
}
