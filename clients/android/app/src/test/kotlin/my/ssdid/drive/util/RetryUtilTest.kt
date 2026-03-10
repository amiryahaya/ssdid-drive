package my.ssdid.drive.util

import android.util.Log
import io.mockk.*
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import java.io.IOException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import javax.net.ssl.SSLException

/**
 * Unit tests for RetryUtil.
 *
 * Tests cover:
 * - Successful operation on first attempt
 * - Retry with eventual success
 * - Retry exhaustion and exception propagation
 * - Non-retryable exception immediate throw
 * - Retryable exception detection (including cause chain)
 * - Retry callback invocation
 * - withRetryResult wrapper
 * - Retryable HTTP status codes
 * - Transient error messages
 * - Configuration presets (DEFAULT, NETWORK, CRYPTO)
 */
@OptIn(ExperimentalCoroutinesApi::class)
class RetryUtilTest {

    @Before
    fun setup() {
        mockkStatic(Log::class)
        every { Log.d(any(), any()) } returns 0
        every { Log.d(any(), any(), any()) } returns 0
        every { Log.i(any(), any()) } returns 0
        every { Log.w(any(), any<String>()) } returns 0
        every { Log.w(any(), any<String>(), any()) } returns 0
        every { Log.e(any(), any()) } returns 0
        every { Log.e(any(), any(), any()) } returns 0

        mockkObject(Logger)
        every { Logger.w(any(), any(), any()) } just Runs
    }

    @After
    fun tearDown() {
        unmockkStatic(Log::class)
        unmockkObject(Logger)
    }

    // ==================== Success Tests ====================

    @Test
    fun `withRetry returns result on first success`() = runTest {
        val result = RetryUtil.withRetry(config = fastConfig()) {
            "success"
        }

        assertEquals("success", result)
    }

    @Test
    fun `withRetry returns result after transient failure`() = runTest {
        var attempt = 0

        val result = RetryUtil.withRetry(config = fastConfig(maxAttempts = 3)) {
            attempt++
            if (attempt < 3) throw IOException("transient")
            "recovered"
        }

        assertEquals("recovered", result)
        assertEquals(3, attempt)
    }

    @Test
    fun `withRetry succeeds on second attempt`() = runTest {
        var attempt = 0

        val result = RetryUtil.withRetry(config = fastConfig(maxAttempts = 3)) {
            attempt++
            if (attempt == 1) throw SocketTimeoutException("timeout")
            42
        }

        assertEquals(42, result)
        assertEquals(2, attempt)
    }

    // ==================== Exhaustion Tests ====================

    @Test
    fun `withRetry throws after all attempts exhausted`() = runTest {
        var attempt = 0

        try {
            RetryUtil.withRetry(config = fastConfig(maxAttempts = 3)) {
                attempt++
                throw IOException("always fails")
            }
            fail("Should have thrown")
        } catch (e: IOException) {
            assertEquals("always fails", e.message)
            assertEquals(3, attempt)
        }
    }

    @Test
    fun `withRetry throws the last exception on exhaustion`() = runTest {
        var attempt = 0

        try {
            RetryUtil.withRetry(config = fastConfig(maxAttempts = 2)) {
                attempt++
                throw IOException("attempt $attempt")
            }
            fail("Should have thrown")
        } catch (e: IOException) {
            assertEquals("attempt 2", e.message)
        }
    }

    // ==================== Non-Retryable Exception Tests ====================

    @Test
    fun `withRetry throws immediately for non-retryable exception`() = runTest {
        var attempt = 0

        try {
            RetryUtil.withRetry(config = fastConfig(maxAttempts = 3)) {
                attempt++
                throw IllegalArgumentException("bad input")
            }
            fail("Should have thrown")
        } catch (e: IllegalArgumentException) {
            assertEquals("bad input", e.message)
            assertEquals(1, attempt) // Only one attempt, no retry
        }
    }

    @Test
    fun `withRetry does not retry RuntimeException`() = runTest {
        var attempt = 0

        try {
            RetryUtil.withRetry(config = fastConfig(maxAttempts = 3)) {
                attempt++
                throw RuntimeException("runtime error")
            }
            fail("Should have thrown")
        } catch (e: RuntimeException) {
            assertEquals(1, attempt)
        }
    }

