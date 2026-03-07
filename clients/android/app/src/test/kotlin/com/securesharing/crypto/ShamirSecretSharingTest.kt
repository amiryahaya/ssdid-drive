package com.securesharing.crypto

import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import java.security.SecureRandom

/**
 * Unit tests for ShamirSecretSharing.
 *
 * Tests cover:
 * - Split and reconstruct with various k,n combinations
 * - Reconstruction with exactly k shares (minimum)
 * - Failure with k-1 shares (insufficient)
 * - Duplicate share indices detection
 * - Edge cases and invalid inputs
 */
class ShamirSecretSharingTest {

    private lateinit var shamir: ShamirSecretSharing
    private val secureRandom = SecureRandom()

    @Before
    fun setup() {
        shamir = ShamirSecretSharing()
    }

    // ==================== Basic Split/Reconstruct Tests ====================

    @Test
    fun `split and reconstruct with 2-of-3 scheme`() {
        val secret = generateRandomSecret(32)
        val shares = shamir.split(secret, k = 2, n = 3)

        assertEquals(3, shares.size)

        // Reconstruct with any 2 shares
        val reconstructed = shamir.reconstruct(listOf(shares[0], shares[1]))
        assertArrayEquals(secret, reconstructed)
    }

    @Test
    fun `split and reconstruct with 3-of-5 scheme`() {
        val secret = generateRandomSecret(32)
        val shares = shamir.split(secret, k = 3, n = 5)

        assertEquals(5, shares.size)

        // Reconstruct with shares 1, 3, 5 (indices 0, 2, 4)
        val reconstructed = shamir.reconstruct(listOf(shares[0], shares[2], shares[4]))
        assertArrayEquals(secret, reconstructed)
    }

    @Test
    fun `split and reconstruct with 5-of-10 scheme`() {
        val secret = generateRandomSecret(32)
        val shares = shamir.split(secret, k = 5, n = 10)

        assertEquals(10, shares.size)

        // Use first 5 shares
        val reconstructed = shamir.reconstruct(shares.take(5))
        assertArrayEquals(secret, reconstructed)
    }

    @Test
    fun `split and reconstruct with maximum shares (255)`() {
        val secret = generateRandomSecret(16)
        val shares = shamir.split(secret, k = 3, n = 255)

        assertEquals(255, shares.size)

        // Use 3 random shares
        val selectedShares = listOf(shares[0], shares[127], shares[254])
        val reconstructed = shamir.reconstruct(selectedShares)
        assertArrayEquals(secret, reconstructed)
    }

    // ==================== Minimum Shares Tests ====================

    @Test
    fun `reconstruct with exactly k shares works`() {
        val secret = generateRandomSecret(32)
        val shares = shamir.split(secret, k = 3, n = 5)

        // Use exactly 3 shares (the threshold)
        val reconstructed = shamir.reconstruct(shares.take(3))
        assertArrayEquals(secret, reconstructed)
    }

    @Test
    fun `reconstruct with more than k shares works`() {
        val secret = generateRandomSecret(32)
        val shares = shamir.split(secret, k = 2, n = 5)

        // Use all 5 shares
        val reconstructed = shamir.reconstruct(shares)
        assertArrayEquals(secret, reconstructed)
    }

    // ==================== Insufficient Shares Tests ====================

    @Test
    fun `reconstruct with k-1 shares produces wrong result`() {
        val secret = generateRandomSecret(32)
        val shares = shamir.split(secret, k = 3, n = 5)

        // Use only 2 shares (k-1) - should NOT reconstruct correctly
        val wrongReconstruction = shamir.reconstruct(shares.take(2))

        // The result should be different from the original secret
        // (with overwhelming probability for a 32-byte secret)
        assertFalse(secret.contentEquals(wrongReconstruction))
    }

    @Test
    fun `single share reveals nothing about secret`() {
        val secret = generateRandomSecret(32)
        val shares = shamir.split(secret, k = 2, n = 3)

        // A single share's data should not equal the secret
        assertFalse(secret.contentEquals(shares[0].data))
        assertFalse(secret.contentEquals(shares[1].data))
        assertFalse(secret.contentEquals(shares[2].data))
    }

