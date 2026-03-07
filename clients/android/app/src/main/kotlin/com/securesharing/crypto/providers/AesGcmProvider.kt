package com.securesharing.crypto.providers

import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Provider for AES-256-GCM encryption/decryption.
 */
@Singleton
class AesGcmProvider @Inject constructor() {

    companion object {
        private const val ALGORITHM = "AES/GCM/NoPadding"
        private const val KEY_SIZE = 32 // 256 bits
        private const val NONCE_SIZE = 12 // 96 bits (recommended for GCM)
        private const val TAG_SIZE = 128 // bits
    }

    private val secureRandom = SecureRandom()

    /**
     * Encrypt data using AES-256-GCM.
     *
     * @param plaintext The data to encrypt
     * @param key 32-byte AES key
     * @return nonce (12 bytes) || ciphertext || tag (16 bytes)
     */
    fun encrypt(plaintext: ByteArray, key: ByteArray): ByteArray {
        require(key.size == KEY_SIZE) { "Key must be $KEY_SIZE bytes" }

        val nonce = ByteArray(NONCE_SIZE)
        secureRandom.nextBytes(nonce)

        val cipher = Cipher.getInstance(ALGORITHM)
        val keySpec = SecretKeySpec(key, "AES")
        val gcmSpec = GCMParameterSpec(TAG_SIZE, nonce)

        cipher.init(Cipher.ENCRYPT_MODE, keySpec, gcmSpec)
        val ciphertext = cipher.doFinal(plaintext)

        // Return: nonce || ciphertext (includes tag)
        return nonce + ciphertext
    }

    /**
     * Decrypt data using AES-256-GCM.
     *
     * @param data nonce (12 bytes) || ciphertext || tag
     * @param key 32-byte AES key
     * @return decrypted plaintext
     */
    fun decrypt(data: ByteArray, key: ByteArray): ByteArray {
        require(key.size == KEY_SIZE) { "Key must be $KEY_SIZE bytes" }
        require(data.size > NONCE_SIZE) { "Data too short" }

        val nonce = data.copyOfRange(0, NONCE_SIZE)
        val ciphertext = data.copyOfRange(NONCE_SIZE, data.size)

        val cipher = Cipher.getInstance(ALGORITHM)
        val keySpec = SecretKeySpec(key, "AES")
        val gcmSpec = GCMParameterSpec(TAG_SIZE, nonce)

        cipher.init(Cipher.DECRYPT_MODE, keySpec, gcmSpec)
        return cipher.doFinal(ciphertext)
    }

    /**
     * Encrypt with additional authenticated data (AAD).
     */
    fun encryptWithAad(
        plaintext: ByteArray,
        key: ByteArray,
        aad: ByteArray
    ): ByteArray {
        require(key.size == KEY_SIZE) { "Key must be $KEY_SIZE bytes" }

        val nonce = ByteArray(NONCE_SIZE)
        secureRandom.nextBytes(nonce)

        val cipher = Cipher.getInstance(ALGORITHM)
        val keySpec = SecretKeySpec(key, "AES")
        val gcmSpec = GCMParameterSpec(TAG_SIZE, nonce)

        cipher.init(Cipher.ENCRYPT_MODE, keySpec, gcmSpec)
        cipher.updateAAD(aad)
        val ciphertext = cipher.doFinal(plaintext)

        return nonce + ciphertext
    }

    /**
     * Decrypt with a separately provided nonce (nonce is NOT prepended to data).
     * Used for vault/PRF key bundle decryption.
     *
     * @param ciphertext Ciphertext with appended auth tag (no nonce prefix)
     * @param key 32-byte AES key
     * @param nonce 12-byte nonce
     * @return Decrypted plaintext
     */
    fun decryptWithNonce(
        ciphertext: ByteArray,
        key: ByteArray,
        nonce: ByteArray
    ): ByteArray {
        require(key.size == KEY_SIZE) { "Key must be $KEY_SIZE bytes" }
        require(nonce.size == NONCE_SIZE) { "Nonce must be $NONCE_SIZE bytes" }

        val cipher = Cipher.getInstance(ALGORITHM)
        val keySpec = SecretKeySpec(key, "AES")
        val gcmSpec = GCMParameterSpec(TAG_SIZE, nonce)

        cipher.init(Cipher.DECRYPT_MODE, keySpec, gcmSpec)
        return cipher.doFinal(ciphertext)
    }

    /**
     * Decrypt with additional authenticated data (AAD).
     */
    fun decryptWithAad(
        data: ByteArray,
        key: ByteArray,
        aad: ByteArray
    ): ByteArray {
        require(key.size == KEY_SIZE) { "Key must be $KEY_SIZE bytes" }
        require(data.size > NONCE_SIZE) { "Data too short" }

        val nonce = data.copyOfRange(0, NONCE_SIZE)
        val ciphertext = data.copyOfRange(NONCE_SIZE, data.size)

        val cipher = Cipher.getInstance(ALGORITHM)
        val keySpec = SecretKeySpec(key, "AES")
        val gcmSpec = GCMParameterSpec(TAG_SIZE, nonce)

        cipher.init(Cipher.DECRYPT_MODE, keySpec, gcmSpec)
        cipher.updateAAD(aad)
        return cipher.doFinal(ciphertext)
    }
}
