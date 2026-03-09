package my.ssdid.drive.crypto

import android.util.Base64
import my.ssdid.drive.domain.model.PublicKeys
import java.security.MessageDigest
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Handles key encapsulation for sharing.
 *
 * When sharing a file or folder, we need to:
 * 1. Encapsulate a shared secret using the recipient's public keys
 * 2. Derive a wrapping key from the shared secret
 * 3. Wrap the DEK/KEK with the derived key
 * 4. Sign the share grant
 *
 * The recipient can then:
 * 1. Decapsulate the shared secret using their private keys
 * 2. Derive the same wrapping key
 * 3. Unwrap the DEK/KEK
 * 4. Verify the signature
 */
@Singleton
class KeyEncapsulation @Inject constructor(
    private val cryptoManager: CryptoManager,
    private val keyManager: KeyManager
) {
    // ==================== Simple Encapsulate / Decapsulate ====================

    /**
     * Encapsulate a folder key for a recipient using their public KEM key.
     *
     * Performs KEM encapsulation to establish a shared secret, derives a wrapping
     * key via HKDF, and wraps the folder key with AES-GCM.
     *
     * The algorithm used (KAZ-KEM, ML-KEM, or HYBRID) is determined by the
     * tenant's [CryptoConfig].
     *
     * @param folderKey The folder KEK to encapsulate (32 bytes)
     * @param recipientPublicKeys Recipient's public keys
     * @return EncapsulationResult containing the wrapped key and KEM ciphertexts
     */
    fun encapsulate(
        folderKey: ByteArray,
        recipientPublicKeys: PublicKeys
    ): EncapsulationResult {
        return encapsulateKey(
            key = folderKey,
            recipientPublicKeys = recipientPublicKeys,
            resourceType = "folder-key",
            resourceId = "",
            permission = "owner"
        )
    }

    /**
     * Decapsulate a folder key from an encapsulation result.
     *
     * Performs KEM decapsulation using the user's private key, derives the
     * unwrapping key via HKDF, and unwraps the folder key.
     *
     * @param wrappedKey Base64-encoded wrapped folder key
     * @param kemCiphertext Base64-encoded KEM ciphertext
     * @param mlKemCiphertext Base64-encoded ML-KEM ciphertext (for HYBRID mode)
     * @return The decapsulated folder key (32 bytes)
     */
    fun decapsulate(
        wrappedKey: String,
        kemCiphertext: String,
        mlKemCiphertext: String? = null
    ): ByteArray {
        return decapsulateSharedKey(
            wrappedKey = wrappedKey,
            kemCiphertext = kemCiphertext,
            mlKemCiphertext = mlKemCiphertext
        )
    }

    /**
     * Result of encapsulating a key for a recipient.
     */
    data class EncapsulationResult(
        val wrappedKey: String,          // Base64-encoded wrapped DEK/KEK
        val kemCiphertext: String,        // Base64-encoded KAZ-KEM ciphertext
        val mlKemCiphertext: String?,     // Base64-encoded ML-KEM ciphertext (for NIST/HYBRID)
        val signature: String             // Base64-encoded signature
    )

    /**
     * Encapsulate a DEK for sharing a file with a recipient.
     *
     * @param dek The Data Encryption Key to share
     * @param recipientPublicKeys Recipient's public keys
     * @param fileId File ID (included in signature)
     * @param permission Permission level (included in signature)
     * @return EncapsulationResult with wrapped key and ciphertexts
     */
    fun encapsulateForFileShare(
        dek: ByteArray,
        recipientPublicKeys: PublicKeys,
        fileId: String,
        permission: String
    ): EncapsulationResult {
        return encapsulateKey(
            key = dek,
            recipientPublicKeys = recipientPublicKeys,
            resourceType = "file",
            resourceId = fileId,
            permission = permission
        )
    }

    /**
     * Encapsulate a KEK for sharing a folder with a recipient.
     *
     * @param kek The Key Encryption Key to share
     * @param recipientPublicKeys Recipient's public keys
     * @param folderId Folder ID (included in signature)
     * @param permission Permission level (included in signature)
     * @param recursive Whether the share is recursive (included in signature)
     * @return EncapsulationResult with wrapped key and ciphertexts
     */
    fun encapsulateForFolderShare(
        kek: ByteArray,
        recipientPublicKeys: PublicKeys,
        folderId: String,
        permission: String,
        recursive: Boolean
    ): EncapsulationResult {
        return encapsulateKey(
            key = kek,
            recipientPublicKeys = recipientPublicKeys,
            resourceType = "folder",
            resourceId = folderId,
            permission = permission,
            recursive = recursive
        )
    }

    /**
     * Core key encapsulation logic.
     */
    private fun encapsulateKey(
        key: ByteArray,
        recipientPublicKeys: PublicKeys,
        resourceType: String,
        resourceId: String,
        permission: String,
        recursive: Boolean? = null
    ): EncapsulationResult {
        val config = cryptoManager.cryptoConfig
        val keys = keyManager.getUnlockedKeys()

        // Encapsulate shared secret based on tenant algorithm
        val (sharedSecret, kazCiphertext, mlKemCiphertext) = when (config.getAlgorithm()) {
            PqcAlgorithm.KAZ -> {
                val (secret, ct) = cryptoManager.kazKemEncapsulate(recipientPublicKeys.kem)
                Triple(secret, ct, null)
            }
            PqcAlgorithm.NIST -> {
                val mlKemPk = recipientPublicKeys.mlKem
                    ?: throw IllegalStateException("Recipient ML-KEM public key required for NIST mode")
                val (secret, enc) = cryptoManager.mlKemEncapsulate(mlKemPk)
                Triple(secret, enc, null) // For NIST-only, we put ML-KEM in kemCiphertext
            }
            PqcAlgorithm.HYBRID -> {
                val mlKemPk = recipientPublicKeys.mlKem
                    ?: throw IllegalStateException("Recipient ML-KEM public key required for HYBRID mode")
                val (secret, kazCt, mlKemEnc) = cryptoManager.combinedKemEncapsulate(
                    recipientPublicKeys.kem,
                    mlKemPk
                )
                Triple(secret, kazCt, mlKemEnc)
            }
        }

        // Derive wrapping key from shared secret
        val wrapKey = cryptoManager.hkdfProvider.deriveKey(
            ikm = sharedSecret,
            salt = "SsdidDrive-ShareKey".toByteArray(),
            info = "share-wrap".toByteArray(),
            length = 32
        )

        // Wrap the key
        val wrappedKey = cryptoManager.wrapKey(key, wrapKey)

        // Create signature message
        val signatureMessage = createSignatureMessage(
            wrappedKey = wrappedKey,
            kemCiphertext = kazCiphertext,
            mlKemCiphertext = mlKemCiphertext,
            resourceType = resourceType,
            resourceId = resourceId,
            permission = permission,
            recursive = recursive
        )

        // Sign based on algorithm
        val signature = when (config.getAlgorithm()) {
            PqcAlgorithm.KAZ -> {
                cryptoManager.kazSign(signatureMessage, keys.kazSignPrivateKey)
            }
            PqcAlgorithm.NIST -> {
                cryptoManager.mlDsaSign(signatureMessage, keys.mlDsaPrivateKey)
            }
            PqcAlgorithm.HYBRID -> {
                cryptoManager.combinedSign(signatureMessage, keys.kazSignPrivateKey, keys.mlDsaPrivateKey)
            }
        }

        // Zeroize sensitive data
        cryptoManager.zeroize(sharedSecret)
        cryptoManager.zeroize(wrapKey)

        return EncapsulationResult(
            wrappedKey = Base64.encodeToString(wrappedKey, Base64.NO_WRAP),
            kemCiphertext = Base64.encodeToString(kazCiphertext, Base64.NO_WRAP),
            mlKemCiphertext = mlKemCiphertext?.let { Base64.encodeToString(it, Base64.NO_WRAP) },
            signature = Base64.encodeToString(signature, Base64.NO_WRAP)
        )
    }

    /**
     * Decapsulate a shared key from a received share.
     *
     * @param wrappedKey Base64-encoded wrapped key
     * @param kemCiphertext Base64-encoded KEM ciphertext
     * @param mlKemCiphertext Base64-encoded ML-KEM ciphertext (for HYBRID mode)
     * @return The unwrapped DEK/KEK
     */
    fun decapsulateSharedKey(
        wrappedKey: String,
        kemCiphertext: String,
        mlKemCiphertext: String?
    ): ByteArray {
        val config = cryptoManager.cryptoConfig
        val keys = keyManager.getUnlockedKeys()

        val kemCt = Base64.decode(kemCiphertext, Base64.NO_WRAP)
        val wrappedKeyBytes = Base64.decode(wrappedKey, Base64.NO_WRAP)
        val mlKemCt = mlKemCiphertext?.let { Base64.decode(it, Base64.NO_WRAP) }

        // Decapsulate shared secret based on algorithm
        val sharedSecret = when (config.getAlgorithm()) {
            PqcAlgorithm.KAZ -> {
                cryptoManager.kazKemDecapsulate(kemCt, keys.kazKemPrivateKey)
            }
            PqcAlgorithm.NIST -> {
                // For NIST mode, kemCiphertext contains ML-KEM ciphertext
                cryptoManager.mlKemDecapsulate(kemCt, keys.mlKemPrivateKey)
            }
            PqcAlgorithm.HYBRID -> {
                val mlCt = mlKemCt
                    ?: throw IllegalStateException("ML-KEM ciphertext required for HYBRID mode")
                cryptoManager.combinedKemDecapsulate(
                    kemCt,
                    mlCt,
                    keys.kazKemPrivateKey,
                    keys.mlKemPrivateKey
                )
            }
        }

        // Derive unwrapping key
        val unwrapKey = cryptoManager.hkdfProvider.deriveKey(
            ikm = sharedSecret,
            salt = "SsdidDrive-ShareKey".toByteArray(),
            info = "share-wrap".toByteArray(),
            length = 32
        )

        // Unwrap the key
        val key = cryptoManager.unwrapKey(wrappedKeyBytes, unwrapKey)

        // Zeroize sensitive data
        cryptoManager.zeroize(sharedSecret)
        cryptoManager.zeroize(unwrapKey)

        return key
    }

    /**
     * Verify a share signature.
     *
     * @param wrappedKey Base64-encoded wrapped key
     * @param kemCiphertext Base64-encoded KEM ciphertext
     * @param mlKemCiphertext Base64-encoded ML-KEM ciphertext (optional)
     * @param signature Base64-encoded signature
     * @param grantorPublicKeys Grantor's public keys
     * @param resourceType "file" or "folder"
     * @param resourceId File or folder ID
     * @param permission Permission level
     * @param recursive Whether share is recursive (for folders)
     * @return true if signature is valid
     */
    fun verifyShareSignature(
        wrappedKey: String,
        kemCiphertext: String,
        mlKemCiphertext: String?,
        signature: String,
        grantorPublicKeys: PublicKeys,
        resourceType: String,
        resourceId: String,
        permission: String,
        recursive: Boolean? = null
    ): Boolean {
        val config = cryptoManager.cryptoConfig

        val wrappedKeyBytes = Base64.decode(wrappedKey, Base64.NO_WRAP)
        val kemCt = Base64.decode(kemCiphertext, Base64.NO_WRAP)
        val mlKemCt = mlKemCiphertext?.let { Base64.decode(it, Base64.NO_WRAP) }
        val signatureBytes = Base64.decode(signature, Base64.NO_WRAP)

        // Recreate signature message
        val signatureMessage = createSignatureMessage(
            wrappedKey = wrappedKeyBytes,
            kemCiphertext = kemCt,
            mlKemCiphertext = mlKemCt,
            resourceType = resourceType,
            resourceId = resourceId,
            permission = permission,
            recursive = recursive
        )

        // Verify based on algorithm
        return when (config.getAlgorithm()) {
            PqcAlgorithm.KAZ -> {
                cryptoManager.kazVerify(signatureMessage, signatureBytes, grantorPublicKeys.sign)
            }
            PqcAlgorithm.NIST -> {
                val mlDsaPk = grantorPublicKeys.mlDsa
                    ?: throw IllegalStateException("Grantor ML-DSA public key required for NIST mode")
                cryptoManager.mlDsaVerify(signatureMessage, signatureBytes, mlDsaPk)
            }
            PqcAlgorithm.HYBRID -> {
                val mlDsaPk = grantorPublicKeys.mlDsa
                    ?: throw IllegalStateException("Grantor ML-DSA public key required for HYBRID mode")
                cryptoManager.combinedVerify(signatureMessage, signatureBytes, grantorPublicKeys.sign, mlDsaPk)
            }
        }
    }

    /**
     * Create a signature for updating share permission.
     *
     * @param shareId Share ID
     * @param newPermission New permission level
     * @return Base64-encoded signature
     */
    fun signPermissionUpdate(shareId: String, newPermission: String): String {
        val config = cryptoManager.cryptoConfig
        val keys = keyManager.getUnlockedKeys()

        // Create message to sign
        val message = "permission:$shareId:$newPermission".toByteArray()
        val digest = MessageDigest.getInstance("SHA-256")
        val messageHash = digest.digest(message)

        val signature = when (config.getAlgorithm()) {
            PqcAlgorithm.KAZ -> {
                cryptoManager.kazSign(messageHash, keys.kazSignPrivateKey)
            }
            PqcAlgorithm.NIST -> {
                cryptoManager.mlDsaSign(messageHash, keys.mlDsaPrivateKey)
            }
            PqcAlgorithm.HYBRID -> {
                cryptoManager.combinedSign(messageHash, keys.kazSignPrivateKey, keys.mlDsaPrivateKey)
            }
        }

        return Base64.encodeToString(signature, Base64.NO_WRAP)
    }

    /**
     * Create signature message for share grant.
     */
    private fun createSignatureMessage(
        wrappedKey: ByteArray,
        kemCiphertext: ByteArray,
        mlKemCiphertext: ByteArray?,
        resourceType: String,
        resourceId: String,
        permission: String,
        recursive: Boolean?
    ): ByteArray {
        val digest = MessageDigest.getInstance("SHA-256")
        digest.update(wrappedKey)
        digest.update(kemCiphertext)
        mlKemCiphertext?.let { digest.update(it) }
        digest.update(resourceType.toByteArray())
        digest.update(resourceId.toByteArray())
        digest.update(permission.toByteArray())
        recursive?.let { digest.update(if (it) byteArrayOf(1) else byteArrayOf(0)) }
        return digest.digest()
    }
}
