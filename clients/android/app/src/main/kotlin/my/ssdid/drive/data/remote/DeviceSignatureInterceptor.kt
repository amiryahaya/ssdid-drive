package my.ssdid.drive.data.remote

import android.util.Base64
import my.ssdid.drive.data.local.SecureStorage
import okhttp3.Interceptor
import okhttp3.Response
import javax.inject.Inject

/**
 * OkHttp Interceptor that adds device signature headers to requests.
 *
 * When a device is enrolled, this interceptor adds:
 * - X-Device-ID: The enrolled device's enrollment ID
 *
 * This binds API requests to the enrolled device for server-side
 * device verification and audit logging.
 */
class DeviceSignatureInterceptor @Inject constructor(
    private val secureStorage: SecureStorage
) : Interceptor {

    override fun intercept(chain: Interceptor.Chain): Response {
        val originalRequest = chain.request()

        // Get device enrollment ID
        val enrollmentId = secureStorage.getDeviceEnrollmentIdSync()

        // If not enrolled, proceed without device headers
        if (enrollmentId.isNullOrEmpty()) {
            return chain.proceed(originalRequest)
        }

        // Add device identification header
        val signedRequest = originalRequest.newBuilder()
            .header("X-Device-ID", enrollmentId)
            .build()

        return chain.proceed(signedRequest)
    }
}
