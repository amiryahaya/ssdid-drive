package com.securesharing.crypto.providers

import org.bouncycastle.pqc.jcajce.provider.BouncyCastlePQCProvider
import org.bouncycastle.pqc.jcajce.spec.DilithiumParameterSpec
import java.security.KeyFactory
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.PrivateKey
import java.security.PublicKey
import java.security.Security
import java.security.Signature
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Provider for ML-DSA (Dilithium) post-quantum digital signatures using Bouncy Castle.
 * Implements ML-DSA-65 (NIST FIPS 204).
 */
@Singleton
class MlDsaProvider @Inject constructor() {

    companion object {
        private const val ALGORITHM = "Dilithium"
        private const val SIGNATURE_ALGORITHM = "Dilithium"
        private const val PROVIDER = "BCPQC"

        init {
            // Register Bouncy Castle PQC provider
            if (Security.getProvider(PROVIDER) == null) {
                Security.addProvider(BouncyCastlePQCProvider())
            }
        }
    }

    /**
     * Generate an ML-DSA-65 key pair.
     * @return Pair of (publicKey bytes, privateKey bytes)
     */
    fun generateKeyPair(): Pair<ByteArray, ByteArray> {
        val keyPairGenerator = KeyPairGenerator.getInstance(ALGORITHM, PROVIDER)
        keyPairGenerator.initialize(DilithiumParameterSpec.dilithium3) // ML-DSA-65 equivalent
        val keyPair = keyPairGenerator.generateKeyPair()

        return Pair(
            keyPair.public.encoded,
            keyPair.private.encoded
        )
    }

    /**
     * Sign a message using ML-DSA.
     * @param message The message to sign
     * @param privateKeyBytes The encoded private key
     * @return The signature
     */
    fun sign(message: ByteArray, privateKeyBytes: ByteArray): ByteArray {
        val privateKey = decodePrivateKey(privateKeyBytes)

        val signature = Signature.getInstance(SIGNATURE_ALGORITHM, PROVIDER)
        signature.initSign(privateKey)
        signature.update(message)

        return signature.sign()
    }

    /**
     * Verify a signature using ML-DSA.
     * @param message The original message
     * @param signatureBytes The signature to verify
     * @param publicKeyBytes The encoded public key
     * @return true if the signature is valid
     */
    fun verify(message: ByteArray, signatureBytes: ByteArray, publicKeyBytes: ByteArray): Boolean {
        return try {
            val publicKey = decodePublicKey(publicKeyBytes)

            val signature = Signature.getInstance(SIGNATURE_ALGORITHM, PROVIDER)
            signature.initVerify(publicKey)
            signature.update(message)

            signature.verify(signatureBytes)
        } catch (e: Exception) {
            false
        }
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
        keyPairGenerator.initialize(DilithiumParameterSpec.dilithium3)
        return keyPairGenerator.generateKeyPair()
    }
}
