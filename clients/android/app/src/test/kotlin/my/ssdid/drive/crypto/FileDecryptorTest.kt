package my.ssdid.drive.crypto

import android.content.Context
import android.util.Base64
import my.ssdid.drive.domain.model.FileMetadata
import my.ssdid.drive.domain.model.PublicKeys
import io.mockk.every
import io.mockk.mockk
import io.mockk.mockkStatic
import io.mockk.verify
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.security.MessageDigest

/**
 * Unit tests for FileDecryptor.
 *
 * Tests cover:
 * - Metadata decryption with folder KEK
 * - Metadata decryption with provided DEK
 * - Signature verification (new and legacy formats)
 * - DEK unwrapping
 * - Blob hash verification
 * - Error handling (missing KEK, decryption failures)
 * - Chunk-based content decryption flow
 */
class FileDecryptorTest {

    private lateinit var context: Context
    private lateinit var cryptoManager: CryptoManager
    private lateinit var keyManager: KeyManager
    private lateinit var folderKeyManager: FolderKeyManager
    private lateinit var fileDecryptor: FileDecryptor

    private val testDek = ByteArray(32) { it.toByte() }
    private val testKek = ByteArray(32) { (it + 50).toByte() }
    private val testFolderId = "folder-456"
    private val testWrappedDekBytes = ByteArray(60) { (it + 10).toByte() }
    private lateinit var testWrappedDekBase64: String

    @Before
    fun setup() {
        context = mockk(relaxed = true)
        cryptoManager = mockk(relaxed = true)
        keyManager = mockk(relaxed = true)
        folderKeyManager = mockk(relaxed = true)

        // Mock Base64 since it's an Android API
        mockkStatic(Base64::class)
        every { Base64.encodeToString(any(), any()) } answers {
            java.util.Base64.getEncoder().encodeToString(firstArg<ByteArray>())
        }
        every { Base64.decode(any<String>(), any()) } answers {
            java.util.Base64.getDecoder().decode(firstArg<String>())
        }

        testWrappedDekBase64 = java.util.Base64.getEncoder().encodeToString(testWrappedDekBytes)

        fileDecryptor = FileDecryptor(
            context = context,
            cryptoManager = cryptoManager,
            keyManager = keyManager,
            folderKeyManager = folderKeyManager
        )
    }

    // ==================== decryptMetadata Tests ====================

    @Test
    fun `decryptMetadata unwraps DEK with KEK and decrypts metadata`() {
        val metadataJson = """{"name":"photo.jpg","mimeType":"image/jpeg","size":2048}"""
        val encryptedMetadataBytes = ByteArray(100) { it.toByte() }
        val encryptedMetadataBase64 = java.util.Base64.getEncoder().encodeToString(encryptedMetadataBytes)

        every { folderKeyManager.getCachedKek(testFolderId) } returns testKek
        every { cryptoManager.unwrapKey(testWrappedDekBytes, testKek) } returns testDek
        every {
            cryptoManager.decryptAesGcmWithAad(
                ciphertext = encryptedMetadataBytes,
                key = testDek,
                aad = "file-metadata".toByteArray(Charsets.UTF_8)
            )
        } returns metadataJson.toByteArray()
        every { cryptoManager.zeroize(testDek) } answers {
            // Simulate zeroize
            firstArg<ByteArray>().fill(0)
        }

        val result = fileDecryptor.decryptMetadata(
            folderId = testFolderId,
            encryptedMetadata = encryptedMetadataBase64,
            wrappedDek = testWrappedDekBase64
        )

        assertEquals("photo.jpg", result.name)
        assertEquals("image/jpeg", result.mimeType)
        assertEquals(2048L, result.size)

        // Verify DEK is zeroized after use
        verify { cryptoManager.zeroize(testDek) }
    }

    @Test
    fun `decryptMetadata throws FolderKekNotAvailable when KEK not cached`() {
        every { folderKeyManager.getCachedKek(testFolderId) } returns null

        val exception = assertThrows(FileDecryptor.DecryptionError.FolderKekNotAvailable::class.java) {
            fileDecryptor.decryptMetadata(
                folderId = testFolderId,
                encryptedMetadata = "dummyMetadata",
                wrappedDek = testWrappedDekBase64
            )
        }

        assertEquals(testFolderId, exception.folderId)
    }

