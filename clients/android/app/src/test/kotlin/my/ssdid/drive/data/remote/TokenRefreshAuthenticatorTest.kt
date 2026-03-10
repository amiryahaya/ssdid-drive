package my.ssdid.drive.data.remote

import my.ssdid.drive.data.local.SecureStorage
import my.ssdid.drive.util.Logger
import io.mockk.*
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/**
 * Unit tests for TokenRefreshAuthenticator.
 *
 * Tests cover:
 * - Refreshing token on 401 response
 * - Handling refresh failure (returns null)
 * - Handling refresh exception
 * - No refresh when no token is available
 * - Max retry limit
 * - Concurrent refresh deduplication
 * - clearRefreshState
 */
class TokenRefreshAuthenticatorTest {

    private lateinit var secureStorage: SecureStorage
    private lateinit var tokenRefresher: TokenRefresher
    private lateinit var authenticator: TokenRefreshAuthenticator
    private lateinit var mockWebServer: MockWebServer

    @Before
    fun setup() {
        mockkObject(Logger)
        every { Logger.d(any(), any(), any()) } just Runs
        every { Logger.i(any(), any(), any()) } just Runs
        every { Logger.w(any(), any(), any()) } just Runs
        every { Logger.e(any(), any(), any()) } just Runs

        secureStorage = mockk(relaxed = true)
        tokenRefresher = mockk()
        authenticator = TokenRefreshAuthenticator(secureStorage, tokenRefresher)
        mockWebServer = MockWebServer()
        mockWebServer.start()
    }

    @After
    fun tearDown() {
        mockWebServer.shutdown()
        unmockkObject(Logger)
    }

    private fun buildClient(): OkHttpClient {
        return OkHttpClient.Builder()
            .authenticator(authenticator)
            .build()
    }

    // ==================== Successful Refresh Tests ====================

    @Test
    fun `refreshes token on 401 and retries request`() {
        every { secureStorage.getAccessTokenSync() } returns "old-token"
        every { tokenRefresher.refreshToken() } returns "new-token"

        // First response: 401 triggers authenticator
        // Second response: 200 with the refreshed token
        mockWebServer.enqueue(MockResponse().setResponseCode(401))
        mockWebServer.enqueue(MockResponse().setResponseCode(200).setBody("success"))

        val client = buildClient()
        val request = Request.Builder()
            .url(mockWebServer.url("/api/files"))
            .header("Authorization", "Bearer old-token")
            .build()

        val response = client.newCall(request).execute()

        assertEquals(200, response.code)

        // Verify the retried request has the new token
        mockWebServer.takeRequest() // first request (401)
        val retryRequest = mockWebServer.takeRequest() // second request (retried)
        assertEquals("Bearer new-token", retryRequest.getHeader("Authorization"))
    }

    // ==================== Refresh Failure Tests ====================

    @Test
    fun `returns null when refresh returns null token`() {
        every { secureStorage.getAccessTokenSync() } returns "old-token"
        every { tokenRefresher.refreshToken() } returns null

        // 401 triggers authenticator, which returns null -> no retry
        mockWebServer.enqueue(MockResponse().setResponseCode(401))

        val client = buildClient()
        val request = Request.Builder()
            .url(mockWebServer.url("/api/files"))
            .header("Authorization", "Bearer old-token")
            .build()

        val response = client.newCall(request).execute()

        // Should get the 401 since refresh failed
        assertEquals(401, response.code)
    }

    @Test
    fun `returns null when refresh throws exception`() {
        every { secureStorage.getAccessTokenSync() } returns "old-token"
        every { tokenRefresher.refreshToken() } throws RuntimeException("Network error")

        mockWebServer.enqueue(MockResponse().setResponseCode(401))

        val client = buildClient()
        val request = Request.Builder()
            .url(mockWebServer.url("/api/files"))
            .header("Authorization", "Bearer old-token")
            .build()

        val response = client.newCall(request).execute()

        assertEquals(401, response.code)
        verify { Logger.e(any(), "Token refresh failed", any()) }
    }

