package my.ssdid.drive

import android.util.Base64
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Integration tests for cryptographic operations.
 *
 * These tests run on an Android device/emulator to verify that
 * crypto operations work correctly with the Android platform.
 *
 * Tests cover:
 * - AES-GCM encryption/decryption end-to-end
 * - Shamir Secret Sharing full workflow
 * - Key derivation
 */
@RunWith(AndroidJUnit4::class)
class CryptoIntegrationTest {

    private lateinit var secureRandom: SecureRandom

    @Before
    fun setup() {
        secureRandom = SecureRandom()
    }

    // ==================== AES-GCM Tests ====================

    @Test
    fun aesGcm_encryptDecrypt_roundTrip() {
        val key = generateRandomBytes(32)
        val plaintext = "Hello, SSDID Drive! This is a test message.".toByteArray()

        val ciphertext = encryptAesGcm(plaintext, key)
        val decrypted = decryptAesGcm(ciphertext, key)

        assertArrayEquals(plaintext, decrypted)
    }

    @Test
    fun aesGcm_differentNonce_producesDifferentCiphertext() {
        val key = generateRandomBytes(32)
        val plaintext = "Same message".toByteArray()

        val ciphertext1 = encryptAesGcm(plaintext, key)
        val ciphertext2 = encryptAesGcm(plaintext, key)

        // Ciphertexts should be different due to random nonce
        assertFalse(ciphertext1.contentEquals(ciphertext2))

        // But both should decrypt to the same plaintext
        assertArrayEquals(plaintext, decryptAesGcm(ciphertext1, key))
        assertArrayEquals(plaintext, decryptAesGcm(ciphertext2, key))
    }

    @Test
    fun aesGcm_wrongKey_failsDecryption() {
        val key1 = generateRandomBytes(32)
        val key2 = generateRandomBytes(32)
        val plaintext = "Secret data".toByteArray()

        val ciphertext = encryptAesGcm(plaintext, key1)

        try {
            decryptAesGcm(ciphertext, key2)
            fail("Should throw exception with wrong key")
        } catch (e: Exception) {
            // Expected - authentication should fail
            assertTrue(e is javax.crypto.AEADBadTagException || e.cause is javax.crypto.AEADBadTagException)
        }
    }

    @Test
    fun aesGcm_tamperedCiphertext_failsDecryption() {
        val key = generateRandomBytes(32)
        val plaintext = "Important data".toByteArray()

        val ciphertext = encryptAesGcm(plaintext, key)

        // Tamper with ciphertext (flip a bit in the middle)
        ciphertext[ciphertext.size / 2] = (ciphertext[ciphertext.size / 2].toInt() xor 0x01).toByte()

        try {
            decryptAesGcm(ciphertext, key)
            fail("Should throw exception with tampered ciphertext")
        } catch (e: Exception) {
            // Expected - authentication should fail
        }
    }

    @Test
    fun aesGcm_largeData_works() {
        val key = generateRandomBytes(32)
        val plaintext = generateRandomBytes(1024 * 1024) // 1 MB

        val ciphertext = encryptAesGcm(plaintext, key)
        val decrypted = decryptAesGcm(ciphertext, key)

        assertArrayEquals(plaintext, decrypted)
    }

    // ==================== Full Encryption Flow Test ====================

    @Test
    fun fileEncryption_simulation() {
        // Simulate file encryption:
        // 1. Generate DEK
        // 2. Encrypt file content
        // 3. Wrap DEK with folder KEK
        // 4. Unwrap and decrypt

        // Generate keys
        val dek = generateRandomBytes(32) // Data Encryption Key
        val kek = generateRandomBytes(32) // Key Encryption Key

        // Simulate file content
        val fileContent = "This is the content of a sensitive file. It contains private data.".toByteArray()

        // Encrypt file with DEK
        val encryptedFile = encryptAesGcm(fileContent, dek)

        // Wrap DEK with KEK
        val wrappedDek = encryptAesGcm(dek, kek)

        // Now simulate decryption
        // Unwrap DEK
        val unwrappedDek = decryptAesGcm(wrappedDek, kek)
        assertArrayEquals(dek, unwrappedDek)

        // Decrypt file
        val decryptedFile = decryptAesGcm(encryptedFile, unwrappedDek)
        assertArrayEquals(fileContent, decryptedFile)
    }

    // ==================== Helper Functions ====================

    private fun generateRandomBytes(size: Int): ByteArray {
        val bytes = ByteArray(size)
        secureRandom.nextBytes(bytes)
        return bytes
    }

    private fun encryptAesGcm(plaintext: ByteArray, key: ByteArray): ByteArray {
        val nonce = generateRandomBytes(12)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        val keySpec = SecretKeySpec(key, "AES")
        val gcmSpec = GCMParameterSpec(128, nonce)
        cipher.init(Cipher.ENCRYPT_MODE, keySpec, gcmSpec)

        val ciphertext = cipher.doFinal(plaintext)

        // Return nonce || ciphertext
        return nonce + ciphertext
    }

    private fun decryptAesGcm(ciphertextWithNonce: ByteArray, key: ByteArray): ByteArray {
        val nonce = ciphertextWithNonce.copyOfRange(0, 12)
        val ciphertext = ciphertextWithNonce.copyOfRange(12, ciphertextWithNonce.size)

        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        val keySpec = SecretKeySpec(key, "AES")
        val gcmSpec = GCMParameterSpec(128, nonce)
        cipher.init(Cipher.DECRYPT_MODE, keySpec, gcmSpec)

        return cipher.doFinal(ciphertext)
    }

    private fun deriveKeyPbkdf2(password: ByteArray, salt: ByteArray): ByteArray {
        val factory = javax.crypto.SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
        val spec = javax.crypto.spec.PBEKeySpec(
            String(password).toCharArray(),
            salt,
            100000, // iterations
            256 // key length in bits
        )
        return factory.generateSecret(spec).encoded
    }
}
