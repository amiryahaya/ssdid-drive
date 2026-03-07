package my.ssdid.drive.crypto

import javax.inject.Inject
import javax.inject.Singleton

/**
 * Holds user key material received from the SSDID Wallet.
 *
 * The drive client no longer generates identity keys -- that is the wallet's
 * responsibility.  This class simply stores the key bundle in memory so that
 * file-encryption components (FileEncryptor, FolderKeyManager, KeyEncapsulation,
 * etc.) can access the KEM and signing keys needed for file operations.
 *
 * Keys are set after the wallet returns them via deep-link callback and
 * cleared on logout / lock.
 */
@Singleton
class KeyManager @Inject constructor() {

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
     * Set the unlocked keys received from the SSDID Wallet.
     */
    fun setUnlockedKeys(keys: KeyBundle) {
        unlockedKeys = keys
    }

    /**
     * Clear unlocked keys from memory.
     *
     * SECURITY: Uses secure multi-pass zeroization to clear all key material
     * from memory.
     */
    fun clearUnlockedKeys() {
        unlockedKeys?.zeroize()
        unlockedKeys = null
    }
}

/**
 * Bundle of user keys needed for file-level crypto operations.
 *
 * Contains KEM keys (for folder KEK wrapping / share encapsulation) and
 * signing keys (for file & folder signatures).  The master key is included
 * for backward-compatible key-wrapping flows.
 *
 * SECURITY: This is intentionally NOT a data class to prevent accidental
 * key leaks via .copy().  Call [zeroize] when done with the key bundle.
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
         * for performance.  Caller should not retain references to the arrays.
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
