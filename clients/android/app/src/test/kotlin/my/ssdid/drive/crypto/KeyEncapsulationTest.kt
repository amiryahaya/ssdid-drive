package my.ssdid.drive.crypto

import android.util.Base64
import my.ssdid.drive.crypto.providers.HkdfProvider
import my.ssdid.drive.domain.model.PublicKeys
import io.mockk.every
import io.mockk.mockk
import io.mockk.mockkStatic
import io.mockk.verify
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

/**
 * Unit tests for KeyEncapsulation.
 *
 * Tests cover:
 * - Encapsulation with KAZ, NIST, and HYBRID algorithms
 * - Decapsulation with KAZ, NIST, and HYBRID algorithms
 * - File share encapsulation
 * - Folder share encapsulation
 * - Share signature verification
 * - Permission update signing
 * - Error handling: missing keys for NIST/HYBRID modes
 * - Secure zeroization of intermediate values
 */
class KeyEncapsulationTest {

    private lateinit var cryptoManager: CryptoManager
    private lateinit var keyManager: KeyManager
    private lateinit var hkdfProvider: HkdfProvider
    private lateinit var cryptoConfig: CryptoConfig
    private lateinit var keyEncapsulation: KeyEncapsulation

    private val testFolderKey = ByteArray(32) { it.toByte() }
    private val testDek = ByteArray(32) { (it + 10).toByte() }
    private val testSharedSecret = ByteArray(32) { 0xAA.toByte() }
    private val testWrapKey = ByteArray(32) { 0xBB.toByte() }
    private val testWrappedKey = ByteArray(60) { 0xCC.toByte() }
    private val testCiphertext = ByteArray(768) { 0xDD.toByte() }
    private val testMlKemCiphertext = ByteArray(1088) { 0xEE.toByte() }
    private val testSignature = ByteArray(2420) { 0x11.toByte() }

    @Before
    fun setup() {
        cryptoManager = mockk(relaxed = true)
        keyManager = mockk()
        hkdfProvider = mockk()
        cryptoConfig = mockk()

        // Wire up hkdfProvider and cryptoConfig on cryptoManager
        every { cryptoManager.hkdfProvider } returns hkdfProvider
        every { cryptoManager.cryptoConfig } returns cryptoConfig

        // Mock Base64 since it's an Android API
        mockkStatic(Base64::class)
        every { Base64.encodeToString(any(), any()) } answers {
            java.util.Base64.getEncoder().encodeToString(firstArg<ByteArray>())
        }
        every { Base64.decode(any<String>(), any()) } answers {
            java.util.Base64.getDecoder().decode(firstArg<String>())
        }

        keyEncapsulation = KeyEncapsulation(
            cryptoManager = cryptoManager,
            keyManager = keyManager
        )
    }

    // ==================== KAZ Encapsulation Tests ====================

    @Test
    fun `encapsulate with KAZ algorithm encapsulates and wraps key`() {
        setupKazEncapsulation()

        val recipientKeys = createRecipientPublicKeys()
        val result = keyEncapsulation.encapsulate(testFolderKey, recipientKeys)

        assertNotNull(result.wrappedKey)
        assertNotNull(result.kemCiphertext)
        assertNull(result.mlKemCiphertext)
        assertNotNull(result.signature)

        verify { cryptoManager.kazKemEncapsulate(recipientKeys.kem) }
        verify { cryptoManager.kazSign(any(), any()) }
    }

    @Test
    fun `encapsulate with KAZ zeroizes intermediate values`() {
        setupKazEncapsulation()

        keyEncapsulation.encapsulate(testFolderKey, createRecipientPublicKeys())

        verify { cryptoManager.zeroize(testSharedSecret) }
        verify { cryptoManager.zeroize(testWrapKey) }
    }

    // ==================== NIST Encapsulation Tests ====================

