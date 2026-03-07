package my.ssdid.drive.crypto

import my.ssdid.drive.crypto.providers.AesGcmProvider
import my.ssdid.drive.crypto.providers.HkdfProvider
import my.ssdid.drive.crypto.providers.KazKemProvider
import my.ssdid.drive.crypto.providers.KazSignProvider
import my.ssdid.drive.crypto.providers.MlKemProvider
import my.ssdid.drive.crypto.providers.MlDsaProvider
import io.mockk.every
import io.mockk.mockk
import io.mockk.verify
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

/**
 * Unit tests for CryptoManager.
 *
 * Tests cover:
 * - AES-GCM encrypt/decrypt round-trip
 * - HKDF key derivation
 * - Combined KEM encapsulation/decapsulation
 * - Combined signature sign/verify
 * - Key wrapping/unwrapping
 * - Tenant-aware operations
 */
class CryptoManagerTest {

    private lateinit var aesGcmProvider: AesGcmProvider
    private lateinit var hkdfProvider: HkdfProvider
    private lateinit var kazKemProvider: KazKemProvider
    private lateinit var kazSignProvider: KazSignProvider
    private lateinit var mlKemProvider: MlKemProvider
    private lateinit var mlDsaProvider: MlDsaProvider
    private lateinit var cryptoConfig: CryptoConfig
    private lateinit var cryptoManager: CryptoManager

    // Test data
    private val testPlaintext = "Hello, SsdidDrive!".toByteArray()
    private val testKey = ByteArray(32) { it.toByte() }
    private val testPassword = "testPassword123".toByteArray()
    private val testSalt = ByteArray(16) { (it * 2).toByte() }

    @Before
    fun setup() {
        aesGcmProvider = mockk()
        hkdfProvider = mockk()
        kazKemProvider = mockk()
        kazSignProvider = mockk()
        mlKemProvider = mockk()
        mlDsaProvider = mockk()
        cryptoConfig = mockk()

        cryptoManager = CryptoManager(
            aesGcmProvider = aesGcmProvider,
            hkdfProvider = hkdfProvider,
            kazKemProvider = kazKemProvider,
            kazSignProvider = kazSignProvider,
            mlKemProvider = mlKemProvider,
            mlDsaProvider = mlDsaProvider,
            cryptoConfig = cryptoConfig
        )
    }

    // ==================== Random Generation Tests ====================

    @Test
    fun `generateRandom produces bytes of correct size`() {
        val size = 32
        val random = cryptoManager.generateRandom(size)
        assertEquals(size, random.size)
    }

    @Test
    fun `generateRandom produces different values on each call`() {
        val random1 = cryptoManager.generateRandom(32)
        val random2 = cryptoManager.generateRandom(32)
        assertFalse(random1.contentEquals(random2))
    }

    @Test
    fun `generateKey produces 32 byte key`() {
        val key = cryptoManager.generateKey()
        assertEquals(32, key.size)
    }

    // ==================== AES-GCM Tests ====================

    @Test
    fun `encryptAesGcm calls provider with correct parameters`() {
        val ciphertext = ByteArray(testPlaintext.size + 28) // nonce + tag overhead
        every { aesGcmProvider.encrypt(testPlaintext, testKey) } returns ciphertext

        val result = cryptoManager.encryptAesGcm(testPlaintext, testKey)

        verify { aesGcmProvider.encrypt(testPlaintext, testKey) }
        assertArrayEquals(ciphertext, result)
    }

    @Test
    fun `decryptAesGcm calls provider with correct parameters`() {
        val ciphertext = ByteArray(50)
        every { aesGcmProvider.decrypt(ciphertext, testKey) } returns testPlaintext

        val result = cryptoManager.decryptAesGcm(ciphertext, testKey)

        verify { aesGcmProvider.decrypt(ciphertext, testKey) }
        assertArrayEquals(testPlaintext, result)
    }

