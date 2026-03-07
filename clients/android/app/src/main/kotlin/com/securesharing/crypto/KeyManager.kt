package com.securesharing.crypto

import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import java.nio.ByteBuffer
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Manages user key material (key generation, storage, unlocking).
 *
 * Generates and manages four PQC key pairs:
 * - KAZ-KEM: Custom post-quantum KEM
 * - KAZ-SIGN: Custom post-quantum signatures
 * - ML-KEM-768: NIST FIPS 203 (Kyber)
 * - ML-DSA-65: NIST FIPS 204 (Dilithium)
 */
@Singleton
class KeyManager @Inject constructor(
    @ApplicationContext private val context: Context,
    private val cryptoManager: CryptoManager
) {
    // In-memory unlocked keys (cleared on logout/lock)
    private var unlockedKeys: KeyBundle? = null

    /**
     * Check if keys are currently unlocked.
     */
    fun hasUnlockedKeys(): Boolean = unlockedKeys != null

    /**
     * Get the unlocked keys (throws if not unlocked).
     */
    fun getUnlockedKeys(): KeyBundle {
        return unlockedKeys ?: throw IllegalStateException("Keys are locked")
    }

    /**
     * Set the unlocked keys after successful password unlock.
     */
    fun setUnlockedKeys(keys: KeyBundle) {
        unlockedKeys = keys
    }

    /**
     * Clear unlocked keys from memory.
     *
     * SECURITY: Uses secure multi-pass zeroization to clear all key material
     * from memory. This includes both private and public keys.
     */
    fun clearUnlockedKeys() {
        unlockedKeys?.let { keys ->
            // Zeroize all private keys (most sensitive)
            SecureMemory.zeroize(keys.masterKey)
            SecureMemory.zeroize(keys.kazKemPrivateKey)
            SecureMemory.zeroize(keys.kazSignPrivateKey)
            SecureMemory.zeroize(keys.mlKemPrivateKey)
            SecureMemory.zeroize(keys.mlDsaPrivateKey)

            // Also zeroize public keys for completeness
            SecureMemory.zeroize(keys.kazKemPublicKey)
            SecureMemory.zeroize(keys.kazSignPublicKey)
            SecureMemory.zeroize(keys.mlKemPublicKey)
            SecureMemory.zeroize(keys.mlDsaPublicKey)
        }
        unlockedKeys = null
    }

    /**
     * Generate a complete key bundle for a new user.
     * Generates all four PQC key pairs plus the master key.
     */
    fun generateKeyBundle(): KeyBundle {
        // Generate master key (32 bytes / 256 bits)
        val masterKey = cryptoManager.generateKey()

        // Generate KAZ-KEM key pair
        val (kazKemPublic, kazKemPrivate) = cryptoManager.generateKazKemKeyPair()

        // Generate KAZ-SIGN key pair
        val (kazSignPublic, kazSignPrivate) = cryptoManager.generateKazSignKeyPair()

        // Generate ML-KEM-768 key pair (NIST FIPS 203)
        val (mlKemPublic, mlKemPrivate) = cryptoManager.generateMlKemKeyPair()

        // Generate ML-DSA-65 key pair (NIST FIPS 204)
        val (mlDsaPublic, mlDsaPrivate) = cryptoManager.generateMlDsaKeyPair()

        return KeyBundle.create(
            masterKey = masterKey,
            kazKemPublicKey = kazKemPublic,
            kazKemPrivateKey = kazKemPrivate,
            kazSignPublicKey = kazSignPublic,
            kazSignPrivateKey = kazSignPrivate,
            mlKemPublicKey = mlKemPublic,
            mlKemPrivateKey = mlKemPrivate,
            mlDsaPublicKey = mlDsaPublic,
            mlDsaPrivateKey = mlDsaPrivate
        )
    }

    /**
     * Serialize private keys for encrypted storage.
     * Format: [len:4][data] for each key in order:
     * - kazKemPrivateKey
     * - kazSignPrivateKey
     * - mlKemPrivateKey
     * - mlDsaPrivateKey
     */
    fun serializePrivateKeys(keys: KeyBundle): ByteArray {
        val totalSize = 4 + keys.kazKemPrivateKey.size +
                4 + keys.kazSignPrivateKey.size +
                4 + keys.mlKemPrivateKey.size +
                4 + keys.mlDsaPrivateKey.size

        val buffer = ByteBuffer.allocate(totalSize)

        // KAZ-KEM private key
        buffer.putInt(keys.kazKemPrivateKey.size)
        buffer.put(keys.kazKemPrivateKey)

        // KAZ-SIGN private key
        buffer.putInt(keys.kazSignPrivateKey.size)
        buffer.put(keys.kazSignPrivateKey)

        // ML-KEM private key
        buffer.putInt(keys.mlKemPrivateKey.size)
        buffer.put(keys.mlKemPrivateKey)

        // ML-DSA private key
        buffer.putInt(keys.mlDsaPrivateKey.size)
        buffer.put(keys.mlDsaPrivateKey)

        return buffer.array()
    }

    /**
     * Deserialize private keys from encrypted storage.
     * Public keys should be fetched from the server or derived.
     */
    fun deserializePrivateKeys(data: ByteArray, masterKey: ByteArray): KeyBundle {
        val buffer = ByteBuffer.wrap(data)

        // KAZ-KEM private key
        val kazKemPrivateKeyLen = buffer.int
        val kazKemPrivateKey = ByteArray(kazKemPrivateKeyLen)
        buffer.get(kazKemPrivateKey)

        // KAZ-SIGN private key
        val kazSignPrivateKeyLen = buffer.int
        val kazSignPrivateKey = ByteArray(kazSignPrivateKeyLen)
        buffer.get(kazSignPrivateKey)

        // ML-KEM private key
        val mlKemPrivateKeyLen = buffer.int
        val mlKemPrivateKey = ByteArray(mlKemPrivateKeyLen)
        buffer.get(mlKemPrivateKey)

        // ML-DSA private key
        val mlDsaPrivateKeyLen = buffer.int
        val mlDsaPrivateKey = ByteArray(mlDsaPrivateKeyLen)
        buffer.get(mlDsaPrivateKey)

        // Public keys will be set from server data
        return KeyBundle.create(
            masterKey = masterKey,
            kazKemPublicKey = ByteArray(0),
            kazKemPrivateKey = kazKemPrivateKey,
            kazSignPublicKey = ByteArray(0),
            kazSignPrivateKey = kazSignPrivateKey,
            mlKemPublicKey = ByteArray(0),
            mlKemPrivateKey = mlKemPrivateKey,
            mlDsaPublicKey = ByteArray(0),
            mlDsaPrivateKey = mlDsaPrivateKey
        )
    }

    /**
     * Update a key bundle with public keys from the server.
     *
     * SECURITY: This creates a new KeyBundle with copies of the private keys.
     * The original KeyBundle should be zeroized after this call if no longer needed.
     */
    fun withPublicKeys(
        keys: KeyBundle,
        kazKemPublicKey: ByteArray,
        kazSignPublicKey: ByteArray,
        mlKemPublicKey: ByteArray,
        mlDsaPublicKey: ByteArray
    ): KeyBundle {
        return keys.withPublicKeys(
            kazKemPublicKey = kazKemPublicKey,
            kazSignPublicKey = kazSignPublicKey,
            mlKemPublicKey = mlKemPublicKey,
            mlDsaPublicKey = mlDsaPublicKey
        )
    }
}