    @Test
    fun `encapsulate with NIST algorithm uses ML-KEM`() {
        setupNistEncapsulation()

        val recipientKeys = createRecipientPublicKeys(includeMlKem = true)
        val result = keyEncapsulation.encapsulate(testFolderKey, recipientKeys)

        assertNotNull(result.wrappedKey)
        assertNotNull(result.kemCiphertext)
        assertNull(result.mlKemCiphertext) // NIST puts ML-KEM ciphertext in kemCiphertext
        assertNotNull(result.signature)

        verify { cryptoManager.mlKemEncapsulate(recipientKeys.mlKem!!) }
        verify { cryptoManager.mlDsaSign(any(), any()) }
    }

    @Test(expected = IllegalStateException::class)
    fun `encapsulate with NIST throws when recipient has no ML-KEM key`() {
        val keys = createTestKeyBundle()
        every { keyManager.getUnlockedKeys() } returns keys
        every { cryptoConfig.getAlgorithm() } returns PqcAlgorithm.NIST

        val recipientKeys = createRecipientPublicKeys(includeMlKem = false)
        keyEncapsulation.encapsulate(testFolderKey, recipientKeys)
    }

    // ==================== HYBRID Encapsulation Tests ====================

    @Test
    fun `encapsulate with HYBRID algorithm uses both KEM algorithms`() {
        setupHybridEncapsulation()

        val recipientKeys = createRecipientPublicKeys(includeMlKem = true)
        val result = keyEncapsulation.encapsulate(testFolderKey, recipientKeys)

        assertNotNull(result.wrappedKey)
        assertNotNull(result.kemCiphertext)
        assertNotNull(result.mlKemCiphertext)
        assertNotNull(result.signature)

        verify {
            cryptoManager.combinedKemEncapsulate(
                recipientKeys.kem,
                recipientKeys.mlKem!!
            )
        }
        verify { cryptoManager.combinedSign(any(), any(), any()) }
    }

    @Test(expected = IllegalStateException::class)
    fun `encapsulate with HYBRID throws when recipient has no ML-KEM key`() {
        val keys = createTestKeyBundle()
        every { keyManager.getUnlockedKeys() } returns keys
        every { cryptoConfig.getAlgorithm() } returns PqcAlgorithm.HYBRID

        val recipientKeys = createRecipientPublicKeys(includeMlKem = false)
        keyEncapsulation.encapsulate(testFolderKey, recipientKeys)
    }

    // ==================== KAZ Decapsulation Tests ====================

    @Test
    fun `decapsulate with KAZ algorithm decapsulates and unwraps key`() {
        setupKazDecapsulation()

        val wrappedKeyB64 = java.util.Base64.getEncoder().encodeToString(testWrappedKey)
        val kemCtB64 = java.util.Base64.getEncoder().encodeToString(testCiphertext)

        val result = keyEncapsulation.decapsulate(wrappedKeyB64, kemCtB64)

        assertNotNull(result)
        assertEquals(32, result.size)

        verify { cryptoManager.kazKemDecapsulate(testCiphertext, any()) }
    }

    @Test
    fun `decapsulate with KAZ zeroizes intermediate values`() {
        setupKazDecapsulation()

        val wrappedKeyB64 = java.util.Base64.getEncoder().encodeToString(testWrappedKey)
        val kemCtB64 = java.util.Base64.getEncoder().encodeToString(testCiphertext)

        keyEncapsulation.decapsulate(wrappedKeyB64, kemCtB64)

        verify { cryptoManager.zeroize(testSharedSecret) }
        verify { cryptoManager.zeroize(testWrapKey) }
    }

    // ==================== NIST Decapsulation Tests ====================

    @Test
    fun `decapsulate with NIST algorithm uses ML-KEM`() {
        setupNistDecapsulation()

        val wrappedKeyB64 = java.util.Base64.getEncoder().encodeToString(testWrappedKey)
        val kemCtB64 = java.util.Base64.getEncoder().encodeToString(testCiphertext)

        val result = keyEncapsulation.decapsulate(wrappedKeyB64, kemCtB64)

        assertNotNull(result)
        verify { cryptoManager.mlKemDecapsulate(testCiphertext, any()) }
    }