    @Test
    fun `encrypt then decrypt round-trip returns original data`() {
        val ciphertext = ByteArray(testPlaintext.size + 28)
        every { aesGcmProvider.encrypt(testPlaintext, testKey) } returns ciphertext
        every { aesGcmProvider.decrypt(ciphertext, testKey) } returns testPlaintext

        val encrypted = cryptoManager.encryptAesGcm(testPlaintext, testKey)
        val decrypted = cryptoManager.decryptAesGcm(encrypted, testKey)

        assertArrayEquals(testPlaintext, decrypted)
    }

    // ==================== Key Derivation Tests ====================

    @Test
    fun `deriveKeyLegacy calls hkdfProvider with correct parameters`() {
        val derivedKey = ByteArray(32)
        every {
            hkdfProvider.deriveKey(testPassword, testSalt, info = "SsdidDrive-v1".toByteArray())
        } returns derivedKey

        val result = cryptoManager.deriveKeyLegacy(testPassword, testSalt)

        verify { hkdfProvider.deriveKey(testPassword, testSalt, info = "SsdidDrive-v1".toByteArray()) }
        assertArrayEquals(derivedKey, result)
    }

    @Test
    fun `deriveKey uses Argon2id output with HKDF`() {
        // deriveKey internally uses Argon2id (not mocked) then HKDF
        // We can only verify the HKDF is called with some input
        val derivedKey = ByteArray(32)
        every {
            hkdfProvider.deriveKey(
                ikm = any(),
                salt = "SsdidDrive-MasterKey-v1".toByteArray(),
                info = "mk-encryption-key".toByteArray()
            )
        } returns derivedKey

        val result = cryptoManager.deriveKey(testPassword, testSalt)

        verify {
            hkdfProvider.deriveKey(
                ikm = any(),
                salt = "SsdidDrive-MasterKey-v1".toByteArray(),
                info = "mk-encryption-key".toByteArray()
            )
        }
        assertArrayEquals(derivedKey, result)
    }

    // ==================== KAZ-KEM Tests ====================

    @Test
    fun `generateKazKemKeyPair delegates to provider`() {
        val publicKey = ByteArray(800)
        val privateKey = ByteArray(1600)
        every { kazKemProvider.generateKeyPair() } returns Pair(publicKey, privateKey)

        val (pub, priv) = cryptoManager.generateKazKemKeyPair()

        verify { kazKemProvider.generateKeyPair() }
        assertArrayEquals(publicKey, pub)
        assertArrayEquals(privateKey, priv)
    }

    @Test
    fun `kazKemEncapsulate returns shared secret and ciphertext`() {
        val publicKey = ByteArray(800)
        val sharedSecret = ByteArray(32)
        val ciphertext = ByteArray(768)
        every { kazKemProvider.encapsulate(publicKey) } returns Pair(sharedSecret, ciphertext)

        val (secret, ct) = cryptoManager.kazKemEncapsulate(publicKey)

        verify { kazKemProvider.encapsulate(publicKey) }
        assertArrayEquals(sharedSecret, secret)
        assertArrayEquals(ciphertext, ct)
    }

    @Test
    fun `kazKemDecapsulate returns shared secret`() {
        val ciphertext = ByteArray(768)
        val privateKey = ByteArray(1600)
        val sharedSecret = ByteArray(32)
        every { kazKemProvider.decapsulate(ciphertext, privateKey) } returns sharedSecret

        val result = cryptoManager.kazKemDecapsulate(ciphertext, privateKey)

        verify { kazKemProvider.decapsulate(ciphertext, privateKey) }
        assertArrayEquals(sharedSecret, result)
    }

    // ==================== ML-KEM Tests ====================

