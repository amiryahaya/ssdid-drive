package my.ssdid.drive.util

import android.util.Log
import my.ssdid.drive.BuildConfig
import io.mockk.*
import io.sentry.Sentry
import io.sentry.SentryLevel
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

/**
 * Unit tests for Logger.
 *
 * Tests cover:
 * - Log level methods (d, i, w, e)
 * - Security logging
 * - Sensitive data redaction
 * - Breadcrumb management
 * - URL sanitization
 * - Crypto operation logging
 */
class LoggerTest {

    @Before
    fun setup() {
        mockkStatic(Log::class)
        every { Log.d(any(), any()) } returns 0
        every { Log.d(any(), any(), any()) } returns 0
        every { Log.i(any(), any()) } returns 0
        every { Log.i(any(), any(), any()) } returns 0
        every { Log.w(any(), any<String>()) } returns 0
        every { Log.w(any(), any<String>(), any()) } returns 0
        every { Log.e(any(), any()) } returns 0
        every { Log.e(any(), any(), any()) } returns 0

        mockkObject(SentryConfig)
        every { SentryConfig.captureException(any(), any()) } just Runs
        every { SentryConfig.captureMessage(any(), any()) } just Runs

        mockkStatic(Sentry::class)
        every { Sentry.withScope(any()) } just Runs

        // Clear breadcrumbs before each test
        Logger.clearBreadcrumbs()
    }

    @After
    fun tearDown() {
        unmockkStatic(Log::class)
        unmockkObject(SentryConfig)
        unmockkStatic(Sentry::class)
        Logger.clearBreadcrumbs()
    }

    // ==================== Debug Logging ====================

    @Test
    fun `d logs with TAG_PREFIX in debug builds`() {
        Logger.d("TestTag", "debug message")

        verify { Log.d("SsdidDrive:TestTag", "debug message") }
    }

    @Test
    fun `d logs with throwable when provided`() {
        val throwable = RuntimeException("test error")

        Logger.d("TestTag", "debug message", throwable)

        verify { Log.d("SsdidDrive:TestTag", "debug message", throwable) }
    }

    @Test
    fun `d adds breadcrumb`() {
        Logger.d("TestTag", "breadcrumb message")

        val breadcrumbs = Logger.getBreadcrumbs()
        assertTrue(breadcrumbs.isNotEmpty())
        val last = breadcrumbs.last()
        assertEquals(LogLevel.DEBUG, last.level)
        assertEquals("TestTag", last.tag)
    }

    // ==================== Info Logging ====================

    @Test
    fun `i logs with TAG_PREFIX`() {
        Logger.i("InfoTag", "info message")

        verify { Log.i("SsdidDrive:InfoTag", "info message") }
    }

    @Test
    fun `i adds breadcrumb with INFO level`() {
        Logger.i("InfoTag", "info breadcrumb")

        val last = Logger.getBreadcrumbs().last()
        assertEquals(LogLevel.INFO, last.level)
    }

    // ==================== Warning Logging ====================

    @Test
    fun `w logs with TAG_PREFIX`() {
        Logger.w("WarnTag", "warning message")

        verify { Log.w("SsdidDrive:WarnTag", "warning message") }
    }

    @Test
    fun `w adds breadcrumb with WARNING level and throwable class`() {
        val throwable = IllegalStateException("bad state")

        Logger.w("WarnTag", "warning with cause", throwable)

        val last = Logger.getBreadcrumbs().last()
        assertEquals(LogLevel.WARNING, last.level)
        assertEquals("IllegalStateException", last.throwableClass)
    }

    // ==================== Error Logging ====================

    @Test
    fun `e always logs even in release mode`() {
        Logger.e("ErrorTag", "error message")

        verify { Log.e("SsdidDrive:ErrorTag", "error message") }
    }

    @Test
    fun `e logs with throwable when provided`() {
        val throwable = NullPointerException("null ref")

        Logger.e("ErrorTag", "error occurred", throwable)

        verify { Log.e("SsdidDrive:ErrorTag", "error occurred", throwable) }
    }