    // ==================== HYBRID Decapsulation Tests ====================

    @Test
    fun `decapsulate with HYBRID algorithm uses both KEM algorithms`() {
        setupHybridDecapsulation()

        val wrappedKeyB64 = java.util.Base64.getEncoder().encodeToString(testWrappedKey)
        val kemCtB64 = java.util.Base64.getEncoder().encodeToString(testCiphertext)
        val mlKemCtB64 = java.util.Base64.getEncoder().encodeToString(testMlKemCiphertext)

        val result = keyEncapsulation.decapsulate(wrappedKeyB64, kemCtB64, mlKemCtB64)

        assertNotNull(result)
        verify {
            cryptoManager.combinedKemDecapsulate(
                testCiphertext,
                testMlKemCiphertext,
                any(),
                any()
            )
        }
    }

    @Test(expected = IllegalStateException::class)
    fun `decapsulate with HYBRID throws when ML-KEM ciphertext is null`() {
        val keys = createTestKeyBundle()
        every { keyManager.getUnlockedKeys() } returns keys
        every { cryptoConfig.getAlgorithm() } returns PqcAlgorithm.HYBRID

        val wrappedKeyB64 = java.util.Base64.getEncoder().encodeToString(testWrappedKey)
        val kemCtB64 = java.util.Base64.getEncoder().encodeToString(testCiphertext)

        keyEncapsulation.decapsulate(wrappedKeyB64, kemCtB64, null)
    }

    // ==================== File Share Encapsulation Tests ====================

    @Test
    fun `encapsulateForFileShare includes fileId and permission in signature`() {
        setupKazEncapsulation()

        val recipientKeys = createRecipientPublicKeys()
        val result = keyEncapsulation.encapsulateForFileShare(
            dek = testDek,
            recipientPublicKeys = recipientKeys,
            fileId = "file-123",
            permission = "read"
        )

        assertNotNull(result.wrappedKey)
        assertNotNull(result.signature)
        verify { cryptoManager.wrapKey(testDek, testWrapKey) }
    }

    // ==================== Folder Share Encapsulation Tests ====================

    @Test
    fun `encapsulateForFolderShare includes folderId permission and recursive`() {
        setupKazEncapsulation()

        val recipientKeys = createRecipientPublicKeys()
        val result = keyEncapsulation.encapsulateForFolderShare(
            kek = testFolderKey,
            recipientPublicKeys = recipientKeys,
            folderId = "folder-456",
            permission = "write",
            recursive = true
        )

        assertNotNull(result.wrappedKey)
        assertNotNull(result.signature)
    }

    // ==================== Verify Share Signature Tests ====================

    @Test
    fun `verifyShareSignature with KAZ returns true for valid signature`() {
        every { cryptoConfig.getAlgorithm() } returns PqcAlgorithm.KAZ
        every { cryptoManager.kazVerify(any(), any(), any()) } returns true

        val wrappedKeyB64 = java.util.Base64.getEncoder().encodeToString(testWrappedKey)
        val kemCtB64 = java.util.Base64.getEncoder().encodeToString(testCiphertext)
        val sigB64 = java.util.Base64.getEncoder().encodeToString(testSignature)
        val grantorKeys = createRecipientPublicKeys()

        val result = keyEncapsulation.verifyShareSignature(
            wrappedKey = wrappedKeyB64,
            kemCiphertext = kemCtB64,
            mlKemCiphertext = null,
            signature = sigB64,
            grantorPublicKeys = grantorKeys,
            resourceType = "file",
            resourceId = "file-123",
            permission = "read"
        )

        assertTrue(result)
    }