    // ==================== isRetryable Tests ====================

    @Test
    fun `isRetryable returns true for IOException with default config`() {
        assertTrue(RetryUtil.isRetryable(IOException("io error")))
    }

    @Test
    fun `isRetryable returns true for SocketTimeoutException with default config`() {
        assertTrue(RetryUtil.isRetryable(SocketTimeoutException("timeout")))
    }

    @Test
    fun `isRetryable returns true for UnknownHostException with default config`() {
        assertTrue(RetryUtil.isRetryable(UnknownHostException("no host")))
    }

    @Test
    fun `isRetryable returns false for RuntimeException with default config`() {
        assertFalse(RetryUtil.isRetryable(RuntimeException("not retryable")))
    }

    @Test
    fun `isRetryable checks cause chain`() {
        val wrapper = RuntimeException("wrapper", IOException("root cause"))

        assertTrue(RetryUtil.isRetryable(wrapper))
    }

    @Test
    fun `isRetryable checks nested cause chain`() {
        val deepNested = RuntimeException(
            "level1",
            IllegalStateException(
                "level2",
                SocketTimeoutException("root timeout")
            )
        )

        assertTrue(RetryUtil.isRetryable(deepNested))
    }

    @Test
    fun `isRetryable returns false when no retryable exceptions configured`() {
        val config = RetryUtil.CRYPTO_CONFIG // has empty retryableExceptions

        assertFalse(RetryUtil.isRetryable(IOException("io"), config))
    }

    @Test
    fun `isRetryable with NETWORK_CONFIG includes SSLException`() {
        assertTrue(RetryUtil.isRetryable(SSLException("ssl error"), RetryUtil.NETWORK_CONFIG))
    }

    // ==================== Callback Tests ====================

    @Test
    fun `onRetry callback is invoked on each retry`() = runTest {
        val retryAttempts = mutableListOf<Int>()
        var attempt = 0

        RetryUtil.withRetry(
            config = fastConfig(maxAttempts = 3),
            onRetry = { attemptNum, _, _ -> retryAttempts.add(attemptNum) }
        ) {
            attempt++
            if (attempt < 3) throw IOException("fail")
            "ok"
        }

        assertEquals(listOf(1, 2), retryAttempts)
    }

    @Test
    fun `onRetry receives the exception that caused the retry`() = runTest {
        var capturedException: Exception? = null
        var attempt = 0

        RetryUtil.withRetry(
            config = fastConfig(maxAttempts = 2),
            onRetry = { _, ex, _ -> capturedException = ex }
        ) {
            attempt++
            if (attempt == 1) throw IOException("network down")
            "ok"
        }

        assertNotNull(capturedException)
        assertTrue(capturedException is IOException)
        assertEquals("network down", capturedException?.message)
    }

    @Test
    fun `onRetry is not called when first attempt succeeds`() = runTest {
        var callbackInvoked = false

        RetryUtil.withRetry(
            config = fastConfig(),
            onRetry = { _, _, _ -> callbackInvoked = true }
        ) {
            "immediate success"
        }

        assertFalse(callbackInvoked)
    }

    // ==================== withRetryResult Tests ====================

    @Test
    fun `withRetryResult returns success on success`() = runTest {
        val result = RetryUtil.withRetryResult(config = fastConfig()) {
            "value"
        }

        assertTrue(result.isSuccess)
        assertEquals("value", result.getOrNull())
    }

    @Test
    fun `withRetryResult returns failure on exhaustion`() = runTest {
        val result = RetryUtil.withRetryResult(config = fastConfig(maxAttempts = 2)) {
            throw IOException("always fails")
        }

        assertTrue(result.isFailure)
        assertTrue(result.exceptionOrNull() is IOException)
    }

    // ==================== HTTP Status Code Tests ====================

    @Test
    fun `isRetryableStatusCode returns true for 408`() {
        assertTrue(RetryUtil.isRetryableStatusCode(408))
    }

    @Test
    fun `isRetryableStatusCode returns true for 429`() {
        assertTrue(RetryUtil.isRetryableStatusCode(429))
    }

    @Test
    fun `isRetryableStatusCode returns true for 500`() {
        assertTrue(RetryUtil.isRetryableStatusCode(500))
    }

