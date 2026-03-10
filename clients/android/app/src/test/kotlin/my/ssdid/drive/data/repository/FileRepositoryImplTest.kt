package my.ssdid.drive.data.repository

import android.content.ContentResolver
import android.content.Context
import android.net.Uri
import android.util.Base64
import app.cash.turbine.test
import my.ssdid.drive.crypto.CryptoConfig
import my.ssdid.drive.crypto.FileDecryptor
import my.ssdid.drive.crypto.FileEncryptor
import my.ssdid.drive.crypto.FolderKeyManager
import my.ssdid.drive.crypto.SecureMemory
import my.ssdid.drive.data.local.dao.FileDao
import my.ssdid.drive.data.local.entity.FileEntity
import my.ssdid.drive.data.remote.ApiService
import my.ssdid.drive.data.remote.dto.DownloadUrlData
import my.ssdid.drive.data.remote.dto.DownloadUrlResponse
import my.ssdid.drive.data.remote.dto.FileDto
import my.ssdid.drive.data.remote.dto.FileResponse
import my.ssdid.drive.data.remote.dto.FilesResponse
import my.ssdid.drive.data.remote.dto.PublicKeysDto
import my.ssdid.drive.data.remote.dto.UploadUrlData
import my.ssdid.drive.data.remote.dto.UploadUrlResponse
import my.ssdid.drive.domain.model.FileItem
import my.ssdid.drive.domain.model.FileMetadata
import my.ssdid.drive.domain.model.FileStatus
import my.ssdid.drive.domain.repository.DownloadProgress
import my.ssdid.drive.domain.repository.UploadProgress
import my.ssdid.drive.util.AnalyticsManager
import my.ssdid.drive.util.AppException
import my.ssdid.drive.util.Logger
import my.ssdid.drive.util.Result
import io.mockk.*
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.runTest
import okhttp3.Call
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response as OkHttpResponse
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import retrofit2.Response
import java.io.ByteArrayInputStream
import java.io.IOException
import java.time.Instant

