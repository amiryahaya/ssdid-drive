package my.ssdid.drive.crypto

import android.util.Base64
import androidx.collection.LruCache
import com.google.gson.Gson
import my.ssdid.drive.domain.model.FolderMetadata
import java.security.MessageDigest
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Manages folder Key Encryption Keys (KEKs).
 *
 * Each folder has its own KEK that:
 * - Wraps file DEKs within the folder
 * - Wraps child folder KEKs
 *
 * The folder's KEK can be obtained via:
 * - owner_wrapped_kek/owner_kem_ciphertext: Direct owner access (always available)
 * - wrapped_kek/kem_ciphertext: Via parent KEK hierarchy
 *
 * This manager handles:
 * - Decapsulating KEKs using the user's private keys
 * - Caching decrypted KEKs in memory with LRU eviction
 * - Encrypting/decrypting folder metadata
 */
@Singleton
class FolderKeyManager @Inject constructor(
    private val cryptoManager: CryptoManager,
    private val keyManager: KeyManager
) {
    private val gson = Gson()

    companion object {
        // Maximum number of KEKs to cache (32 bytes each = ~3.2KB max)
        private const val MAX_CACHED_KEKS = 100
        private const val METADATA_NONCE_SIZE = 12
        private val FOLDER_METADATA_AAD = "folder-metadata".toByteArray(Charsets.UTF_8)
    }

    /**
     * LRU cache of decrypted KEKs by folder ID.
     * Uses secure removal callback to zeroize evicted KEKs.
     * Cleared on logout.
     */
    private val kekCache = object : LruCache<String, ByteArray>(MAX_CACHED_KEKS) {
        override fun entryRemoved(evicted: Boolean, key: String, oldValue: ByteArray, newValue: ByteArray?) {
            // SECURITY: Zeroize evicted KEKs
            cryptoManager.zeroize(oldValue)
        }

        override fun sizeOf(key: String, value: ByteArray): Int {
            // Each entry counts as 1 (we're limiting by count, not size)
            return 1
        }
    }

    /**
     * Clear all cached KEKs (call on logout).
     */
    @Synchronized
    fun clearCache() {
        // Manually zeroize all remaining entries before eviction
        kekCache.snapshot().values.forEach { cryptoManager.zeroize(it) }
        kekCache.evictAll()
    }

    /**
     * Get the cached KEK for a folder, if available.
     */
    @Synchronized
    fun getCachedKek(folderId: String): ByteArray? {
        return kekCache.get(folderId)
    }

    /**
     * Cache a KEK for a folder.
     */
    @Synchronized
    fun cacheKek(folderId: String, kek: ByteArray) {
        kekCache.put(folderId, kek.copyOf())
    }

    /**
     * Get cache statistics for monitoring.
     */
    fun getCacheStats(): CacheStats {
        return CacheStats(
            size = kekCache.size(),
            maxSize = kekCache.maxSize(),
            hitCount = kekCache.hitCount(),
            missCount = kekCache.missCount()
        )
    }

    data class CacheStats(
        val size: Int,
        val maxSize: Int,
        val hitCount: Int,
        val missCount: Int
    ) {
        val hitRate: Float get() = if (hitCount + missCount > 0) {
            hitCount.toFloat() / (hitCount + missCount)
        } else 0f
    }

    /**
     * Decrypt a folder's KEK using the owner's direct access.
     *
     * Uses owner_kem_ciphertext to decapsulate a shared secret, then
     * uses that to unwrap owner_wrapped_kek to get the KEK.
     *
     * @param folderId Folder ID for caching
     * @param ownerKemCiphertext Base64-encoded KEM ciphertext for owner
     * @param ownerWrappedKek Base64-encoded wrapped KEK for owner
     * @param ownerMlKemCiphertext Base64-encoded ML-KEM ciphertext (for NIST/HYBRID)
     * @return Decrypted KEK
     */
    fun decryptFolderKek(
        folderId: String,
        ownerKemCiphertext: String,
        ownerWrappedKek: String,
        ownerMlKemCiphertext: String? = null
    ): ByteArray {
        // Check cache first (using synchronized method)
        getCachedKek(folderId)?.let { return it }

        val keys = keyManager.getUnlockedKeys()
        val config = cryptoManager.cryptoConfig

        // Decode from Base64
        val kemCiphertext = Base64.decode(ownerKemCiphertext, Base64.NO_WRAP)
        val wrappedKek = Base64.decode(ownerWrappedKek, Base64.NO_WRAP)
        val mlKemCiphertext = ownerMlKemCiphertext?.let { Base64.decode(it, Base64.NO_WRAP) }

        // Decapsulate shared secret based on algorithm
        val sharedSecret = when (config.getAlgorithm()) {
            PqcAlgorithm.KAZ -> {
                cryptoManager.kazKemDecapsulate(kemCiphertext, keys.kazKemPrivateKey)
            }
            PqcAlgorithm.NIST -> {
                // For NIST mode, kem_ciphertext contains ML-KEM ciphertext
                val mlCt = mlKemCiphertext ?: kemCiphertext
                cryptoManager.mlKemDecapsulate(mlCt, keys.mlKemPrivateKey)
            }
            PqcAlgorithm.HYBRID -> {
                // For hybrid, we need both ciphertexts
                val mlCt = mlKemCiphertext
                    ?: throw IllegalStateException("ML-KEM ciphertext required for HYBRID mode")
                cryptoManager.combinedKemDecapsulate(
                    kemCiphertext,
                    mlCt,
                    keys.kazKemPrivateKey,
                    keys.mlKemPrivateKey
                )
            }
        }

        // Derive unwrapping key from shared secret
        val unwrapKey = cryptoManager.hkdfProvider.deriveKey(
            ikm = sharedSecret,
            salt = "SsdidDrive-FolderKEK".toByteArray(),
            info = "kek-unwrap".toByteArray(),
            length = 32
        )

        // Unwrap the KEK
        val kek = cryptoManager.unwrapKey(wrappedKek, unwrapKey)

        // Cache and return
        cacheKek(folderId, kek)

        // Zeroize intermediate values
        cryptoManager.zeroize(sharedSecret)
        cryptoManager.zeroize(unwrapKey)

        return kek
    }

    /**
     * Decrypt a child folder's KEK using the parent's KEK.
     *
     * @param folderId Child folder ID for caching
     * @param parentKek Parent folder's decrypted KEK
     * @param wrappedKek Base64-encoded wrapped KEK
     * @return Decrypted KEK
     */
    fun decryptChildFolderKek(
        folderId: String,
        parentKek: ByteArray,
        wrappedKek: String
    ): ByteArray {
        // Check cache first (using synchronized method)
        getCachedKek(folderId)?.let { return it }

        // Decode and unwrap
        val wrapped = Base64.decode(wrappedKek, Base64.NO_WRAP)
        val kek = cryptoManager.unwrapKey(wrapped, parentKek)

        // Cache and return
        cacheKek(folderId, kek)
        return kek
    }

    /**
     * Decrypt folder metadata using the folder's KEK.
     *
     * @param encryptedMetadata Base64-encoded encrypted metadata
     * @param kek Folder's decrypted KEK
     * @return Decrypted FolderMetadata
     */
    fun decryptMetadata(encryptedMetadata: String, kek: ByteArray): FolderMetadata {
        val encrypted = Base64.decode(encryptedMetadata, Base64.NO_WRAP)
        val decrypted = try {
            cryptoManager.decryptAesGcmWithAad(
                ciphertext = encrypted,
                key = kek,
                aad = FOLDER_METADATA_AAD
            )
        } catch (e: Exception) {
            // Backward compatibility for metadata encrypted without AAD.
            cryptoManager.decryptAesGcm(encrypted, kek)
        }
        val json = String(decrypted, Charsets.UTF_8)
        return gson.fromJson(json, FolderMetadata::class.java)
    }

    /**
     * Encrypt folder metadata using the folder's KEK.
     *
     * @param metadata FolderMetadata to encrypt
     * @param kek Folder's KEK
     * @return Base64-encoded encrypted metadata
     */
    fun encryptMetadata(metadata: FolderMetadata, kek: ByteArray): String {
        val json = gson.toJson(metadata)
        val encrypted = cryptoManager.encryptAesGcmWithAad(
            plaintext = json.toByteArray(),
            key = kek,
            aad = FOLDER_METADATA_AAD
        )
        return Base64.encodeToString(encrypted, Base64.NO_WRAP)
    }

    /**
     * Result of creating folder encryption data.
     */
    data class FolderEncryptionData(
        val kek: ByteArray,
        val wrappedKek: String,
        val kemCiphertext: String,
        val ownerWrappedKek: String,
        val ownerKemCiphertext: String,
        val mlKemCiphertext: String?,
        val ownerMlKemCiphertext: String?,
        val encryptedMetadata: String,
        val metadataNonce: String
    )

    /**
     * Create encryption data for a new root folder.
     *
     * Generates a new KEK, wraps it with the user's public keys, and encrypts metadata.
     *
     * @param name Folder name
     * @return FolderEncryptionData with all required fields
     */
    fun createRootFolderEncryption(name: String): FolderEncryptionData {
        val keys = keyManager.getUnlockedKeys()
        val config = cryptoManager.cryptoConfig

        // Generate folder KEK
        val kek = cryptoManager.generateKey()

        // Encapsulate and wrap KEK based on algorithm
        val (wrappedKek, kemCiphertext, mlKemCiphertext) = encapsulateAndWrapKek(
            kek = kek,
            kazPublicKey = keys.kazKemPublicKey,
            mlKemPublicKey = keys.mlKemPublicKey
        )

        // For root folder, owner access is the same
        val metadata = FolderMetadata(name = name)
        val encryptedMetadata = encryptMetadata(metadata, kek)
        val metadataNonce = extractMetadataNonce(encryptedMetadata)

        return FolderEncryptionData(
            kek = kek,
            wrappedKek = wrappedKek,
            kemCiphertext = kemCiphertext,
            ownerWrappedKek = wrappedKek,
            ownerKemCiphertext = kemCiphertext,
            mlKemCiphertext = mlKemCiphertext,
            ownerMlKemCiphertext = mlKemCiphertext,
            encryptedMetadata = encryptedMetadata,
            metadataNonce = metadataNonce
        )
    }

    /**
     * Create encryption data for a new child folder.
     *
     * Generates a new KEK, wraps it with both the parent KEK and owner's public keys.
     *
     * @param name Folder name
     * @param parentKek Parent folder's decrypted KEK
     * @return FolderEncryptionData with all required fields
     */
    fun createChildFolderEncryption(name: String, parentKek: ByteArray): FolderEncryptionData {
        val keys = keyManager.getUnlockedKeys()

        // Generate folder KEK
        val kek = cryptoManager.generateKey()

        // Wrap KEK with parent's KEK (simple AES wrap for hierarchy)
        val wrappedKek = Base64.encodeToString(
            cryptoManager.wrapKey(kek, parentKek),
            Base64.NO_WRAP
        )

        // For hierarchy traversal, we don't need KEM (it's AES-wrapped by parent)
        // But we still need owner access via PQC
        val (ownerWrappedKek, ownerKemCiphertext, ownerMlKemCiphertext) = encapsulateAndWrapKek(
            kek = kek,
            kazPublicKey = keys.kazKemPublicKey,
            mlKemPublicKey = keys.mlKemPublicKey
        )

        val metadata = FolderMetadata(name = name)
        val encryptedMetadata = encryptMetadata(metadata, kek)
        val metadataNonce = extractMetadataNonce(encryptedMetadata)

        return FolderEncryptionData(
            kek = kek,
            wrappedKek = wrappedKek,
            kemCiphertext = "", // Not used for child folders (AES-wrapped by parent)
            ownerWrappedKek = ownerWrappedKek,
            ownerKemCiphertext = ownerKemCiphertext,
            mlKemCiphertext = null,
            ownerMlKemCiphertext = ownerMlKemCiphertext,
            encryptedMetadata = encryptedMetadata,
            metadataNonce = metadataNonce
        )
    }

    /**
     * Encapsulate a shared secret and wrap a KEK with it.
     *
     * @return Triple of (wrappedKek, kemCiphertext, mlKemCiphertext?)
     */
    private fun encapsulateAndWrapKek(
        kek: ByteArray,
        kazPublicKey: ByteArray,
        mlKemPublicKey: ByteArray
    ): Triple<String, String, String?> {
        val config = cryptoManager.cryptoConfig

        return when (config.getAlgorithm()) {
            PqcAlgorithm.KAZ -> {
                val (sharedSecret, ciphertext) = cryptoManager.kazKemEncapsulate(kazPublicKey)
                val wrapKey = deriveWrapKey(sharedSecret)
                val wrapped = cryptoManager.wrapKey(kek, wrapKey)
                cryptoManager.zeroize(sharedSecret)
                cryptoManager.zeroize(wrapKey)

                Triple(
                    Base64.encodeToString(wrapped, Base64.NO_WRAP),
                    Base64.encodeToString(ciphertext, Base64.NO_WRAP),
                    null
                )
            }
            PqcAlgorithm.NIST -> {
                val (sharedSecret, encapsulation) = cryptoManager.mlKemEncapsulate(mlKemPublicKey)
                val wrapKey = deriveWrapKey(sharedSecret)
                val wrapped = cryptoManager.wrapKey(kek, wrapKey)
                cryptoManager.zeroize(sharedSecret)
                cryptoManager.zeroize(wrapKey)

                Triple(
                    Base64.encodeToString(wrapped, Base64.NO_WRAP),
                    Base64.encodeToString(encapsulation, Base64.NO_WRAP),
                    null
                )
            }
            PqcAlgorithm.HYBRID -> {
                val (sharedSecret, kazCt, mlKemEnc) = cryptoManager.combinedKemEncapsulate(
                    kazPublicKey,
                    mlKemPublicKey
                )
                val wrapKey = deriveWrapKey(sharedSecret)
                val wrapped = cryptoManager.wrapKey(kek, wrapKey)
                cryptoManager.zeroize(sharedSecret)
                cryptoManager.zeroize(wrapKey)

                Triple(
                    Base64.encodeToString(wrapped, Base64.NO_WRAP),
                    Base64.encodeToString(kazCt, Base64.NO_WRAP),
                    Base64.encodeToString(mlKemEnc, Base64.NO_WRAP)
                )
            }
        }
    }

    /**
     * Derive a wrapping key from a shared secret.
     */
    private fun deriveWrapKey(sharedSecret: ByteArray): ByteArray {
        return cryptoManager.hkdfProvider.deriveKey(
            ikm = sharedSecret,
            salt = "SsdidDrive-FolderKEK".toByteArray(),
            info = "kek-unwrap".toByteArray(),
            length = 32
        )
    }

    /**
     * Result of re-wrapping a KEK for a new parent.
     */
    data class KekRewrapResult(
        val wrappedKek: String,
        val kemCiphertext: String?
    )

    /**
     * Re-wrap a folder's KEK for a new parent folder (for move operation).
     *
     * When moving a folder to a new parent, its KEK needs to be re-wrapped
     * with the new parent's KEK to maintain the hierarchy.
     *
     * @param kek The folder's decrypted KEK
     * @param newParentKek The new parent folder's KEK
     * @return KekRewrapResult with the new wrapped KEK
     */
    fun rewrapKekForParent(kek: ByteArray, newParentKek: ByteArray): KekRewrapResult {
        // Wrap the KEK with the new parent's KEK (simple AES wrap for hierarchy)
        val wrapped = cryptoManager.wrapKey(kek, newParentKek)
        val wrappedKek = Base64.encodeToString(wrapped, Base64.NO_WRAP)

        // For hierarchy traversal, we use AES key wrap (no KEM ciphertext needed)
        return KekRewrapResult(
            wrappedKek = wrappedKek,
            kemCiphertext = null
        )
    }

    /**
     * Extract the AES-GCM nonce from encrypted metadata.
     */
    fun extractMetadataNonce(encryptedMetadata: String): String {
        val decoded = Base64.decode(encryptedMetadata, Base64.NO_WRAP)
        require(decoded.size >= METADATA_NONCE_SIZE) { "Encrypted metadata too short for nonce" }
        val nonce = decoded.copyOfRange(0, METADATA_NONCE_SIZE)
        return Base64.encodeToString(nonce, Base64.NO_WRAP)
    }

    /**
     * Create a signature over folder state.
     */
    fun createFolderSignature(
        folderId: String?,
        parentId: String?,
        encryptedMetadata: String,
        metadataNonce: String?,
        ownerWrappedKek: String,
        ownerKemCiphertext: String,
        ownerMlKemCiphertext: String?,
        wrappedKek: String,
        kemCiphertext: String?,
        mlKemCiphertext: String?
    ): String {
        val keys = keyManager.getUnlockedKeys()
        val message = buildFolderSignatureMessage(
            folderId = folderId,
            parentId = parentId,
            encryptedMetadata = encryptedMetadata,
            metadataNonce = metadataNonce,
            ownerWrappedKek = ownerWrappedKek,
            ownerKemCiphertext = ownerKemCiphertext,
            ownerMlKemCiphertext = ownerMlKemCiphertext,
            wrappedKek = wrappedKek,
            kemCiphertext = kemCiphertext,
            mlKemCiphertext = mlKemCiphertext
        )
        val signature = cryptoManager.tenantSign(
            message = message,
            kazPrivateKey = keys.kazSignPrivateKey,
            mlDsaPrivateKey = keys.mlDsaPrivateKey
        ).signature
        return Base64.encodeToString(signature, Base64.NO_WRAP)
    }

    /**
     * Verify a folder signature before trusting metadata or key access.
     */
    fun verifyFolderSignature(
        folderId: String?,
        parentId: String?,
        encryptedMetadata: String,
        metadataNonce: String?,
        ownerWrappedKek: String,
        ownerKemCiphertext: String,
        ownerMlKemCiphertext: String?,
        wrappedKek: String,
        kemCiphertext: String?,
        mlKemCiphertext: String?,
        signature: String,
        ownerPublicKeys: my.ssdid.drive.domain.model.PublicKeys
    ): Boolean {
        val message = buildFolderSignatureMessage(
            folderId = folderId,
            parentId = parentId,
            encryptedMetadata = encryptedMetadata,
            metadataNonce = metadataNonce,
            ownerWrappedKek = ownerWrappedKek,
            ownerKemCiphertext = ownerKemCiphertext,
            ownerMlKemCiphertext = ownerMlKemCiphertext,
            wrappedKek = wrappedKek,
            kemCiphertext = kemCiphertext,
            mlKemCiphertext = mlKemCiphertext
        )
        val signatureBytes = Base64.decode(signature, Base64.NO_WRAP)
        return try {
            cryptoManager.tenantVerify(
                message = message,
                signature = signatureBytes,
                kazPublicKey = ownerPublicKeys.sign,
                mlDsaPublicKey = ownerPublicKeys.mlDsa,
                isCombined = false
            )
        } catch (e: Exception) {
            false
        }
    }

    private fun buildFolderSignatureMessage(
        folderId: String?,
        parentId: String?,
        encryptedMetadata: String,
        metadataNonce: String?,
        ownerWrappedKek: String,
        ownerKemCiphertext: String,
        ownerMlKemCiphertext: String?,
        wrappedKek: String,
        kemCiphertext: String?,
        mlKemCiphertext: String?
    ): ByteArray {
        val digest = MessageDigest.getInstance("SHA-256")
        folderId?.let { digest.update(it.toByteArray()) }
        parentId?.let { digest.update(it.toByteArray()) }
        digest.update(Base64.decode(encryptedMetadata, Base64.NO_WRAP))
        val resolvedNonce = metadataNonce ?: extractMetadataNonce(encryptedMetadata)
        digest.update(Base64.decode(resolvedNonce, Base64.NO_WRAP))
        digest.update(Base64.decode(ownerWrappedKek, Base64.NO_WRAP))
        digest.update(Base64.decode(ownerKemCiphertext, Base64.NO_WRAP))
        ownerMlKemCiphertext?.takeIf { it.isNotBlank() }?.let {
            digest.update(Base64.decode(it, Base64.NO_WRAP))
        }
        digest.update(Base64.decode(wrappedKek, Base64.NO_WRAP))
        kemCiphertext?.takeIf { it.isNotBlank() }?.let {
            digest.update(Base64.decode(it, Base64.NO_WRAP))
        }
        mlKemCiphertext?.takeIf { it.isNotBlank() }?.let {
            digest.update(Base64.decode(it, Base64.NO_WRAP))
        }
        return digest.digest()
    }
}
