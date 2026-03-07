package my.ssdid.drive.crypto.providers

import com.antrapol.kaz.kem.KazKem
import com.antrapol.kaz.kem.SecurityLevel
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Provider for KAZ-KEM post-quantum key encapsulation.
 * Wraps the native KAZ-KEM library for secure key exchange.
 *
 * Uses 128-bit security level by default (NIST Level 1).
 */
@Singleton
class KazKemProvider @Inject constructor() : AutoCloseable {

    private val kem: KazKem

    init {
        kem = KazKem.initialize(SecurityLevel.LEVEL_128)
    }

    /**
     * Public key size in bytes for the current security level.
     */
    val publicKeySize: Int
        get() = kem.publicKeySize

    /**
     * Private key size in bytes for the current security level.
     */
    val privateKeySize: Int
        get() = kem.privateKeySize

    /**
     * Ciphertext size in bytes for the current security level.
     */
    val ciphertextSize: Int
        get() = kem.ciphertextSize

    /**
     * Shared secret size in bytes for the current security level.
     */
    val sharedSecretSize: Int
        get() = kem.sharedSecretSize

    /**
     * Current security level.
     */
    val securityLevel: SecurityLevel
        get() = kem.securityLevel

    /**
     * Generate a KAZ-KEM key pair.
     * @return Pair of (publicKey, privateKey)
     * @throws KazKemException if key generation fails
     */
    fun generateKeyPair(): Pair<ByteArray, ByteArray> {
        val keyPair = kem.generateKeyPair()
        return Pair(keyPair.publicKey, keyPair.privateKey)
    }

    /**
     * Encapsulate a shared secret for a recipient's public key.
     * @param publicKey Recipient's public key
     * @return Pair of (sharedSecret, ciphertext)
     * @throws KazKemException if encapsulation fails
     */
    fun encapsulate(publicKey: ByteArray): Pair<ByteArray, ByteArray> {
        require(publicKey.size == publicKeySize) {
            "Invalid public key size: ${publicKey.size}, expected $publicKeySize"
        }

        val result = kem.encapsulate(publicKey)
        return Pair(result.sharedSecret, result.ciphertext)
    }

    /**
     * Decapsulate a shared secret using our private key.
     * @param ciphertext The KEM ciphertext
     * @param privateKey Our private key
     * @return The shared secret
     * @throws KazKemException if decapsulation fails
     */
    fun decapsulate(ciphertext: ByteArray, privateKey: ByteArray): ByteArray {
        require(ciphertext.size == ciphertextSize) {
            "Invalid ciphertext size: ${ciphertext.size}, expected $ciphertextSize"
        }
        require(privateKey.size == privateKeySize) {
            "Invalid private key size: ${privateKey.size}, expected $privateKeySize"
        }

        return kem.decapsulate(ciphertext, privateKey)
    }

    override fun close() {
        // KazKem singleton cleanup is handled by the library
    }

    companion object {
        /**
         * Library version string.
         */
        val version: String
            get() = KazKem.version

        /**
         * Check if KAZ-KEM is initialized.
         */
        val isInitialized: Boolean
            get() = KazKem.isInitialized
    }
}
