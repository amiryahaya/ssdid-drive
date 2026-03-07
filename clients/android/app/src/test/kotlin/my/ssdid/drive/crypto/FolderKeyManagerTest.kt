package my.ssdid.drive.crypto

import android.util.Base64
import my.ssdid.drive.domain.model.FolderMetadata
import io.mockk.every
import io.mockk.mockk
import io.mockk.mockkStatic
import io.mockk.verify
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

/**
 * Unit tests for FolderKeyManager.
 *
 * Tests cover:
 * - KEK caching (put, get, clear)
 * - Cache eviction and zeroization of evicted KEKs
 * - Cache statistics
 * - Child folder KEK decryption via parent KEK
 * - Folder metadata encryption/decryption round-trip
 * - Metadata nonce extraction
 * - KEK re-wrapping for folder moves
 * - Backward-compatible metadata decryption (without AAD)
 */
class FolderKeyManagerTest {

    private lateinit var cryptoManager: CryptoManager
    private lateinit var keyManager: KeyManager
    private lateinit var folderKeyManager: FolderKeyManager

    private val testKek = ByteArray(32) { it.toByte() }
    private val testParentKek = ByteArray(32) { (it + 100).toByte() }
    private val testFolderId = "folder-abc"

    @Before
    fun setup() {
        cryptoManager = mockk(relaxed = true)
        keyManager = mockk(relaxed = true)

        // Mock Base64 since it's an Android API
        mockkStatic(Base64::class)
        every { Base64.encodeToString(any(), any()) } answers {
            java.util.Base64.getEncoder().encodeToString(firstArg<ByteArray>())
        }
        every { Base64.decode(any<String>(), any()) } answers {
            java.util.Base64.getDecoder().decode(firstArg<String>())
        }

        folderKeyManager = FolderKeyManager(
            cryptoManager = cryptoManager,
            keyManager = keyManager
        )
    }

    // ==================== KEK Cache Tests ====================

    @Test
    fun `cacheKek stores KEK and getCachedKek retrieves it`() {
        folderKeyManager.cacheKek(testFolderId, testKek)

        val cached = folderKeyManager.getCachedKek(testFolderId)

        assertNotNull(cached)
        assertArrayEquals(testKek, cached)
    }

    @Test
    fun `cacheKek stores a copy of the KEK`() {
        val originalKek = ByteArray(32) { 0xAA.toByte() }
        folderKeyManager.cacheKek(testFolderId, originalKek)

        // Modify the original - cache should not be affected
        originalKek.fill(0)

        val cached = folderKeyManager.getCachedKek(testFolderId)
        assertNotNull(cached)
        assertTrue("Cached KEK should not be zeroed", cached!!.any { it != 0.toByte() })
    }

    @Test
    fun `getCachedKek returns null for unknown folder`() {
        val result = folderKeyManager.getCachedKek("nonexistent-folder")
        assertNull(result)
    }

    @Test
    fun `clearCache removes all cached KEKs`() {
        folderKeyManager.cacheKek("folder-1", ByteArray(32) { 1 })
        folderKeyManager.cacheKek("folder-2", ByteArray(32) { 2 })
        folderKeyManager.cacheKek("folder-3", ByteArray(32) { 3 })

        folderKeyManager.clearCache()

        assertNull(folderKeyManager.getCachedKek("folder-1"))
        assertNull(folderKeyManager.getCachedKek("folder-2"))
        assertNull(folderKeyManager.getCachedKek("folder-3"))
    }

    @Test
    fun `clearCache zeroizes all KEKs before eviction`() {
        val kek1 = ByteArray(32) { 0xAA.toByte() }
        val kek2 = ByteArray(32) { 0xBB.toByte() }
        folderKeyManager.cacheKek("folder-1", kek1)
        folderKeyManager.cacheKek("folder-2", kek2)

        folderKeyManager.clearCache()

        // Verify zeroize was called for the cached copies
        verify(atLeast = 2) { cryptoManager.zeroize(any<ByteArray>()) }
    }

    @Test
    fun `cacheKek overwrites previous KEK for same folder`() {
        val kek1 = ByteArray(32) { 0x11.toByte() }
        val kek2 = ByteArray(32) { 0x22.toByte() }

        folderKeyManager.cacheKek(testFolderId, kek1)
        folderKeyManager.cacheKek(testFolderId, kek2)

        val cached = folderKeyManager.getCachedKek(testFolderId)
        assertNotNull(cached)
        assertArrayEquals(kek2, cached)
    }

    // ==================== Cache Statistics Tests ====================

    @Test
    fun `getCacheStats returns correct size`() {
        folderKeyManager.cacheKek("a", ByteArray(32))
        folderKeyManager.cacheKek("b", ByteArray(32))

        val stats = folderKeyManager.getCacheStats()

        assertEquals(2, stats.size)
        assertEquals(100, stats.maxSize)
    }

