package my.ssdid.drive.crypto.providers

import org.bouncycastle.jcajce.SecretKeyWithEncapsulation
import org.bouncycastle.jcajce.spec.KEMExtractSpec
import org.bouncycastle.jcajce.spec.KEMGenerateSpec
import org.bouncycastle.pqc.jcajce.provider.BouncyCastlePQCProvider
import org.bouncycastle.pqc.jcajce.spec.KyberParameterSpec
import java.security.KeyFactory
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.PrivateKey
import java.security.PublicKey
import java.security.Security
import javax.crypto.KeyGenerator
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Provider for ML-KEM (Kyber) post-quantum key encapsulation using Bouncy Castle.
 * Implements ML-KEM-768 (NIST FIPS 203).
 */
@Singleton
class MlKemProvider @Inject constructor() {

    companion object {
        private const val ALGORITHM = "Kyber"
        private const val PROVIDER = "BCPQC"

        init {
            // Register Bouncy Castle PQC provider
            if (Security.getProvider(PROVIDER) == null) {
                Security.addProvider(BouncyCastlePQCProvider())
            }
        }
    }

    /**
     * Generate an ML-KEM-768 key pair.
     * @return Pair of (publicKey bytes, privateKey bytes)
     */
    fun generateKeyPair(): Pair<ByteArray, ByteArray> {
        val keyPairGenerator = KeyPairGenerator.getInstance(ALGORITHM, PROVIDER)
        keyPairGenerator.initialize(KyberParameterSpec.kyber768)
        val keyPair = keyPairGenerator.generateKeyPair()

        return Pair(
            keyPair.public.encoded,
            keyPair.private.encoded
        )
    }

    /**
     * Encapsulate a shared secret for a recipient's public key.
     * @param publicKeyBytes Recipient's encoded public key
     * @return Pair of (sharedSecret, ciphertext/encapsulation)
     */
    fun encapsulate(publicKeyBytes: ByteArray): Pair<ByteArray, ByteArray> {
        val publicKey = decodePublicKey(publicKeyBytes)

        val keyGenerator = KeyGenerator.getInstance(ALGORITHM, PROVIDER)
        keyGenerator.init(KEMGenerateSpec(publicKey, "AES"))

        val secretKey = keyGenerator.generateKey() as SecretKeyWithEncapsulation
        val sharedSecret = secretKey.encoded
        val encapsulation = secretKey.encapsulation

        return Pair(sharedSecret, encapsulation)
    }

    /**
     * Decapsulate a shared secret using our private key.
     * @param encapsulation The KEM ciphertext/encapsulation
     * @param privateKeyBytes Our encoded private key
     * @return The shared secret
     */
    fun decapsulate(encapsulation: ByteArray, privateKeyBytes: ByteArray): ByteArray {
        val privateKey = decodePrivateKey(privateKeyBytes)

        val keyGenerator = KeyGenerator.getInstance(ALGORITHM, PROVIDER)
        keyGenerator.init(KEMExtractSpec(privateKey, encapsulation, "AES"))

        val secretKey = keyGenerator.generateKey()
        return secretKey.encoded
    }

    /**
     * Decode a public key from its encoded form.
     */
    private fun decodePublicKey(encoded: ByteArray): PublicKey {
        val keyFactory = KeyFactory.getInstance(ALGORITHM, PROVIDER)
        val keySpec = java.security.spec.X509EncodedKeySpec(encoded)
        return keyFactory.generatePublic(keySpec)
    }

    /**
     * Decode a private key from its encoded form.
     */
    private fun decodePrivateKey(encoded: ByteArray): PrivateKey {
        val keyFactory = KeyFactory.getInstance(ALGORITHM, PROVIDER)
        val keySpec = java.security.spec.PKCS8EncodedKeySpec(encoded)
        return keyFactory.generatePrivate(keySpec)
    }

    /**
     * Get the raw key pair objects (for advanced use cases).
     */
    fun generateKeyPairRaw(): KeyPair {
        val keyPairGenerator = KeyPairGenerator.getInstance(ALGORITHM, PROVIDER)
        keyPairGenerator.initialize(KyberParameterSpec.kyber768)
        return keyPairGenerator.generateKeyPair()
    }
}
