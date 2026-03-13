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
 * - Setting and consuming session tokens with flow tagging
 * - Consume-once semantics (result cleared after consume)
 * - Flow isolation (auth and invite don't cross-contaminate)
 * - Error results
 * - Thread safety / concurrent access
 */
class WalletCallbackHolderTest {

    @Before
    fun setup() {
        // Ensure clean state before each test
        WalletCallbackHolder.consume(WalletCallbackHolder.Flow.AUTH)
        WalletCallbackHolder.consume(WalletCallbackHolder.Flow.INVITE)
    }

    // ==================== Basic Functionality Tests ====================

    @Test
    fun `consume returns null when nothing is set`() {
        assertNull(WalletCallbackHolder.consume(WalletCallbackHolder.Flow.AUTH))
        assertNull(WalletCallbackHolder.consume(WalletCallbackHolder.Flow.INVITE))
    }

    @Test
    fun `set stores success result with flow tag`() {
        WalletCallbackHolder.set("token-abc", WalletCallbackHolder.Flow.AUTH)

        val result = WalletCallbackHolder.consume(WalletCallbackHolder.Flow.AUTH)

        assertTrue(result is WalletCallbackHolder.Result.Success)
        assertEquals("token-abc", (result as WalletCallbackHolder.Result.Success).sessionToken)
        assertEquals(WalletCallbackHolder.Flow.AUTH, result.flow)
    }

    @Test
    fun `consume clears result after retrieval`() {
        WalletCallbackHolder.set("one-time-token", WalletCallbackHolder.Flow.INVITE)

        WalletCallbackHolder.consume(WalletCallbackHolder.Flow.INVITE)
        val second = WalletCallbackHolder.consume(WalletCallbackHolder.Flow.INVITE)

        assertNull(second)
    }

    @Test
    fun `consumeToken returns session token string`() {
        WalletCallbackHolder.set("my-token", WalletCallbackHolder.Flow.AUTH)

        val token = WalletCallbackHolder.consumeToken(WalletCallbackHolder.Flow.AUTH)

        assertEquals("my-token", token)
    }

    // ==================== Flow Isolation Tests ====================

    @Test
    fun `auth flow does not consume invite result`() {
        WalletCallbackHolder.set("invite-token", WalletCallbackHolder.Flow.INVITE)

        val authResult = WalletCallbackHolder.consume(WalletCallbackHolder.Flow.AUTH)

        assertNull(authResult)
        // Invite result should still be pending
        val inviteResult = WalletCallbackHolder.consume(WalletCallbackHolder.Flow.INVITE)
        assertNotNull(inviteResult)
    }

    @Test
    fun `invite flow does not consume auth result`() {
        WalletCallbackHolder.set("auth-token", WalletCallbackHolder.Flow.AUTH)

        val inviteResult = WalletCallbackHolder.consume(WalletCallbackHolder.Flow.INVITE)

        assertNull(inviteResult)
        // Auth result should still be pending
        val authResult = WalletCallbackHolder.consume(WalletCallbackHolder.Flow.AUTH)
        assertNotNull(authResult)
    }

    // ==================== Error Result Tests ====================

    @Test
    fun `setError stores error result`() {
        WalletCallbackHolder.setError("Something went wrong", WalletCallbackHolder.Flow.INVITE)

        val result = WalletCallbackHolder.consume(WalletCallbackHolder.Flow.INVITE)

        assertTrue(result is WalletCallbackHolder.Result.Error)
        assertEquals("Something went wrong", (result as WalletCallbackHolder.Result.Error).message)
    }

    @Test
    fun `consumeToken returns null for error results`() {
        WalletCallbackHolder.setError("error msg", WalletCallbackHolder.Flow.INVITE)

        val token = WalletCallbackHolder.consumeToken(WalletCallbackHolder.Flow.INVITE)

        assertNull(token)
    }

    // ==================== Overwrite Behavior Tests ====================

    @Test
    fun `set overwrites previous result`() {
        WalletCallbackHolder.set("first-token", WalletCallbackHolder.Flow.AUTH)
        WalletCallbackHolder.set("second-token", WalletCallbackHolder.Flow.AUTH)

        val token = WalletCallbackHolder.consumeToken(WalletCallbackHolder.Flow.AUTH)

        assertEquals("second-token", token)
    }

    @Test
    fun `set after consume stores new result`() {
        WalletCallbackHolder.set("token-1", WalletCallbackHolder.Flow.AUTH)
        WalletCallbackHolder.consume(WalletCallbackHolder.Flow.AUTH)

        WalletCallbackHolder.set("token-2", WalletCallbackHolder.Flow.AUTH)

        val token = WalletCallbackHolder.consumeToken(WalletCallbackHolder.Flow.AUTH)
        assertEquals("token-2", token)
    }

    // ==================== Edge Cases ====================

    @Test
    fun `set with empty string is valid`() {
        WalletCallbackHolder.set("", WalletCallbackHolder.Flow.AUTH)

        val token = WalletCallbackHolder.consumeToken(WalletCallbackHolder.Flow.AUTH)

        assertEquals("", token)
    }

    @Test
    fun `set with very long token works`() {
        val longToken = "x".repeat(10_000)
        WalletCallbackHolder.set(longToken, WalletCallbackHolder.Flow.AUTH)

        val token = WalletCallbackHolder.consumeToken(WalletCallbackHolder.Flow.AUTH)

        assertEquals(longToken, token)
    }

    // ==================== Concurrent Access Tests ====================

    @Test
    fun `concurrent set and consume is thread-safe`() {
        val iterations = 1000
        val successfulConsumes = AtomicInteger(0)
        val errors = AtomicReference<Throwable?>(null)

        val threads = (1..iterations).map { i ->
            Thread {
                try {
                    WalletCallbackHolder.set("token-$i", WalletCallbackHolder.Flow.AUTH)
                    val consumed = WalletCallbackHolder.consume(WalletCallbackHolder.Flow.AUTH)
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
        assertTrue("Some consumes should succeed", successfulConsumes.get() > 0)
    }

    @Test
    fun `only one thread can consume a given result`() {
        val barrier = CyclicBarrier(2)
        val results = arrayOfNulls<WalletCallbackHolder.Result>(2)

        WalletCallbackHolder.set("exclusive-token", WalletCallbackHolder.Flow.AUTH)

        val t1 = Thread {
            barrier.await()
            results[0] = WalletCallbackHolder.consume(WalletCallbackHolder.Flow.AUTH)
        }
        val t2 = Thread {
            barrier.await()
            results[1] = WalletCallbackHolder.consume(WalletCallbackHolder.Flow.AUTH)
        }

        t1.start()
        t2.start()
        t1.join(5000)
        t2.join(5000)

        // With AtomicReference.compareAndSet, exactly one thread gets the result
        val nonNullCount = results.count { it != null }
        assertEquals("Exactly one thread should consume the result", 1, nonNullCount)
    }
}