    // ==================== No Token Tests ====================

    @Test
    fun `returns null when no access token available`() {
        every { secureStorage.getAccessTokenSync() } returns null

        mockWebServer.enqueue(MockResponse().setResponseCode(401))

        val client = buildClient()
        val request = Request.Builder()
            .url(mockWebServer.url("/api/files"))
            .build()

        val response = client.newCall(request).execute()

        assertEquals(401, response.code)
        verify(exactly = 0) { tokenRefresher.refreshToken() }
    }

    @Test
    fun `returns null when access token is empty`() {
        every { secureStorage.getAccessTokenSync() } returns ""

        mockWebServer.enqueue(MockResponse().setResponseCode(401))

        val client = buildClient()
        val request = Request.Builder()
            .url(mockWebServer.url("/api/files"))
            .build()

        val response = client.newCall(request).execute()

        assertEquals(401, response.code)
        verify(exactly = 0) { tokenRefresher.refreshToken() }
    }

    // ==================== Max Retry Tests ====================

    @Test
    fun `stops retrying after max retries exceeded`() {
        val refreshCount = AtomicInteger(0)
        every { secureStorage.getAccessTokenSync() } returns "old-token"
        every { tokenRefresher.refreshToken() } answers {
            "new-token-${refreshCount.incrementAndGet()}"
        }

        // 401 -> authenticator refreshes -> retries -> 401 again -> should give up
        mockWebServer.enqueue(MockResponse().setResponseCode(401))
        mockWebServer.enqueue(MockResponse().setResponseCode(401))

        val client = buildClient()
        val request = Request.Builder()
            .url(mockWebServer.url("/api/files"))
            .header("Authorization", "Bearer old-token")
            .build()

        val response = client.newCall(request).execute()

        // Should eventually get a 401 because we hit max retries
        assertEquals(401, response.code)
    }

    // ==================== Concurrent Refresh Tests ====================

    @Test
    fun `uses token refreshed by another thread`() {
        // First call gets "old-token", second call (after another thread refreshed) gets "new-token"
        every { secureStorage.getAccessTokenSync() } returnsMany listOf("old-token", "new-token")
        every { tokenRefresher.refreshToken() } returns "new-token"

        mockWebServer.enqueue(MockResponse().setResponseCode(401))
        mockWebServer.enqueue(MockResponse().setResponseCode(200).setBody("ok"))

        val client = buildClient()
        val request = Request.Builder()
            .url(mockWebServer.url("/api/files"))
            .header("Authorization", "Bearer old-token")
            .build()

        val response = client.newCall(request).execute()

        assertEquals(200, response.code)
    }

    // ==================== Clear State Tests ====================

    @Test
    fun `clearRefreshState resets last refreshed token`() {
        every { secureStorage.getAccessTokenSync() } returns "token-1"
        every { tokenRefresher.refreshToken() } returns "refreshed-token"

        // Trigger a refresh
        mockWebServer.enqueue(MockResponse().setResponseCode(401))
        mockWebServer.enqueue(MockResponse().setResponseCode(200))

        val client = buildClient()
        val request = Request.Builder()
            .url(mockWebServer.url("/api/files"))
            .header("Authorization", "Bearer token-1")
            .build()

        client.newCall(request).execute()

        // Clear refresh state
        authenticator.clearRefreshState()

        // Subsequent 401 should trigger a fresh refresh
        every { secureStorage.getAccessTokenSync() } returns "token-2"
        every { tokenRefresher.refreshToken() } returns "refreshed-token-2"

        mockWebServer.enqueue(MockResponse().setResponseCode(401))
        mockWebServer.enqueue(MockResponse().setResponseCode(200))

        val request2 = Request.Builder()
            .url(mockWebServer.url("/api/files"))
            .header("Authorization", "Bearer token-2")
            .build()

        val response2 = client.newCall(request2).execute()
        assertEquals(200, response2.code)

        // tokenRefresher should have been called twice (once before clear, once after)
        verify(exactly = 2) { tokenRefresher.refreshToken() }
    }
}