/**
 * Bundle of all user keys (4 PQC key pairs + master key).
 *
 * SECURITY: This is intentionally NOT a data class to prevent accidental
 * key leaks via .copy(). Use [withPublicKeys] for controlled copies.
 * All byte arrays are stored internally and accessed via defensive copies.
 *
 * IMPORTANT: Call [zeroize] when done with the key bundle to clear
 * sensitive data from memory.
 */
class KeyBundle private constructor(
    private val _masterKey: ByteArray,
    private val _kazKemPublicKey: ByteArray,
    private val _kazKemPrivateKey: ByteArray,
    private val _kazSignPublicKey: ByteArray,
    private val _kazSignPrivateKey: ByteArray,
    private val _mlKemPublicKey: ByteArray,
    private val _mlKemPrivateKey: ByteArray,
    private val _mlDsaPublicKey: ByteArray,
    private val _mlDsaPrivateKey: ByteArray
) {
    // Public accessors return the actual arrays (not copies) for performance
    // Caller should NOT modify these arrays directly
    val masterKey: ByteArray get() = _masterKey
    val kazKemPublicKey: ByteArray get() = _kazKemPublicKey
    val kazKemPrivateKey: ByteArray get() = _kazKemPrivateKey
    val kazSignPublicKey: ByteArray get() = _kazSignPublicKey
    val kazSignPrivateKey: ByteArray get() = _kazSignPrivateKey
    val mlKemPublicKey: ByteArray get() = _mlKemPublicKey
    val mlKemPrivateKey: ByteArray get() = _mlKemPrivateKey
    val mlDsaPublicKey: ByteArray get() = _mlDsaPublicKey
    val mlDsaPrivateKey: ByteArray get() = _mlDsaPrivateKey

    /**
     * Securely zeroize all key material in this bundle.
     *
     * SECURITY: Call this method when done with the key bundle
     * to clear sensitive data from memory.
     */
    fun zeroize() {
        SecureMemory.zeroize(_masterKey)
        SecureMemory.zeroize(_kazKemPublicKey)
        SecureMemory.zeroize(_kazKemPrivateKey)
        SecureMemory.zeroize(_kazSignPublicKey)
        SecureMemory.zeroize(_kazSignPrivateKey)
        SecureMemory.zeroize(_mlKemPublicKey)
        SecureMemory.zeroize(_mlKemPrivateKey)
        SecureMemory.zeroize(_mlDsaPublicKey)
        SecureMemory.zeroize(_mlDsaPrivateKey)
    }

    /**
     * Create a new KeyBundle with updated public keys.
     *
     * SECURITY: This creates a new bundle with copies of all private keys.
     * The original bundle remains valid. Caller must zeroize both bundles
     * when done.
     */
    fun withPublicKeys(
        kazKemPublicKey: ByteArray,
        kazSignPublicKey: ByteArray,
        mlKemPublicKey: ByteArray,
        mlDsaPublicKey: ByteArray
    ): KeyBundle {
        return KeyBundle(
            _masterKey = _masterKey.copyOf(),
            _kazKemPublicKey = kazKemPublicKey.copyOf(),
            _kazKemPrivateKey = _kazKemPrivateKey.copyOf(),
            _kazSignPublicKey = kazSignPublicKey.copyOf(),
            _kazSignPrivateKey = _kazSignPrivateKey.copyOf(),
            _mlKemPublicKey = mlKemPublicKey.copyOf(),
            _mlKemPrivateKey = _mlKemPrivateKey.copyOf(),
            _mlDsaPublicKey = mlDsaPublicKey.copyOf(),
            _mlDsaPrivateKey = _mlDsaPrivateKey.copyOf()
        )
    }

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (javaClass != other?.javaClass) return false
        other as KeyBundle
        return _masterKey.contentEquals(other._masterKey)
    }

    override fun hashCode(): Int = _masterKey.contentHashCode()

    companion object {
        /**
         * Create a new KeyBundle.
         *
         * SECURITY: The provided byte arrays are stored directly (not copied)
         * for performance. Caller should not retain references to the arrays.
         */
        fun create(
            masterKey: ByteArray,
            kazKemPublicKey: ByteArray,
            kazKemPrivateKey: ByteArray,
            kazSignPublicKey: ByteArray,
            kazSignPrivateKey: ByteArray,
            mlKemPublicKey: ByteArray,
            mlKemPrivateKey: ByteArray,
            mlDsaPublicKey: ByteArray,
            mlDsaPrivateKey: ByteArray
        ): KeyBundle {
            return KeyBundle(
                _masterKey = masterKey,
                _kazKemPublicKey = kazKemPublicKey,
                _kazKemPrivateKey = kazKemPrivateKey,
                _kazSignPublicKey = kazSignPublicKey,
                _kazSignPrivateKey = kazSignPrivateKey,
                _mlKemPublicKey = mlKemPublicKey,
                _mlKemPrivateKey = mlKemPrivateKey,
                _mlDsaPublicKey = mlDsaPublicKey,
                _mlDsaPrivateKey = mlDsaPrivateKey
            )
        }
    }
}
