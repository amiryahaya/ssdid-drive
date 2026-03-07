package my.ssdid.drive.crypto

import android.content.ContentResolver
import android.content.Context
import android.net.Uri
import android.util.Base64
import my.ssdid.drive.domain.model.FileMetadata
import my.ssdid.drive.util.BufferPool
import io.mockk.every
import io.mockk.mockk
import io.mockk.mockkStatic
import io.mockk.slot
import io.mockk.verify
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream

/**
 * Unit tests for FileEncryptor.
 *
 * Tests cover:
 * - Metadata encryption with DEK
 * - DEK re-wrapping for folder moves
 * - Encrypt-from-stream flow with mocked crypto
 * - Progress callback invocation
 * - Failure handling / DEK zeroization
 * - EncryptionResult zeroize
 */
class FileEncryptorTest {

    private lateinit var context: Context
    private lateinit var contentResolver: ContentResolver
    private lateinit var cryptoManager: CryptoManager
    private lateinit var keyManager: KeyManager
    private lateinit var folderKeyManager: FolderKeyManager
    private lateinit var bufferPool: BufferPool
    private lateinit var fileEncryptor: FileEncryptor

    private val testDek = ByteArray(32) { it.toByte() }
    private val testKek = ByteArray(32) { (it + 50).toByte() }
    private val testFolderId = "folder-123"

    @Before
    fun setup() {
        context = mockk(relaxed = true)
        contentResolver = mockk(relaxed = true)
        cryptoManager = mockk(relaxed = true)
        keyManager = mockk(relaxed = true)
        folderKeyManager = mockk(relaxed = true)
        bufferPool = BufferPool()

        every { context.contentResolver } returns contentResolver

        // Mock Base64 since it's an Android API
        mockkStatic(Base64::class)
        every { Base64.encodeToString(any(), any()) } answers {
            java.util.Base64.getEncoder().encodeToString(firstArg<ByteArray>())
        }
        every { Base64.decode(any<String>(), any()) } answers {
            java.util.Base64.getDecoder().decode(firstArg<String>())
        }

        fileEncryptor = FileEncryptor(
            context = context,
            cryptoManager = cryptoManager,
            keyManager = keyManager,
            folderKeyManager = folderKeyManager,
            bufferPool = bufferPool
        )
    }

    // ==================== encryptMetadataWithDek Tests ====================

    @Test
    fun `encryptMetadataWithDek encrypts metadata JSON with AES-GCM and AAD`() {
        val metadata = FileMetadata(name = "test.pdf", mimeType = "application/pdf", size = 1024)
        val encryptedBytes = ByteArray(64) { it.toByte() }

        every {
            cryptoManager.encryptAesGcmWithAad(
                plaintext = any(),
                key = testDek,
                aad = any()
            )
        } returns encryptedBytes

        val result = fileEncryptor.encryptMetadataWithDek(metadata, testDek)

        assertNotNull(result)
        assertTrue(result.isNotEmpty())
        verify {
            cryptoManager.encryptAesGcmWithAad(
                plaintext = any(),
                key = testDek,
                aad = "file-metadata".toByteArray(Charsets.UTF_8)
            )
        }
    }

    @Test
    fun `encryptMetadataWithDek includes filename, mimeType and size in plaintext`() {
        val metadata = FileMetadata(name = "report.docx", mimeType = "application/vnd.openxmlformats", size = 5000)
        val plaintextSlot = slot<ByteArray>()

        every {
            cryptoManager.encryptAesGcmWithAad(
                plaintext = capture(plaintextSlot),
                key = any(),
                aad = any()
            )
        } returns ByteArray(80)

        fileEncryptor.encryptMetadataWithDek(metadata, testDek)

        val json = String(plaintextSlot.captured, Charsets.UTF_8)
        assertTrue("JSON should contain filename", json.contains("report.docx"))
        assertTrue("JSON should contain mimeType", json.contains("application/vnd.openxmlformats"))
        assertTrue("JSON should contain size", json.contains("5000"))
    }