    @Test
    fun `e adds breadcrumb with ERROR level`() {
        Logger.e("ErrorTag", "error breadcrumb")

        val last = Logger.getBreadcrumbs().last()
        assertEquals(LogLevel.ERROR, last.level)
    }

    // ==================== Sensitive Data Redaction ====================

    @Test
    fun `sanitize redacts password patterns`() {
        Logger.d("Auth", "password: secret123")

        verify { Log.d("SsdidDrive:Auth", "[REDACTED]") }
    }

    @Test
    fun `sanitize redacts token patterns`() {
        Logger.d("Auth", "token: eyJhbGciOiJIUzI1NiJ9.payload.signature")

        verify { Log.d("SsdidDrive:Auth", match { it.contains("[REDACTED]") }) }
    }

    @Test
    fun `sanitize redacts bearer patterns`() {
        Logger.d("Net", "bearer abc123def456")

        verify { Log.d("SsdidDrive:Net", match { it.contains("[REDACTED]") }) }
    }

    @Test
    fun `sanitize redacts key patterns`() {
        Logger.d("Crypto", "key=ABCDEF0123456789")

        verify { Log.d("SsdidDrive:Crypto", match { it.contains("[REDACTED]") }) }
    }

    @Test
    fun `sanitize redacts email patterns`() {
        Logger.d("User", "email: user@example.com")

        verify { Log.d("SsdidDrive:User", match { it.contains("[REDACTED]") }) }
    }

    @Test
    fun `sanitize redacts long base64 strings`() {
        val longBase64 = "A".repeat(50)
        Logger.d("Crypto", "data: $longBase64")

        verify { Log.d("SsdidDrive:Crypto", match { it.contains("[REDACTED]") }) }
    }

    @Test
    fun `sanitize preserves non-sensitive messages`() {
        Logger.d("App", "User tapped login button")

        verify { Log.d("SsdidDrive:App", "User tapped login button") }
    }

    // ==================== Security Logging ====================

    @Test
    fun `security logs with SECURITY prefix and WARNING level`() {
        Logger.security("Auth", "login_attempt", mapOf("did" to "did:example:123"))

        verify { Log.w("SsdidDrive:Auth", match<String> { it.startsWith("SECURITY: login_attempt") }) }
    }

    @Test
    fun `security sanitizes detail values`() {
        // Use a long base64 string (40+ chars) which matches the sanitize pattern
        val sensitiveValue = "A".repeat(50)
        Logger.security("Auth", "auth_failure", mapOf("data" to sensitiveValue))

        verify {
            Log.w("SsdidDrive:Auth", match<String> {
                it.contains("SECURITY: auth_failure") && it.contains("[REDACTED]")
            })
        }
    }

    @Test
    fun `security adds breadcrumb with SECURITY level`() {
        Logger.security("Auth", "device_registered")

        val last = Logger.getBreadcrumbs().last()
        assertEquals(LogLevel.SECURITY, last.level)
    }

    @Test
    fun `security includes non-sensitive detail values`() {
        Logger.security("Auth", "login", mapOf("method" to "ssdid", "success" to true))

        verify {
            Log.w("SsdidDrive:Auth", match<String> {
                it.contains("method=ssdid") && it.contains("success=true")
            })
        }
    }

    // ==================== Breadcrumb Management ====================

    @Test
    fun `getBreadcrumbs returns empty list initially`() {
        assertTrue(Logger.getBreadcrumbs().isEmpty())
    }

    @Test
    fun `breadcrumbs accumulate across log calls`() {
        Logger.d("A", "msg1")
        Logger.i("B", "msg2")
        Logger.w("C", "msg3")

        assertEquals(3, Logger.getBreadcrumbs().size)
    }

    @Test
    fun `clearBreadcrumbs removes all breadcrumbs`() {
        Logger.d("A", "msg1")
        Logger.i("B", "msg2")

        Logger.clearBreadcrumbs()

        assertTrue(Logger.getBreadcrumbs().isEmpty())
    }

