package my.ssdid.drive.crypto

import java.security.SecureRandom

/**
 * Shamir's Secret Sharing over GF(256).
 * Irreducible polynomial: x^8 + x^4 + x^3 + x + 1 (0x11B, same as AES).
 */
object ShamirSecretSharing {

    // GF(256) multiplication using Russian peasant algorithm
    private fun gfMul(a: Int, b: Int): Int {
        var aa = a
        var bb = b
        var result = 0
        while (bb > 0) {
            if (bb and 1 != 0) result = result xor aa
            aa = aa shl 1
            if (aa and 0x100 != 0) aa = aa xor 0x11B
            bb = bb shr 1
        }
        return result
    }

    // GF(256) multiplicative inverse via Fermat's little theorem: a^254 = a^(-1)
    private fun gfInv(a: Int): Int {
        if (a == 0) throw ArithmeticException("No inverse for 0")
        // a^254 = a^(-1) in GF(256) since a^255 = 1
        var result = a
        repeat(6) { result = gfMul(result, result); result = gfMul(result, a) }
        result = gfMul(result, result) // a^254
        return result
    }

    /**
     * Split a secret byte array into [totalShares] shares with [threshold] required to reconstruct.
     * Returns a list of pairs: (shareIndex: Int, shareData: ByteArray).
     */
    fun split(secret: ByteArray, threshold: Int, totalShares: Int): List<Pair<Int, ByteArray>> {
        require(threshold in 2..totalShares)
        require(totalShares <= 255)

        val rng = SecureRandom()
        val shares = (1..totalShares).map { x -> x to ByteArray(secret.size) }

        for (byteIdx in secret.indices) {
            val coeffs = IntArray(threshold)
            coeffs[0] = secret[byteIdx].toInt() and 0xFF
            for (i in 1 until threshold) {
                coeffs[i] = rng.nextInt(256)
            }

            for ((x, shareData) in shares) {
                var value = 0
                var xPow = 1
                for (c in coeffs) {
                    value = value xor gfMul(c, xPow)
                    xPow = gfMul(xPow, x)
                }
                shareData[byteIdx] = value.toByte()
            }
        }

        return shares
    }

    /**
     * Reconstruct secret from [shares] using Lagrange interpolation over GF(256).
     */
    fun reconstruct(shares: List<Pair<Int, ByteArray>>): ByteArray {
        require(shares.size >= 2)
        require(shares.map { it.first }.toSet().size == shares.size) { "Duplicate share indices" }
        val len = shares[0].second.size
        require(shares.all { it.second.size == len })

        val result = ByteArray(len)

        for (byteIdx in 0 until len) {
            var value = 0
            for (i in shares.indices) {
                val (xi, yi) = shares[i]
                val yiByte = yi[byteIdx].toInt() and 0xFF

                var basis = 1
                for (j in shares.indices) {
                    if (i == j) continue
                    val xj = shares[j].first
                    basis = gfMul(basis, gfMul(xj, gfInv(xj xor xi)))
                }

                value = value xor gfMul(yiByte, basis)
            }
            result[byteIdx] = value.toByte()
        }

        return result
    }
}