    // ==================== Different Share Combinations Tests ====================

    @Test
    fun `all share combinations of size k reconstruct correctly`() {
        val secret = generateRandomSecret(16)
        val shares = shamir.split(secret, k = 2, n = 4)

        // All possible pairs should reconstruct the secret
        val combinations = listOf(
            listOf(shares[0], shares[1]),
            listOf(shares[0], shares[2]),
            listOf(shares[0], shares[3]),
            listOf(shares[1], shares[2]),
            listOf(shares[1], shares[3]),
            listOf(shares[2], shares[3])
        )

        for (combination in combinations) {
            val reconstructed = shamir.reconstruct(combination)
            assertArrayEquals("Failed for combination: ${combination.map { it.index }}", secret, reconstructed)
        }
    }

    @Test
    fun `non-consecutive share indices work`() {
        val secret = generateRandomSecret(32)
        val shares = shamir.split(secret, k = 3, n = 10)

        // Use non-consecutive shares: 2, 5, 9
        val selectedShares = listOf(shares[1], shares[4], shares[8])
        val reconstructed = shamir.reconstruct(selectedShares)
        assertArrayEquals(secret, reconstructed)
    }

    // ==================== Duplicate Index Tests ====================

    @Test(expected = IllegalArgumentException::class)
    fun `reconstruct with duplicate indices throws exception`() {
        val secret = generateRandomSecret(32)
        val shares = shamir.split(secret, k = 2, n = 3)

        // Create duplicate by using same share twice
        val duplicateShares = listOf(shares[0], shares[0])
        shamir.reconstruct(duplicateShares)
    }

    @Test
    fun `verifyShares detects duplicate indices`() {
        val share1 = ShamirSecretSharing.Share(1, ByteArray(32))
        val share2 = ShamirSecretSharing.Share(1, ByteArray(32)) // Same index

        assertFalse(shamir.verifyShares(listOf(share1, share2), threshold = 2))
    }

    // ==================== Edge Cases Tests ====================

    @Test
    fun `handles single byte secret`() {
        val secret = byteArrayOf(42)
        val shares = shamir.split(secret, k = 2, n = 3)

        val reconstructed = shamir.reconstruct(shares.take(2))
        assertArrayEquals(secret, reconstructed)
    }

    @Test
    fun `handles large secret (1KB)`() {
        val secret = generateRandomSecret(1024)
        val shares = shamir.split(secret, k = 3, n = 5)

        val reconstructed = shamir.reconstruct(shares.take(3))
        assertArrayEquals(secret, reconstructed)
    }

    @Test
    fun `handles all zero secret`() {
        val secret = ByteArray(32) { 0 }
        val shares = shamir.split(secret, k = 2, n = 3)

        val reconstructed = shamir.reconstruct(shares.take(2))
        assertArrayEquals(secret, reconstructed)
    }

    @Test
    fun `handles all 0xFF secret`() {
        val secret = ByteArray(32) { 0xFF.toByte() }
        val shares = shamir.split(secret, k = 2, n = 3)

        val reconstructed = shamir.reconstruct(shares.take(2))
        assertArrayEquals(secret, reconstructed)
    }

    @Test
    fun `shares have same length as secret`() {
        val secret = generateRandomSecret(64)
        val shares = shamir.split(secret, k = 3, n = 5)

        for (share in shares) {
            assertEquals(secret.size, share.data.size)
        }
    }

    @Test
    fun `share indices are 1-indexed`() {
        val secret = generateRandomSecret(32)
        val shares = shamir.split(secret, k = 2, n = 5)

        val indices = shares.map { it.index }
        assertEquals(listOf(1, 2, 3, 4, 5), indices)
    }

    // ==================== Invalid Input Tests ====================