    @Test
    fun `decryptMetadata falls back to non-AAD decryption for backward compatibility`() {
        val metadataJson = """{"name":"old.txt","mimeType":"text/plain","size":100}"""
        val encryptedMetadataBytes = ByteArray(80) { it.toByte() }
        val encryptedMetadataBase64 = java.util.Base64.getEncoder().encodeToString(encryptedMetadataBytes)

        every { folderKeyManager.getCachedKek(testFolderId) } returns testKek
        every { cryptoManager.unwrapKey(any(), testKek) } returns testDek
        // AAD decryption fails (old format)
        every {
            cryptoManager.decryptAesGcmWithAad(any(), testDek, any())
        } throws RuntimeException("AAD mismatch")
        // Non-AAD decryption succeeds
        every {
            cryptoManager.decryptAesGcm(encryptedMetadataBytes, testDek)
        } returns metadataJson.toByteArray()
        every { cryptoManager.zeroize(any<ByteArray>()) } answers {}

        val result = fileDecryptor.decryptMetadata(
            folderId = testFolderId,
            encryptedMetadata = encryptedMetadataBase64,
            wrappedDek = testWrappedDekBase64
        )

        assertEquals("old.txt", result.name)
        verify { cryptoManager.decryptAesGcm(encryptedMetadataBytes, testDek) }
    }

    // ==================== decryptMetadataWithDek Tests ====================

    @Test
    fun `decryptMetadataWithDek decrypts metadata using provided DEK`() {
        val metadataJson = """{"name":"doc.pdf","mimeType":"application/pdf","size":4096}"""
        val encryptedBytes = ByteArray(90) { it.toByte() }
        val encryptedBase64 = java.util.Base64.getEncoder().encodeToString(encryptedBytes)

        every {
            cryptoManager.decryptAesGcmWithAad(encryptedBytes, testDek, any())
        } returns metadataJson.toByteArray()

        val result = fileDecryptor.decryptMetadataWithDek(encryptedBase64, testDek)

        assertEquals("doc.pdf", result.name)
        assertEquals("application/pdf", result.mimeType)
        assertEquals(4096L, result.size)
    }

    @Test
    fun `decryptMetadataWithDek falls back to non-AAD for old metadata`() {
        val metadataJson = """{"name":"legacy.txt","mimeType":"text/plain","size":50}"""
        val encryptedBytes = ByteArray(70) { it.toByte() }
        val encryptedBase64 = java.util.Base64.getEncoder().encodeToString(encryptedBytes)

        every {
            cryptoManager.decryptAesGcmWithAad(any(), testDek, any())
        } throws RuntimeException("No AAD")
        every {
            cryptoManager.decryptAesGcm(encryptedBytes, testDek)
        } returns metadataJson.toByteArray()

        val result = fileDecryptor.decryptMetadataWithDek(encryptedBase64, testDek)

        assertEquals("legacy.txt", result.name)
    }

    // ==================== unwrapDek Tests ====================

    @Test
    fun `unwrapDek returns unwrapped DEK bytes`() {
        every { folderKeyManager.getCachedKek(testFolderId) } returns testKek
        every { cryptoManager.unwrapKey(testWrappedDekBytes, testKek) } returns testDek

        val result = fileDecryptor.unwrapDek(testFolderId, testWrappedDekBase64)

        assertArrayEquals(testDek, result)
    }

    @Test
    fun `unwrapDek throws FolderKekNotAvailable when KEK missing`() {
        every { folderKeyManager.getCachedKek(testFolderId) } returns null

        assertThrows(FileDecryptor.DecryptionError.FolderKekNotAvailable::class.java) {
            fileDecryptor.unwrapDek(testFolderId, testWrappedDekBase64)
        }
    }

    // ==================== verifySignature Tests ====================

    @Test
    fun `verifySignature with new format verifies using blobSize and chunkCount`() {
        val encryptedMetadata = java.util.Base64.getEncoder().encodeToString(ByteArray(40))
        val wrappedDek = java.util.Base64.getEncoder().encodeToString(ByteArray(60))
        val signature = java.util.Base64.getEncoder().encodeToString(ByteArray(100))
        val uploaderKeys = PublicKeys(
            kem = ByteArray(800),
            sign = ByteArray(1312),
            mlKem = null,
            mlDsa = null
        )

        every { cryptoManager.cryptoConfig } returns mockk {
            every { getAlgorithm() } returns PqcAlgorithm.KAZ
        }
        every { cryptoManager.kazVerify(any(), any(), uploaderKeys.sign) } returns true

        val result = fileDecryptor.verifySignature(
            encryptedMetadata = encryptedMetadata,
            blobHash = "abc123",
            wrappedDek = wrappedDek,
            signature = signature,
            uploaderPublicKeys = uploaderKeys,
            blobSize = 1024,
            chunkCount = 1
        )

        assertTrue(result)
    }