    @Test
    fun `getCacheStats tracks hits and misses`() {
        folderKeyManager.cacheKek("exists", ByteArray(32))

        // Hit
        folderKeyManager.getCachedKek("exists")
        // Miss
        folderKeyManager.getCachedKek("not-exists")

        val stats = folderKeyManager.getCacheStats()
        assertTrue("Hit count should be >= 1", stats.hitCount >= 1)
        assertTrue("Miss count should be >= 1", stats.missCount >= 1)
    }

    @Test
    fun `CacheStats hitRate is zero when no accesses`() {
        val stats = FolderKeyManager.CacheStats(
            size = 0,
            maxSize = 100,
            hitCount = 0,
            missCount = 0
        )
        assertEquals(0f, stats.hitRate)
    }

    @Test
    fun `CacheStats hitRate computes correctly`() {
        val stats = FolderKeyManager.CacheStats(
            size = 5,
            maxSize = 100,
            hitCount = 3,
            missCount = 1
        )
        assertEquals(0.75f, stats.hitRate)
    }

    // ==================== decryptChildFolderKek Tests ====================

    @Test
    fun `decryptChildFolderKek unwraps KEK using parent KEK`() {
        val childKek = ByteArray(32) { 0xCC.toByte() }
        val wrappedKekBytes = ByteArray(60) { 0xDD.toByte() }
        val wrappedKekBase64 = java.util.Base64.getEncoder().encodeToString(wrappedKekBytes)

        every { cryptoManager.unwrapKey(wrappedKekBytes, testParentKek) } returns childKek

        val result = folderKeyManager.decryptChildFolderKek(
            folderId = "child-folder",
            parentKek = testParentKek,
            wrappedKek = wrappedKekBase64
        )

        assertArrayEquals(childKek, result)
    }

    @Test
    fun `decryptChildFolderKek caches the result`() {
        val childKek = ByteArray(32) { 0xCC.toByte() }
        val wrappedKekBytes = ByteArray(60) { 0xDD.toByte() }
        val wrappedKekBase64 = java.util.Base64.getEncoder().encodeToString(wrappedKekBytes)
        val childFolderId = "child-folder-cached"

        every { cryptoManager.unwrapKey(wrappedKekBytes, testParentKek) } returns childKek

        folderKeyManager.decryptChildFolderKek(
            folderId = childFolderId,
            parentKek = testParentKek,
            wrappedKek = wrappedKekBase64
        )

        // Second call should use cache
        val cached = folderKeyManager.getCachedKek(childFolderId)
        assertNotNull(cached)
        assertArrayEquals(childKek, cached)
    }

    @Test
    fun `decryptChildFolderKek returns cached KEK if available`() {
        val cachedKek = ByteArray(32) { 0xEE.toByte() }
        val childFolderId = "already-cached"

        folderKeyManager.cacheKek(childFolderId, cachedKek)

        val result = folderKeyManager.decryptChildFolderKek(
            folderId = childFolderId,
            parentKek = testParentKek,
            wrappedKek = "irrelevant"
        )

        assertArrayEquals(cachedKek, result)
        // unwrapKey should NOT be called since cache hit
        verify(exactly = 0) { cryptoManager.unwrapKey(any(), any()) }
    }

    // ==================== Metadata Encryption/Decryption Tests ====================

    @Test
    fun `encryptMetadata encrypts folder metadata with KEK and AAD`() {
        val metadata = FolderMetadata(name = "My Folder")
        val encryptedBytes = ByteArray(80) { it.toByte() }

        every {
            cryptoManager.encryptAesGcmWithAad(any(), testKek, "folder-metadata".toByteArray(Charsets.UTF_8))
        } returns encryptedBytes

        val result = folderKeyManager.encryptMetadata(metadata, testKek)

        assertNotNull(result)
        assertTrue(result.isNotEmpty())
        verify {
            cryptoManager.encryptAesGcmWithAad(any(), testKek, "folder-metadata".toByteArray(Charsets.UTF_8))
        }
    }

    @Test
    fun `decryptMetadata decrypts folder metadata with KEK and AAD`() {
        val metadataJson = """{"name":"Documents","color":"blue"}"""
        val encryptedBytes = ByteArray(80) { it.toByte() }
        val encryptedBase64 = java.util.Base64.getEncoder().encodeToString(encryptedBytes)

        every {
            cryptoManager.decryptAesGcmWithAad(
                ciphertext = encryptedBytes,
                key = testKek,
                aad = "folder-metadata".toByteArray(Charsets.UTF_8)
            )
        } returns metadataJson.toByteArray()

        val result = folderKeyManager.decryptMetadata(encryptedBase64, testKek)

        assertEquals("Documents", result.name)
    }

