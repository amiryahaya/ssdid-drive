package com.securesharing.crypto

import android.util.Base64
import com.securesharing.domain.model.PublicKeys
import java.security.MessageDigest
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Manages cryptographic operations for key recovery.
 *
 * Handles:
 * - Encrypting Shamir shares for trustees
 * - Decrypting shares as a trustee
 * - Re-encrypting shares for recovery requester's new keys
 * - Signing and verifying share operations
 */
@Singleton
class RecoveryKeyManager @Inject constructor(
    private val cryptoManager: CryptoManager,
    private val keyManager: KeyManager,
    private val shamirSecretSharing: ShamirSecretSharing
) {
    /**
     * Result of encrypting a share for a trustee.
     */
    data class EncryptedShareResult(
        val encryptedShare: String,      // Base64-encoded encrypted share
        val kemCiphertext: String,        // Base64-encoded KAZ-KEM ciphertext
        val mlKemCiphertext: String?,     // Base64-encoded ML-KEM ciphertext (for HYBRID)
        val signature: String             // Base64-encoded signature
    )

    /**
     * Result of splitting the master key.
     */
    data class SplitResult(
        val shares: List<ShamirSecretSharing.Share>,
        val threshold: Int,
        val total: Int
    )

    /**
     * Split the master key using Shamir secret sharing.
     *
     * @param masterKey The master key to split
     * @param threshold Minimum shares required to reconstruct (k)
     * @param totalShares Total number of shares to create (n)
     * @return SplitResult containing all shares
     */
    fun splitMasterKey(
        masterKey: ByteArray,
        threshold: Int,
        totalShares: Int
    ): SplitResult {
        val shares = shamirSecretSharing.split(masterKey, threshold, totalShares)
        return SplitResult(shares, threshold, totalShares)
    }

    /**
     * Encrypt a share for a trustee.
     *
     * @param share The Shamir share to encrypt
     * @param trusteePublicKeys Trustee's public keys
     * @param grantorId The grantor's user ID (for signature)
     * @param trusteeId The trustee's user ID (for signature)
     * @return EncryptedShareResult
     */
    fun encryptShareForTrustee(
        share: ShamirSecretSharing.Share,
        trusteePublicKeys: PublicKeys,
        grantorId: String,
        trusteeId: String
    ): EncryptedShareResult {
        val config = cryptoManager.cryptoConfig
        val keys = keyManager.getUnlockedKeys()

        // Serialize share: [index:1][data]
        val shareBytes = ByteArray(1 + share.data.size)
        shareBytes[0] = share.index.toByte()
        System.arraycopy(share.data, 0, shareBytes, 1, share.data.size)

        // Encapsulate shared secret based on algorithm
        val (sharedSecret, kazCiphertext, mlKemCiphertext) = when (config.getAlgorithm()) {
            PqcAlgorithm.KAZ -> {
                val (secret, ct) = cryptoManager.kazKemEncapsulate(trusteePublicKeys.kem)
                Triple(secret, ct, null)
            }
            PqcAlgorithm.NIST -> {
                val mlKemPk = trusteePublicKeys.mlKem
                    ?: throw IllegalStateException("Trustee ML-KEM public key required for NIST mode")
                val (secret, enc) = cryptoManager.mlKemEncapsulate(mlKemPk)
                Triple(secret, enc, null)
            }
            PqcAlgorithm.HYBRID -> {
                val mlKemPk = trusteePublicKeys.mlKem
                    ?: throw IllegalStateException("Trustee ML-KEM public key required for HYBRID mode")
                val (secret, kazCt, mlKemEnc) = cryptoManager.combinedKemEncapsulate(
                    trusteePublicKeys.kem,
                    mlKemPk
                )
                Triple(secret, kazCt, mlKemEnc)
            }
        }

        // Derive encryption key
        val encryptKey = cryptoManager.hkdfProvider.deriveKey(
            ikm = sharedSecret,
            salt = "SecureSharing-RecoveryShare".toByteArray(),
            info = "share-encrypt".toByteArray(),
            length = 32
        )

        // Encrypt the share
        val encryptedShare = cryptoManager.encryptAesGcm(shareBytes, encryptKey)

        // Create signature
        val signatureMessage = createShareSignatureMessage(
            encryptedShare = encryptedShare,
            kemCiphertext = kazCiphertext,
            mlKemCiphertext = mlKemCiphertext,
            grantorId = grantorId,
            trusteeId = trusteeId,
            shareIndex = share.index
        )

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
        cryptoManager.zeroize(encryptKey)

        return EncryptedShareResult(
            encryptedShare = Base64.encodeToString(encryptedShare, Base64.NO_WRAP),
            kemCiphertext = Base64.encodeToString(kazCiphertext, Base64.NO_WRAP),
            mlKemCiphertext = mlKemCiphertext?.let { Base64.encodeToString(it, Base64.NO_WRAP) },
            signature = Base64.encodeToString(signature, Base64.NO_WRAP)
        )
    }

    /**
     * Decrypt a share as a trustee.
     *
     * @param encryptedShare Base64-encoded encrypted share
     * @param kemCiphertext Base64-encoded KEM ciphertext
     * @param mlKemCiphertext Base64-encoded ML-KEM ciphertext (for HYBRID)
     * @return The decrypted Shamir share
     */
    fun decryptShareAsTrustee(
        encryptedShare: String,
        kemCiphertext: String,
        mlKemCiphertext: String?
    ): ShamirSecretSharing.Share {
        val config = cryptoManager.cryptoConfig
        val keys = keyManager.getUnlockedKeys()

        val encryptedBytes = Base64.decode(encryptedShare, Base64.NO_WRAP)
        val kemCt = Base64.decode(kemCiphertext, Base64.NO_WRAP)
        val mlKemCt = mlKemCiphertext?.let { Base64.decode(it, Base64.NO_WRAP) }

        // Decapsulate shared secret
        val sharedSecret = when (config.getAlgorithm()) {
            PqcAlgorithm.KAZ -> {
                cryptoManager.kazKemDecapsulate(kemCt, keys.kazKemPrivateKey)
            }
            PqcAlgorithm.NIST -> {
                cryptoManager.mlKemDecapsulate(kemCt, keys.mlKemPrivateKey)
            }
            PqcAlgorithm.HYBRID -> {
                val mlCt = mlKemCt
                    ?: throw IllegalStateException("ML-KEM ciphertext required for HYBRID mode")
                cryptoManager.combinedKemDecapsulate(kemCt, mlCt, keys.kazKemPrivateKey, keys.mlKemPrivateKey)
            }
        }

        // Derive decryption key
        val decryptKey = cryptoManager.hkdfProvider.deriveKey(
            ikm = sharedSecret,
            salt = "SecureSharing-RecoveryShare".toByteArray(),
            info = "share-encrypt".toByteArray(),
            length = 32
        )

        // Decrypt the share
        val shareBytes = cryptoManager.decryptAesGcm(encryptedBytes, decryptKey)

        // Zeroize sensitive data
        cryptoManager.zeroize(sharedSecret)
        cryptoManager.zeroize(decryptKey)

        // Parse share: [index:1][data]
        val index = shareBytes[0].toInt() and 0xFF
        val data = shareBytes.copyOfRange(1, shareBytes.size)

        return ShamirSecretSharing.Share(index, data)
    }

    /**
     * Re-encrypt a share for the recovery requester's new keys.
     *
     * Called by a trustee when approving a recovery request.
     *
     * @param share The decrypted Shamir share
     * @param requesterPublicKeys The requester's new public keys
     * @param requestId The recovery request ID
     * @param shareId The share ID
     * @return EncryptedShareResult for the requester
     */
    fun reencryptShareForRequester(
        share: ShamirSecretSharing.Share,
        requesterPublicKeys: PublicKeys,
        requestId: String,
        shareId: String
    ): EncryptedShareResult {
        val config = cryptoManager.cryptoConfig
        val keys = keyManager.getUnlockedKeys()

        // Serialize share
        val shareBytes = ByteArray(1 + share.data.size)
        shareBytes[0] = share.index.toByte()
        System.arraycopy(share.data, 0, shareBytes, 1, share.data.size)

        // Encapsulate for requester
        val (sharedSecret, kazCiphertext, mlKemCiphertext) = when (config.getAlgorithm()) {
            PqcAlgorithm.KAZ -> {
                val (secret, ct) = cryptoManager.kazKemEncapsulate(requesterPublicKeys.kem)
                Triple(secret, ct, null)
            }
            PqcAlgorithm.NIST -> {
                val mlKemPk = requesterPublicKeys.mlKem
                    ?: throw IllegalStateException("Requester ML-KEM public key required for NIST mode")
                val (secret, enc) = cryptoManager.mlKemEncapsulate(mlKemPk)
                Triple(secret, enc, null)
            }
            PqcAlgorithm.HYBRID -> {
                val mlKemPk = requesterPublicKeys.mlKem
                    ?: throw IllegalStateException("Requester ML-KEM public key required for HYBRID mode")
                val (secret, kazCt, mlKemEnc) = cryptoManager.combinedKemEncapsulate(
                    requesterPublicKeys.kem,
                    mlKemPk
                )
                Triple(secret, kazCt, mlKemEnc)
            }
        }

        // Derive encryption key
        val encryptKey = cryptoManager.hkdfProvider.deriveKey(
            ikm = sharedSecret,
            salt = "SecureSharing-RecoveryApproval".toByteArray(),
            info = "approval-encrypt".toByteArray(),
            length = 32
        )

        // Encrypt the share
        val encryptedShare = cryptoManager.encryptAesGcm(shareBytes, encryptKey)

        // Create signature for approval
        val signatureMessage = createApprovalSignatureMessage(
            encryptedShare = encryptedShare,
            kemCiphertext = kazCiphertext,
            mlKemCiphertext = mlKemCiphertext,
            requestId = requestId,
            shareId = shareId
        )

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

        // Zeroize
        cryptoManager.zeroize(sharedSecret)
        cryptoManager.zeroize(encryptKey)

        return EncryptedShareResult(
            encryptedShare = Base64.encodeToString(encryptedShare, Base64.NO_WRAP),
            kemCiphertext = Base64.encodeToString(kazCiphertext, Base64.NO_WRAP),
            mlKemCiphertext = mlKemCiphertext?.let { Base64.encodeToString(it, Base64.NO_WRAP) },
            signature = Base64.encodeToString(signature, Base64.NO_WRAP)
        )
    }

    /**
     * Decrypt an approval share (during recovery completion).
     *
     * @param encryptedShare Base64-encoded encrypted share
     * @param kemCiphertext Base64-encoded KEM ciphertext
     * @param mlKemCiphertext Base64-encoded ML-KEM ciphertext
     * @param privateKeys The requester's new private keys
     * @return The decrypted Shamir share
     */
    fun decryptApprovalShare(
        encryptedShare: String,
        kemCiphertext: String,
        mlKemCiphertext: String?,
        kazPrivateKey: ByteArray,
        mlKemPrivateKey: ByteArray?
    ): ShamirSecretSharing.Share {
        val config = cryptoManager.cryptoConfig

        val encryptedBytes = Base64.decode(encryptedShare, Base64.NO_WRAP)
        val kemCt = Base64.decode(kemCiphertext, Base64.NO_WRAP)
        val mlKemCt = mlKemCiphertext?.let { Base64.decode(it, Base64.NO_WRAP) }

        // Decapsulate shared secret
        val sharedSecret = when (config.getAlgorithm()) {
            PqcAlgorithm.KAZ -> {
                cryptoManager.kazKemDecapsulate(kemCt, kazPrivateKey)
            }
            PqcAlgorithm.NIST -> {
                val mlKemPk = mlKemPrivateKey
                    ?: throw IllegalStateException("ML-KEM private key required for NIST mode")
                cryptoManager.mlKemDecapsulate(kemCt, mlKemPk)
            }
            PqcAlgorithm.HYBRID -> {
                val mlKemPk = mlKemPrivateKey
                    ?: throw IllegalStateException("ML-KEM private key required for HYBRID mode")
                val mlCt = mlKemCt
                    ?: throw IllegalStateException("ML-KEM ciphertext required for HYBRID mode")
                cryptoManager.combinedKemDecapsulate(kemCt, mlCt, kazPrivateKey, mlKemPk)
            }
        }

        // Derive decryption key
        val decryptKey = cryptoManager.hkdfProvider.deriveKey(
            ikm = sharedSecret,
            salt = "SecureSharing-RecoveryApproval".toByteArray(),
            info = "approval-encrypt".toByteArray(),
            length = 32
        )

        // Decrypt
        val shareBytes = cryptoManager.decryptAesGcm(encryptedBytes, decryptKey)

        // Zeroize
        cryptoManager.zeroize(sharedSecret)
        cryptoManager.zeroize(decryptKey)

        // Parse share
        val index = shareBytes[0].toInt() and 0xFF
        val data = shareBytes.copyOfRange(1, shareBytes.size)

        return ShamirSecretSharing.Share(index, data)
    }

    /**
     * Reconstruct the master key from shares.
     *
     * @param shares List of decrypted Shamir shares
     * @return The reconstructed master key
     */
    fun reconstructMasterKey(shares: List<ShamirSecretSharing.Share>): ByteArray {
        return shamirSecretSharing.reconstruct(shares)
    }

    /**
     * Verify a share signature.
     */
    fun verifyShareSignature(
        encryptedShare: String,
        kemCiphertext: String,
        mlKemCiphertext: String?,
        signature: String,
        grantorPublicKeys: PublicKeys,
        grantorId: String,
        trusteeId: String,
        shareIndex: Int
    ): Boolean {
        val config = cryptoManager.cryptoConfig

        val encryptedBytes = Base64.decode(encryptedShare, Base64.NO_WRAP)
        val kemCt = Base64.decode(kemCiphertext, Base64.NO_WRAP)
        val mlKemCt = mlKemCiphertext?.let { Base64.decode(it, Base64.NO_WRAP) }
        val signatureBytes = Base64.decode(signature, Base64.NO_WRAP)

        val signatureMessage = createShareSignatureMessage(
            encryptedShare = encryptedBytes,
            kemCiphertext = kemCt,
            mlKemCiphertext = mlKemCt,
            grantorId = grantorId,
            trusteeId = trusteeId,
            shareIndex = shareIndex
        )

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

    // ==================== Helper Methods ====================

    private fun createShareSignatureMessage(
        encryptedShare: ByteArray,
        kemCiphertext: ByteArray,
        mlKemCiphertext: ByteArray?,
        grantorId: String,
        trusteeId: String,
        shareIndex: Int
    ): ByteArray {
        val digest = MessageDigest.getInstance("SHA-256")
        digest.update(encryptedShare)
        digest.update(kemCiphertext)
        mlKemCiphertext?.let { digest.update(it) }
        digest.update(grantorId.toByteArray())
        digest.update(trusteeId.toByteArray())
        digest.update(shareIndex.toByte())
        return digest.digest()
    }

    private fun createApprovalSignatureMessage(
        encryptedShare: ByteArray,
        kemCiphertext: ByteArray,
        mlKemCiphertext: ByteArray?,
        requestId: String,
        shareId: String
    ): ByteArray {
        val digest = MessageDigest.getInstance("SHA-256")
        digest.update(encryptedShare)
        digest.update(kemCiphertext)
        mlKemCiphertext?.let { digest.update(it) }
        digest.update(requestId.toByteArray())
        digest.update(shareId.toByteArray())
        return digest.digest()
    }
}
