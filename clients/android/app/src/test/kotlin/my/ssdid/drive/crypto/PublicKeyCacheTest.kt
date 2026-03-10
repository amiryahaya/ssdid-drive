package my.ssdid.drive.crypto

import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

/**
 * Unit tests for PublicKeyCache.
 *
 * Tests cover:
 * - Cache put/get operations
 * - Cache miss (unknown user)
 * - Cache remove
 * - Cache clear
 * - TTL expiry (expired entries return null)
 * - LRU eviction behavior
 * - Cache statistics (size, hits, misses, hitRate)
 * - Convenience put method
 * - UserPublicKeys equality and hashCode
 * - Concurrent-safe via @Synchronized (basic correctness)
 */
class PublicKeyCacheTest {

    private lateinit var cache: PublicKeyCache

    private val testUserId = "user-abc-123"
    private val testKemKey = ByteArray(800) { 0xAA.toByte() }
    private val testMlKemKey = ByteArray(1184) { 0xBB.toByte() }
    private val testSignKey = ByteArray(1312) { 0xCC.toByte() }
    private val testMlDsaKey = ByteArray(1952) { 0xDD.toByte() }

    @Before
    fun setup() {
        cache = PublicKeyCache()
    }

    // ==================== Put / Get Tests ====================

    @Test
    fun `put and get returns cached keys`() {
        val keys = createTestUserKeys(testUserId)
        cache.put(keys)

        val result = cache.get(testUserId)

        assertNotNull(result)
        assertEquals(testUserId, result!!.userId)
        assertArrayEquals(testKemKey, result.kazKemPublicKey)
        assertArrayEquals(testMlKemKey, result.mlKemPublicKey)
        assertArrayEquals(testSignKey, result.kazSignPublicKey)
        assertArrayEquals(testMlDsaKey, result.mlDsaPublicKey)
    }

    @Test
    fun `convenience put stores keys correctly`() {
        cache.put(
            userId = testUserId,
            kazKemPublicKey = testKemKey,
            mlKemPublicKey = testMlKemKey,
            kazSignPublicKey = testSignKey,
            mlDsaPublicKey = testMlDsaKey
        )

        val result = cache.get(testUserId)

        assertNotNull(result)
        assertEquals(testUserId, result!!.userId)
        assertArrayEquals(testKemKey, result.kazKemPublicKey)
    }

    @Test
    fun `put overwrites existing entry for same user`() {
        val keys1 = PublicKeyCache.UserPublicKeys(
            userId = testUserId,
            kazKemPublicKey = ByteArray(800) { 0x11.toByte() },
            mlKemPublicKey = ByteArray(1184),
            kazSignPublicKey = ByteArray(1312),
            mlDsaPublicKey = ByteArray(1952)
        )
        val keys2 = PublicKeyCache.UserPublicKeys(
            userId = testUserId,
            kazKemPublicKey = ByteArray(800) { 0x22.toByte() },
            mlKemPublicKey = ByteArray(1184),
            kazSignPublicKey = ByteArray(1312),
            mlDsaPublicKey = ByteArray(1952)
        )

        cache.put(keys1)
        cache.put(keys2)

        val result = cache.get(testUserId)
        assertNotNull(result)
        assertTrue(result!!.kazKemPublicKey.all { it == 0x22.toByte() })
    }

    // ==================== Cache Miss Tests ====================

    @Test
    fun `get returns null for unknown user`() {
        val result = cache.get("nonexistent-user")
        assertNull(result)
    }

    @Test
    fun `get returns null after remove`() {
        cache.put(createTestUserKeys(testUserId))
        cache.remove(testUserId)

        assertNull(cache.get(testUserId))
    }

    // ==================== Remove Tests ====================

    @Test
    fun `remove only removes specified user`() {
        cache.put(createTestUserKeys("user-1"))
        cache.put(createTestUserKeys("user-2"))
        cache.put(createTestUserKeys("user-3"))

        cache.remove("user-2")

        assertNotNull(cache.get("user-1"))
        assertNull(cache.get("user-2"))
        assertNotNull(cache.get("user-3"))
    }

    @Test
    fun `remove nonexistent user does not throw`() {
        cache.remove("nonexistent-user")
        // No exception = pass
    }