    @Test
    fun `decryptMetadata falls back to non-AAD for backward compatibility`() {
        val metadataJson = """{"name":"Old Folder"}"""
        val encryptedBytes = ByteArray(60) { it.toByte() }
        val encryptedBase64 = java.util.Base64.getEncoder().encodeToString(encryptedBytes)

        every {
            cryptoManager.decryptAesGcmWithAad(any(), testKek, any())
        } throws RuntimeException("AAD mismatch")
        every {
            cryptoManager.decryptAesGcm(encryptedBytes, testKek)
        } returns metadataJson.toByteArray()

        val result = folderKeyManager.decryptMetadata(encryptedBase64, testKek)

        assertEquals("Old Folder", result.name)
        verify { cryptoManager.decryptAesGcm(encryptedBytes, testKek) }
    }

    // ==================== extractMetadataNonce Tests ====================

    @Test
    fun `extractMetadataNonce extracts first 12 bytes as nonce`() {
        // Create a byte array where the first 12 bytes are the nonce
        val data = ByteArray(50) { it.toByte() }
        val encryptedBase64 = java.util.Base64.getEncoder().encodeToString(data)

        val nonceBase64 = folderKeyManager.extractMetadataNonce(encryptedBase64)

        val nonceBytes = java.util.Base64.getDecoder().decode(nonceBase64)
        assertEquals(12, nonceBytes.size)
        // Should be first 12 bytes of the data
        assertArrayEquals(data.copyOfRange(0, 12), nonceBytes)
    }

    @Test
    fun `extractMetadataNonce throws for data shorter than nonce size`() {
        val shortData = ByteArray(5) { it.toByte() }
        val shortBase64 = java.util.Base64.getEncoder().encodeToString(shortData)

        assertThrows(IllegalArgumentException::class.java) {
            folderKeyManager.extractMetadataNonce(shortBase64)
        }
    }

    // ==================== rewrapKekForParent Tests ====================

    @Test
    fun `rewrapKekForParent wraps KEK with new parent KEK`() {
        val kek = ByteArray(32) { 0xAA.toByte() }
        val newParentKek = ByteArray(32) { 0xBB.toByte() }
        val wrappedResult = ByteArray(60) { 0xCC.toByte() }

        every { cryptoManager.wrapKey(kek, newParentKek) } returns wrappedResult

        val result = folderKeyManager.rewrapKekForParent(kek, newParentKek)

        assertNotNull(result.wrappedKek)
        assertTrue(result.wrappedKek.isNotEmpty())
        assertNull("KEM ciphertext should be null for parent-wrap", result.kemCiphertext)

        // Verify the wrapped data decodes to the expected bytes
        val decoded = java.util.Base64.getDecoder().decode(result.wrappedKek)
        assertArrayEquals(wrappedResult, decoded)
    }

    // ==================== decryptFolderKek Tests ====================

    @Test
    fun `decryptFolderKek returns cached KEK if available`() {
        folderKeyManager.cacheKek(testFolderId, testKek)

        val result = folderKeyManager.decryptFolderKek(
            folderId = testFolderId,
            ownerKemCiphertext = "irrelevant",
            ownerWrappedKek = "irrelevant"
        )

        assertArrayEquals(testKek, result)
        // No KEM operations should be called
        verify(exactly = 0) { cryptoManager.kazKemDecapsulate(any(), any()) }
    }

    @Test
    fun `decryptFolderKek with KAZ algorithm decapsulates and unwraps`() {
        val kemCiphertext = ByteArray(768) { it.toByte() }
        val wrappedKek = ByteArray(60) { (it + 10).toByte() }
        val sharedSecret = ByteArray(32) { 0xAA.toByte() }
        val derivedUnwrapKey = ByteArray(32) { 0xBB.toByte() }
        val decryptedKek = ByteArray(32) { 0xCC.toByte() }

        val kemCtBase64 = java.util.Base64.getEncoder().encodeToString(kemCiphertext)
        val wrappedKekBase64 = java.util.Base64.getEncoder().encodeToString(wrappedKek)

        val keys = createTestKeyBundle()
        every { keyManager.getUnlockedKeys() } returns keys
        every { cryptoManager.cryptoConfig } returns mockk {
            every { getAlgorithm() } returns PqcAlgorithm.KAZ
        }
        every { cryptoManager.kazKemDecapsulate(kemCiphertext, keys.kazKemPrivateKey) } returns sharedSecret
        every {
            cryptoManager.hkdfProvider.deriveKey(
                ikm = sharedSecret,
                salt = "SsdidDrive-FolderKEK".toByteArray(),
                info = "kek-unwrap".toByteArray(),
                length = 32
            )
        } returns derivedUnwrapKey
        every { cryptoManager.unwrapKey(wrappedKek, derivedUnwrapKey) } returns decryptedKek

        val result = folderKeyManager.decryptFolderKek(
            folderId = "new-folder",
            ownerKemCiphertext = kemCtBase64,
            ownerWrappedKek = wrappedKekBase64
        )

        assertArrayEquals(decryptedKek, result)

        // Verify intermediate values are zeroized
        verify { cryptoManager.zeroize(sharedSecret) }
        verify { cryptoManager.zeroize(derivedUnwrapKey) }
    }

