package my.ssdid.drive.data.remote

import my.ssdid.drive.crypto.DeviceManager
import my.ssdid.drive.data.local.SecureStorage
import okhttp3.Interceptor
import okhttp3.Response
import okio.Buffer
import javax.inject.Inject

/**
 * OkHttp Interceptor that adds device signature headers to requests.
 *
 * Headers added when device is enrolled:
 * - X-Device-ID: The device ID (from enrollment)
 * - X-Device-Signature: Base64-encoded signature of the request
 * - X-Signature-Timestamp: Unix timestamp (milliseconds) when signature was created
 *
 * The signature payload format is:
 * {method}|{path}|{timestamp}|{body_hash}
 *
 * Where body_hash is the SHA-256 hex digest of the request body (empty string for GET).
 */
class DeviceSignatureInterceptor @Inject constructor(
    private val secureStorage: SecureStorage,
    private val deviceManager: DeviceManager
) : Interceptor {

    override fun intercept(chain: Interceptor.Chain): Response {
        val originalRequest = chain.request()

        // Skip signing for non-authenticated endpoints
        if (isPublicEndpoint(originalRequest.url.encodedPath)) {
            return chain.proceed(originalRequest)
        }

        // Check if device is enrolled
        val enrollmentId = secureStorage.getDeviceEnrollmentIdSync()
        if (enrollmentId.isNullOrEmpty()) {
            // Not enrolled, proceed without device signature
            return chain.proceed(originalRequest)
        }

        // Check if device keys are loaded
        if (!deviceManager.hasDeviceKey()) {
            // Keys not loaded yet (will be loaded after login)
            return chain.proceed(originalRequest)
        }

        // Build signature
        val timestamp = System.currentTimeMillis()
        val method = originalRequest.method

        // SECURITY: Include full path with query params to prevent query tampering
        val pathWithQuery = buildString {
            append(originalRequest.url.encodedPath)
            val query = originalRequest.url.encodedQuery
            if (!query.isNullOrEmpty()) {
                append("?")
                append(query)
            }
        }

        // SECURITY: Hash raw body bytes directly to preserve binary content
        // Avoid UTF-8 decode/encode which can alter non-UTF-8 bytes
        val bodyBytes = originalRequest.body?.let { requestBody ->
            try {
                val buffer = Buffer()
                requestBody.writeTo(buffer)
                buffer.readByteArray()
            } catch (e: Exception) {
                null
            }
        }

        // Build and sign payload
        val payload = deviceManager.buildSignaturePayload(method, pathWithQuery, timestamp, bodyBytes)

        return try {
            val signature = kotlinx.coroutines.runBlocking {
                deviceManager.signRequest(payload)
            }

            if (signature != null) {
                // Add device signature headers
                val signedRequest = originalRequest.newBuilder()
                    .header("X-Device-ID", enrollmentId)
                    .header("X-Device-Signature", signature)
                    .header("X-Signature-Timestamp", timestamp.toString())
                    .build()

                chain.proceed(signedRequest)
            } else {
                // Signing failed, proceed without signature
                chain.proceed(originalRequest)
            }
        } catch (e: Exception) {
            // Signing error, proceed without signature
            chain.proceed(originalRequest)
        }
    }

    private fun isPublicEndpoint(path: String): Boolean {
        return path.contains("auth/login") ||
               path.contains("auth/register") ||
               path.contains("auth/refresh") ||
               path.contains("auth/webauthn/register/") ||
               path.contains("auth/webauthn/login/") ||
               path.contains("auth/oidc/") ||
               path.contains("auth/providers") ||
               path.contains("/health")
    }
}