    @Test
    fun `generateMlKemKeyPair delegates to provider`() {
        val publicKey = ByteArray(1184)
        val privateKey = ByteArray(2400)
        every { mlKemProvider.generateKeyPair() } returns Pair(publicKey, privateKey)

        val (pub, priv) = cryptoManager.generateMlKemKeyPair()

        verify { mlKemProvider.generateKeyPair() }
        assertArrayEquals(publicKey, pub)
        assertArrayEquals(privateKey, priv)
    }

    // ==================== Combined KEM Tests ====================

    @Test
    fun `combinedKemEncapsulate uses both algorithms`() {
        val kazPublicKey = ByteArray(800)
        val mlKemPublicKey = ByteArray(1184)
        val kazSecret = ByteArray(32) { 0xAA.toByte() }
        val mlKemSecret = ByteArray(32) { 0x55.toByte() }
        val kazCiphertext = ByteArray(768)
        val mlKemEncapsulation = ByteArray(1088)
        val combinedDerivedKey = ByteArray(32)

        every { kazKemProvider.encapsulate(kazPublicKey) } returns Pair(kazSecret, kazCiphertext)
        every { mlKemProvider.encapsulate(mlKemPublicKey) } returns Pair(mlKemSecret, mlKemEncapsulation)
        every {
            hkdfProvider.deriveKey(
                ikm = any(),
                salt = "SsdidDrive-CombinedKEM".toByteArray(),
                info = "shared-secret".toByteArray(),
                length = 32
            )
        } returns combinedDerivedKey

        val (secret, kazCt, mlKemEnc) = cryptoManager.combinedKemEncapsulate(kazPublicKey, mlKemPublicKey)

        verify { kazKemProvider.encapsulate(kazPublicKey) }
        verify { mlKemProvider.encapsulate(mlKemPublicKey) }
        assertArrayEquals(combinedDerivedKey, secret)
        assertArrayEquals(kazCiphertext, kazCt)
        assertArrayEquals(mlKemEncapsulation, mlKemEnc)
    }

    @Test
    fun `combinedKemDecapsulate uses both algorithms`() {
        val kazCiphertext = ByteArray(768)
        val mlKemEncapsulation = ByteArray(1088)
        val kazPrivateKey = ByteArray(1600)
        val mlKemPrivateKey = ByteArray(2400)
        val kazSecret = ByteArray(32) { 0xAA.toByte() }
        val mlKemSecret = ByteArray(32) { 0x55.toByte() }
        val combinedDerivedKey = ByteArray(32)

        every { kazKemProvider.decapsulate(kazCiphertext, kazPrivateKey) } returns kazSecret
        every { mlKemProvider.decapsulate(mlKemEncapsulation, mlKemPrivateKey) } returns mlKemSecret
        every {
            hkdfProvider.deriveKey(
                ikm = any(),
                salt = "SsdidDrive-CombinedKEM".toByteArray(),
                info = "shared-secret".toByteArray(),
                length = 32
            )
        } returns combinedDerivedKey

        val result = cryptoManager.combinedKemDecapsulate(
            kazCiphertext, mlKemEncapsulation, kazPrivateKey, mlKemPrivateKey
        )

        verify { kazKemProvider.decapsulate(kazCiphertext, kazPrivateKey) }
        verify { mlKemProvider.decapsulate(mlKemEncapsulation, mlKemPrivateKey) }
        assertArrayEquals(combinedDerivedKey, result)
    }

    // ==================== KAZ-SIGN Tests ====================

    @Test
    fun `generateKazSignKeyPair delegates to provider`() {
        val publicKey = ByteArray(1312)
        val privateKey = ByteArray(2528)
        every { kazSignProvider.generateKeyPair() } returns Pair(publicKey, privateKey)

        val (pub, priv) = cryptoManager.generateKazSignKeyPair()

        verify { kazSignProvider.generateKeyPair() }
        assertArrayEquals(publicKey, pub)
        assertArrayEquals(privateKey, priv)
    }