/**
 * Unit tests for FileRepositoryImpl.
 *
 * Tests cover:
 * - getFile success and error paths (404, 403, signature failure, crypto errors)
 * - getFiles (list files in folder) success and error
 * - deleteFile success and error
 * - renameFile success and error
 * - moveFile success and error
 * - searchFiles success and error
 * - Network error handling (mapping HTTP errors to domain errors)
 * - syncFiles success and error
 *
 * Note: uploadFile and downloadFile use Flows with IO dispatchers and filesystem
 * operations; they are tested at a higher level via integration tests.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class FileRepositoryImplTest {

    private lateinit var context: Context
    private lateinit var contentResolver: ContentResolver
    private lateinit var apiService: ApiService
    private lateinit var fileDao: FileDao
    private lateinit var fileEncryptor: FileEncryptor
    private lateinit var fileDecryptor: FileDecryptor
    private lateinit var folderKeyManager: FolderKeyManager
    private lateinit var cryptoConfig: CryptoConfig
    private lateinit var okHttpClient: OkHttpClient
    private lateinit var analyticsManager: AnalyticsManager
    private lateinit var fileRepository: FileRepositoryImpl

    private val testFileId = "file-123"
    private val testFolderId = "folder-456"
    private val testOwnerId = "user-789"
    private val testTenantId = "tenant-001"
    private val testFileName = "document.pdf"
    private val testMimeType = "application/pdf"
    private val testFileSize = 1024L
    private val testTimestamp = "2024-06-01T12:00:00Z"

    @Before
    fun setup() {
        mockkStatic(Base64::class)
        every { Base64.decode(any<String>(), any()) } returns ByteArray(32)
        every { Base64.encodeToString(any(), any()) } returns "base64encoded"

        mockkObject(Logger)
        every { Logger.d(any(), any(), any()) } just Runs
        every { Logger.i(any(), any(), any()) } just Runs
        every { Logger.w(any(), any(), any()) } just Runs
        every { Logger.e(any(), any(), any()) } just Runs

        mockkObject(SecureMemory)
        every { SecureMemory.zeroize(any<ByteArray>()) } just Runs

        context = mockk(relaxed = true)
        contentResolver = mockk(relaxed = true)
        every { context.contentResolver } returns contentResolver
        every { context.cacheDir } returns mockk(relaxed = true)

        apiService = mockk()
        fileDao = mockk(relaxed = true)
        fileEncryptor = mockk()
        fileDecryptor = mockk()
        folderKeyManager = mockk()
        cryptoConfig = mockk(relaxed = true)
        okHttpClient = mockk()
        analyticsManager = mockk(relaxed = true)

        fileRepository = FileRepositoryImpl(
            context = context,
            apiService = apiService,
            fileDao = fileDao,
            fileEncryptor = fileEncryptor,
            fileDecryptor = fileDecryptor,
            folderKeyManager = folderKeyManager,
            cryptoConfig = cryptoConfig,
            okHttpClient = okHttpClient,
            analyticsManager = analyticsManager
        )
    }

    @After
    fun tearDown() {
        unmockkStatic(Base64::class)
        unmockkObject(Logger)
        unmockkObject(SecureMemory)
    }

    // ==================== getFile Tests ====================

    @Test
    fun `getFile returns file on success with valid signature`() = runTest {
        val fileDto = createTestFileDto()
        coEvery { apiService.getFile(testFileId) } returns Response.success(FileResponse(data = fileDto))
        every {
            fileDecryptor.verifySignature(
                encryptedMetadata = any(),
                blobHash = any(),
                wrappedDek = any(),
                signature = any(),
                uploaderPublicKeys = any(),
                blobSize = any(),
                chunkCount = any()
            )
        } returns true
        every {
            fileDecryptor.decryptMetadata(
                folderId = any(),
                encryptedMetadata = any(),
                wrappedDek = any()
            )
        } returns FileMetadata(name = testFileName, mimeType = testMimeType, size = testFileSize)

        val result = fileRepository.getFile(testFileId)

        assertTrue(result is Result.Success)
        val file = (result as Result.Success).data
        assertEquals(testFileId, file.id)
        assertEquals(testFolderId, file.folderId)
        assertEquals(testOwnerId, file.ownerId)
        assertEquals(testFileName, file.name)
        assertEquals(testMimeType, file.mimeType)
        assertEquals(testFileSize, file.size)
    }

    @Test
    fun `getFile returns error when signature verification fails`() = runTest {
        val fileDto = createTestFileDto()
        coEvery { apiService.getFile(testFileId) } returns Response.success(FileResponse(data = fileDto))
        every {
            fileDecryptor.verifySignature(
                encryptedMetadata = any(),
                blobHash = any(),
                wrappedDek = any(),
                signature = any(),
                uploaderPublicKeys = any(),
                blobSize = any(),
                chunkCount = any()
            )
        } returns false

        val result = fileRepository.getFile(testFileId)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.CryptoError)
        assertTrue(error.message.contains("tampered"))
    }

    @Test
    fun `getFile returns NotFound on 404`() = runTest {
        coEvery { apiService.getFile(testFileId) } returns Response.error(
            404,
            "Not Found".toResponseBody()
        )

        val result = fileRepository.getFile(testFileId)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.NotFound)
    }

    @Test
    fun `getFile returns Forbidden on 403`() = runTest {
        coEvery { apiService.getFile(testFileId) } returns Response.error(
            403,
            "Forbidden".toResponseBody()
        )

        val result = fileRepository.getFile(testFileId)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Forbidden)
    }

    @Test
    fun `getFile returns Unknown error on other HTTP errors`() = runTest {
        coEvery { apiService.getFile(testFileId) } returns Response.error(
            500,
            "Internal Server Error".toResponseBody()
        )

        val result = fileRepository.getFile(testFileId)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Unknown)
    }

    @Test
    fun `getFile returns Network error on IOException`() = runTest {
        coEvery { apiService.getFile(testFileId) } throws IOException("Connection refused")

        val result = fileRepository.getFile(testFileId)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Network)
    }

    @Test
    fun `getFile returns CryptoError when uploaderPublicKeys is null`() = runTest {
        val fileDto = createTestFileDto(uploaderPublicKeys = null)
        coEvery { apiService.getFile(testFileId) } returns Response.success(FileResponse(data = fileDto))

        val result = fileRepository.getFile(testFileId)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.CryptoError)
        assertTrue(error.message.contains("public keys"))
    }

    @Test
    fun `getFile returns CryptoError when blobHash is null`() = runTest {
        val fileDto = createTestFileDto(blobHash = null)
        coEvery { apiService.getFile(testFileId) } returns Response.success(FileResponse(data = fileDto))

        val result = fileRepository.getFile(testFileId)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.CryptoError)
        assertTrue(error.message.contains("blob hash"))
    }

    @Test
    fun `getFile returns CryptoError when blobSize is null`() = runTest {
        val fileDto = createTestFileDto(blobSize = null)
        coEvery { apiService.getFile(testFileId) } returns Response.success(FileResponse(data = fileDto))

        val result = fileRepository.getFile(testFileId)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.CryptoError)
        assertTrue(error.message.contains("blob size"))
    }

    @Test
    fun `getFile returns CryptoError when chunkCount is null`() = runTest {
        val fileDto = createTestFileDto(chunkCount = null)
        coEvery { apiService.getFile(testFileId) } returns Response.success(FileResponse(data = fileDto))

        val result = fileRepository.getFile(testFileId)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.CryptoError)
        assertTrue(error.message.contains("chunk count"))
    }

    // ==================== getFiles Tests ====================

    @Test
    fun `getFiles returns list of files on success`() = runTest {
        val fileDto1 = createTestFileDto(id = "file-1")
        val fileDto2 = createTestFileDto(id = "file-2")
        coEvery { apiService.getFolderFiles(testFolderId) } returns Response.success(
            FilesResponse(data = listOf(fileDto1, fileDto2))
        )
        every {
            fileDecryptor.verifySignature(
                encryptedMetadata = any(),
                blobHash = any(),
                wrappedDek = any(),
                signature = any(),
                uploaderPublicKeys = any(),
                blobSize = any(),
                chunkCount = any()
            )
        } returns true
        every {
            fileDecryptor.decryptMetadata(
                folderId = any(),
                encryptedMetadata = any(),
                wrappedDek = any()
            )
        } returns FileMetadata(name = testFileName, mimeType = testMimeType, size = testFileSize)

        val result = fileRepository.getFiles(testFolderId)

        assertTrue(result is Result.Success)
        val files = (result as Result.Success).data
        assertEquals(2, files.size)
        assertEquals("file-1", files[0].id)
        assertEquals("file-2", files[1].id)
    }

    @Test
    fun `getFiles returns empty list when all files have invalid signatures`() = runTest {
        val fileDto = createTestFileDto()
        coEvery { apiService.getFolderFiles(testFolderId) } returns Response.success(
            FilesResponse(data = listOf(fileDto))
        )
        every {
            fileDecryptor.verifySignature(
                encryptedMetadata = any(),
                blobHash = any(),
                wrappedDek = any(),
                signature = any(),
                uploaderPublicKeys = any(),
                blobSize = any(),
                chunkCount = any()
            )
        } returns false

        val result = fileRepository.getFiles(testFolderId)

        assertTrue(result is Result.Success)
        val files = (result as Result.Success).data
        assertTrue(files.isEmpty())
    }

    @Test
    fun `getFiles skips files that fail decryption`() = runTest {
        val fileDto1 = createTestFileDto(id = "file-1")
        val fileDto2 = createTestFileDto(id = "file-2", encryptedMetadata = "bad-metadata")
        coEvery { apiService.getFolderFiles(testFolderId) } returns Response.success(
            FilesResponse(data = listOf(fileDto1, fileDto2))
        )
        every {
            fileDecryptor.verifySignature(
                encryptedMetadata = any(),
                blobHash = any(),
                wrappedDek = any(),
                signature = any(),
                uploaderPublicKeys = any(),
                blobSize = any(),
                chunkCount = any()
            )
        } returns true
        // First call succeeds, second call throws
        every {
            fileDecryptor.decryptMetadata(
                folderId = any(),
                encryptedMetadata = "enc-metadata-base64",
                wrappedDek = any()
            )
        } returns FileMetadata(name = testFileName, mimeType = testMimeType, size = testFileSize)
        every {
            fileDecryptor.decryptMetadata(
                folderId = any(),
                encryptedMetadata = "bad-metadata",
                wrappedDek = any()
            )
        } throws RuntimeException("Decryption failed")

        val result = fileRepository.getFiles(testFolderId)

        assertTrue(result is Result.Success)
        val files = (result as Result.Success).data
        assertEquals(1, files.size)
        assertEquals("file-1", files[0].id)
    }

    @Test
    fun `getFiles includes files without uploaderPublicKeys (pending uploads)`() = runTest {
        val fileDto = createTestFileDto(uploaderPublicKeys = null)
        coEvery { apiService.getFolderFiles(testFolderId) } returns Response.success(
            FilesResponse(data = listOf(fileDto))
        )
        every {
            fileDecryptor.decryptMetadata(
                folderId = any(),
                encryptedMetadata = any(),
                wrappedDek = any()
            )
        } returns FileMetadata(name = testFileName, mimeType = testMimeType, size = testFileSize)

        val result = fileRepository.getFiles(testFolderId)

        assertTrue(result is Result.Success)
        val files = (result as Result.Success).data
        assertEquals(1, files.size)
        // Verify signature was NOT called (no uploader keys)
        verify(exactly = 0) {
            fileDecryptor.verifySignature(
                encryptedMetadata = any(),
                blobHash = any(),
                wrappedDek = any(),
                signature = any(),
                uploaderPublicKeys = any(),
                blobSize = any(),
                chunkCount = any()
            )
        }
    }

    @Test
    fun `getFiles returns error on API failure`() = runTest {
        coEvery { apiService.getFolderFiles(testFolderId) } returns Response.error(
            500,
            "Server Error".toResponseBody()
        )

        val result = fileRepository.getFiles(testFolderId)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Unknown)
    }

    @Test
    fun `getFiles returns Network error on IOException`() = runTest {
        coEvery { apiService.getFolderFiles(testFolderId) } throws IOException("Timeout")

        val result = fileRepository.getFiles(testFolderId)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Network)
    }

    // ==================== deleteFile Tests ====================

    @Test
    fun `deleteFile returns success and deletes from local DB`() = runTest {
        coEvery { apiService.deleteFile(testFileId) } returns Response.success(Unit)

        val result = fileRepository.deleteFile(testFileId)

        assertTrue(result is Result.Success)
        coVerify { fileDao.deleteById(testFileId) }
    }

    @Test
    fun `deleteFile returns error on API failure`() = runTest {
        coEvery { apiService.deleteFile(testFileId) } returns Response.error(
            500,
            "Server Error".toResponseBody()
        )

        val result = fileRepository.deleteFile(testFileId)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Unknown)
        // Should NOT delete from local DB on failure
        coVerify(exactly = 0) { fileDao.deleteById(any()) }
    }

    @Test
    fun `deleteFile returns Network error on IOException`() = runTest {
        coEvery { apiService.deleteFile(testFileId) } throws IOException("Network error")

        val result = fileRepository.deleteFile(testFileId)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Network)
    }

    // ==================== renameFile Tests ====================

    @Test
    fun `renameFile returns renamed file on success`() = runTest {
        val newName = "renamed-document.pdf"
        val originalFileDto = createTestFileDto()
        val updatedFileDto = createTestFileDto()

        coEvery { apiService.getFile(testFileId) } returns Response.success(FileResponse(data = originalFileDto))
        every {
            fileDecryptor.decryptMetadata(
                folderId = any(),
                encryptedMetadata = any(),
                wrappedDek = any()
            )
        } returns FileMetadata(name = testFileName, mimeType = testMimeType, size = testFileSize)
        coEvery {
            fileEncryptor.updateMetadata(
                folderId = any(),
                wrappedDek = any(),
                newName = newName,
                mimeType = testMimeType,
                size = testFileSize,
                blobHash = any(),
                blobSize = any(),
                chunkCount = any()
            )
        } returns FileEncryptor.MetadataUpdateResult(
            encryptedMetadata = "new-enc-metadata",
            signature = "new-signature"
        )
        coEvery { apiService.updateFile(testFileId, any()) } returns Response.success(
            FileResponse(data = updatedFileDto)
        )

        val result = fileRepository.renameFile(testFileId, newName)

        assertTrue(result is Result.Success)
        val file = (result as Result.Success).data
        assertEquals(newName, file.name)
        assertEquals(testMimeType, file.mimeType)
    }

    @Test
    fun `renameFile returns NotFound when file does not exist`() = runTest {
        coEvery { apiService.getFile(testFileId) } returns Response.error(
            404,
            "Not Found".toResponseBody()
        )

        val result = fileRepository.renameFile(testFileId, "new-name.pdf")

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.NotFound)
    }

    @Test
    fun `renameFile returns CryptoError when blobHash is missing`() = runTest {
        val fileDto = createTestFileDto(blobHash = null)
        coEvery { apiService.getFile(testFileId) } returns Response.success(FileResponse(data = fileDto))

        val result = fileRepository.renameFile(testFileId, "new-name.pdf")

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.CryptoError)
    }

    @Test
    fun `renameFile returns error when update API fails`() = runTest {
        val originalFileDto = createTestFileDto()

        coEvery { apiService.getFile(testFileId) } returns Response.success(FileResponse(data = originalFileDto))
        every {
            fileDecryptor.decryptMetadata(
                folderId = any(),
                encryptedMetadata = any(),
                wrappedDek = any()
            )
        } returns FileMetadata(name = testFileName, mimeType = testMimeType, size = testFileSize)
        coEvery {
            fileEncryptor.updateMetadata(
                folderId = any(),
                wrappedDek = any(),
                newName = any(),
                mimeType = any(),
                size = any(),
                blobHash = any(),
                blobSize = any(),
                chunkCount = any()
            )
        } returns FileEncryptor.MetadataUpdateResult(
            encryptedMetadata = "new-enc-metadata",
            signature = "new-signature"
        )
        coEvery { apiService.updateFile(testFileId, any()) } returns Response.error(
            500,
            "Server Error".toResponseBody()
        )

        val result = fileRepository.renameFile(testFileId, "new-name.pdf")

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Unknown)
    }

    @Test
    fun `renameFile returns Network error on IOException`() = runTest {
        coEvery { apiService.getFile(testFileId) } throws IOException("Connection timeout")

        val result = fileRepository.renameFile(testFileId, "new-name.pdf")

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Network)
    }

    // ==================== moveFile Tests ====================

    @Test
    fun `moveFile returns moved file on success`() = runTest {
        val newFolderId = "folder-new"
        val originalFileDto = createTestFileDto()
        val movedFileDto = createTestFileDto(folderId = newFolderId)
        val dek = ByteArray(32)
        val newFolderKek = ByteArray(32)

        coEvery { apiService.getFile(testFileId) } returns Response.success(FileResponse(data = originalFileDto))
        every { fileDecryptor.unwrapDek(testFolderId, any()) } returns dek
        every { folderKeyManager.getCachedKek(newFolderId) } returns newFolderKek
        every { fileEncryptor.rewrapDek(dek, newFolderKek) } returns "new-wrapped-dek"
        every {
            fileEncryptor.signFilePackage(
                encryptedMetadata = any(),
                blobHash = any(),
                wrappedDek = "new-wrapped-dek",
                blobSize = any(),
                chunkCount = any()
            )
        } returns "new-signature"
        coEvery { apiService.moveFile(testFileId, any()) } returns Response.success(
            FileResponse(data = movedFileDto)
        )
        every {
            fileDecryptor.decryptMetadata(
                folderId = newFolderId,
                encryptedMetadata = any(),
                wrappedDek = any()
            )
        } returns FileMetadata(name = testFileName, mimeType = testMimeType, size = testFileSize)

        val result = fileRepository.moveFile(testFileId, newFolderId)

        assertTrue(result is Result.Success)
        val file = (result as Result.Success).data
        assertEquals(newFolderId, file.folderId)
        assertEquals(testFileName, file.name)
        // Verify DEK was zeroized
        verify { SecureMemory.zeroize(dek) }
    }

    @Test
    fun `moveFile returns NotFound when file does not exist`() = runTest {
        coEvery { apiService.getFile(testFileId) } returns Response.error(
            404,
            "Not Found".toResponseBody()
        )

        val result = fileRepository.moveFile(testFileId, "folder-new")

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.NotFound)
    }

    @Test
    fun `moveFile returns CryptoError when new folder KEK is not available`() = runTest {
        val newFolderId = "folder-new"
        val originalFileDto = createTestFileDto()
        val dek = ByteArray(32)

        coEvery { apiService.getFile(testFileId) } returns Response.success(FileResponse(data = originalFileDto))
        every { fileDecryptor.unwrapDek(testFolderId, any()) } returns dek
        every { folderKeyManager.getCachedKek(newFolderId) } returns null

        val result = fileRepository.moveFile(testFileId, newFolderId)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.CryptoError)
        assertTrue(error.message.contains("KEK"))
    }

    @Test
    fun `moveFile returns CryptoError when blobHash is missing`() = runTest {
        val fileDto = createTestFileDto(blobHash = null)
        coEvery { apiService.getFile(testFileId) } returns Response.success(FileResponse(data = fileDto))

        val result = fileRepository.moveFile(testFileId, "folder-new")

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.CryptoError)
    }

    @Test
    fun `moveFile returns error when move API fails`() = runTest {
        val newFolderId = "folder-new"
        val originalFileDto = createTestFileDto()
        val dek = ByteArray(32)
        val newFolderKek = ByteArray(32)

        coEvery { apiService.getFile(testFileId) } returns Response.success(FileResponse(data = originalFileDto))
        every { fileDecryptor.unwrapDek(testFolderId, any()) } returns dek
        every { folderKeyManager.getCachedKek(newFolderId) } returns newFolderKek
        every { fileEncryptor.rewrapDek(dek, newFolderKek) } returns "new-wrapped-dek"
        every {
            fileEncryptor.signFilePackage(
                encryptedMetadata = any(),
                blobHash = any(),
                wrappedDek = any(),
                blobSize = any(),
                chunkCount = any()
            )
        } returns "new-signature"
        coEvery { apiService.moveFile(testFileId, any()) } returns Response.error(
            500,
            "Server Error".toResponseBody()
        )

        val result = fileRepository.moveFile(testFileId, newFolderId)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Unknown)
        // Verify DEK was still zeroized even on failure
        verify { SecureMemory.zeroize(dek) }
    }

    @Test
    fun `moveFile returns Network error on IOException`() = runTest {
        coEvery { apiService.getFile(testFileId) } throws IOException("Connection lost")

        val result = fileRepository.moveFile(testFileId, "folder-new")

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Network)
    }

    // ==================== searchFiles Tests ====================

    @Test
    fun `searchFiles returns matching files on success`() = runTest {
        val query = "document"
        val fileDto = createTestFileDto()
        coEvery { apiService.searchFiles(query) } returns Response.success(
            FilesResponse(data = listOf(fileDto))
        )
        every {
            fileDecryptor.decryptMetadata(
                folderId = any(),
                encryptedMetadata = any(),
                wrappedDek = any()
            )
        } returns FileMetadata(name = testFileName, mimeType = testMimeType, size = testFileSize)

        val result = fileRepository.searchFiles(query)

        assertTrue(result is Result.Success)
        val files = (result as Result.Success).data
        assertEquals(1, files.size)
        assertEquals(testFileName, files[0].name)
    }

    @Test
    fun `searchFiles returns empty list when no matches`() = runTest {
        coEvery { apiService.searchFiles("nonexistent") } returns Response.success(
            FilesResponse(data = emptyList())
        )

        val result = fileRepository.searchFiles("nonexistent")

        assertTrue(result is Result.Success)
        val files = (result as Result.Success).data
        assertTrue(files.isEmpty())
    }

    @Test
    fun `searchFiles skips files that fail decryption`() = runTest {
        val fileDto1 = createTestFileDto(id = "file-1")
        val fileDto2 = createTestFileDto(id = "file-2", encryptedMetadata = "corrupt")
        coEvery { apiService.searchFiles("doc") } returns Response.success(
            FilesResponse(data = listOf(fileDto1, fileDto2))
        )
        every {
            fileDecryptor.decryptMetadata(
                folderId = any(),
                encryptedMetadata = "enc-metadata-base64",
                wrappedDek = any()
            )
        } returns FileMetadata(name = testFileName, mimeType = testMimeType, size = testFileSize)
        every {
            fileDecryptor.decryptMetadata(
                folderId = any(),
                encryptedMetadata = "corrupt",
                wrappedDek = any()
            )
        } throws RuntimeException("Decryption failed")

        val result = fileRepository.searchFiles("doc")

        assertTrue(result is Result.Success)
        val files = (result as Result.Success).data
        assertEquals(1, files.size)
        assertEquals("file-1", files[0].id)
    }

    @Test
    fun `searchFiles returns error on API failure`() = runTest {
        coEvery { apiService.searchFiles("doc") } returns Response.error(
            500,
            "Server Error".toResponseBody()
        )

        val result = fileRepository.searchFiles("doc")

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Unknown)
    }

    @Test
    fun `searchFiles returns Network error on IOException`() = runTest {
        coEvery { apiService.searchFiles("doc") } throws IOException("DNS failure")

        val result = fileRepository.searchFiles("doc")

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Network)
    }

    // ==================== syncFiles Tests ====================

    @Test
    fun `syncFiles replaces local files on success`() = runTest {
        val fileDto = createTestFileDto()
        coEvery { apiService.getFolderFiles(testFolderId) } returns Response.success(
            FilesResponse(data = listOf(fileDto))
        )
        every {
            fileDecryptor.decryptMetadata(
                folderId = any(),
                encryptedMetadata = any(),
                wrappedDek = any()
            )
        } returns FileMetadata(name = testFileName, mimeType = testMimeType, size = testFileSize)

        val result = fileRepository.syncFiles(testFolderId)

        assertTrue(result is Result.Success)
        coVerify { fileDao.replaceAllInFolder(testFolderId, any()) }
    }

    @Test
    fun `syncFiles returns error on API failure`() = runTest {
        coEvery { apiService.getFolderFiles(testFolderId) } returns Response.error(
            500,
            "Server Error".toResponseBody()
        )

        val result = fileRepository.syncFiles(testFolderId)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Unknown)
    }

    @Test
    fun `syncFiles returns Network error on IOException`() = runTest {
        coEvery { apiService.getFolderFiles(testFolderId) } throws IOException("Timeout")

        val result = fileRepository.syncFiles(testFolderId)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Network)
    }

    @Test
    fun `syncFiles skips files that fail decryption`() = runTest {
        val fileDto1 = createTestFileDto(id = "file-1")
        val fileDto2 = createTestFileDto(id = "file-2", encryptedMetadata = "bad")
        coEvery { apiService.getFolderFiles(testFolderId) } returns Response.success(
            FilesResponse(data = listOf(fileDto1, fileDto2))
        )
        every {
            fileDecryptor.decryptMetadata(
                folderId = any(),
                encryptedMetadata = "enc-metadata-base64",
                wrappedDek = any()
            )
        } returns FileMetadata(name = testFileName, mimeType = testMimeType, size = testFileSize)
        every {
            fileDecryptor.decryptMetadata(
                folderId = any(),
                encryptedMetadata = "bad",
                wrappedDek = any()
            )
        } throws RuntimeException("Cannot decrypt")

        val result = fileRepository.syncFiles(testFolderId)

        assertTrue(result is Result.Success)
        coVerify {
            fileDao.replaceAllInFolder(testFolderId, match { entities ->
                entities.size == 1 && entities[0].id == "file-1"
            })
        }
    }

    // ==================== observeFiles Tests ====================

    @Test
    fun `observeFiles maps FileEntity to FileItem`() = runTest {
        val entity = createTestFileEntity()
        every { fileDao.observeByFolderId(testFolderId) } returns flowOf(listOf(entity))

        fileRepository.observeFiles(testFolderId).test {
            val files = awaitItem()
            assertEquals(1, files.size)
            assertEquals(testFileId, files[0].id)
            assertEquals(testFileName, files[0].name)
            assertEquals(testMimeType, files[0].mimeType)
            awaitComplete()
        }
    }

    @Test
    fun `observeFiles uses defaults when cached fields are null`() = runTest {
        val entity = createTestFileEntity(cachedName = null, cachedMimeType = null)
        every { fileDao.observeByFolderId(testFolderId) } returns flowOf(listOf(entity))

        fileRepository.observeFiles(testFolderId).test {
            val files = awaitItem()
            assertEquals("File", files[0].name)
            assertEquals("application/octet-stream", files[0].mimeType)
            awaitComplete()
        }
    }

    // ==================== observeFile Tests ====================

    @Test
    fun `observeFile returns file when found`() = runTest {
        val entity = createTestFileEntity()
        every { fileDao.observeById(testFileId) } returns flowOf(entity)

        fileRepository.observeFile(testFileId).test {
            val file = awaitItem()
            assertNotNull(file)
            assertEquals(testFileId, file!!.id)
            assertEquals(testFileName, file.name)
            awaitComplete()
        }
    }

    @Test
    fun `observeFile returns null when file not found`() = runTest {
        every { fileDao.observeById(testFileId) } returns flowOf(null)

        fileRepository.observeFile(testFileId).test {
            val file = awaitItem()
            assertNull(file)
            awaitComplete()
        }
    }

    // ==================== Network Error Mapping Tests ====================

    @Test
    fun `all methods map IOException to AppException Network`() = runTest {
        val ioException = IOException("Connection refused")

        // getFile
        coEvery { apiService.getFile(any()) } throws ioException
        val getFileResult = fileRepository.getFile(testFileId)
        assertTrue((getFileResult as Result.Error).exception is AppException.Network)

        // getFiles
        coEvery { apiService.getFolderFiles(any()) } throws ioException
        val getFilesResult = fileRepository.getFiles(testFolderId)
        assertTrue((getFilesResult as Result.Error).exception is AppException.Network)

        // deleteFile
        coEvery { apiService.deleteFile(any()) } throws ioException
        val deleteResult = fileRepository.deleteFile(testFileId)
        assertTrue((deleteResult as Result.Error).exception is AppException.Network)

        // searchFiles
        coEvery { apiService.searchFiles(any()) } throws ioException
        val searchResult = fileRepository.searchFiles("query")
        assertTrue((searchResult as Result.Error).exception is AppException.Network)

        // syncFiles
        val syncResult = fileRepository.syncFiles(testFolderId)
        assertTrue((syncResult as Result.Error).exception is AppException.Network)
    }

    @Test
    fun `all methods map generic exceptions to AppException Network`() = runTest {
        val genericException = RuntimeException("Something went wrong")

        coEvery { apiService.getFile(any()) } throws genericException
        val result = fileRepository.getFile(testFileId)
        assertTrue((result as Result.Error).exception is AppException.Network)
    }

    // ==================== Helper Functions ====================

    private fun createTestFileDto(
        id: String = testFileId,
        folderId: String = testFolderId,
        ownerId: String = testOwnerId,
        tenantId: String = testTenantId,
        blobHash: String? = "sha256-hash",
        blobSize: Long? = testFileSize,
        chunkCount: Int? = 1,
        status: String = "complete",
        encryptedMetadata: String = "enc-metadata-base64",
        wrappedDek: String = "wrapped-dek-base64",
        signature: String = "signature-base64",
        uploaderPublicKeys: PublicKeysDto? = PublicKeysDto(
            kem = "kem-key",
            sign = "sign-key",
            mlKem = "ml-kem-key",
            mlDsa = "ml-dsa-key"
        )
    ) = FileDto(
        id = id,
        folderId = folderId,
        ownerId = ownerId,
        tenantId = tenantId,
        storagePath = "storage/path",
        blobSize = blobSize,
        blobHash = blobHash,
        chunkCount = chunkCount,
        status = status,
        encryptedMetadata = encryptedMetadata,
        wrappedDek = wrappedDek,
        kemCiphertext = null,
        mlKemCiphertext = null,
        signature = signature,
        insertedAt = testTimestamp,
        updatedAt = testTimestamp,
        uploaderPublicKeys = uploaderPublicKeys
    )

    private fun createTestFileEntity(
        id: String = testFileId,
        cachedName: String? = testFileName,
        cachedMimeType: String? = testMimeType
    ) = FileEntity(
        id = id,
        folderId = testFolderId,
        ownerId = testOwnerId,
        tenantId = testTenantId,
        storagePath = "storage/path",
        blobSize = testFileSize,
        blobHash = "sha256-hash",
        chunkCount = 1,
        status = "complete",
        encryptedMetadata = ByteArray(32),
        wrappedDek = ByteArray(32),
        kemCiphertext = ByteArray(0),
        signature = ByteArray(64),
        cachedName = cachedName,
        cachedMimeType = cachedMimeType,
        insertedAt = Instant.parse(testTimestamp),
        updatedAt = Instant.parse(testTimestamp)
    )
}