    @Test(expected = IllegalArgumentException::class)
    fun `split throws for k less than 2`() {
        shamir.split(ByteArray(32), k = 1, n = 3)
    }

    @Test(expected = IllegalArgumentException::class)
    fun `split throws for n less than k`() {
        shamir.split(ByteArray(32), k = 5, n = 3)
    }

    @Test(expected = IllegalArgumentException::class)
    fun `split throws for n greater than 255`() {
        shamir.split(ByteArray(32), k = 2, n = 256)
    }

    @Test(expected = IllegalArgumentException::class)
    fun `split throws for empty secret`() {
        shamir.split(ByteArray(0), k = 2, n = 3)
    }

    @Test(expected = IllegalArgumentException::class)
    fun `reconstruct throws for empty shares list`() {
        shamir.reconstruct(emptyList())
    }

    @Test(expected = IllegalArgumentException::class)
    fun `reconstruct throws for single share`() {
        val share = ShamirSecretSharing.Share(1, ByteArray(32))
        shamir.reconstruct(listOf(share))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `reconstruct throws for mismatched share lengths`() {
        val share1 = ShamirSecretSharing.Share(1, ByteArray(32))
        val share2 = ShamirSecretSharing.Share(2, ByteArray(16))
        shamir.reconstruct(listOf(share1, share2))
    }

    // ==================== Verify Shares Tests ====================

    @Test
    fun `verifyShares returns true for valid shares`() {
        val secret = generateRandomSecret(32)
        val shares = shamir.split(secret, k = 3, n = 5)

        assertTrue(shamir.verifyShares(shares, threshold = 3))
        assertTrue(shamir.verifyShares(shares.take(3), threshold = 3))
    }

    @Test
    fun `verifyShares returns false for insufficient shares`() {
        val secret = generateRandomSecret(32)
        val shares = shamir.split(secret, k = 3, n = 5)

        assertFalse(shamir.verifyShares(shares.take(2), threshold = 3))
    }

    @Test
    fun `verifyShares returns false for invalid indices`() {
        val invalidShare = ShamirSecretSharing.Share(0, ByteArray(32)) // Index 0 is invalid
        val validShare = ShamirSecretSharing.Share(1, ByteArray(32))

        assertFalse(shamir.verifyShares(listOf(invalidShare, validShare), threshold = 2))
    }

    @Test
    fun `verifyShares returns false for index greater than 255`() {
        val invalidShare = ShamirSecretSharing.Share(256, ByteArray(32))
        val validShare = ShamirSecretSharing.Share(1, ByteArray(32))

        assertFalse(shamir.verifyShares(listOf(invalidShare, validShare), threshold = 2))
    }

    // ==================== Determinism Tests ====================

    @Test
    fun `same secret produces different shares each time`() {
        val secret = generateRandomSecret(32)
        val shares1 = shamir.split(secret, k = 2, n = 3)
        val shares2 = shamir.split(secret, k = 2, n = 3)

        // Shares should be different (random coefficients)
        assertFalse(shares1[0].data.contentEquals(shares2[0].data))
    }

    // ==================== Share Equality Tests ====================

    @Test
    fun `share equals works correctly`() {
        val data = ByteArray(32) { it.toByte() }
        val share1 = ShamirSecretSharing.Share(1, data.copyOf())
        val share2 = ShamirSecretSharing.Share(1, data.copyOf())
        val share3 = ShamirSecretSharing.Share(2, data.copyOf())

        assertEquals(share1, share2)
        assertNotEquals(share1, share3)
    }

    @Test
    fun `share hashCode is consistent`() {
        val data = ByteArray(32) { it.toByte() }
        val share1 = ShamirSecretSharing.Share(1, data.copyOf())
        val share2 = ShamirSecretSharing.Share(1, data.copyOf())

        assertEquals(share1.hashCode(), share2.hashCode())
    }

    // ==================== Helper Functions ====================

    private fun generateRandomSecret(size: Int): ByteArray {
        val bytes = ByteArray(size)
        secureRandom.nextBytes(bytes)
        return bytes
    }
}