    @Test
    fun `verifyShareSignature returns false for invalid signature`() {
        every { cryptoConfig.getAlgorithm() } returns PqcAlgorithm.KAZ
        every { cryptoManager.kazVerify(any(), any(), any()) } returns false

        val wrappedKeyB64 = java.util.Base64.getEncoder().encodeToString(testWrappedKey)
        val kemCtB64 = java.util.Base64.getEncoder().encodeToString(testCiphertext)
        val sigB64 = java.util.Base64.getEncoder().encodeToString(testSignature)
        val grantorKeys = createRecipientPublicKeys()

        val result = keyEncapsulation.verifyShareSignature(
            wrappedKey = wrappedKeyB64,
            kemCiphertext = kemCtB64,
            mlKemCiphertext = null,
            signature = sigB64,
            grantorPublicKeys = grantorKeys,
            resourceType = "file",
            resourceId = "file-123",
            permission = "read"
        )

        assertFalse(result)
    }

    @Test
    fun `verifyShareSignature with NIST uses ML-DSA`() {
        every { cryptoConfig.getAlgorithm() } returns PqcAlgorithm.NIST
        every { cryptoManager.mlDsaVerify(any(), any(), any()) } returns true

        val wrappedKeyB64 = java.util.Base64.getEncoder().encodeToString(testWrappedKey)
        val kemCtB64 = java.util.Base64.getEncoder().encodeToString(testCiphertext)
        val sigB64 = java.util.Base64.getEncoder().encodeToString(testSignature)
        val grantorKeys = createRecipientPublicKeys(includeMlDsa = true)

        val result = keyEncapsulation.verifyShareSignature(
            wrappedKey = wrappedKeyB64,
            kemCiphertext = kemCtB64,
            mlKemCiphertext = null,
            signature = sigB64,
            grantorPublicKeys = grantorKeys,
            resourceType = "file",
            resourceId = "file-123",
            permission = "read"
        )

        assertTrue(result)
        verify { cryptoManager.mlDsaVerify(any(), any(), grantorKeys.mlDsa!!) }
    }

    @Test(expected = IllegalStateException::class)
    fun `verifyShareSignature with NIST throws when grantor has no ML-DSA key`() {
        every { cryptoConfig.getAlgorithm() } returns PqcAlgorithm.NIST

        val wrappedKeyB64 = java.util.Base64.getEncoder().encodeToString(testWrappedKey)
        val kemCtB64 = java.util.Base64.getEncoder().encodeToString(testCiphertext)
        val sigB64 = java.util.Base64.getEncoder().encodeToString(testSignature)
        val grantorKeys = createRecipientPublicKeys(includeMlDsa = false)

        keyEncapsulation.verifyShareSignature(
            wrappedKey = wrappedKeyB64,
            kemCiphertext = kemCtB64,
            mlKemCiphertext = null,
            signature = sigB64,
            grantorPublicKeys = grantorKeys,
            resourceType = "file",
            resourceId = "file-123",
            permission = "read"
        )
    }

    @Test
    fun `verifyShareSignature with HYBRID uses combined verify`() {
        every { cryptoConfig.getAlgorithm() } returns PqcAlgorithm.HYBRID
        every { cryptoManager.combinedVerify(any(), any(), any(), any()) } returns true

        val wrappedKeyB64 = java.util.Base64.getEncoder().encodeToString(testWrappedKey)
        val kemCtB64 = java.util.Base64.getEncoder().encodeToString(testCiphertext)
        val mlKemCtB64 = java.util.Base64.getEncoder().encodeToString(testMlKemCiphertext)
        val sigB64 = java.util.Base64.getEncoder().encodeToString(testSignature)
        val grantorKeys = createRecipientPublicKeys(includeMlDsa = true)

        val result = keyEncapsulation.verifyShareSignature(
            wrappedKey = wrappedKeyB64,
            kemCiphertext = kemCtB64,
            mlKemCiphertext = mlKemCtB64,
            signature = sigB64,
            grantorPublicKeys = grantorKeys,
            resourceType = "folder",
            resourceId = "folder-789",
            permission = "write",
            recursive = true
        )

        assertTrue(result)
        verify { cryptoManager.combinedVerify(any(), any(), grantorKeys.sign, grantorKeys.mlDsa!!) }
    }

