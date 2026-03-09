package my.ssdid.drive.crypto

import androidx.collection.LruCache
import javax.inject.Inject
import javax.inject.Singleton

/**
 * LRU cache for user public keys to avoid repeated API calls.
 *
 * Caches KAZ-KEM and ML-KEM public keys for users that the current
 * user has shared files with or received shares from.
 */
@Singleton
class PublicKeyCache @Inject constructor() {

    companion object {
        // Maximum number of user key bundles to cache
        private const val MAX_CACHED_USERS = 50
    }

    /**
     * Cached public key bundle for a user.
     */
    data class UserPublicKeys(
        val userId: String,
        val kazKemPublicKey: ByteArray,
        val mlKemPublicKey: ByteArray,
        val kazSignPublicKey: ByteArray,
        val mlDsaPublicKey: ByteArray,
        val cachedAt: Long = System.currentTimeMillis()
    ) {
        // 1 hour cache validity
        fun isExpired(): Boolean =
            System.currentTimeMillis() - cachedAt > 60 * 60 * 1000

        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (javaClass != other?.javaClass) return false
            other as UserPublicKeys
            return userId == other.userId
        }

        override fun hashCode(): Int = userId.hashCode()
    }

    private val cache = object : LruCache<String, UserPublicKeys>(MAX_CACHED_USERS) {
        override fun sizeOf(key: String, value: UserPublicKeys): Int = 1
    }

    /**
     * Get cached public keys for a user.
     * Returns null if not cached or expired.
     */
    @Synchronized
    fun get(userId: String): UserPublicKeys? {
        val cached = cache.get(userId) ?: return null
        if (cached.isExpired()) {
            cache.remove(userId)
            return null
        }
        return cached
    }

    /**
     * Cache public keys for a user.
     */
    @Synchronized
    fun put(keys: UserPublicKeys) {
        cache.put(keys.userId, keys)
    }

    /**
     * Cache public keys for a user (convenience method).
     */
    @Synchronized
    fun put(
        userId: String,
        kazKemPublicKey: ByteArray,
        mlKemPublicKey: ByteArray,
        kazSignPublicKey: ByteArray,
        mlDsaPublicKey: ByteArray
    ) {
        cache.put(userId, UserPublicKeys(
            userId = userId,
            kazKemPublicKey = kazKemPublicKey,
            mlKemPublicKey = mlKemPublicKey,
            kazSignPublicKey = kazSignPublicKey,
            mlDsaPublicKey = mlDsaPublicKey
        ))
    }

    /**
     * Remove cached keys for a user.
     */
    @Synchronized
    fun remove(userId: String) {
        cache.remove(userId)
    }

    /**
     * Clear all cached keys.
     */
    @Synchronized
    fun clear() {
        cache.evictAll()
    }

    /**
     * Get cache statistics.
     */
    fun getStats(): CacheStats {
        return CacheStats(
            size = cache.size(),
            maxSize = cache.maxSize(),
            hitCount = cache.hitCount(),
            missCount = cache.missCount()
        )
    }

    data class CacheStats(
        val size: Int,
        val maxSize: Int,
        val hitCount: Int,
        val missCount: Int
    ) {
        val hitRate: Float get() = if (hitCount + missCount > 0) {
            hitCount.toFloat() / (hitCount + missCount)
        } else 0f
    }
}