    // ==================== createRootFolderEncryption Tests ====================

    @Test
    fun `createRootFolderEncryption generates KEK and encryption data`() {
        val generatedKek = ByteArray(32) { 0x11.toByte() }
        val sharedSecret = ByteArray(32) { 0x22.toByte() }
        val kemCiphertext = ByteArray(768) { 0x33.toByte() }
        val wrapKey = ByteArray(32) { 0x44.toByte() }
        val wrappedKek = ByteArray(60) { 0x55.toByte() }
        val encryptedMeta = ByteArray(80) { 0x66.toByte() }

        val keys = createTestKeyBundle()
        every { keyManager.getUnlockedKeys() } returns keys
        every { cryptoManager.cryptoConfig } returns mockk {
            every { getAlgorithm() } returns PqcAlgorithm.KAZ
        }
        every { cryptoManager.generateKey() } returns generatedKek
        every { cryptoManager.kazKemEncapsulate(keys.kazKemPublicKey) } returns Pair(sharedSecret, kemCiphertext)
        every {
            cryptoManager.hkdfProvider.deriveKey(any(), any(), any(), any())
        } returns wrapKey
        every { cryptoManager.wrapKey(generatedKek, wrapKey) } returns wrappedKek
        every { cryptoManager.encryptAesGcmWithAad(any(), generatedKek, any()) } returns encryptedMeta

        val result = folderKeyManager.createRootFolderEncryption("My Root Folder")

        assertArrayEquals(generatedKek, result.kek)
        assertTrue(result.wrappedKek.isNotEmpty())
        assertTrue(result.kemCiphertext.isNotEmpty())
        assertTrue(result.encryptedMetadata.isNotEmpty())
        assertTrue(result.metadataNonce.isNotEmpty())
        // For root folder, owner access equals regular access
        assertEquals(result.wrappedKek, result.ownerWrappedKek)
        assertEquals(result.kemCiphertext, result.ownerKemCiphertext)
    }

    // ==================== createChildFolderEncryption Tests ====================

    @Test
    fun `createChildFolderEncryption wraps KEK with parent KEK`() {
        val generatedKek = ByteArray(32) { 0x11.toByte() }
        val parentWrapped = ByteArray(60) { 0x22.toByte() }
        val ownerSharedSecret = ByteArray(32) { 0x33.toByte() }
        val ownerKemCt = ByteArray(768) { 0x44.toByte() }
        val ownerWrapKey = ByteArray(32) { 0x55.toByte() }
        val ownerWrapped = ByteArray(60) { 0x66.toByte() }
        val encryptedMeta = ByteArray(80) { 0x77.toByte() }

        val keys = createTestKeyBundle()
        every { keyManager.getUnlockedKeys() } returns keys
        every { cryptoManager.cryptoConfig } returns mockk {
            every { getAlgorithm() } returns PqcAlgorithm.KAZ
        }
        every { cryptoManager.generateKey() } returns generatedKek
        every { cryptoManager.wrapKey(generatedKek, testParentKek) } returns parentWrapped
        every { cryptoManager.kazKemEncapsulate(keys.kazKemPublicKey) } returns Pair(ownerSharedSecret, ownerKemCt)
        every {
            cryptoManager.hkdfProvider.deriveKey(any(), any(), any(), any())
        } returns ownerWrapKey
        every { cryptoManager.wrapKey(generatedKek, ownerWrapKey) } returns ownerWrapped
        every { cryptoManager.encryptAesGcmWithAad(any(), generatedKek, any()) } returns encryptedMeta

        val result = folderKeyManager.createChildFolderEncryption("Child Folder", testParentKek)

        assertArrayEquals(generatedKek, result.kek)
        // wrappedKek should be the parent-wrapped version
        val decodedWrapped = java.util.Base64.getDecoder().decode(result.wrappedKek)
        assertArrayEquals(parentWrapped, decodedWrapped)
        // kemCiphertext should be empty for child folders
        assertEquals("", result.kemCiphertext)
        // Owner access should use PQC
        assertTrue(result.ownerWrappedKek.isNotEmpty())
        assertTrue(result.ownerKemCiphertext.isNotEmpty())
    }

    // ==================== Helper Methods ====================

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
}
