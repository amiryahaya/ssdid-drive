package my.ssdid.drive.crypto.providers

import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.math.ceil

/**
 * Provider for HKDF (HMAC-based Key Derivation Function) using SHA-384.
 * RFC 5869 implementation.
 */
@Singleton
class HkdfProvider @Inject constructor() {

    companion object {
        private const val ALGORITHM = "HmacSHA384"
        private const val HASH_LENGTH = 48 // SHA-384 output in bytes
        private const val DEFAULT_OUTPUT_LENGTH = 32 // 256-bit key
    }

    /**
     * Derive a key using HKDF-SHA384.
     *
     * @param ikm Input keying material (e.g., password bytes)
     * @param salt Optional salt (recommended to be random)
     * @param info Optional context and application specific information
     * @param length Desired output length (default 32 bytes)
     * @return Derived key material
     */
    fun deriveKey(
        ikm: ByteArray,
        salt: ByteArray,
        info: ByteArray = ByteArray(0),
        length: Int = DEFAULT_OUTPUT_LENGTH
    ): ByteArray {
        // Step 1: Extract
        val prk = extract(salt, ikm)

        // Step 2: Expand
        return expand(prk, info, length)
    }

    /**
     * HKDF Extract step.
     * PRK = HMAC-Hash(salt, IKM)
     */
    private fun extract(salt: ByteArray, ikm: ByteArray): ByteArray {
        val actualSalt = if (salt.isEmpty()) {
            ByteArray(HASH_LENGTH) // Use zero-filled salt if not provided
        } else {
            salt
        }

        val mac = Mac.getInstance(ALGORITHM)
        mac.init(SecretKeySpec(actualSalt, ALGORITHM))
        return mac.doFinal(ikm)
    }

    /**
     * HKDF Expand step.
     * OKM = T(1) || T(2) || ... || T(N)
     * T(i) = HMAC-Hash(PRK, T(i-1) || info || i)
     */
    private fun expand(prk: ByteArray, info: ByteArray, length: Int): ByteArray {
        require(length <= 255 * HASH_LENGTH) { "Output length too large" }

        val n = ceil(length.toDouble() / HASH_LENGTH).toInt()
        val mac = Mac.getInstance(ALGORITHM)
        mac.init(SecretKeySpec(prk, ALGORITHM))

        val okm = ByteArray(n * HASH_LENGTH)
        var previousT = ByteArray(0)

        for (i in 1..n) {
            mac.reset()
            mac.update(previousT)
            mac.update(info)
            mac.update(i.toByte())
            previousT = mac.doFinal()
            System.arraycopy(previousT, 0, okm, (i - 1) * HASH_LENGTH, HASH_LENGTH)
        }

        return okm.copyOfRange(0, length)
    }

    /**
     * Convenience function for password-based key derivation with domain separation.
     */
    fun derivePasswordKey(
        password: ByteArray,
        salt: ByteArray,
        purpose: String = "master-key"
    ): ByteArray {
        return deriveKey(
            ikm = password,
            salt = salt,
            info = "SsdidDrive:$purpose".toByteArray()
        )
    }
}