    @Test
    fun `kazSign delegates to provider`() {
        val message = "test message".toByteArray()
        val privateKey = ByteArray(2528)
        val signature = ByteArray(2420)
        every { kazSignProvider.sign(message, privateKey) } returns signature

        val result = cryptoManager.kazSign(message, privateKey)

        verify { kazSignProvider.sign(message, privateKey) }
        assertArrayEquals(signature, result)
    }

    @Test
    fun `kazVerify delegates to provider`() {
        val message = "test message".toByteArray()
        val signature = ByteArray(2420)
        val publicKey = ByteArray(1312)
        every { kazSignProvider.verify(message, signature, publicKey) } returns true

        val result = cryptoManager.kazVerify(message, signature, publicKey)

        verify { kazSignProvider.verify(message, signature, publicKey) }
        assertTrue(result)
    }

    // ==================== Combined Signature Tests ====================

    @Test
    fun `combinedSign creates signature with both algorithms`() {
        val message = "test message".toByteArray()
        val kazPrivateKey = ByteArray(2528)
        val mlDsaPrivateKey = ByteArray(4032)
        val kazSignature = ByteArray(2420)
        val mlDsaSignature = ByteArray(3309)

        every { kazSignProvider.sign(message, kazPrivateKey) } returns kazSignature
        every { mlDsaProvider.sign(message, mlDsaPrivateKey) } returns mlDsaSignature

        val combined = cryptoManager.combinedSign(message, kazPrivateKey, mlDsaPrivateKey)

        verify { kazSignProvider.sign(message, kazPrivateKey) }
        verify { mlDsaProvider.sign(message, mlDsaPrivateKey) }

        // Verify structure: [kazSigLen:4][kazSig][mlDsaSigLen:4][mlDsaSig]
        val expectedSize = 4 + kazSignature.size + 4 + mlDsaSignature.size
        assertEquals(expectedSize, combined.size)
    }

    @Test
    fun `combinedVerify requires both signatures to be valid`() {
        val message = "test message".toByteArray()
        val kazPublicKey = ByteArray(1312)
        val mlDsaPublicKey = ByteArray(1952)
        val kazSignature = ByteArray(2420)
        val mlDsaSignature = ByteArray(3309)

        // Create combined signature
        val combined = ByteArray(4 + kazSignature.size + 4 + mlDsaSignature.size)
        var offset = 0
        combined[offset++] = (kazSignature.size shr 24).toByte()
        combined[offset++] = (kazSignature.size shr 16).toByte()
        combined[offset++] = (kazSignature.size shr 8).toByte()
        combined[offset++] = kazSignature.size.toByte()
        System.arraycopy(kazSignature, 0, combined, offset, kazSignature.size)
        offset += kazSignature.size
        combined[offset++] = (mlDsaSignature.size shr 24).toByte()
        combined[offset++] = (mlDsaSignature.size shr 16).toByte()
        combined[offset++] = (mlDsaSignature.size shr 8).toByte()
        combined[offset++] = mlDsaSignature.size.toByte()
        System.arraycopy(mlDsaSignature, 0, combined, offset, mlDsaSignature.size)

        // Both valid
        every { kazSignProvider.verify(message, any(), kazPublicKey) } returns true
        every { mlDsaProvider.verify(message, any(), mlDsaPublicKey) } returns true

        assertTrue(cryptoManager.combinedVerify(message, combined, kazPublicKey, mlDsaPublicKey))

        // KAZ invalid
        every { kazSignProvider.verify(message, any(), kazPublicKey) } returns false
        every { mlDsaProvider.verify(message, any(), mlDsaPublicKey) } returns true

        assertFalse(cryptoManager.combinedVerify(message, combined, kazPublicKey, mlDsaPublicKey))

        // ML-DSA invalid
        every { kazSignProvider.verify(message, any(), kazPublicKey) } returns true
        every { mlDsaProvider.verify(message, any(), mlDsaPublicKey) } returns false

        assertFalse(cryptoManager.combinedVerify(message, combined, kazPublicKey, mlDsaPublicKey))
    }