    @Test
    fun `verifySignature falls back to legacy format when new format fails`() {
        val encryptedMetadata = java.util.Base64.getEncoder().encodeToString(ByteArray(40))
        val wrappedDek = java.util.Base64.getEncoder().encodeToString(ByteArray(60))
        val signature = java.util.Base64.getEncoder().encodeToString(ByteArray(100))
        val uploaderKeys = PublicKeys(
            kem = ByteArray(800),
            sign = ByteArray(1312),
            mlKem = null,
            mlDsa = null
        )

        every { cryptoManager.cryptoConfig } returns mockk {
            every { getAlgorithm() } returns PqcAlgorithm.KAZ
        }

        // First call (new format) returns false, second call (legacy) returns true
        every { cryptoManager.kazVerify(any(), any(), uploaderKeys.sign) } returnsMany listOf(false, true)

        val result = fileDecryptor.verifySignature(
            encryptedMetadata = encryptedMetadata,
            blobHash = "abc123",
            wrappedDek = wrappedDek,
            signature = signature,
            uploaderPublicKeys = uploaderKeys,
            blobSize = 1024,
            chunkCount = 1
        )

        assertTrue(result)
    }

    @Test
    fun `verifySignature returns false when both formats fail`() {
        val encryptedMetadata = java.util.Base64.getEncoder().encodeToString(ByteArray(40))
        val wrappedDek = java.util.Base64.getEncoder().encodeToString(ByteArray(60))
        val signature = java.util.Base64.getEncoder().encodeToString(ByteArray(100))
        val uploaderKeys = PublicKeys(
            kem = ByteArray(800),
            sign = ByteArray(1312),
            mlKem = null,
            mlDsa = null
        )

        every { cryptoManager.cryptoConfig } returns mockk {
            every { getAlgorithm() } returns PqcAlgorithm.KAZ
        }
        every { cryptoManager.kazVerify(any(), any(), any()) } returns false

        val result = fileDecryptor.verifySignature(
            encryptedMetadata = encryptedMetadata,
            blobHash = "abc123",
            wrappedDek = wrappedDek,
            signature = signature,
            uploaderPublicKeys = uploaderKeys,
            blobSize = 1024,
            chunkCount = 1
        )

        assertFalse(result)
    }

    @Test
    fun `verifySignature without blobSize uses legacy format only`() {
        val encryptedMetadata = java.util.Base64.getEncoder().encodeToString(ByteArray(40))
        val wrappedDek = java.util.Base64.getEncoder().encodeToString(ByteArray(60))
        val signature = java.util.Base64.getEncoder().encodeToString(ByteArray(100))
        val uploaderKeys = PublicKeys(
            kem = ByteArray(800),
            sign = ByteArray(1312),
            mlKem = null,
            mlDsa = null
        )

        every { cryptoManager.cryptoConfig } returns mockk {
            every { getAlgorithm() } returns PqcAlgorithm.KAZ
        }
        every { cryptoManager.kazVerify(any(), any(), uploaderKeys.sign) } returns true

        val result = fileDecryptor.verifySignature(
            encryptedMetadata = encryptedMetadata,
            blobHash = "abc123",
            wrappedDek = wrappedDek,
            signature = signature,
            uploaderPublicKeys = uploaderKeys,
            blobSize = null,
            chunkCount = null
        )

        assertTrue(result)
    }

    @Test
    fun `verifySignature catches exceptions and returns false`() {
        val encryptedMetadata = java.util.Base64.getEncoder().encodeToString(ByteArray(40))
        val wrappedDek = java.util.Base64.getEncoder().encodeToString(ByteArray(60))
        val signature = java.util.Base64.getEncoder().encodeToString(ByteArray(100))
        val uploaderKeys = PublicKeys(
            kem = ByteArray(800),
            sign = ByteArray(1312),
            mlKem = null,
            mlDsa = null
        )

        every { cryptoManager.cryptoConfig } returns mockk {
            every { getAlgorithm() } returns PqcAlgorithm.KAZ
        }
        every { cryptoManager.kazVerify(any(), any(), any()) } throws RuntimeException("Crypto error")

        val result = fileDecryptor.verifySignature(
            encryptedMetadata = encryptedMetadata,
            blobHash = "abc123",
            wrappedDek = wrappedDek,
            signature = signature,
            uploaderPublicKeys = uploaderKeys
        )

        assertFalse(result)
    }

    // ==================== verifyBlobHash Tests ====================

    @Test
    fun `verifyBlobHash returns true for matching hash`() = runBlocking {
        val content = "hello world".toByteArray()
        val digest = MessageDigest.getInstance("SHA-256")
        digest.update(content)
        val expectedHash = digest.digest().joinToString("") { "%02x".format(it) }

        val inputStream = ByteArrayInputStream(content)

        val result = fileDecryptor.verifyBlobHash(inputStream, expectedHash)

        assertTrue(result)
    }