    @Test
    fun `breadcrumbs are capped at MAX_BREADCRUMBS`() {
        // Add more than MAX_BREADCRUMBS (100)
        repeat(120) { i ->
            Logger.d("Tag", "message $i")
        }

        val breadcrumbs = Logger.getBreadcrumbs()
        assertEquals(100, breadcrumbs.size)
        // Oldest entries should be removed (FIFO)
        assertTrue(breadcrumbs.first().message.contains("message 20"))
    }

    @Test
    fun `breadcrumbs store sanitized messages`() {
        Logger.d("Auth", "password: mysecret123")

        val last = Logger.getBreadcrumbs().last()
        assertTrue(last.message.contains("[REDACTED]"))
        assertFalse(last.message.contains("mysecret123"))
    }

    @Test
    fun `getBreadcrumbs returns a snapshot copy`() {
        Logger.d("A", "msg1")
        val snapshot = Logger.getBreadcrumbs()

        Logger.d("B", "msg2")

        // Snapshot should not be affected by new additions
        assertEquals(1, snapshot.size)
        assertEquals(2, Logger.getBreadcrumbs().size)
    }

    // ==================== Network Logging ====================

    @Test
    fun `network logs method and sanitized URL`() {
        Logger.network("Api", "GET", "https://api.example.com/users?token=abc123")

        verify {
            Log.d("SsdidDrive:Api", match {
                it.contains("GET") &&
                    it.contains("https://api.example.com/users") &&
                    it.contains("[params redacted]")
            })
        }
    }

    @Test
    fun `network logs URL without query params as-is`() {
        Logger.network("Api", "POST", "https://api.example.com/auth")

        verify {
            Log.d("SsdidDrive:Api", "POST https://api.example.com/auth")
        }
    }

    @Test
    fun `network includes status code when provided`() {
        Logger.network("Api", "GET", "https://api.example.com/files", statusCode = 200)

        verify {
            Log.d("SsdidDrive:Api", match { it.contains("-> 200") })
        }
    }

    @Test
    fun `network includes error when provided`() {
        Logger.network("Api", "POST", "https://api.example.com/upload", error = "timeout")

        verify {
            Log.d("SsdidDrive:Api", match { it.contains("ERROR: timeout") })
        }
    }

    // ==================== Crypto Logging ====================

    @Test
    fun `crypto logs success operations at debug level`() {
        Logger.crypto("Enc", "encrypt_file", success = true, details = "256-bit AES")

        verify { Log.d("SsdidDrive:Enc", match { it.contains("CRYPTO: encrypt_file SUCCESS") }) }
    }

    @Test
    fun `crypto logs failed operations at warning level`() {
        Logger.crypto("Dec", "decrypt_file", success = false, details = "wrong key")

        verify { Log.w("SsdidDrive:Dec", match<String> { it.contains("CRYPTO: decrypt_file FAILED") }) }
    }

    // ==================== Breadcrumb toString ====================

    @Test
    fun `Breadcrumb toString includes level, tag, and message`() {
        val breadcrumb = Breadcrumb(
            timestamp = 1700000000000L,
            level = LogLevel.ERROR,
            tag = "TestTag",
            message = "test message"
        )

        val str = breadcrumb.toString()
        assertTrue(str.contains("ERROR"))
        assertTrue(str.contains("TestTag"))
        assertTrue(str.contains("test message"))
    }

    @Test
    fun `Breadcrumb toString includes throwable class when present`() {
        val breadcrumb = Breadcrumb(
            timestamp = 1700000000000L,
            level = LogLevel.ERROR,
            tag = "Tag",
            message = "msg",
            throwableClass = "IOException"
        )

        assertTrue(breadcrumb.toString().contains("(IOException)"))
    }

    // ==================== LogLevel Enum ====================

    @Test
    fun `LogLevel has all expected values`() {
        val expected = setOf("DEBUG", "INFO", "WARNING", "ERROR", "SECURITY")
        val actual = LogLevel.entries.map { it.name }.toSet()
        assertEquals(expected, actual)
    }
}
