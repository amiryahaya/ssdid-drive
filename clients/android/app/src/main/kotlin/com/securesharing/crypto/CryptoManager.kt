package com.securesharing.crypto

import com.securesharing.crypto.providers.AesGcmProvider
import com.securesharing.crypto.providers.HkdfProvider
import com.securesharing.crypto.providers.KazKemProvider
import com.securesharing.crypto.providers.KazSignProvider
import com.securesharing.crypto.providers.MlKemProvider
import com.securesharing.crypto.providers.MlDsaProvider
import com.securesharing.util.AnalyticsManager
import com.securesharing.util.SentryConfig
import org.bouncycastle.crypto.generators.Argon2BytesGenerator
import org.bouncycastle.crypto.generators.BCrypt
import org.bouncycastle.crypto.params.Argon2Parameters
import java.security.SecureRandom
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Central manager for all cryptographic operations.
 * Coordinates between different crypto providers.
 *
 * Supports dual-algorithm approach:
 * - KAZ-KEM + ML-KEM for key encapsulation
 * - KAZ-SIGN + ML-DSA for digital signatures
 *
 * Algorithm selection is controlled by [CryptoConfig] based on tenant settings.
 */
@Singleton
class CryptoManager @Inject constructor(
    val aesGcmProvider: AesGcmProvider,
    val hkdfProvider: HkdfProvider,
    val kazKemProvider: KazKemProvider,
    val kazSignProvider: KazSignProvider,
    val mlKemProvider: MlKemProvider,
    val mlDsaProvider: MlDsaProvider,
    val cryptoConfig: CryptoConfig,
    val analyticsManager: AnalyticsManager
) {
    private val secureRandom = SecureRandom()

    companion object {
        private const val MASTER_KEY_SALT = "SecureSharing-MasterKey-v1"
        private const val MK_ENCRYPTION_KEY_INFO = "mk-encryption-key"

        // Argon2id-standard parameters (64 MiB)
        private const val ARGON2_MEMORY_KIB = 65536
        private const val ARGON2_ITERATIONS = 3
        private const val ARGON2_PARALLELISM = 4
        private const val ARGON2_OUTPUT_LENGTH = 32

        // Argon2id-low parameters (19 MiB)
        private const val ARGON2_LOW_MEMORY_KIB = 19456
        private const val ARGON2_LOW_ITERATIONS = 4

        // Bcrypt-HKDF parameters
        private const val BCRYPT_COST = 13
        private const val BCRYPT_HKDF_SALT = "SecureSharing-Bcrypt-KDF-v1"
        private const val BCRYPT_HKDF_INFO = "bcrypt-derived-key"
    }

    // ==================== Random Generation ====================

    /**
     * Generate cryptographically secure random bytes.
     */
    fun generateRandom(size: Int): ByteArray {
        val bytes = ByteArray(size)
        secureRandom.nextBytes(bytes)
        return bytes
    }

    /**
     * Generate a 32-byte key (256 bits).
     */
    fun generateKey(): ByteArray = generateRandom(32)

    // ==================== Key Derivation ====================

    /**
     * Derive a key from password using Argon2id + HKDF-SHA384.
     */
    fun deriveKey(password: ByteArray, salt: ByteArray): ByteArray {
        val argon2Output = deriveArgon2id(password, salt)
        return try {
            hkdfProvider.deriveKey(
                ikm = argon2Output,
                salt = MASTER_KEY_SALT.toByteArray(),
                info = MK_ENCRYPTION_KEY_INFO.toByteArray()
            )
        } finally {
            SecureMemory.zeroize(argon2Output)
        }
    }

    /**
     * Legacy HKDF-only derivation for backward compatibility.
     */
    fun deriveKeyLegacy(password: ByteArray, salt: ByteArray): ByteArray {
        return hkdfProvider.deriveKey(password, salt, info = "SecureSharing-v1".toByteArray())
    }

    /**
     * Derive a 32-byte key using Argon2id (RFC 9106 parameters).
     */
    private fun deriveArgon2id(password: ByteArray, salt: ByteArray): ByteArray {
        val params = Argon2Parameters.Builder(Argon2Parameters.ARGON2_id)
            .withSalt(salt)
            .withMemoryAsKB(ARGON2_MEMORY_KIB)
            .withIterations(ARGON2_ITERATIONS)
            .withParallelism(ARGON2_PARALLELISM)
            .build()

        val generator = Argon2BytesGenerator()
        generator.init(params)

        val output = ByteArray(ARGON2_OUTPUT_LENGTH)
        generator.generateBytes(password, output)
        return output
    }

    /**
     * Derive a 32-byte key using Argon2id-low profile (19 MiB, t=4).
     */
    private fun deriveArgon2idLow(password: ByteArray, salt: ByteArray): ByteArray {
        val params = Argon2Parameters.Builder(Argon2Parameters.ARGON2_id)
            .withSalt(salt)
            .withMemoryAsKB(ARGON2_LOW_MEMORY_KIB)
            .withIterations(ARGON2_LOW_ITERATIONS)
            .withParallelism(ARGON2_PARALLELISM)
            .build()

        val generator = Argon2BytesGenerator()
        generator.init(params)

        val output = ByteArray(ARGON2_OUTPUT_LENGTH)
        generator.generateBytes(password, output)
        return output
    }

    /**
     * Derive a 32-byte key using bcrypt + HKDF-SHA-384.
     *
     * 1. Bcrypt hash (cost=13) -> 24-byte output
     * 2. HKDF-SHA-384 stretch to 32 bytes
     */
    private fun deriveBcryptHkdf(password: ByteArray, salt: ByteArray): ByteArray {
        // BCrypt.generate expects 16-byte salt and password as byte array
        // BouncyCastle BCrypt.generate returns 24 bytes
        val bcryptOutput = BCrypt.generate(password, salt, BCRYPT_COST)

        return try {
            hkdfProvider.deriveKey(
                ikm = bcryptOutput,
                salt = BCRYPT_HKDF_SALT.toByteArray(),
                info = BCRYPT_HKDF_INFO.toByteArray(),
                length = ARGON2_OUTPUT_LENGTH
            )
        } finally {
            SecureMemory.zeroize(bcryptOutput)
        }
    }

    /**
     * Derive a key using the tiered KDF system.
     *
     * Parses the profile byte from the first byte of [saltWithProfile],
     * then dispatches to the correct KDF.
     *
     * For backward compatibility: if the salt is not 17 bytes or the first
     * byte is not a valid profile, falls back to legacy Argon2id-standard.
     */
    fun deriveKeyWithProfile(password: ByteArray, saltWithProfile: ByteArray): ByteArray {
        if (KdfProfile.isTieredSalt(saltWithProfile)) {
            val profile = KdfProfile.fromByte(saltWithProfile[0])
            val salt = saltWithProfile.copyOfRange(1, KdfProfile.WIRE_SALT_SIZE)

            return when (profile) {
                KdfProfile.ARGON2ID_STANDARD -> deriveArgon2id(password, salt)
                KdfProfile.ARGON2ID_LOW -> deriveArgon2idLow(password, salt)
                KdfProfile.BCRYPT_HKDF -> deriveBcryptHkdf(password, salt)
            }
        }

        // Legacy fallback: use existing deriveKey path (includes HKDF post-processing)
        return deriveKey(password, saltWithProfile)
    }

    // ==================== AES-GCM Encryption ====================

    /**
     * Encrypt data using AES-256-GCM.
     * Returns: nonce || ciphertext || tag
     */
    fun encryptAesGcm(plaintext: ByteArray, key: ByteArray): ByteArray {
        return aesGcmProvider.encrypt(plaintext, key)
    }

    /**
     * Decrypt data using AES-256-GCM.
     * Input: nonce || ciphertext || tag
     */
    fun decryptAesGcm(ciphertext: ByteArray, key: ByteArray): ByteArray {
        return aesGcmProvider.decrypt(ciphertext, key)
    }

    /**
     * Encrypt data using AES-256-GCM with AAD.
     * Returns: nonce || ciphertext || tag
     */
    fun encryptAesGcmWithAad(plaintext: ByteArray, key: ByteArray, aad: ByteArray): ByteArray {
        return aesGcmProvider.encryptWithAad(plaintext, key, aad)
    }

    /**
     * Decrypt data using AES-256-GCM with AAD.
     * Input: nonce || ciphertext || tag
     */
    fun decryptAesGcmWithAad(ciphertext: ByteArray, key: ByteArray, aad: ByteArray): ByteArray {
        return aesGcmProvider.decryptWithAad(ciphertext, key, aad)
    }

    // ==================== KAZ-KEM Operations ====================

    /**
     * Generate a KAZ-KEM key pair.
     */
    fun generateKazKemKeyPair(): Pair<ByteArray, ByteArray> {
        SentryConfig.addCryptoBreadcrumb(
            message = "Generating KAZ-KEM key pair",
            operation = "key_generation",
            algorithm = "KAZ-KEM"
        )
        val startNs = System.nanoTime()
        val result = kazKemProvider.generateKeyPair()
        val durationMs = (System.nanoTime() - startNs) / 1_000_000
        analyticsManager.trackCryptoTiming("keygen", durationMs, "KAZ-KEM")
        return result
    }

    /**
     * Encapsulate a shared secret using KAZ-KEM.
     * Returns: (sharedSecret, ciphertext)
     */
    fun kazKemEncapsulate(publicKey: ByteArray): Pair<ByteArray, ByteArray> {
        return kazKemProvider.encapsulate(publicKey)
    }

    /**
     * Decapsulate a shared secret using KAZ-KEM.
     */
    fun kazKemDecapsulate(ciphertext: ByteArray, privateKey: ByteArray): ByteArray {
        return kazKemProvider.decapsulate(ciphertext, privateKey)
    }

    // ==================== ML-KEM Operations (NIST FIPS 203) ====================

    /**
     * Generate an ML-KEM-768 key pair.
     */
    fun generateMlKemKeyPair(): Pair<ByteArray, ByteArray> {
        SentryConfig.addCryptoBreadcrumb(
            message = "Generating ML-KEM-768 key pair",
            operation = "key_generation",
            algorithm = "ML-KEM-768"
        )
        val startNs = System.nanoTime()
        val result = mlKemProvider.generateKeyPair()
        val durationMs = (System.nanoTime() - startNs) / 1_000_000
        analyticsManager.trackCryptoTiming("keygen", durationMs, "ML-KEM-768")
        return result
    }

    /**
     * Encapsulate a shared secret using ML-KEM-768.
     * Returns: (sharedSecret, encapsulation)
     */
    fun mlKemEncapsulate(publicKey: ByteArray): Pair<ByteArray, ByteArray> {
        return mlKemProvider.encapsulate(publicKey)
    }

    /**
     * Decapsulate a shared secret using ML-KEM-768.
     */
    fun mlKemDecapsulate(encapsulation: ByteArray, privateKey: ByteArray): ByteArray {
        return mlKemProvider.decapsulate(encapsulation, privateKey)
    }

    // ==================== Combined KEM (Dual Algorithm) ====================

    /**
     * Combined KEM encapsulation using both KAZ-KEM and ML-KEM.
     * The shared secrets are combined using XOR for defense-in-depth.
     *
     * @param kazPublicKey KAZ-KEM public key
     * @param mlKemPublicKey ML-KEM public key
     * @return Triple of (combinedSharedSecret, kazCiphertext, mlKemEncapsulation)
     */
    fun combinedKemEncapsulate(
        kazPublicKey: ByteArray,
        mlKemPublicKey: ByteArray
    ): Triple<ByteArray, ByteArray, ByteArray> {
        val (kazSecret, kazCiphertext) = kazKemEncapsulate(kazPublicKey)
        val (mlKemSecret, mlKemEncapsulation) = mlKemEncapsulate(mlKemPublicKey)

        // Combine secrets using XOR (if one algorithm is broken, the other still protects)
        val combinedSecret = combineSecrets(kazSecret, mlKemSecret)

        return Triple(combinedSecret, kazCiphertext, mlKemEncapsulation)
    }

    /**
     * Combined KEM decapsulation using both KAZ-KEM and ML-KEM.
     *
     * @param kazCiphertext KAZ-KEM ciphertext
     * @param mlKemEncapsulation ML-KEM encapsulation
     * @param kazPrivateKey KAZ-KEM private key
     * @param mlKemPrivateKey ML-KEM private key
     * @return Combined shared secret
     */
    fun combinedKemDecapsulate(
        kazCiphertext: ByteArray,
        mlKemEncapsulation: ByteArray,
        kazPrivateKey: ByteArray,
        mlKemPrivateKey: ByteArray
    ): ByteArray {
        val kazSecret = kazKemDecapsulate(kazCiphertext, kazPrivateKey)
        val mlKemSecret = mlKemDecapsulate(mlKemEncapsulation, mlKemPrivateKey)

        return combineSecrets(kazSecret, mlKemSecret)
    }

    /**
     * Combine two secrets using XOR and HKDF for uniform output.
     */
    private fun combineSecrets(secret1: ByteArray, secret2: ByteArray): ByteArray {
        // XOR the secrets (pad shorter one if needed)
        val maxLen = maxOf(secret1.size, secret2.size)
        val combined = ByteArray(maxLen)

        for (i in 0 until maxLen) {
            val b1 = if (i < secret1.size) secret1[i] else 0
            val b2 = if (i < secret2.size) secret2[i] else 0
            combined[i] = (b1.toInt() xor b2.toInt()).toByte()
        }

        // Use HKDF to derive a uniform 32-byte key from the combined secret
        return hkdfProvider.deriveKey(
            ikm = combined,
            salt = "SecureSharing-CombinedKEM".toByteArray(),
            info = "shared-secret".toByteArray(),
            length = 32
        )
    }

    // ==================== KAZ-SIGN Operations ====================

    /**
     * Generate a KAZ-SIGN key pair.
     */
    fun generateKazSignKeyPair(): Pair<ByteArray, ByteArray> {
        SentryConfig.addCryptoBreadcrumb(
            message = "Generating KAZ-SIGN key pair",
            operation = "key_generation",
            algorithm = "KAZ-SIGN"
        )
        val startNs = System.nanoTime()
        val result = kazSignProvider.generateKeyPair()
        val durationMs = (System.nanoTime() - startNs) / 1_000_000
        analyticsManager.trackCryptoTiming("keygen", durationMs, "KAZ-SIGN")
        return result
    }

    /**
     * Sign a message using KAZ-SIGN.
     */
    fun kazSign(message: ByteArray, privateKey: ByteArray): ByteArray {
        return kazSignProvider.sign(message, privateKey)
    }

    /**
     * Verify a KAZ-SIGN signature.
     */
    fun kazVerify(message: ByteArray, signature: ByteArray, publicKey: ByteArray): Boolean {
        return kazSignProvider.verify(message, signature, publicKey)
    }

    // ==================== ML-DSA Operations (NIST FIPS 204) ====================

    /**
     * Generate an ML-DSA-65 key pair.
     */
    fun generateMlDsaKeyPair(): Pair<ByteArray, ByteArray> {
        SentryConfig.addCryptoBreadcrumb(
            message = "Generating ML-DSA-65 key pair",
            operation = "key_generation",
            algorithm = "ML-DSA-65"
        )
        val startNs = System.nanoTime()
        val result = mlDsaProvider.generateKeyPair()
        val durationMs = (System.nanoTime() - startNs) / 1_000_000
        analyticsManager.trackCryptoTiming("keygen", durationMs, "ML-DSA-65")
        return result
    }

    /**
     * Sign a message using ML-DSA-65.
     */
    fun mlDsaSign(message: ByteArray, privateKey: ByteArray): ByteArray {
        return mlDsaProvider.sign(message, privateKey)
    }

    /**
     * Verify an ML-DSA-65 signature.
     */
    fun mlDsaVerify(message: ByteArray, signature: ByteArray, publicKey: ByteArray): Boolean {
        return mlDsaProvider.verify(message, signature, publicKey)
    }

    // ==================== Combined Signature (Dual Algorithm) ====================

    /**
     * Combined signature using both KAZ-SIGN and ML-DSA.
     * Both signatures must verify for the combined signature to be valid.
     *
     * @param message The message to sign
     * @param kazPrivateKey KAZ-SIGN private key
     * @param mlDsaPrivateKey ML-DSA private key
     * @return Combined signature (kazSignature || mlDsaSignature with length prefixes)
     */
    fun combinedSign(
        message: ByteArray,
        kazPrivateKey: ByteArray,
        mlDsaPrivateKey: ByteArray
    ): ByteArray {
        val kazSignature = kazSign(message, kazPrivateKey)
        val mlDsaSignature = mlDsaSign(message, mlDsaPrivateKey)

        // Encode: [kazSigLen:4][kazSignature][mlDsaSigLen:4][mlDsaSignature]
        val result = ByteArray(4 + kazSignature.size + 4 + mlDsaSignature.size)
        var offset = 0

        // KAZ signature length and data
        result[offset++] = (kazSignature.size shr 24).toByte()
        result[offset++] = (kazSignature.size shr 16).toByte()
        result[offset++] = (kazSignature.size shr 8).toByte()
        result[offset++] = kazSignature.size.toByte()
        System.arraycopy(kazSignature, 0, result, offset, kazSignature.size)
        offset += kazSignature.size

        // ML-DSA signature length and data
        result[offset++] = (mlDsaSignature.size shr 24).toByte()
        result[offset++] = (mlDsaSignature.size shr 16).toByte()
        result[offset++] = (mlDsaSignature.size shr 8).toByte()
        result[offset++] = mlDsaSignature.size.toByte()
        System.arraycopy(mlDsaSignature, 0, result, offset, mlDsaSignature.size)

        return result
    }

    /**
     * Verify a combined signature (both KAZ-SIGN and ML-DSA must verify).
     *
     * @param message The original message
     * @param combinedSignature The combined signature
     * @param kazPublicKey KAZ-SIGN public key
     * @param mlDsaPublicKey ML-DSA public key
     * @return true only if BOTH signatures verify
     */
    fun combinedVerify(
        message: ByteArray,
        combinedSignature: ByteArray,
        kazPublicKey: ByteArray,
        mlDsaPublicKey: ByteArray
    ): Boolean {
        return try {
            var offset = 0

            // Extract KAZ signature
            val kazSigLen = ((combinedSignature[offset++].toInt() and 0xFF) shl 24) or
                    ((combinedSignature[offset++].toInt() and 0xFF) shl 16) or
                    ((combinedSignature[offset++].toInt() and 0xFF) shl 8) or
                    (combinedSignature[offset++].toInt() and 0xFF)
            val kazSignature = combinedSignature.copyOfRange(offset, offset + kazSigLen)
            offset += kazSigLen

            // Extract ML-DSA signature
            val mlDsaSigLen = ((combinedSignature[offset++].toInt() and 0xFF) shl 24) or
                    ((combinedSignature[offset++].toInt() and 0xFF) shl 16) or
                    ((combinedSignature[offset++].toInt() and 0xFF) shl 8) or
                    (combinedSignature[offset++].toInt() and 0xFF)
            val mlDsaSignature = combinedSignature.copyOfRange(offset, offset + mlDsaSigLen)

            // BOTH must verify
            val kazValid = kazVerify(message, kazSignature, kazPublicKey)
            val mlDsaValid = mlDsaVerify(message, mlDsaSignature, mlDsaPublicKey)

            kazValid && mlDsaValid
        } catch (e: Exception) {
            false
        }
    }

    // ==================== HKDF Direct Derivation ====================

    /**
     * Derive a key using HKDF-SHA384 directly from input key material.
     * Used for vault key derivation (OIDC) and PRF wrapping key derivation (WebAuthn).
     *
     * @param inputKey Input key material
     * @param salt Salt for HKDF
     * @param info Context info for HKDF
     * @param length Output key length (default 32)
     * @return Derived key
     */
    fun hkdfDerive(
        inputKey: ByteArray,
        salt: ByteArray,
        info: ByteArray,
        length: Int = 32
    ): ByteArray {
        return hkdfProvider.deriveKey(
            ikm = inputKey,
            salt = salt,
            info = info,
            length = length
        )
    }

    // ==================== AES-GCM with Separate Nonce ====================

    /**
     * Decrypt data using AES-256-GCM with a separately provided nonce.
     * Used for vault/PRF key bundle decryption where nonce is a separate field.
     *
     * @param ciphertext Ciphertext with appended auth tag (no nonce prefix)
     * @param key 32-byte AES key
     * @param nonce 12-byte nonce
     * @return Decrypted plaintext
     */
    fun decryptAesGcmWithNonce(ciphertext: ByteArray, key: ByteArray, nonce: ByteArray): ByteArray {
        return aesGcmProvider.decryptWithNonce(ciphertext, key, nonce)
    }

    // ==================== Key Wrapping ====================

    /**
     * Wrap a key using AES-256-GCM.
     */
    fun wrapKey(keyToWrap: ByteArray, wrappingKey: ByteArray): ByteArray {
        return encryptAesGcm(keyToWrap, wrappingKey)
    }

    /**
     * Unwrap a key.
     */
    fun unwrapKey(wrappedKey: ByteArray, wrappingKey: ByteArray): ByteArray {
        return decryptAesGcm(wrappedKey, wrappingKey)
    }

    // ==================== Secure Memory ====================

    /**
     * Securely zero out sensitive data in memory.
     *
     * SECURITY: Uses multi-pass overwrite with memory barriers
     * to prevent optimization and ensure data is cleared.
     *
     * @param data The byte array to zeroize
     */
    fun zeroize(data: ByteArray) {
        SecureMemory.zeroize(data)
    }

    /**
     * Securely zero out sensitive char array data.
     *
     * @param data The char array to zeroize (e.g., password)
     */
    fun zeroize(data: CharArray) {
        SecureMemory.zeroize(data)
    }

    // ==================== Tenant-Aware Operations ====================

    /**
     * Result of tenant-aware KEM encapsulation.
     * Contains the shared secret and ciphertexts for the algorithms used.
     */
    data class KemEncapsulationResult(
        val sharedSecret: ByteArray,
        val kazCiphertext: ByteArray?,
        val mlKemEncapsulation: ByteArray?
    )

    /**
     * Encapsulate a shared secret using the tenant's configured algorithm(s).
     *
     * @param kazPublicKey KAZ-KEM public key (required if tenant uses KAZ or HYBRID)
     * @param mlKemPublicKey ML-KEM public key (required if tenant uses NIST or HYBRID)
     * @return KemEncapsulationResult with shared secret and relevant ciphertexts
     */
    fun tenantKemEncapsulate(
        kazPublicKey: ByteArray?,
        mlKemPublicKey: ByteArray?
    ): KemEncapsulationResult {
        return when (cryptoConfig.getAlgorithm()) {
            PqcAlgorithm.KAZ -> {
                requireNotNull(kazPublicKey) { "KAZ public key required for KAZ algorithm" }
                val (secret, ciphertext) = kazKemEncapsulate(kazPublicKey)
                KemEncapsulationResult(secret, ciphertext, null)
            }
            PqcAlgorithm.NIST -> {
                requireNotNull(mlKemPublicKey) { "ML-KEM public key required for NIST algorithm" }
                val (secret, encapsulation) = mlKemEncapsulate(mlKemPublicKey)
                KemEncapsulationResult(secret, null, encapsulation)
            }
            PqcAlgorithm.HYBRID -> {
                requireNotNull(kazPublicKey) { "KAZ public key required for HYBRID algorithm" }
                requireNotNull(mlKemPublicKey) { "ML-KEM public key required for HYBRID algorithm" }
                val (secret, kazCt, mlKemEnc) = combinedKemEncapsulate(kazPublicKey, mlKemPublicKey)
                KemEncapsulationResult(secret, kazCt, mlKemEnc)
            }
        }
    }

    /**
     * Decapsulate a shared secret using the tenant's configured algorithm(s).
     *
     * @param kazCiphertext KAZ-KEM ciphertext (required if tenant uses KAZ or HYBRID)
     * @param mlKemEncapsulation ML-KEM encapsulation (required if tenant uses NIST or HYBRID)
     * @param kazPrivateKey KAZ-KEM private key
     * @param mlKemPrivateKey ML-KEM private key
     * @return The shared secret
     */
    fun tenantKemDecapsulate(
        kazCiphertext: ByteArray?,
        mlKemEncapsulation: ByteArray?,
        kazPrivateKey: ByteArray?,
        mlKemPrivateKey: ByteArray?
    ): ByteArray {
        return when (cryptoConfig.getAlgorithm()) {
            PqcAlgorithm.KAZ -> {
                requireNotNull(kazCiphertext) { "KAZ ciphertext required for KAZ algorithm" }
                requireNotNull(kazPrivateKey) { "KAZ private key required for KAZ algorithm" }
                kazKemDecapsulate(kazCiphertext, kazPrivateKey)
            }
            PqcAlgorithm.NIST -> {
                requireNotNull(mlKemEncapsulation) { "ML-KEM encapsulation required for NIST algorithm" }
                requireNotNull(mlKemPrivateKey) { "ML-KEM private key required for NIST algorithm" }
                mlKemDecapsulate(mlKemEncapsulation, mlKemPrivateKey)
            }
            PqcAlgorithm.HYBRID -> {
                requireNotNull(kazCiphertext) { "KAZ ciphertext required for HYBRID algorithm" }
                requireNotNull(mlKemEncapsulation) { "ML-KEM encapsulation required for HYBRID algorithm" }
                requireNotNull(kazPrivateKey) { "KAZ private key required for HYBRID algorithm" }
                requireNotNull(mlKemPrivateKey) { "ML-KEM private key required for HYBRID algorithm" }
                combinedKemDecapsulate(kazCiphertext, mlKemEncapsulation, kazPrivateKey, mlKemPrivateKey)
            }
        }
    }

    /**
     * Result of tenant-aware signature operation.
     * Contains the signature(s) based on the algorithm used.
     */
    data class SignatureResult(
        val signature: ByteArray,
        val isCombined: Boolean
    )

    /**
     * Sign a message using the tenant's configured algorithm(s).
     *
     * @param message The message to sign
     * @param kazPrivateKey KAZ-SIGN private key (required if tenant uses KAZ or HYBRID)
     * @param mlDsaPrivateKey ML-DSA private key (required if tenant uses NIST or HYBRID)
     * @return SignatureResult with signature and whether it's a combined signature
     */
    fun tenantSign(
        message: ByteArray,
        kazPrivateKey: ByteArray?,
        mlDsaPrivateKey: ByteArray?
    ): SignatureResult {
        return when (cryptoConfig.getAlgorithm()) {
            PqcAlgorithm.KAZ -> {
                requireNotNull(kazPrivateKey) { "KAZ-SIGN private key required for KAZ algorithm" }
                val sig = kazSign(message, kazPrivateKey)
                SignatureResult(sig, isCombined = false)
            }
            PqcAlgorithm.NIST -> {
                requireNotNull(mlDsaPrivateKey) { "ML-DSA private key required for NIST algorithm" }
                val sig = mlDsaSign(message, mlDsaPrivateKey)
                SignatureResult(sig, isCombined = false)
            }
            PqcAlgorithm.HYBRID -> {
                requireNotNull(kazPrivateKey) { "KAZ-SIGN private key required for HYBRID algorithm" }
                requireNotNull(mlDsaPrivateKey) { "ML-DSA private key required for HYBRID algorithm" }
                val sig = combinedSign(message, kazPrivateKey, mlDsaPrivateKey)
                SignatureResult(sig, isCombined = true)
            }
        }
    }

    /**
     * Verify a signature using the tenant's configured algorithm(s).
     *
     * @param message The original message
     * @param signature The signature to verify
     * @param kazPublicKey KAZ-SIGN public key (required if tenant uses KAZ or HYBRID)
     * @param mlDsaPublicKey ML-DSA public key (required if tenant uses NIST or HYBRID)
     * @param isCombined Whether the signature is a combined signature
     * @return true if the signature is valid
     */
    fun tenantVerify(
        message: ByteArray,
        signature: ByteArray,
        kazPublicKey: ByteArray?,
        mlDsaPublicKey: ByteArray?,
        isCombined: Boolean
    ): Boolean {
        return when {
            isCombined || cryptoConfig.getAlgorithm() == PqcAlgorithm.HYBRID -> {
                requireNotNull(kazPublicKey) { "KAZ-SIGN public key required for HYBRID verification" }
                requireNotNull(mlDsaPublicKey) { "ML-DSA public key required for HYBRID verification" }
                combinedVerify(message, signature, kazPublicKey, mlDsaPublicKey)
            }
            cryptoConfig.getAlgorithm() == PqcAlgorithm.KAZ -> {
                requireNotNull(kazPublicKey) { "KAZ-SIGN public key required for KAZ verification" }
                kazVerify(message, signature, kazPublicKey)
            }
            cryptoConfig.getAlgorithm() == PqcAlgorithm.NIST -> {
                requireNotNull(mlDsaPublicKey) { "ML-DSA public key required for NIST verification" }
                mlDsaVerify(message, signature, mlDsaPublicKey)
            }
            else -> false
        }
    }

    // ==================== Legacy Aliases (for backward compatibility) ====================

    @Deprecated("Use generateKazKemKeyPair() instead", ReplaceWith("generateKazKemKeyPair()"))
    fun generateKemKeyPair() = generateKazKemKeyPair()

    @Deprecated("Use kazKemEncapsulate() instead", ReplaceWith("kazKemEncapsulate(publicKey)"))
    fun kemEncapsulate(publicKey: ByteArray) = kazKemEncapsulate(publicKey)

    @Deprecated("Use kazKemDecapsulate() instead", ReplaceWith("kazKemDecapsulate(ciphertext, privateKey)"))
    fun kemDecapsulate(ciphertext: ByteArray, privateKey: ByteArray) = kazKemDecapsulate(ciphertext, privateKey)

    @Deprecated("Use generateKazSignKeyPair() instead", ReplaceWith("generateKazSignKeyPair()"))
    fun generateSignKeyPair() = generateKazSignKeyPair()

    @Deprecated("Use kazSign() instead", ReplaceWith("kazSign(message, privateKey)"))
    fun sign(message: ByteArray, privateKey: ByteArray) = kazSign(message, privateKey)

    @Deprecated("Use kazVerify() instead", ReplaceWith("kazVerify(message, signature, publicKey)"))
    fun verify(message: ByteArray, signature: ByteArray, publicKey: ByteArray) = kazVerify(message, signature, publicKey)
}