    // ==================== rewrapDek Tests ====================

    @Test
    fun `rewrapDek wraps DEK with new folder KEK`() {
        val newKek = ByteArray(32) { (it + 100).toByte() }
        val wrappedResult = ByteArray(60) { it.toByte() }

        every { cryptoManager.wrapKey(testDek, newKek) } returns wrappedResult

        val result = fileEncryptor.rewrapDek(testDek, newKek)

        assertNotNull(result)
        assertTrue(result.isNotEmpty())
        verify { cryptoManager.wrapKey(testDek, newKek) }
    }

    @Test
    fun `rewrapDek returns Base64 encoded wrapped key`() {
        val wrappedBytes = ByteArray(48) { (it * 3).toByte() }
        every { cryptoManager.wrapKey(any(), any()) } returns wrappedBytes

        val result = fileEncryptor.rewrapDek(testDek, testKek)

        // Decode the result to verify it matches the wrapped bytes
        val decoded = java.util.Base64.getDecoder().decode(result)
        assertArrayEquals(wrappedBytes, decoded)
    }

    // ==================== encryptFileFromStream Tests ====================

    @Test
    fun `encryptFileFromStream throws when folder KEK not cached`() {
        every { folderKeyManager.getCachedKek(testFolderId) } returns null

        val inputStream = ByteArrayInputStream(ByteArray(100))
        val outputStream = ByteArrayOutputStream()

        assertThrows(IllegalStateException::class.java) {
            runBlocking {
                fileEncryptor.encryptFileFromStream(
                    inputStream = inputStream,
                    fileName = "test.txt",
                    mimeType = "text/plain",
                    fileSize = 100,
                    folderId = testFolderId,
                    outputStream = outputStream
                )
            }
        }
    }

    @Test
    fun `encryptFileFromStream generates DEK and wraps with KEK`() = runBlocking {
        val plaintext = ByteArray(256) { (it % 256).toByte() }
        val generatedDek = ByteArray(32) { 0xAA.toByte() }
        val wrappedDek = ByteArray(60) { 0xBB.toByte() }
        val encryptedChunk = ByteArray(256 + 28) { 0xCC.toByte() }
        val encryptedMetadata = ByteArray(80) { 0xDD.toByte() }
        val signature = ByteArray(100) { 0xEE.toByte() }

        every { folderKeyManager.getCachedKek(testFolderId) } returns testKek
        every { cryptoManager.generateKey() } returns generatedDek
        every { cryptoManager.wrapKey(generatedDek, testKek) } returns wrappedDek
        every { cryptoManager.encryptAesGcm(any(), generatedDek) } returns encryptedChunk
        every { cryptoManager.encryptAesGcmWithAad(any(), generatedDek, any()) } returns encryptedMetadata

        val keys = createTestKeyBundle()
        every { keyManager.getUnlockedKeys() } returns keys
        every { cryptoManager.cryptoConfig } returns mockk {
            every { getAlgorithm() } returns PqcAlgorithm.KAZ
        }
        every { cryptoManager.kazSign(any(), any()) } returns signature

        val inputStream = ByteArrayInputStream(plaintext)
        val outputStream = ByteArrayOutputStream()

        val result = fileEncryptor.encryptFileFromStream(
            inputStream = inputStream,
            fileName = "test.txt",
            mimeType = "text/plain",
            fileSize = plaintext.size.toLong(),
            folderId = testFolderId,
            outputStream = outputStream
        )

        assertNotNull(result)
        assertArrayEquals(generatedDek, result.dek)
        assertTrue(result.wrappedDek.isNotEmpty())
        assertTrue(result.encryptedMetadata.isNotEmpty())
        assertTrue(result.signature.isNotEmpty())
        assertTrue(result.blobSize > 0)
        assertTrue(result.chunkCount > 0)

        verify { cryptoManager.generateKey() }
        verify { cryptoManager.wrapKey(generatedDek, testKek) }
    }

