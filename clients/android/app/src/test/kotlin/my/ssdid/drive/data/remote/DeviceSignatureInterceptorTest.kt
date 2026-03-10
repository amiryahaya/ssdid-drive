package my.ssdid.drive.data.remote

import my.ssdid.drive.data.local.SecureStorage
import io.mockk.*
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

/**
 * Unit tests for DeviceSignatureInterceptor.
 *
 * Tests cover:
 * - Adding X-Device-ID header when device is enrolled
 * - Skipping header when device is not enrolled
 * - Handling null and empty enrollment IDs
 */
class DeviceSignatureInterceptorTest {

    private lateinit var secureStorage: SecureStorage
    private lateinit var interceptor: DeviceSignatureInterceptor
    private lateinit var mockWebServer: MockWebServer
    private lateinit var client: OkHttpClient

    @Before
    fun setup() {
        secureStorage = mockk(relaxed = true)
        interceptor = DeviceSignatureInterceptor(secureStorage)
        mockWebServer = MockWebServer()
        mockWebServer.start()

        client = OkHttpClient.Builder()
            .addInterceptor(interceptor)
            .build()
    }

    @After
    fun tearDown() {
        mockWebServer.shutdown()
    }

    // ==================== Device Enrolled Tests ====================

    @Test
    fun `adds X-Device-ID header when device is enrolled`() {
        every { secureStorage.getDeviceEnrollmentIdSync() } returns "enrollment-abc-123"

        mockWebServer.enqueue(MockResponse().setResponseCode(200))

        val request = Request.Builder()
            .url(mockWebServer.url("/api/files"))
            .build()

        client.newCall(request).execute()

        val recordedRequest = mockWebServer.takeRequest()
        assertEquals("enrollment-abc-123", recordedRequest.getHeader("X-Device-ID"))
    }

    @Test
    fun `preserves existing request headers when adding device header`() {
        every { secureStorage.getDeviceEnrollmentIdSync() } returns "enrollment-xyz"

        mockWebServer.enqueue(MockResponse().setResponseCode(200))

        val request = Request.Builder()
            .url(mockWebServer.url("/api/files"))
            .header("Authorization", "Bearer some-token")
            .build()

        client.newCall(request).execute()

        val recordedRequest = mockWebServer.takeRequest()
        assertEquals("enrollment-xyz", recordedRequest.getHeader("X-Device-ID"))
        assertEquals("Bearer some-token", recordedRequest.getHeader("Authorization"))
    }

    // ==================== Device Not Enrolled Tests ====================

    @Test
    fun `skips device header when enrollment ID is null`() {
        every { secureStorage.getDeviceEnrollmentIdSync() } returns null

        mockWebServer.enqueue(MockResponse().setResponseCode(200))

        val request = Request.Builder()
            .url(mockWebServer.url("/api/files"))
            .build()

        client.newCall(request).execute()

        val recordedRequest = mockWebServer.takeRequest()
        assertNull(recordedRequest.getHeader("X-Device-ID"))
    }

    @Test
    fun `skips device header when enrollment ID is empty`() {
        every { secureStorage.getDeviceEnrollmentIdSync() } returns ""

        mockWebServer.enqueue(MockResponse().setResponseCode(200))

        val request = Request.Builder()
            .url(mockWebServer.url("/api/files"))
            .build()

        client.newCall(request).execute()

        val recordedRequest = mockWebServer.takeRequest()
        assertNull(recordedRequest.getHeader("X-Device-ID"))
    }

    @Test
    fun `proceeds with request when device not enrolled`() {
        every { secureStorage.getDeviceEnrollmentIdSync() } returns null

        mockWebServer.enqueue(MockResponse().setResponseCode(200).setBody("response-body"))

        val request = Request.Builder()
            .url(mockWebServer.url("/api/me"))
            .build()

        val response = client.newCall(request).execute()

        assertEquals(200, response.code)
        assertEquals("response-body", response.body?.string())
    }

    @Test
    fun `proceeds with request when device is enrolled`() {
        every { secureStorage.getDeviceEnrollmentIdSync() } returns "enrollment-123"

        mockWebServer.enqueue(MockResponse().setResponseCode(200).setBody("ok"))

        val request = Request.Builder()
            .url(mockWebServer.url("/api/shares"))
            .build()

        val response = client.newCall(request).execute()

        assertEquals(200, response.code)
    }
}