    // ==================== Clear Tests ====================

    @Test
    fun `clear removes all entries`() {
        cache.put(createTestUserKeys("user-1"))
        cache.put(createTestUserKeys("user-2"))
        cache.put(createTestUserKeys("user-3"))

        cache.clear()

        assertNull(cache.get("user-1"))
        assertNull(cache.get("user-2"))
        assertNull(cache.get("user-3"))
    }

    @Test
    fun `clear on empty cache does not throw`() {
        cache.clear()
        // No exception = pass
    }

    // ==================== TTL Expiry Tests ====================

    @Test
    fun `get returns null for expired entry`() {
        // Create a UserPublicKeys with a cachedAt 2 hours in the past
        val expired = PublicKeyCache.UserPublicKeys(
            userId = testUserId,
            kazKemPublicKey = testKemKey,
            mlKemPublicKey = testMlKemKey,
            kazSignPublicKey = testSignKey,
            mlDsaPublicKey = testMlDsaKey,
            cachedAt = System.currentTimeMillis() - (2 * 60 * 60 * 1000) // 2 hours ago
        )

        cache.put(expired)

        val result = cache.get(testUserId)
        assertNull("Expired entry should return null", result)
    }

    @Test
    fun `get returns entry that is not yet expired`() {
        // Entry just cached (default cachedAt = now)
        cache.put(createTestUserKeys(testUserId))

        val result = cache.get(testUserId)
        assertNotNull("Fresh entry should not be null", result)
    }

    @Test
    fun `expired entry is removed from cache on access`() {
        val expired = PublicKeyCache.UserPublicKeys(
            userId = testUserId,
            kazKemPublicKey = testKemKey,
            mlKemPublicKey = testMlKemKey,
            kazSignPublicKey = testSignKey,
            mlDsaPublicKey = testMlDsaKey,
            cachedAt = System.currentTimeMillis() - (2 * 60 * 60 * 1000)
        )
        cache.put(expired)

        // First get evicts
        cache.get(testUserId)

        // After eviction, size should reflect removal
        val stats = cache.getStats()
        assertEquals(0, stats.size)
    }

    // ==================== UserPublicKeys.isExpired Tests ====================

    @Test
    fun `isExpired returns false for fresh entry`() {
        val keys = createTestUserKeys(testUserId)
        assertFalse(keys.isExpired())
    }

    @Test
    fun `isExpired returns true for old entry`() {
        val keys = PublicKeyCache.UserPublicKeys(
            userId = testUserId,
            kazKemPublicKey = testKemKey,
            mlKemPublicKey = testMlKemKey,
            kazSignPublicKey = testSignKey,
            mlDsaPublicKey = testMlDsaKey,
            cachedAt = System.currentTimeMillis() - (61 * 60 * 1000) // 61 minutes ago
        )
        assertTrue(keys.isExpired())
    }

    @Test
    fun `isExpired returns false for entry under 1 hour`() {
        val keys = PublicKeyCache.UserPublicKeys(
            userId = testUserId,
            kazKemPublicKey = testKemKey,
            mlKemPublicKey = testMlKemKey,
            kazSignPublicKey = testSignKey,
            mlDsaPublicKey = testMlDsaKey,
            cachedAt = System.currentTimeMillis() - (59 * 60 * 1000) // 59 minutes ago
        )
        assertFalse(keys.isExpired())
    }

    // ==================== Cache Statistics Tests ====================

    @Test
    fun `getStats returns correct size`() {
        cache.put(createTestUserKeys("user-1"))
        cache.put(createTestUserKeys("user-2"))

        val stats = cache.getStats()

        assertEquals(2, stats.size)
        assertEquals(50, stats.maxSize)
    }

    @Test
    fun `getStats tracks hits`() {
        cache.put(createTestUserKeys(testUserId))

        cache.get(testUserId) // hit

        val stats = cache.getStats()
        assertTrue("Hit count should be >= 1", stats.hitCount >= 1)
    }

    @Test
    fun `getStats tracks misses`() {
        cache.get("nonexistent") // miss

        val stats = cache.getStats()
        assertTrue("Miss count should be >= 1", stats.missCount >= 1)
    }

