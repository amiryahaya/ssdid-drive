package com.securesharing.crypto

import java.security.SecureRandom
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Shamir's Secret Sharing implementation for key recovery.
 *
 * This implements a (k, n) threshold scheme where:
 * - n shares are created from a secret
 * - Any k or more shares can reconstruct the secret
 * - Fewer than k shares reveal nothing about the secret
 *
 * Uses GF(256) (Galois Field with 256 elements) for byte-level operations.
 * Each byte of the secret is treated independently.
 *
 * Security properties:
 * - Information-theoretically secure (not just computationally)
 * - Each share is as long as the secret
 * - Random coefficients provide perfect secrecy
 */
@Singleton
class ShamirSecretSharing @Inject constructor() {

    private val secureRandom = SecureRandom()

    /**
     * A single share of a secret.
     *
     * @param index The x-coordinate (1-indexed, never 0)
     * @param data The share data (same length as secret)
     */
    data class Share(
        val index: Int,
        val data: ByteArray
    ) {
        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (javaClass != other?.javaClass) return false
            other as Share
            return index == other.index && data.contentEquals(other.data)
        }

        override fun hashCode(): Int {
            var result = index
            result = 31 * result + data.contentHashCode()
            return result
        }
    }

    /**
     * Split a secret into n shares with threshold k.
     *
     * @param secret The secret to split (e.g., master key)
     * @param k Minimum shares required to reconstruct (threshold)
     * @param n Total number of shares to create
     * @return List of n shares (1-indexed)
     * @throws IllegalArgumentException if parameters are invalid
     */
    fun split(secret: ByteArray, k: Int, n: Int): List<Share> {
        require(k >= 2) { "Threshold must be at least 2" }
        require(n >= k) { "Total shares must be at least threshold" }
        require(n <= 255) { "Cannot create more than 255 shares" }
        require(secret.isNotEmpty()) { "Secret cannot be empty" }

        val shares = ArrayList<Share>(n)

        // Initialize share data arrays
        for (i in 1..n) {
            shares.add(Share(i, ByteArray(secret.size)))
        }

        // Process each byte of the secret independently
        for (byteIndex in secret.indices) {
            // Generate random coefficients for polynomial
            // a[0] = secret byte, a[1..k-1] = random
            val coefficients = ByteArray(k)
            coefficients[0] = secret[byteIndex]
            for (i in 1 until k) {
                coefficients[i] = (secureRandom.nextInt(256) and 0xFF).toByte()
            }

            // Evaluate polynomial at each x (1 to n)
            for (shareIndex in 0 until n) {
                val x = (shareIndex + 1).toByte()
                shares[shareIndex].data[byteIndex] = evaluatePolynomial(coefficients, x)
            }
        }

        return shares
    }

    /**
     * Reconstruct a secret from k or more shares.
     *
     * @param shares The shares to use for reconstruction (at least k)
     * @return The reconstructed secret
     * @throws IllegalArgumentException if shares are invalid
     */
    fun reconstruct(shares: List<Share>): ByteArray {
        require(shares.isNotEmpty()) { "Need at least one share" }
        require(shares.size >= 2) { "Need at least 2 shares to reconstruct" }

        val secretLength = shares[0].data.size
        require(shares.all { it.data.size == secretLength }) { "All shares must have same length" }

        // Check for duplicate indices
        val indices = shares.map { it.index }.toSet()
        require(indices.size == shares.size) { "Share indices must be unique" }

        val secret = ByteArray(secretLength)

        // Reconstruct each byte using Lagrange interpolation
        for (byteIndex in 0 until secretLength) {
            secret[byteIndex] = lagrangeInterpolate(shares, byteIndex)
        }

        return secret
    }

    /**
     * Evaluate a polynomial at point x using Horner's method in GF(256).
     *
     * @param coefficients Polynomial coefficients [a0, a1, ..., ak-1]
     * @param x The point to evaluate at
     * @return The polynomial value at x
     */
    private fun evaluatePolynomial(coefficients: ByteArray, x: Byte): Byte {
        if (x.toInt() == 0) {
            return coefficients[0]
        }

        // Horner's method: result = a[k-1]
        // for i = k-2 down to 0: result = result * x + a[i]
        var result = 0
        for (i in coefficients.size - 1 downTo 0) {
            result = gfAdd(gfMul(result, x.toInt() and 0xFF), coefficients[i].toInt() and 0xFF)
        }
        return result.toByte()
    }

    /**
     * Lagrange interpolation at x=0 in GF(256).
     *
     * This reconstructs the secret (which is the polynomial value at x=0).
     *
     * @param shares The shares to interpolate
     * @param byteIndex Which byte to interpolate
     * @return The interpolated value at x=0
     */
    private fun lagrangeInterpolate(shares: List<Share>, byteIndex: Int): Byte {
        var result = 0

        for (i in shares.indices) {
            val xi = shares[i].index
            val yi = shares[i].data[byteIndex].toInt() and 0xFF

            // Calculate Lagrange basis polynomial Li(0)
            var numerator = 1
            var denominator = 1

            for (j in shares.indices) {
                if (i != j) {
                    val xj = shares[j].index
                    // Li(0) = product of (0 - xj) / (xi - xj) for all j != i
                    //       = product of (-xj) / (xi - xj)
                    //       = product of xj / (xi - xj) in GF(256) since -x = x
                    numerator = gfMul(numerator, xj)
                    denominator = gfMul(denominator, gfAdd(xi, xj))
                }
            }

            // Li(0) * yi
            val term = gfMul(gfMul(yi, numerator), gfInverse(denominator))
            result = gfAdd(result, term)
        }

        return result.toByte()
    }

    // ==================== GF(256) Arithmetic ====================
    // Using AES polynomial: x^8 + x^4 + x^3 + x + 1 (0x11B)

    /**
     * Addition in GF(256) is XOR.
     */
    private fun gfAdd(a: Int, b: Int): Int = a xor b

    /**
     * Multiplication in GF(256).
     */
    private fun gfMul(a: Int, b: Int): Int {
        var result = 0
        var aa = a
        var bb = b

        while (bb != 0) {
            if ((bb and 1) != 0) {
                result = result xor aa
            }
            val highBit = aa and 0x80
            aa = aa shl 1
            if (highBit != 0) {
                aa = aa xor 0x1B // Reduce by AES polynomial
            }
            aa = aa and 0xFF
            bb = bb shr 1
        }

        return result
    }

    /**
     * Multiplicative inverse in GF(256) using extended Euclidean algorithm.
     */
    private fun gfInverse(a: Int): Int {
        if (a == 0) {
            throw ArithmeticException("Cannot invert zero in GF(256)")
        }

        // Use the property a^254 = a^(-1) in GF(256)
        // Since the multiplicative group has order 255
        var result = a
        for (i in 0 until 6) {
            result = gfMul(result, result)
            result = gfMul(result, a)
        }
        result = gfMul(result, result)
        return result
    }

    /**
     * Verify that shares are valid and can reconstruct.
     *
     * @param shares List of shares to verify
     * @param threshold Minimum shares required
     * @return true if shares are valid
     */
    fun verifyShares(shares: List<Share>, threshold: Int): Boolean {
        if (shares.size < threshold) return false
        if (shares.isEmpty()) return false

        val secretLength = shares[0].data.size
        if (shares.any { it.data.size != secretLength }) return false

        val indices = shares.map { it.index }.toSet()
        if (indices.size != shares.size) return false // Duplicates

        if (indices.any { it <= 0 || it > 255 }) return false // Invalid indices

        return true
    }
}