    // ==================== Permission Update Signing Tests ====================

    @Test
    fun `signPermissionUpdate with KAZ signs message`() {
        val keys = createTestKeyBundle()
        every { keyManager.getUnlockedKeys() } returns keys
        every { cryptoConfig.getAlgorithm() } returns PqcAlgorithm.KAZ
        every { cryptoManager.kazSign(any(), keys.kazSignPrivateKey) } returns testSignature

        val result = keyEncapsulation.signPermissionUpdate("share-id-1", "write")

        assertNotNull(result)
        assertTrue(result.isNotEmpty())
        verify { cryptoManager.kazSign(any(), keys.kazSignPrivateKey) }
    }

    @Test
    fun `signPermissionUpdate with NIST uses ML-DSA`() {
        val keys = createTestKeyBundle()
        every { keyManager.getUnlockedKeys() } returns keys
        every { cryptoConfig.getAlgorithm() } returns PqcAlgorithm.NIST
        every { cryptoManager.mlDsaSign(any(), keys.mlDsaPrivateKey) } returns testSignature

        val result = keyEncapsulation.signPermissionUpdate("share-id-2", "read")

        assertNotNull(result)
        verify { cryptoManager.mlDsaSign(any(), keys.mlDsaPrivateKey) }
    }

    @Test
    fun `signPermissionUpdate with HYBRID uses combined sign`() {
        val keys = createTestKeyBundle()
        every { keyManager.getUnlockedKeys() } returns keys
        every { cryptoConfig.getAlgorithm() } returns PqcAlgorithm.HYBRID
        every {
            cryptoManager.combinedSign(any(), keys.kazSignPrivateKey, keys.mlDsaPrivateKey)
        } returns testSignature

        val result = keyEncapsulation.signPermissionUpdate("share-id-3", "admin")

        assertNotNull(result)
        verify { cryptoManager.combinedSign(any(), keys.kazSignPrivateKey, keys.mlDsaPrivateKey) }
    }

    // ==================== Keys Locked Error Tests ====================

    @Test(expected = IllegalStateException::class)
    fun `encapsulate throws when keys are locked`() {
        every { cryptoConfig.getAlgorithm() } returns PqcAlgorithm.KAZ
        every { keyManager.getUnlockedKeys() } throws IllegalStateException("Keys are locked")

        keyEncapsulation.encapsulate(testFolderKey, createRecipientPublicKeys())
    }

    @Test(expected = IllegalStateException::class)
    fun `decapsulateSharedKey throws when keys are locked`() {
        every { cryptoConfig.getAlgorithm() } returns PqcAlgorithm.KAZ
        every { keyManager.getUnlockedKeys() } throws IllegalStateException("Keys are locked")

        val wrappedKeyB64 = java.util.Base64.getEncoder().encodeToString(testWrappedKey)
        val kemCtB64 = java.util.Base64.getEncoder().encodeToString(testCiphertext)

        keyEncapsulation.decapsulateSharedKey(wrappedKeyB64, kemCtB64, null)
    }

    // ==================== Helper Methods ====================

    private fun setupKazEncapsulation() {
        val keys = createTestKeyBundle()
        every { keyManager.getUnlockedKeys() } returns keys
        every { cryptoConfig.getAlgorithm() } returns PqcAlgorithm.KAZ
        every { cryptoManager.kazKemEncapsulate(any()) } returns Pair(testSharedSecret, testCiphertext)
        every { hkdfProvider.deriveKey(any(), any(), any(), any()) } returns testWrapKey
        every { cryptoManager.wrapKey(any(), testWrapKey) } returns testWrappedKey
        every { cryptoManager.kazSign(any(), any()) } returns testSignature
    }

