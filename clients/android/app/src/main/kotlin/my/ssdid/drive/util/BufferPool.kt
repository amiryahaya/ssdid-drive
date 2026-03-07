package my.ssdid.drive.util

import java.util.concurrent.ConcurrentLinkedQueue
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Buffer pool for reusing byte arrays during file encryption/decryption.
 *
 * Reduces garbage collection pressure by reusing large buffers instead
 * of allocating new ones for each chunk.
 */
@Singleton
class BufferPool @Inject constructor() {

    companion object {
        // Default chunk size for file encryption (4MB)
        const val DEFAULT_BUFFER_SIZE = 4 * 1024 * 1024

        // Maximum number of pooled buffers
        private const val MAX_POOLED_BUFFERS = 4
    }

    private val pool = ConcurrentLinkedQueue<ByteArray>()
    private var pooledCount = 0

    /**
     * Acquire a buffer from the pool or create a new one.
     *
     * @param size Requested buffer size. If smaller than DEFAULT_BUFFER_SIZE,
     *             a pooled buffer may be returned.
     * @return A byte array of at least the requested size
     */
    @Synchronized
    fun acquire(size: Int = DEFAULT_BUFFER_SIZE): ByteArray {
        // Only pool default-sized buffers
        if (size == DEFAULT_BUFFER_SIZE) {
            pool.poll()?.let { return it }
        }
        return ByteArray(size)
    }

    /**
     * Return a buffer to the pool for reuse.
     *
     * @param buffer The buffer to return. Must be DEFAULT_BUFFER_SIZE.
     */
    @Synchronized
    fun release(buffer: ByteArray) {
        // Only pool default-sized buffers
        if (buffer.size == DEFAULT_BUFFER_SIZE && pooledCount < MAX_POOLED_BUFFERS) {
            // Zero the buffer before returning to pool for security
            buffer.fill(0)
            pool.offer(buffer)
            pooledCount++
        }
    }

    /**
     * Clear all pooled buffers (call on low memory).
     */
    @Synchronized
    fun clear() {
        pool.clear()
        pooledCount = 0
    }

    /**
     * Get the current pool size.
     */
    fun size(): Int = pool.size
}

/**
 * Use a pooled buffer and automatically return it when done.
 *
 * @param pool The buffer pool to use
 * @param size Requested buffer size
 * @param block The operation to perform with the buffer
 * @return The result of the block
 */
inline fun <T> withPooledBuffer(
    pool: BufferPool,
    size: Int = BufferPool.DEFAULT_BUFFER_SIZE,
    block: (ByteArray) -> T
): T {
    val buffer = pool.acquire(size)
    return try {
        block(buffer)
    } finally {
        pool.release(buffer)
    }
}