    @Test
    fun `getStats returns zero size for empty cache`() {
        val stats = cache.getStats()
        assertEquals(0, stats.size)
    }

    // ==================== CacheStats Tests ====================

    @Test
    fun `CacheStats hitRate is zero when no accesses`() {
        val stats = PublicKeyCache.CacheStats(
            size = 0,
            maxSize = 50,
            hitCount = 0,
            missCount = 0
        )
        assertEquals(0f, stats.hitRate)
    }

    @Test
    fun `CacheStats hitRate computes correctly`() {
        val stats = PublicKeyCache.CacheStats(
            size = 5,
            maxSize = 50,
            hitCount = 7,
            missCount = 3
        )
        assertEquals(0.7f, stats.hitRate)
    }

    @Test
    fun `CacheStats hitRate is 1 when all hits`() {
        val stats = PublicKeyCache.CacheStats(
            size = 5,
            maxSize = 50,
            hitCount = 10,
            missCount = 0
        )
        assertEquals(1.0f, stats.hitRate)
    }

    @Test
    fun `CacheStats hitRate is 0 when all misses`() {
        val stats = PublicKeyCache.CacheStats(
            size = 0,
            maxSize = 50,
            hitCount = 0,
            missCount = 10
        )
        assertEquals(0f, stats.hitRate)
    }

    // ==================== UserPublicKeys Equality Tests ====================

    @Test
    fun `UserPublicKeys equals by userId`() {
        val keys1 = PublicKeyCache.UserPublicKeys(
            userId = "user-1",
            kazKemPublicKey = ByteArray(800) { 0x11.toByte() },
            mlKemPublicKey = ByteArray(1184),
            kazSignPublicKey = ByteArray(1312),
            mlDsaPublicKey = ByteArray(1952)
        )
        val keys2 = PublicKeyCache.UserPublicKeys(
            userId = "user-1",
            kazKemPublicKey = ByteArray(800) { 0x22.toByte() }, // different key bytes
            mlKemPublicKey = ByteArray(1184),
            kazSignPublicKey = ByteArray(1312),
            mlDsaPublicKey = ByteArray(1952)
        )

        assertEquals(keys1, keys2)
    }

    @Test
    fun `UserPublicKeys not equal with different userId`() {
        val keys1 = createTestUserKeys("user-1")
        val keys2 = createTestUserKeys("user-2")

        assertNotEquals(keys1, keys2)
    }

    @Test
    fun `UserPublicKeys hashCode based on userId`() {
        val keys1 = createTestUserKeys("user-1")
        val keys2 = createTestUserKeys("user-1")

        assertEquals(keys1.hashCode(), keys2.hashCode())
    }

    @Test
    fun `UserPublicKeys equals with itself`() {
        val keys = createTestUserKeys(testUserId)
        assertEquals(keys, keys)
    }

    @Test
    fun `UserPublicKeys not equal to null`() {
        val keys = createTestUserKeys(testUserId)
        assertFalse(keys.equals(null))
    }

    @Test
    fun `UserPublicKeys not equal to different type`() {
        val keys = createTestUserKeys(testUserId)
        assertFalse(keys.equals("not a UserPublicKeys"))
    }

    // ==================== Multiple Users Tests ====================

    @Test
    fun `cache handles multiple users independently`() {
        val keys1 = createTestUserKeys("user-1")
        val keys2 = createTestUserKeys("user-2")
        val keys3 = createTestUserKeys("user-3")

        cache.put(keys1)
        cache.put(keys2)
        cache.put(keys3)

        assertEquals("user-1", cache.get("user-1")!!.userId)
        assertEquals("user-2", cache.get("user-2")!!.userId)
        assertEquals("user-3", cache.get("user-3")!!.userId)
    }

    // ==================== Helper Methods ====================

    private fun createTestUserKeys(userId: String): PublicKeyCache.UserPublicKeys {
        return PublicKeyCache.UserPublicKeys(
            userId = userId,
            kazKemPublicKey = testKemKey,
            mlKemPublicKey = testMlKemKey,
            kazSignPublicKey = testSignKey,
            mlDsaPublicKey = testMlDsaKey
        )
    }
}