    @Test
    fun `verifyBlobHash returns false for non-matching hash`() = runBlocking {
        val content = "hello world".toByteArray()
        val inputStream = ByteArrayInputStream(content)

        val result = fileDecryptor.verifyBlobHash(inputStream, "0000000000000000000000000000000000000000000000000000000000000000")

        assertFalse(result)
    }

    @Test
    fun `verifyBlobHash handles empty input`() = runBlocking {
        val emptyContent = ByteArray(0)
        val digest = MessageDigest.getInstance("SHA-256")
        val expectedHash = digest.digest().joinToString("") { "%02x".format(it) }

        val inputStream = ByteArrayInputStream(emptyContent)

        val result = fileDecryptor.verifyBlobHash(inputStream, expectedHash)

        assertTrue(result)
    }

    // ==================== decryptFile Tests ====================

    @Test
    fun `decryptFile throws FolderKekNotAvailable when KEK missing`() {
        every { folderKeyManager.getCachedKek(testFolderId) } returns null

        assertThrows(FileDecryptor.DecryptionError.FolderKekNotAvailable::class.java) {
            runBlocking {
                fileDecryptor.decryptFile(
                    folderId = testFolderId,
                    encryptedMetadata = "dummy",
                    wrappedDek = testWrappedDekBase64,
                    inputStream = ByteArrayInputStream(ByteArray(0)),
                    outputStream = ByteArrayOutputStream(),
                    encryptedSize = 0
                )
            }
        }
    }

    @Test
    fun `decryptFile zeroizes DEK after completion`() = runBlocking {
        val metadataJson = """{"name":"file.txt","mimeType":"text/plain","size":0}"""
        val encryptedMetadataBytes = ByteArray(100) { it.toByte() }
        val encryptedMetadataBase64 = java.util.Base64.getEncoder().encodeToString(encryptedMetadataBytes)
        val dek = ByteArray(32) { 0xFF.toByte() }

        every { folderKeyManager.getCachedKek(testFolderId) } returns testKek
        every { cryptoManager.unwrapKey(any(), testKek) } returns dek
        every { cryptoManager.decryptAesGcmWithAad(any(), dek, any()) } returns metadataJson.toByteArray()
        every { cryptoManager.zeroize(dek) } answers {
            firstArg<ByteArray>().fill(0)
        }

        fileDecryptor.decryptFile(
            folderId = testFolderId,
            encryptedMetadata = encryptedMetadataBase64,
            wrappedDek = testWrappedDekBase64,
            inputStream = ByteArrayInputStream(ByteArray(0)),
            outputStream = ByteArrayOutputStream(),
            encryptedSize = 0
        )

        verify { cryptoManager.zeroize(dek) }
    }

    // ==================== Companion Object Constants ====================

    @Test
    fun `CHUNK_SIZE matches FileEncryptor`() {
        assertEquals(FileEncryptor.CHUNK_SIZE, FileDecryptor.CHUNK_SIZE)
    }

    @Test
    fun `ENCRYPTED_CHUNK_OVERHEAD is NONCE_SIZE plus TAG_SIZE`() {
        assertEquals(
            FileDecryptor.NONCE_SIZE + FileDecryptor.TAG_SIZE,
            FileDecryptor.ENCRYPTED_CHUNK_OVERHEAD
        )
    }

    @Test
    fun `MAX_ENCRYPTED_CHUNK_SIZE is CHUNK_SIZE plus overhead`() {
        assertEquals(
            FileDecryptor.CHUNK_SIZE + FileDecryptor.ENCRYPTED_CHUNK_OVERHEAD,
            FileDecryptor.MAX_ENCRYPTED_CHUNK_SIZE
        )
    }

    // ==================== DecryptionError Tests ====================

    @Test
    fun `DecryptionError types are distinguishable`() {
        val sigError = FileDecryptor.DecryptionError.SignatureVerificationFailed("bad sig")
        val kekError = FileDecryptor.DecryptionError.FolderKekNotAvailable("folder-1")
        val metaError = FileDecryptor.DecryptionError.MetadataDecryptionFailed("bad meta")
        val contentError = FileDecryptor.DecryptionError.ContentDecryptionFailed("bad chunk")

        assertTrue(sigError is FileDecryptor.DecryptionError)
        assertTrue(kekError is FileDecryptor.DecryptionError)
        assertTrue(metaError is FileDecryptor.DecryptionError)
        assertTrue(contentError is FileDecryptor.DecryptionError)

        // All are Exceptions
        assertTrue(sigError is Exception)
        assertTrue(kekError is Exception)

        assertEquals("bad sig", sigError.message)
        assertEquals("folder-1", kekError.folderId)
        assertEquals("bad meta", metaError.message)
        assertEquals("bad chunk", contentError.message)
    }
}