    @Test
    fun `encryptFileFromStream reports progress`() = runBlocking {
        val plaintext = ByteArray(100) { it.toByte() }
        val progressUpdates = mutableListOf<Pair<Long, Long>>()

        setupEncryptionMocks()

        val inputStream = ByteArrayInputStream(plaintext)
        val outputStream = ByteArrayOutputStream()

        fileEncryptor.encryptFileFromStream(
            inputStream = inputStream,
            fileName = "test.txt",
            mimeType = "text/plain",
            fileSize = plaintext.size.toLong(),
            folderId = testFolderId,
            outputStream = outputStream,
            onProgress = { processed, total ->
                progressUpdates.add(processed to total)
            }
        )

        assertTrue("Progress should be reported at least once", progressUpdates.isNotEmpty())
        assertEquals("Total size should match file size", plaintext.size.toLong(), progressUpdates.last().second)
    }

    @Test
    fun `encryptFileFromStream computes blob hash`() = runBlocking {
        val plaintext = ByteArray(50) { it.toByte() }

        setupEncryptionMocks()

        val inputStream = ByteArrayInputStream(plaintext)
        val outputStream = ByteArrayOutputStream()

        val result = fileEncryptor.encryptFileFromStream(
            inputStream = inputStream,
            fileName = "test.txt",
            mimeType = "text/plain",
            fileSize = plaintext.size.toLong(),
            folderId = testFolderId,
            outputStream = outputStream
        )

        assertTrue("Blob hash should be a hex string", result.blobHash.matches(Regex("[0-9a-f]{64}")))
    }

    // ==================== EncryptionResult Tests ====================

    @Test
    fun `EncryptionResult zeroize clears DEK`() {
        val dek = ByteArray(32) { 0xFF.toByte() }
        val result = FileEncryptor.EncryptionResult(
            dek = dek,
            wrappedDek = "wrapped",
            encryptedMetadata = "metadata",
            signature = "sig",
            blobSize = 100,
            blobHash = "hash",
            chunkCount = 1
        )

        result.zeroize()

        // After zeroization, the DEK should be cleared (all zeros after SecureMemory 3-pass)
        assertTrue("DEK should be zeroed", dek.all { it == 0.toByte() })
    }

    // ==================== Companion Object Constants ====================

    @Test
    fun `CHUNK_SIZE is 4MB`() {
        assertEquals(4 * 1024 * 1024, FileEncryptor.CHUNK_SIZE)
    }

    @Test
    fun `NONCE_SIZE is 12`() {
        assertEquals(12, FileEncryptor.NONCE_SIZE)
    }

    @Test
    fun `TAG_SIZE is 16`() {
        assertEquals(16, FileEncryptor.TAG_SIZE)
    }

    // ==================== Helper Methods ====================

    private fun setupEncryptionMocks() {
        val generatedDek = ByteArray(32) { 0xAA.toByte() }
        val wrappedDek = ByteArray(60) { 0xBB.toByte() }
        val encryptedChunk = ByteArray(128) { 0xCC.toByte() }
        val encryptedMetadata = ByteArray(80) { 0xDD.toByte() }
        val signature = ByteArray(100) { 0xEE.toByte() }

        every { folderKeyManager.getCachedKek(testFolderId) } returns testKek
        every { cryptoManager.generateKey() } returns generatedDek
        every { cryptoManager.wrapKey(any(), any()) } returns wrappedDek
        every { cryptoManager.encryptAesGcm(any(), any()) } returns encryptedChunk
        every { cryptoManager.encryptAesGcmWithAad(any(), any(), any()) } returns encryptedMetadata

        val keys = createTestKeyBundle()
        every { keyManager.getUnlockedKeys() } returns keys
        every { cryptoManager.cryptoConfig } returns mockk {
            every { getAlgorithm() } returns PqcAlgorithm.KAZ
        }
        every { cryptoManager.kazSign(any(), any()) } returns signature
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
}
