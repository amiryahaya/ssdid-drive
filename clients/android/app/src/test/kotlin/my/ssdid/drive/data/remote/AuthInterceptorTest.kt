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
 * Unit tests for AuthInterceptor.
 *
 * Tests cover:
 * - Adding Authorization header when session token exists
 * - Skipping header when no token is available
 * - Skipping auth for unauthenticated endpoints (server-info, invite)
 * - Adding X-Tenant-ID header when tenant is set
 * - Skipping X-Tenant-ID header when tenant is not set
 */
class AuthInterceptorTest {

    private lateinit var secureStorage: SecureStorage
    private lateinit var authInterceptor: AuthInterceptor
    private lateinit var mockWebServer: MockWebServer
    private lateinit var client: OkHttpClient

    @Before
    fun setup() {
        secureStorage = mockk(relaxed = true)
        authInterceptor = AuthInterceptor(secureStorage)
        mockWebServer = MockWebServer()
        mockWebServer.start()

        client = OkHttpClient.Builder()
            .addInterceptor(authInterceptor)
            .build()
    }

    @After
    fun tearDown() {
        mockWebServer.shutdown()
    }

    // ==================== Token Present Tests ====================

    @Test
    fun `adds Authorization header when session token exists`() {
        every { secureStorage.getStringSync("session_token") } returns "test-session-token"
        every { secureStorage.getTenantIdSync() } returns null

        mockWebServer.enqueue(MockResponse().setResponseCode(200))

        val request = Request.Builder()
            .url(mockWebServer.url("/api/files"))
            .build()

        client.newCall(request).execute()

        val recordedRequest = mockWebServer.takeRequest()
        assertEquals("Bearer test-session-token", recordedRequest.getHeader("Authorization"))
    }

    @Test
    fun `adds Content-Type header for authenticated requests`() {
        every { secureStorage.getStringSync("session_token") } returns "test-token"
        every { secureStorage.getTenantIdSync() } returns null

        mockWebServer.enqueue(MockResponse().setResponseCode(200))

        val request = Request.Builder()
            .url(mockWebServer.url("/api/me"))
            .build()

        client.newCall(request).execute()

        val recordedRequest = mockWebServer.takeRequest()
        assertEquals("application/json", recordedRequest.getHeader("Content-Type"))
    }

    @Test
    fun `adds X-Tenant-ID header when tenant is set`() {
        every { secureStorage.getStringSync("session_token") } returns "test-token"
        every { secureStorage.getTenantIdSync() } returns "tenant-abc-123"

        mockWebServer.enqueue(MockResponse().setResponseCode(200))

        val request = Request.Builder()
            .url(mockWebServer.url("/api/folders"))
            .build()

        client.newCall(request).execute()

        val recordedRequest = mockWebServer.takeRequest()
        assertEquals("tenant-abc-123", recordedRequest.getHeader("X-Tenant-ID"))
    }

    @Test
    fun `does not add X-Tenant-ID header when tenant is null`() {
        every { secureStorage.getStringSync("session_token") } returns "test-token"
        every { secureStorage.getTenantIdSync() } returns null

        mockWebServer.enqueue(MockResponse().setResponseCode(200))

        val request = Request.Builder()
            .url(mockWebServer.url("/api/folders"))
            .build()

        client.newCall(request).execute()

        val recordedRequest = mockWebServer.takeRequest()
        assertNull(recordedRequest.getHeader("X-Tenant-ID"))
    }

    @Test
    fun `does not add X-Tenant-ID header when tenant is empty`() {
        every { secureStorage.getStringSync("session_token") } returns "test-token"
        every { secureStorage.getTenantIdSync() } returns ""

        mockWebServer.enqueue(MockResponse().setResponseCode(200))

        val request = Request.Builder()
            .url(mockWebServer.url("/api/folders"))
            .build()

        client.newCall(request).execute()

        val recordedRequest = mockWebServer.takeRequest()
        assertNull(recordedRequest.getHeader("X-Tenant-ID"))
    }

    // ==================== No Token Tests ====================

    @Test
    fun `skips Authorization header when no session token`() {
        every { secureStorage.getStringSync("session_token") } returns null

        mockWebServer.enqueue(MockResponse().setResponseCode(200))

        val request = Request.Builder()
            .url(mockWebServer.url("/api/files"))
            .build()

        client.newCall(request).execute()

        val recordedRequest = mockWebServer.takeRequest()
        assertNull(recordedRequest.getHeader("Authorization"))
    }

    @Test
    fun `skips Authorization header when session token is empty`() {
        every { secureStorage.getStringSync("session_token") } returns ""

        mockWebServer.enqueue(MockResponse().setResponseCode(200))

        val request = Request.Builder()
            .url(mockWebServer.url("/api/files"))
            .build()

        client.newCall(request).execute()

        val recordedRequest = mockWebServer.takeRequest()
        assertNull(recordedRequest.getHeader("Authorization"))
    }

    // ==================== Unauthenticated Endpoint Tests ====================

    @Test
    fun `skips auth for server-info endpoint`() {
        every { secureStorage.getStringSync("session_token") } returns "test-token"

        mockWebServer.enqueue(MockResponse().setResponseCode(200))

        val request = Request.Builder()
            .url(mockWebServer.url("/api/auth/ssdid/server-info"))
            .build()

        client.newCall(request).execute()

        val recordedRequest = mockWebServer.takeRequest()
        assertNull(recordedRequest.getHeader("Authorization"))
        // Should not call getTenantIdSync for unauthenticated endpoints
        verify(exactly = 0) { secureStorage.getTenantIdSync() }
    }

    @Test
    fun `skips auth for invite endpoint`() {
        every { secureStorage.getStringSync("session_token") } returns "test-token"

        mockWebServer.enqueue(MockResponse().setResponseCode(200))

        val request = Request.Builder()
            .url(mockWebServer.url("/api/invite/some-token-here"))
            .build()

        client.newCall(request).execute()

        val recordedRequest = mockWebServer.takeRequest()
        assertNull(recordedRequest.getHeader("Authorization"))
    }

    @Test
    fun `adds auth for non-excluded endpoints`() {
        every { secureStorage.getStringSync("session_token") } returns "test-token"
        every { secureStorage.getTenantIdSync() } returns null

        mockWebServer.enqueue(MockResponse().setResponseCode(200))

        val request = Request.Builder()
            .url(mockWebServer.url("/api/shares/created"))
            .build()

        client.newCall(request).execute()

        val recordedRequest = mockWebServer.takeRequest()
        assertNotNull(recordedRequest.getHeader("Authorization"))
    }

    @Test
    fun `proceeds with chain for all request types`() {
        every { secureStorage.getStringSync("session_token") } returns "test-token"
        every { secureStorage.getTenantIdSync() } returns "tenant-1"

        mockWebServer.enqueue(MockResponse().setResponseCode(200).setBody("ok"))

        val request = Request.Builder()
            .url(mockWebServer.url("/api/me"))
            .build()

        val response = client.newCall(request).execute()

        assertEquals(200, response.code)
        assertEquals("ok", response.body?.string())
    }
}