    @Test
    fun `isRetryableStatusCode returns true for 502`() {
        assertTrue(RetryUtil.isRetryableStatusCode(502))
    }

    @Test
    fun `isRetryableStatusCode returns true for 503`() {
        assertTrue(RetryUtil.isRetryableStatusCode(503))
    }

    @Test
    fun `isRetryableStatusCode returns true for 504`() {
        assertTrue(RetryUtil.isRetryableStatusCode(504))
    }

    @Test
    fun `isRetryableStatusCode returns false for 200`() {
        assertFalse(RetryUtil.isRetryableStatusCode(200))
    }

    @Test
    fun `isRetryableStatusCode returns false for 400`() {
        assertFalse(RetryUtil.isRetryableStatusCode(400))
    }

    @Test
    fun `isRetryableStatusCode returns false for 401`() {
        assertFalse(RetryUtil.isRetryableStatusCode(401))
    }

    @Test
    fun `isRetryableStatusCode returns false for 404`() {
        assertFalse(RetryUtil.isRetryableStatusCode(404))
    }

    // ==================== Transient Error Messages ====================

    @Test
    fun `getTransientErrorMessage for SocketTimeoutException`() {
        val msg = RetryUtil.getTransientErrorMessage(SocketTimeoutException())
        assertTrue(msg.contains("too long to respond"))
    }

    @Test
    fun `getTransientErrorMessage for UnknownHostException`() {
        val msg = RetryUtil.getTransientErrorMessage(UnknownHostException())
        assertTrue(msg.contains("internet connection"))
    }

    @Test
    fun `getTransientErrorMessage for SSLException`() {
        val msg = RetryUtil.getTransientErrorMessage(SSLException("ssl"))
        assertTrue(msg.contains("Secure connection"))
    }

    @Test
    fun `getTransientErrorMessage for IOException`() {
        val msg = RetryUtil.getTransientErrorMessage(IOException("io"))
        assertTrue(msg.contains("network error"))
    }

    @Test
    fun `getTransientErrorMessage for unknown exception uses message`() {
        val msg = RetryUtil.getTransientErrorMessage(RuntimeException("custom error"))
        assertEquals("custom error", msg)
    }

    @Test
    fun `getTransientErrorMessage for exception without message`() {
        val msg = RetryUtil.getTransientErrorMessage(RuntimeException())
        assertTrue(msg.contains("unexpected error"))
    }

    // ==================== Configuration Presets ====================

    @Test
    fun `DEFAULT_CONFIG has 3 max attempts`() {
        assertEquals(3, RetryUtil.DEFAULT_CONFIG.maxAttempts)
    }

    @Test
    fun `DEFAULT_CONFIG has 1000ms initial delay`() {
        assertEquals(1000L, RetryUtil.DEFAULT_CONFIG.initialDelayMs)
    }

    @Test
    fun `NETWORK_CONFIG has 5 max attempts`() {
        assertEquals(5, RetryUtil.NETWORK_CONFIG.maxAttempts)
    }

    @Test
    fun `NETWORK_CONFIG includes SSLException`() {
        assertTrue(RetryUtil.NETWORK_CONFIG.retryableExceptions.contains(SSLException::class.java))
    }

    @Test
    fun `CRYPTO_CONFIG has 2 max attempts`() {
        assertEquals(2, RetryUtil.CRYPTO_CONFIG.maxAttempts)
    }

    @Test
    fun `CRYPTO_CONFIG has empty retryable exceptions`() {
        assertTrue(RetryUtil.CRYPTO_CONFIG.retryableExceptions.isEmpty())
    }

    // ==================== Helper Functions ====================

    /**
     * Create a fast retry config for testing (minimal delays).
     */
    private fun fastConfig(
        maxAttempts: Int = 3,
        retryableExceptions: Set<Class<out Exception>> = setOf(
            IOException::class.java,
            SocketTimeoutException::class.java,
            UnknownHostException::class.java
        )
    ) = RetryConfig(
        maxAttempts = maxAttempts,
        initialDelayMs = 1L, // Minimal delay for tests
        maxDelayMs = 10L,
        backoffMultiplier = 2.0,
        retryableExceptions = retryableExceptions
    )
}