    // ==================== Key Wrapping Tests ====================

    @Test
    fun `wrapKey uses AES-GCM encryption`() {
        val keyToWrap = ByteArray(32)
        val wrappingKey = ByteArray(32)
        val wrappedKey = ByteArray(60)
        every { aesGcmProvider.encrypt(keyToWrap, wrappingKey) } returns wrappedKey

        val result = cryptoManager.wrapKey(keyToWrap, wrappingKey)

        verify { aesGcmProvider.encrypt(keyToWrap, wrappingKey) }
        assertArrayEquals(wrappedKey, result)
    }

    @Test
    fun `unwrapKey uses AES-GCM decryption`() {
        val wrappedKey = ByteArray(60)
        val wrappingKey = ByteArray(32)
        val unwrappedKey = ByteArray(32)
        every { aesGcmProvider.decrypt(wrappedKey, wrappingKey) } returns unwrappedKey

        val result = cryptoManager.unwrapKey(wrappedKey, wrappingKey)

        verify { aesGcmProvider.decrypt(wrappedKey, wrappingKey) }
        assertArrayEquals(unwrappedKey, result)
    }

    // ==================== Tenant-Aware Operations Tests ====================

    @Test
    fun `tenantKemEncapsulate uses KAZ only when configured`() {
        val kazPublicKey = ByteArray(800)
        val sharedSecret = ByteArray(32)
        val ciphertext = ByteArray(768)

        every { cryptoConfig.getAlgorithm() } returns PqcAlgorithm.KAZ
        every { kazKemProvider.encapsulate(kazPublicKey) } returns Pair(sharedSecret, ciphertext)

        val result = cryptoManager.tenantKemEncapsulate(kazPublicKey, null)

        assertEquals(sharedSecret, result.sharedSecret)
        assertEquals(ciphertext, result.kazCiphertext)
        assertNull(result.mlKemEncapsulation)
    }

    @Test
    fun `tenantKemEncapsulate uses NIST only when configured`() {
        val mlKemPublicKey = ByteArray(1184)
        val sharedSecret = ByteArray(32)
        val encapsulation = ByteArray(1088)

        every { cryptoConfig.getAlgorithm() } returns PqcAlgorithm.NIST
        every { mlKemProvider.encapsulate(mlKemPublicKey) } returns Pair(sharedSecret, encapsulation)

        val result = cryptoManager.tenantKemEncapsulate(null, mlKemPublicKey)

        assertEquals(sharedSecret, result.sharedSecret)
        assertNull(result.kazCiphertext)
        assertEquals(encapsulation, result.mlKemEncapsulation)
    }

    @Test
    fun `tenantSign uses correct algorithm based on config`() {
        val message = "test".toByteArray()
        val kazPrivateKey = ByteArray(2528)
        val kazSignature = ByteArray(2420)

        every { cryptoConfig.getAlgorithm() } returns PqcAlgorithm.KAZ
        every { kazSignProvider.sign(message, kazPrivateKey) } returns kazSignature

        val result = cryptoManager.tenantSign(message, kazPrivateKey, null)

        assertFalse(result.isCombined)
        assertArrayEquals(kazSignature, result.signature)
    }

    // ==================== Secure Memory Tests ====================

    @Test
    fun `zeroize clears byte array`() {
        val sensitiveData = ByteArray(32) { 0xFF.toByte() }
        cryptoManager.zeroize(sensitiveData)
        // After zeroize, all bytes should be 0
        assertTrue(sensitiveData.all { it == 0.toByte() })
    }

    @Test
    fun `zeroize clears char array`() {
        val password = charArrayOf('p', 'a', 's', 's', 'w', 'o', 'r', 'd')
        cryptoManager.zeroize(password)
        // After zeroize, all chars should be null char
        assertTrue(password.all { it == '\u0000' })
    }
}