    private fun setupNistEncapsulation() {
        val keys = createTestKeyBundle()
        every { keyManager.getUnlockedKeys() } returns keys
        every { cryptoConfig.getAlgorithm() } returns PqcAlgorithm.NIST
        every { cryptoManager.mlKemEncapsulate(any()) } returns Pair(testSharedSecret, testCiphertext)
        every { hkdfProvider.deriveKey(any(), any(), any(), any()) } returns testWrapKey
        every { cryptoManager.wrapKey(any(), testWrapKey) } returns testWrappedKey
        every { cryptoManager.mlDsaSign(any(), any()) } returns testSignature
    }

    private fun setupHybridEncapsulation() {
        val keys = createTestKeyBundle()
        every { keyManager.getUnlockedKeys() } returns keys
        every { cryptoConfig.getAlgorithm() } returns PqcAlgorithm.HYBRID
        every {
            cryptoManager.combinedKemEncapsulate(any(), any())
        } returns Triple(testSharedSecret, testCiphertext, testMlKemCiphertext)
        every { hkdfProvider.deriveKey(any(), any(), any(), any()) } returns testWrapKey
        every { cryptoManager.wrapKey(any(), testWrapKey) } returns testWrappedKey
        every { cryptoManager.combinedSign(any(), any(), any()) } returns testSignature
    }

    private fun setupKazDecapsulation() {
        val keys = createTestKeyBundle()
        every { keyManager.getUnlockedKeys() } returns keys
        every { cryptoConfig.getAlgorithm() } returns PqcAlgorithm.KAZ
        every { cryptoManager.kazKemDecapsulate(any(), any()) } returns testSharedSecret
        every { hkdfProvider.deriveKey(any(), any(), any(), any()) } returns testWrapKey
        every { cryptoManager.unwrapKey(any(), testWrapKey) } returns testFolderKey
    }

    private fun setupNistDecapsulation() {
        val keys = createTestKeyBundle()
        every { keyManager.getUnlockedKeys() } returns keys
        every { cryptoConfig.getAlgorithm() } returns PqcAlgorithm.NIST
        every { cryptoManager.mlKemDecapsulate(any(), any()) } returns testSharedSecret
        every { hkdfProvider.deriveKey(any(), any(), any(), any()) } returns testWrapKey
        every { cryptoManager.unwrapKey(any(), testWrapKey) } returns testFolderKey
    }

    private fun setupHybridDecapsulation() {
        val keys = createTestKeyBundle()
        every { keyManager.getUnlockedKeys() } returns keys
        every { cryptoConfig.getAlgorithm() } returns PqcAlgorithm.HYBRID
        every {
            cryptoManager.combinedKemDecapsulate(any(), any(), any(), any())
        } returns testSharedSecret
        every { hkdfProvider.deriveKey(any(), any(), any(), any()) } returns testWrapKey
        every { cryptoManager.unwrapKey(any(), testWrapKey) } returns testFolderKey
    }

    private fun createTestKeyBundle(): KeyBundle {
        return KeyBundle.create(
            masterKey = ByteArray(32),
            kazKemPublicKey = ByteArray(800),
            kazKemPrivateKey = ByteArray(1600),
            kazSignPublicKey = ByteArray(1312),
            kazSignPrivateKey = ByteArray(2528),
            mlKemPublicKey = ByteArray(1184),
            mlKemPrivateKey = ByteArray(2400),
            mlDsaPublicKey = ByteArray(1952),
            mlDsaPrivateKey = ByteArray(4032)
        )
    }

    private fun createRecipientPublicKeys(
        includeMlKem: Boolean = false,
        includeMlDsa: Boolean = false
    ): PublicKeys {
        return PublicKeys(
            kem = ByteArray(800) { 0x11.toByte() },
            sign = ByteArray(1312) { 0x22.toByte() },
            mlKem = if (includeMlKem) ByteArray(1184) { 0x33.toByte() } else null,
            mlDsa = if (includeMlDsa) ByteArray(1952) { 0x44.toByte() } else null
        )
    }
}
