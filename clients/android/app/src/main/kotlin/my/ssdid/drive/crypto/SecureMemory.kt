package my.ssdid.drive.crypto

import java.security.SecureRandom
import java.util.Arrays

/**
 * Utility object for secure memory operations.
 *
 * SECURITY: Provides secure zeroization of sensitive data in memory.
 *
 * Note: In JVM environments, secure zeroization has limitations because:
 * 1. The garbage collector may have already copied the data elsewhere
 * 2. JIT optimization might remove "dead" writes
 *
 * We mitigate these risks by:
 * 1. Using multiple overwrite passes with different patterns
 * 2. Using Arrays.fill() which is less likely to be optimized away
 * 3. Adding a memory barrier via volatile read
 * 4. Overwriting with random data before zeroing
 */
object SecureMemory {

    @Volatile
    private var memoryBarrier: Byte = 0

    private val secureRandom = SecureRandom()

    /**
     * Securely zero out a byte array.
     *
     * Uses a three-pass overwrite:
     * 1. Overwrite with 0xFF
     * 2. Overwrite with random bytes
     * 3. Overwrite with 0x00
     *
     * @param data The byte array to zeroize
     */
    fun zeroize(data: ByteArray?) {
        if (data == null || data.isEmpty()) return

        try {
            // Pass 1: Overwrite with 0xFF
            Arrays.fill(data, 0xFF.toByte())
            forceMemoryBarrier()

            // Pass 2: Overwrite with random data
            secureRandom.nextBytes(data)
            forceMemoryBarrier()

            // Pass 3: Overwrite with zeros
            Arrays.fill(data, 0.toByte())
            forceMemoryBarrier()
        } catch (e: Exception) {
            // Fallback: simple zero fill if anything fails
            Arrays.fill(data, 0.toByte())
        }
    }

    /**
     * Securely zero out a char array.
     *
     * @param data The char array to zeroize
     */
    fun zeroize(data: CharArray?) {
        if (data == null || data.isEmpty()) return

        try {
            // Pass 1: Overwrite with 0xFFFF
            Arrays.fill(data, '\uFFFF')
            forceMemoryBarrier()

            // Pass 2: Overwrite with random chars
            for (i in data.indices) {
                data[i] = secureRandom.nextInt(Char.MAX_VALUE.code).toChar()
            }
            forceMemoryBarrier()

            // Pass 3: Overwrite with zeros
            Arrays.fill(data, '\u0000')
            forceMemoryBarrier()
        } catch (e: Exception) {
            Arrays.fill(data, '\u0000')
        }
    }

    /**
     * Force a memory barrier to prevent compiler/JIT optimization
     * from removing our overwrite operations.
     */
    private fun forceMemoryBarrier() {
        // Reading a volatile variable creates a memory barrier
        @Suppress("UNUSED_VARIABLE")
        val barrier = memoryBarrier
        // Writing also creates a barrier
        memoryBarrier = 0
    }

    /**
     * Execute a block with automatic zeroization of the provided byte array.
     *
     * @param data The byte array to zeroize after the block completes
     * @param block The code block to execute
     * @return The result of the block
     */
    inline fun <T> withZeroization(data: ByteArray, block: () -> T): T {
        return try {
            block()
        } finally {
            zeroize(data)
        }
    }

    /**
     * Execute a block with automatic zeroization of multiple byte arrays.
     *
     * @param dataArrays The byte arrays to zeroize after the block completes
     * @param block The code block to execute
     * @return The result of the block
     */
    inline fun <T> withZeroization(vararg dataArrays: ByteArray?, block: () -> T): T {
        return try {
            block()
        } finally {
            dataArrays.forEach { zeroize(it) }
        }
    }

    /**
     * Create a copy of a byte array that will be zeroized when closed.
     * Use with Kotlin's use() function.
     *
     * @param source The source byte array to copy
     * @return A ZeroizableByteArray wrapper
     */
    fun copyOf(source: ByteArray): ZeroizableByteArray {
        return ZeroizableByteArray(source.copyOf())
    }

    /**
     * Wrapper for a byte array that implements AutoCloseable for automatic zeroization.
     */
    class ZeroizableByteArray(val data: ByteArray) : AutoCloseable {
        override fun close() {
            zeroize(data)
        }

        val size: Int get() = data.size

        operator fun get(index: Int): Byte = data[index]

        operator fun set(index: Int, value: Byte) {
            data[index] = value
        }
    }
}
