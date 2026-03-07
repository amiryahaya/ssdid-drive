package my.ssdid.drive.crypto.providers

import com.antrapol.kaz.sign.KazSigner
import com.antrapol.kaz.sign.SecurityLevel
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Provider for KAZ-SIGN post-quantum digital signatures.
 * Wraps the native KAZ-SIGN library for message signing and verification.
 *
 * Uses 128-bit security level by default (NIST Level 1).
 */
@Singleton
class KazSignProvider @Inject constructor() : AutoCloseable {

    private val signer = KazSigner(SecurityLevel.LEVEL_128)

    /**
     * Public key size in bytes for the current security level.
     */
    val publicKeySize: Int = SecurityLevel.LEVEL_128.publicKeyBytes

    /**
     * Private key size in bytes for the current security level.
     */
    val privateKeySize: Int = SecurityLevel.LEVEL_128.secretKeyBytes

    /**
     * Signature overhead in bytes for the current security level.
     */
    val signatureOverhead: Int = SecurityLevel.LEVEL_128.signatureOverhead

    /**
     * Algorithm name for the current security level.
     */
    val algorithmName: String = SecurityLevel.LEVEL_128.algorithmName

    /**
     * Generate a KAZ-SIGN key pair.
     * @return Pair of (publicKey, privateKey)
     * @throws KazSignException if key generation fails
     */
    fun generateKeyPair(): Pair<ByteArray, ByteArray> {
        val keyPair = signer.generateKeyPair()
        return Pair(keyPair.publicKey, keyPair.secretKey)
    }

    /**
     * Sign a message.
     * @param message The message to sign
     * @param privateKey The signing private key
     * @return The signature
     * @throws KazSignException if signing fails
     */
    fun sign(message: ByteArray, privateKey: ByteArray): ByteArray {
        require(privateKey.size == privateKeySize) {
            "Invalid private key size: ${privateKey.size}, expected $privateKeySize"
        }

        val result = signer.sign(message, privateKey)
        return result.signature
    }

    /**
     * Verify a signature.
     * @param message The original message (not used - message is embedded in signature)
     * @param signature The signature to verify
     * @param publicKey The signer's public key
     * @return true if the signature is valid
     */
    fun verify(message: ByteArray, signature: ByteArray, publicKey: ByteArray): Boolean {
        require(publicKey.size == publicKeySize) {
            "Invalid public key size: ${publicKey.size}, expected $publicKeySize"
        }

        return try {
            signer.verify(signature, publicKey).isValid
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Verify a signature and extract the message.
     * @param signature The signature to verify (contains embedded message)
     * @param publicKey The signer's public key
     * @return The recovered message if valid, null otherwise
     */
    fun verifyAndExtract(signature: ByteArray, publicKey: ByteArray): ByteArray? {
        require(publicKey.size == publicKeySize) {
            "Invalid public key size: ${publicKey.size}, expected $publicKeySize"
        }

        return try {
            val result = signer.verify(signature, publicKey)
            if (result.isValid) result.message else null
        } catch (e: Exception) {
            null
        }
    }

    override fun close() {
        signer.close()
    }

    companion object {
        /** KAZ-SIGN OID base: 2.16.458.1.1.1.1 */
        const val OID_BASE = "2.16.458.1.1.1.1"

        /** Get OID for specific level */
        fun getOid(level: SecurityLevel): String = when (level) {
            SecurityLevel.LEVEL_128 -> "$OID_BASE.1"
            SecurityLevel.LEVEL_192 -> "$OID_BASE.2"
            SecurityLevel.LEVEL_256 -> "$OID_BASE.3"
        }
    }
}
