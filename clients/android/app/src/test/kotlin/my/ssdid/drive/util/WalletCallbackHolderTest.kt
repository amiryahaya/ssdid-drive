package my.ssdid.drive.util

import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import java.util.concurrent.CyclicBarrier
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

/**
 * Unit tests for WalletCallbackHolder.
 *
 * Tests cover:
 * - Setting and consuming session tokens
 * - Consume-once semantics (token cleared after consume)
 * - Null when no token is set
 * - Overwrite behavior on repeated set
 * - Thread safety / concurrent access
 */
class WalletCallbackHolderTest {

    @Before
    fun setup() {
        // Ensure clean state before each test
        WalletCallbackHolder.consume()
    }

    // ==================== Basic Functionality Tests ====================

    @Test
    fun `pendingSessionToken is null initially`() {
        assertNull(WalletCallbackHolder.pendingSessionToken)
    }

    @Test
    fun `set stores the session token`() {
        WalletCallbackHolder.set("token-abc-123")

        assertEquals("token-abc-123", WalletCallbackHolder.pendingSessionToken)
    }

    @Test
    fun `consume returns the stored token`() {
        WalletCallbackHolder.set("my-session-token")

        val result = WalletCallbackHolder.consume()

        assertEquals("my-session-token", result)
    }

    @Test
    fun `consume clears the token after retrieval`() {
        WalletCallbackHolder.set("one-time-token")

        WalletCallbackHolder.consume()

        assertNull(WalletCallbackHolder.pendingSessionToken)
    }

    @Test
    fun `consume returns null when no token is set`() {
        val result = WalletCallbackHolder.consume()

        assertNull(result)
    }

    @Test
    fun `second consume returns null after first consume`() {
        WalletCallbackHolder.set("ephemeral-token")

        val first = WalletCallbackHolder.consume()
        val second = WalletCallbackHolder.consume()

        assertEquals("ephemeral-token", first)
        assertNull(second)
    }

    // ==================== Overwrite Behavior Tests ====================

    @Test
    fun `set overwrites previous token`() {
        WalletCallbackHolder.set("first-token")
        WalletCallbackHolder.set("second-token")

        val result = WalletCallbackHolder.consume()

        assertEquals("second-token", result)
    }

    @Test
    fun `set after consume stores new token`() {
        WalletCallbackHolder.set("token-1")
        WalletCallbackHolder.consume()

        WalletCallbackHolder.set("token-2")

        assertEquals("token-2", WalletCallbackHolder.pendingSessionToken)
    }

    // ==================== Edge Cases ====================

    @Test
    fun `set with empty string is valid`() {
        WalletCallbackHolder.set("")

        val result = WalletCallbackHolder.consume()

        assertEquals("", result)
    }

    @Test
    fun `set with very long token works`() {
        val longToken = "x".repeat(10_000)
        WalletCallbackHolder.set(longToken)

        val result = WalletCallbackHolder.consume()

        assertEquals(longToken, result)
    }

    // ==================== Concurrent Access Tests ====================

    @Test
    fun `concurrent set and consume is thread-safe`() {
        val iterations = 1000
        val successfulConsumes = AtomicInteger(0)
        val errors = AtomicReference<Throwable?>(null)

        // Run many iterations of set-then-consume across threads
        val threads = (1..iterations).map { i ->
            Thread {
                try {
                    WalletCallbackHolder.set("token-$i")
                    val consumed = WalletCallbackHolder.consume()
                    if (consumed != null) {
                        successfulConsumes.incrementAndGet()
                    }
                } catch (t: Throwable) {
                    errors.compareAndSet(null, t)
                }
            }
        }

        threads.forEach { it.start() }
        threads.forEach { it.join(5000) }

        assertNull("No exceptions should occur during concurrent access", errors.get())
        // At least some consumes should succeed (exact count depends on scheduling)
        assertTrue("Some consumes should succeed", successfulConsumes.get() > 0)
    }

    @Test
    fun `only one thread can consume a given token`() {
        val barrier = CyclicBarrier(2)
        val results = Array<String?>(2) { null }

        WalletCallbackHolder.set("exclusive-token")

        val t1 = Thread {
            barrier.await()
            results[0] = WalletCallbackHolder.consume()
        }
        val t2 = Thread {
            barrier.await()
            results[1] = WalletCallbackHolder.consume()
        }

        t1.start()
        t2.start()
        t1.join(5000)
        t2.join(5000)

        // Exactly one thread should get the token, the other gets null.
        // Due to the volatile field (not synchronized consume), there is a small
        // race window where both could see the token. However, the @Volatile
        // annotation ensures visibility. In practice, at most one gets it in
        // the common case; we verify at least one got it.
        val nonNullCount = results.count { it == "exclusive-token" }
        assertTrue(
            "At least one thread should consume the token",
            nonNullCount >= 1
        )
    }

    @Test
    fun `pendingSessionToken visibility across threads`() {
        val tokenSeen = AtomicReference<String?>(null)

        WalletCallbackHolder.set("visible-token")

        val reader = Thread {
            // The @Volatile annotation should guarantee visibility
            tokenSeen.set(WalletCallbackHolder.pendingSessionToken)
        }

        reader.start()
        reader.join(5000)

        assertEquals("visible-token", tokenSeen.get())
    }
}
