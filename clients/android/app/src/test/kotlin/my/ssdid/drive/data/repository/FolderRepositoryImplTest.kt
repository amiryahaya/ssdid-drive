package my.ssdid.drive.data.repository

import android.util.Base64
import app.cash.turbine.test
import my.ssdid.drive.crypto.FolderKeyManager
import my.ssdid.drive.data.local.dao.FolderDao
import my.ssdid.drive.data.local.entity.FolderEntity
import my.ssdid.drive.data.remote.ApiService
import my.ssdid.drive.data.remote.dto.CreateFolderRequest
import my.ssdid.drive.data.remote.dto.FolderDto
import my.ssdid.drive.data.remote.dto.FolderOwnerDto
import my.ssdid.drive.data.remote.dto.FolderResponse
import my.ssdid.drive.data.remote.dto.FoldersResponse
import my.ssdid.drive.data.remote.dto.MoveFolderRequest
import my.ssdid.drive.data.remote.dto.PublicKeysDto
import my.ssdid.drive.data.remote.dto.UpdateFolderRequest
import my.ssdid.drive.domain.model.Folder
import my.ssdid.drive.domain.model.FolderMetadata
import my.ssdid.drive.util.AppException
import my.ssdid.drive.util.Result
import io.mockk.*
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.runTest
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import retrofit2.Response
import java.io.IOException
import java.time.Instant

/**
 * Unit tests for FolderRepositoryImpl.
 *
 * Tests cover:
 * - getRootFolder success and error
 * - getFolder success and error (including 404, 403)
 * - getChildFolders success and error
 * - createFolder success and error (including KEK missing, 403, 404)
 * - renameFolder success and error (including KEK missing, API failure)
 * - deleteFolder success and error
 * - moveFolder success and error (including KEK missing, 409 conflict)
 * - syncFolders success and error
 * - getAllFolders success and error
 * - observeRootFolder / observeFolder / observeChildFolders Flow testing
 * - Signature verification scenarios
 * - KEK cache management
 */
@OptIn(ExperimentalCoroutinesApi::class)
class FolderRepositoryImplTest {

    private lateinit var apiService: ApiService
    private lateinit var folderDao: FolderDao
    private lateinit var folderKeyManager: FolderKeyManager
    private lateinit var folderRepository: FolderRepositoryImpl

    private val testFolderId = "folder-123"
    private val testParentId = "folder-parent-456"
    private val testOwnerId = "user-owner-789"
    private val testTenantId = "tenant-abc"
    private val testFolderName = "My Documents"
    private val testTimestamp = "2024-01-01T00:00:00Z"
    private val testKek = ByteArray(32) { it.toByte() }

    @Before
    fun setup() {
        mockkStatic(Base64::class)
        every { Base64.decode(any<String>(), any()) } returns ByteArray(32)
        every { Base64.encodeToString(any(), any()) } returns "base64encoded"

        apiService = mockk()
        folderDao = mockk(relaxed = true)
        folderKeyManager = mockk(relaxed = true)

        folderRepository = FolderRepositoryImpl(
            apiService = apiService,
            folderDao = folderDao,
            folderKeyManager = folderKeyManager
        )
    }

    @After
    fun tearDown() {
        unmockkStatic(Base64::class)
    }

    // ==================== getRootFolder Tests ====================

    @Test
    fun `getRootFolder returns folder on success`() = runTest {
        val folderDto = createTestFolderDto(isRoot = true)
        coEvery { apiService.getRootFolder() } returns Response.success(FolderResponse(data = folderDto))
        setupDecryptFolder()

        val result = folderRepository.getRootFolder()

        assertTrue(result is Result.Success)
        val folder = (result as Result.Success).data
        assertEquals(testFolderId, folder.id)
        assertTrue(folder.isRoot)
    }

    @Test
    fun `getRootFolder returns error on API failure`() = runTest {
        coEvery { apiService.getRootFolder() } returns Response.error(
            500,
            "Internal Server Error".toResponseBody()
        )

        val result = folderRepository.getRootFolder()

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Unknown)
        assertTrue(error.message.contains("root folder"))
    }

    @Test
    fun `getRootFolder returns network error on exception`() = runTest {
        coEvery { apiService.getRootFolder() } throws IOException("Connection refused")

        val result = folderRepository.getRootFolder()

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Network)
    }

    // ==================== getFolder Tests ====================

    @Test
    fun `getFolder returns folder on success`() = runTest {
        val folderDto = createTestFolderDto()
        coEvery { apiService.getFolder(testFolderId) } returns Response.success(
            FolderResponse(data = folderDto)
        )
        setupDecryptFolder()

        val result = folderRepository.getFolder(testFolderId)

        assertTrue(result is Result.Success)
        val folder = (result as Result.Success).data
        assertEquals(testFolderId, folder.id)
        assertEquals(testParentId, folder.parentId)
    }

    @Test
    fun `getFolder returns NotFound on 404`() = runTest {
        coEvery { apiService.getFolder(testFolderId) } returns Response.error(
            404,
            "Not Found".toResponseBody()
        )

        val result = folderRepository.getFolder(testFolderId)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.NotFound)
    }

    @Test
    fun `getFolder returns Forbidden on 403`() = runTest {
        coEvery { apiService.getFolder(testFolderId) } returns Response.error(
            403,
            "Forbidden".toResponseBody()
        )

        val result = folderRepository.getFolder(testFolderId)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Forbidden)
    }

    @Test
    fun `getFolder returns Unknown on other error codes`() = runTest {
        coEvery { apiService.getFolder(testFolderId) } returns Response.error(
            500,
            "Server Error".toResponseBody()
        )

        val result = folderRepository.getFolder(testFolderId)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Unknown)
    }

    @Test
    fun `getFolder returns network error on exception`() = runTest {
        coEvery { apiService.getFolder(testFolderId) } throws IOException("Timeout")

        val result = folderRepository.getFolder(testFolderId)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Network)
    }

    // ==================== getChildFolders Tests ====================

    @Test
    fun `getChildFolders returns list of folders on success`() = runTest {
        val folder1 = createTestFolderDto(id = "child-1")
        val folder2 = createTestFolderDto(id = "child-2")
        coEvery { apiService.getFolderChildren(testParentId) } returns Response.success(
            FoldersResponse(data = listOf(folder1, folder2))
        )
        setupDecryptFolder()

        val result = folderRepository.getChildFolders(testParentId)

        assertTrue(result is Result.Success)
        val folders = (result as Result.Success).data
        assertEquals(2, folders.size)
    }

    @Test
    fun `getChildFolders skips folders that fail decryption`() = runTest {
        val folder1 = createTestFolderDto(id = "child-1")
        val folder2 = createTestFolderDto(id = "child-2", encryptedMetadata = null)
        coEvery { apiService.getFolderChildren(testParentId) } returns Response.success(
            FoldersResponse(data = listOf(folder1, folder2))
        )
        // First call succeeds, second throws (missing metadata)
        every {
            folderKeyManager.verifyFolderSignature(
                any(), any(), any(), any(), any(), any(), any(), any(), any(), any(), any(), any()
            )
        } returns true
        every {
            folderKeyManager.decryptFolderKek(eq("child-1"), any(), any(), any())
        } returns testKek
        every {
            folderKeyManager.decryptMetadata(any(), any())
        } returns FolderMetadata(name = testFolderName)
        // folder2 has null encryptedMetadata -> CryptoError thrown in decryptFolder
        every {
            folderKeyManager.decryptFolderKek(eq("child-2"), any(), any(), any())
        } returns testKek

        val result = folderRepository.getChildFolders(testParentId)

        assertTrue(result is Result.Success)
        val folders = (result as Result.Success).data
        // folder2 should be skipped due to null encryptedMetadata -> exception
        assertEquals(1, folders.size)
        assertEquals("child-1", folders[0].id)
    }

    @Test
    fun `getChildFolders returns error on API failure`() = runTest {
        coEvery { apiService.getFolderChildren(testParentId) } returns Response.error(
            500,
            "Server Error".toResponseBody()
        )

        val result = folderRepository.getChildFolders(testParentId)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Unknown)
    }

    @Test
    fun `getChildFolders returns network error on exception`() = runTest {
        coEvery { apiService.getFolderChildren(testParentId) } throws IOException("Network error")

        val result = folderRepository.getChildFolders(testParentId)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Network)
    }

    // ==================== createFolder Tests ====================

    @Test
    fun `createFolder returns folder on success`() = runTest {
        val encryptionData = createTestEncryptionData()
        val folderDto = createTestFolderDto()

        every { folderKeyManager.getCachedKek(testParentId) } returns testKek
        every { folderKeyManager.createChildFolderEncryption(testFolderName, testKek) } returns encryptionData
        every {
            folderKeyManager.createFolderSignature(
                any(), any(), any(), any(), any(), any(), any(), any(), any(), any()
            )
        } returns "signature-base64"
        coEvery { apiService.createFolder(any()) } returns Response.success(
            FolderResponse(data = folderDto)
        )
        every { folderKeyManager.cacheKek(testFolderId, any()) } just Runs

        val result = folderRepository.createFolder(testParentId, testFolderName)

        assertTrue(result is Result.Success)
        val folder = (result as Result.Success).data
        assertEquals(testFolderId, folder.id)
        assertEquals(testFolderName, folder.name)
        verify { folderKeyManager.cacheKek(testFolderId, encryptionData.kek) }
    }

    @Test
    fun `createFolder returns crypto error when parent KEK not cached`() = runTest {
        every { folderKeyManager.getCachedKek(testParentId) } returns null

        val result = folderRepository.createFolder(testParentId, testFolderName)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.CryptoError)
        assertTrue(error.message.contains("KEK"))
    }

    @Test
    fun `createFolder returns Forbidden on 403`() = runTest {
        val encryptionData = createTestEncryptionData()

        every { folderKeyManager.getCachedKek(testParentId) } returns testKek
        every { folderKeyManager.createChildFolderEncryption(testFolderName, testKek) } returns encryptionData
        every {
            folderKeyManager.createFolderSignature(
                any(), any(), any(), any(), any(), any(), any(), any(), any(), any()
            )
        } returns "signature-base64"
        coEvery { apiService.createFolder(any()) } returns Response.error(
            403,
            "Forbidden".toResponseBody()
        )

        val result = folderRepository.createFolder(testParentId, testFolderName)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Forbidden)
    }

    @Test
    fun `createFolder returns NotFound on 404`() = runTest {
        val encryptionData = createTestEncryptionData()

        every { folderKeyManager.getCachedKek(testParentId) } returns testKek
        every { folderKeyManager.createChildFolderEncryption(testFolderName, testKek) } returns encryptionData
        every {
            folderKeyManager.createFolderSignature(
                any(), any(), any(), any(), any(), any(), any(), any(), any(), any()
            )
        } returns "signature-base64"
        coEvery { apiService.createFolder(any()) } returns Response.error(
            404,
            "Not Found".toResponseBody()
        )

        val result = folderRepository.createFolder(testParentId, testFolderName)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.NotFound)
    }

    @Test
    fun `createFolder returns network error on exception`() = runTest {
        val encryptionData = createTestEncryptionData()

        every { folderKeyManager.getCachedKek(testParentId) } returns testKek
        every { folderKeyManager.createChildFolderEncryption(testFolderName, testKek) } returns encryptionData
        every {
            folderKeyManager.createFolderSignature(
                any(), any(), any(), any(), any(), any(), any(), any(), any(), any()
            )
        } returns "signature-base64"
        coEvery { apiService.createFolder(any()) } throws IOException("Network error")

        val result = folderRepository.createFolder(testParentId, testFolderName)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Network)
    }

    // ==================== renameFolder Tests ====================

    @Test
    fun `renameFolder returns folder on success`() = runTest {
        val newName = "Renamed Folder"
        val folderDto = createTestFolderDto()

        every { folderKeyManager.getCachedKek(testFolderId) } returns testKek
        coEvery { apiService.getFolder(testFolderId) } returns Response.success(
            FolderResponse(data = folderDto)
        )
        every { folderKeyManager.encryptMetadata(any(), testKek) } returns "encrypted-metadata-base64"
        every { folderKeyManager.extractMetadataNonce(any<String>()) } returns "nonce-base64"
        every {
            folderKeyManager.createFolderSignature(
                any(), any(), any(), any(), any(), any(), any(), any(), any(), any()
            )
        } returns "signature-base64"
        coEvery { apiService.updateFolder(testFolderId, any()) } returns Response.success(
            FolderResponse(data = folderDto)
        )

        val result = folderRepository.renameFolder(testFolderId, newName)

        assertTrue(result is Result.Success)
        val folder = (result as Result.Success).data
        assertEquals(newName, folder.name)
    }

    @Test
    fun `renameFolder returns crypto error when KEK not cached`() = runTest {
        every { folderKeyManager.getCachedKek(testFolderId) } returns null

        val result = folderRepository.renameFolder(testFolderId, "New Name")

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.CryptoError)
        assertTrue(error.message.contains("KEK"))
    }

    @Test
    fun `renameFolder returns error when getFolder API fails`() = runTest {
        every { folderKeyManager.getCachedKek(testFolderId) } returns testKek
        coEvery { apiService.getFolder(testFolderId) } returns Response.error(
            500,
            "Server Error".toResponseBody()
        )

        val result = folderRepository.renameFolder(testFolderId, "New Name")

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Unknown)
        assertTrue(error.message.contains("load folder for update"))
    }

    @Test
    fun `renameFolder returns Forbidden on 403`() = runTest {
        val folderDto = createTestFolderDto()

        every { folderKeyManager.getCachedKek(testFolderId) } returns testKek
        coEvery { apiService.getFolder(testFolderId) } returns Response.success(
            FolderResponse(data = folderDto)
        )
        every { folderKeyManager.encryptMetadata(any(), testKek) } returns "encrypted"
        every { folderKeyManager.extractMetadataNonce(any<String>()) } returns "nonce"
        every {
            folderKeyManager.createFolderSignature(
                any(), any(), any(), any(), any(), any(), any(), any(), any(), any()
            )
        } returns "sig"
        coEvery { apiService.updateFolder(testFolderId, any()) } returns Response.error(
            403,
            "Forbidden".toResponseBody()
        )

        val result = folderRepository.renameFolder(testFolderId, "New Name")

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Forbidden)
    }

    @Test
    fun `renameFolder returns NotFound on 404`() = runTest {
        val folderDto = createTestFolderDto()

        every { folderKeyManager.getCachedKek(testFolderId) } returns testKek
        coEvery { apiService.getFolder(testFolderId) } returns Response.success(
            FolderResponse(data = folderDto)
        )
        every { folderKeyManager.encryptMetadata(any(), testKek) } returns "encrypted"
        every { folderKeyManager.extractMetadataNonce(any<String>()) } returns "nonce"
        every {
            folderKeyManager.createFolderSignature(
                any(), any(), any(), any(), any(), any(), any(), any(), any(), any()
            )
        } returns "sig"
        coEvery { apiService.updateFolder(testFolderId, any()) } returns Response.error(
            404,
            "Not Found".toResponseBody()
        )

        val result = folderRepository.renameFolder(testFolderId, "New Name")

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.NotFound)
    }

    @Test
    fun `renameFolder returns network error on exception`() = runTest {
        every { folderKeyManager.getCachedKek(testFolderId) } returns testKek
        coEvery { apiService.getFolder(testFolderId) } throws IOException("Timeout")

        val result = folderRepository.renameFolder(testFolderId, "New Name")

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Network)
    }

    // ==================== deleteFolder Tests ====================

    @Test
    fun `deleteFolder returns success and removes from local DB`() = runTest {
        coEvery { apiService.deleteFolder(testFolderId) } returns Response.success(Unit)
        coEvery { folderDao.deleteById(testFolderId) } just Runs

        val result = folderRepository.deleteFolder(testFolderId)

        assertTrue(result is Result.Success)
        coVerify { folderDao.deleteById(testFolderId) }
    }

    @Test
    fun `deleteFolder returns error on API failure`() = runTest {
        coEvery { apiService.deleteFolder(testFolderId) } returns Response.error(
            500,
            "Server Error".toResponseBody()
        )

        val result = folderRepository.deleteFolder(testFolderId)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Unknown)
        coVerify(exactly = 0) { folderDao.deleteById(any()) }
    }

    @Test
    fun `deleteFolder returns network error on exception`() = runTest {
        coEvery { apiService.deleteFolder(testFolderId) } throws IOException("Network error")

        val result = folderRepository.deleteFolder(testFolderId)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Network)
    }

    // ==================== moveFolder Tests ====================

    @Test
    fun `moveFolder returns folder on success`() = runTest {
        val newParentId = "new-parent-id"
        val newParentKek = ByteArray(32) { (it + 10).toByte() }
        val folderDto = createTestFolderDto()
        val rewrapResult = FolderKeyManager.KekRewrapResult(
            wrappedKek = "rewrapped-kek",
            kemCiphertext = null
        )

        every { folderKeyManager.getCachedKek(testFolderId) } returns testKek
        coEvery { apiService.getFolder(testFolderId) } returns Response.success(
            FolderResponse(data = folderDto)
        )
        every { folderKeyManager.getCachedKek(newParentId) } returns newParentKek
        every { folderKeyManager.rewrapKekForParent(testKek, newParentKek) } returns rewrapResult
        every { folderKeyManager.extractMetadataNonce(any<String>()) } returns "nonce-base64"
        every {
            folderKeyManager.createFolderSignature(
                any(), any(), any(), any(), any(), any(), any(), any(), any(), any()
            )
        } returns "signature-base64"
        coEvery { apiService.moveFolder(testFolderId, any()) } returns Response.success(
            FolderResponse(data = folderDto.copy(parentId = newParentId))
        )
        setupDecryptFolder()

        val result = folderRepository.moveFolder(testFolderId, newParentId)

        assertTrue(result is Result.Success)
    }

    @Test
    fun `moveFolder returns crypto error when folder KEK not cached`() = runTest {
        every { folderKeyManager.getCachedKek(testFolderId) } returns null

        val result = folderRepository.moveFolder(testFolderId, "new-parent")

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.CryptoError)
        assertTrue(error.message.contains("Folder KEK"))
    }

    @Test
    fun `moveFolder returns crypto error when new parent KEK not cached`() = runTest {
        val folderDto = createTestFolderDto()

        every { folderKeyManager.getCachedKek(testFolderId) } returns testKek
        coEvery { apiService.getFolder(testFolderId) } returns Response.success(
            FolderResponse(data = folderDto)
        )
        every { folderKeyManager.getCachedKek("new-parent") } returns null

        val result = folderRepository.moveFolder(testFolderId, "new-parent")

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.CryptoError)
        assertTrue(error.message.contains("New parent"))
    }

    @Test
    fun `moveFolder returns error when getFolder fails`() = runTest {
        every { folderKeyManager.getCachedKek(testFolderId) } returns testKek
        coEvery { apiService.getFolder(testFolderId) } returns Response.error(
            500,
            "Server Error".toResponseBody()
        )

        val result = folderRepository.moveFolder(testFolderId, "new-parent")

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Unknown)
        assertTrue(error.message.contains("load folder for move"))
    }

    @Test
    fun `moveFolder returns Conflict on 409`() = runTest {
        val newParentId = "new-parent-id"
        val newParentKek = ByteArray(32) { (it + 10).toByte() }
        val folderDto = createTestFolderDto()
        val rewrapResult = FolderKeyManager.KekRewrapResult(
            wrappedKek = "rewrapped-kek",
            kemCiphertext = null
        )

        every { folderKeyManager.getCachedKek(testFolderId) } returns testKek
        coEvery { apiService.getFolder(testFolderId) } returns Response.success(
            FolderResponse(data = folderDto)
        )
        every { folderKeyManager.getCachedKek(newParentId) } returns newParentKek
        every { folderKeyManager.rewrapKekForParent(testKek, newParentKek) } returns rewrapResult
        every { folderKeyManager.extractMetadataNonce(any<String>()) } returns "nonce-base64"
        every {
            folderKeyManager.createFolderSignature(
                any(), any(), any(), any(), any(), any(), any(), any(), any(), any()
            )
        } returns "signature-base64"
        coEvery { apiService.moveFolder(testFolderId, any()) } returns Response.error(
            409,
            "Conflict".toResponseBody()
        )

        val result = folderRepository.moveFolder(testFolderId, newParentId)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Conflict)
    }

    @Test
    fun `moveFolder returns Forbidden on 403`() = runTest {
        val newParentId = "new-parent-id"
        val newParentKek = ByteArray(32) { (it + 10).toByte() }
        val folderDto = createTestFolderDto()
        val rewrapResult = FolderKeyManager.KekRewrapResult(
            wrappedKek = "rewrapped-kek",
            kemCiphertext = null
        )

        every { folderKeyManager.getCachedKek(testFolderId) } returns testKek
        coEvery { apiService.getFolder(testFolderId) } returns Response.success(
            FolderResponse(data = folderDto)
        )
        every { folderKeyManager.getCachedKek(newParentId) } returns newParentKek
        every { folderKeyManager.rewrapKekForParent(testKek, newParentKek) } returns rewrapResult
        every { folderKeyManager.extractMetadataNonce(any<String>()) } returns "nonce-base64"
        every {
            folderKeyManager.createFolderSignature(
                any(), any(), any(), any(), any(), any(), any(), any(), any(), any()
            )
        } returns "signature-base64"
        coEvery { apiService.moveFolder(testFolderId, any()) } returns Response.error(
            403,
            "Forbidden".toResponseBody()
        )

        val result = folderRepository.moveFolder(testFolderId, newParentId)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Forbidden)
    }

    @Test
    fun `moveFolder returns network error on exception`() = runTest {
        every { folderKeyManager.getCachedKek(testFolderId) } returns testKek
        coEvery { apiService.getFolder(testFolderId) } throws IOException("Timeout")

        val result = folderRepository.moveFolder(testFolderId, "new-parent")

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Network)
    }

    @Test
    fun `moveFolder returns crypto error when encrypted metadata is missing`() = runTest {
        val newParentId = "new-parent-id"
        val newParentKek = ByteArray(32) { (it + 10).toByte() }
        val folderDto = createTestFolderDto(encryptedMetadata = null, metadataNonce = null)
        val rewrapResult = FolderKeyManager.KekRewrapResult(
            wrappedKek = "rewrapped-kek",
            kemCiphertext = null
        )

        every { folderKeyManager.getCachedKek(testFolderId) } returns testKek
        coEvery { apiService.getFolder(testFolderId) } returns Response.success(
            FolderResponse(data = folderDto)
        )
        every { folderKeyManager.getCachedKek(newParentId) } returns newParentKek
        every { folderKeyManager.rewrapKekForParent(testKek, newParentKek) } returns rewrapResult

        val result = folderRepository.moveFolder(testFolderId, newParentId)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.CryptoError)
        assertTrue(error.message.contains("metadata"))
    }

    // ==================== syncFolders Tests ====================

    @Test
    fun `syncFolders inserts decrypted folders into local DB`() = runTest {
        val folder1 = createTestFolderDto(id = "sync-1")
        val folder2 = createTestFolderDto(id = "sync-2")
        coEvery { apiService.listFolders() } returns Response.success(
            FoldersResponse(data = listOf(folder1, folder2))
        )
        setupDecryptFolder()
        coEvery { folderDao.insertAll(any()) } just Runs

        val result = folderRepository.syncFolders()

        assertTrue(result is Result.Success)
        coVerify { folderDao.insertAll(match { it.size == 2 }) }
    }

    @Test
    fun `syncFolders skips undecryptable folders`() = runTest {
        val folder1 = createTestFolderDto(id = "sync-1")
        val folder2 = createTestFolderDto(id = "sync-2", encryptedMetadata = null)
        coEvery { apiService.listFolders() } returns Response.success(
            FoldersResponse(data = listOf(folder1, folder2))
        )
        // Setup so first folder decrypts, second throws due to null encryptedMetadata
        every {
            folderKeyManager.verifyFolderSignature(
                any(), any(), any(), any(), any(), any(), any(), any(), any(), any(), any(), any()
            )
        } returns true
        every {
            folderKeyManager.decryptFolderKek(eq("sync-1"), any(), any(), any())
        } returns testKek
        every {
            folderKeyManager.decryptMetadata(any(), any())
        } returns FolderMetadata(name = testFolderName)
        coEvery { folderDao.insertAll(any()) } just Runs

        val result = folderRepository.syncFolders()

        assertTrue(result is Result.Success)
        coVerify { folderDao.insertAll(match { it.size == 1 }) }
    }

    @Test
    fun `syncFolders returns error on API failure`() = runTest {
        coEvery { apiService.listFolders() } returns Response.error(
            500,
            "Server Error".toResponseBody()
        )

        val result = folderRepository.syncFolders()

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Unknown)
    }

    @Test
    fun `syncFolders returns network error on exception`() = runTest {
        coEvery { apiService.listFolders() } throws IOException("Connection lost")

        val result = folderRepository.syncFolders()

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Network)
    }

    // ==================== getAllFolders Tests ====================

    @Test
    fun `getAllFolders returns list on success`() = runTest {
        val folder1 = createTestFolderDto(id = "all-1")
        val folder2 = createTestFolderDto(id = "all-2")
        coEvery { apiService.listFolders() } returns Response.success(
            FoldersResponse(data = listOf(folder1, folder2))
        )
        setupDecryptFolder()

        val result = folderRepository.getAllFolders()

        assertTrue(result is Result.Success)
        val folders = (result as Result.Success).data
        assertEquals(2, folders.size)
    }

    @Test
    fun `getAllFolders returns error on API failure`() = runTest {
        coEvery { apiService.listFolders() } returns Response.error(
            500,
            "Server Error".toResponseBody()
        )

        val result = folderRepository.getAllFolders()

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Unknown)
    }

    @Test
    fun `getAllFolders returns network error on exception`() = runTest {
        coEvery { apiService.listFolders() } throws IOException("Timeout")

        val result = folderRepository.getAllFolders()

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Network)
    }

    // ==================== observeRootFolder Tests ====================

    @Test
    fun `observeRootFolder emits folder from local DB`() = runTest {
        val entity = createTestFolderEntity(isRoot = true, cachedName = "My Files")
        every { folderDao.observeRootFolder() } returns flowOf(entity)

        folderRepository.observeRootFolder().test {
            val folder = awaitItem()
            assertNotNull(folder)
            assertEquals(testFolderId, folder!!.id)
            assertEquals("My Files", folder.name)
            assertTrue(folder.isRoot)
            awaitComplete()
        }
    }

    @Test
    fun `observeRootFolder emits null when no root folder`() = runTest {
        every { folderDao.observeRootFolder() } returns flowOf(null)

        folderRepository.observeRootFolder().test {
            val folder = awaitItem()
            assertNull(folder)
            awaitComplete()
        }
    }

    @Test
    fun `observeRootFolder uses default name when cachedName is null`() = runTest {
        val entity = createTestFolderEntity(isRoot = true, cachedName = null)
        every { folderDao.observeRootFolder() } returns flowOf(entity)

        folderRepository.observeRootFolder().test {
            val folder = awaitItem()
            assertNotNull(folder)
            assertEquals("My Files", folder!!.name)
            awaitComplete()
        }
    }

    // ==================== observeFolder Tests ====================

    @Test
    fun `observeFolder emits folder from local DB`() = runTest {
        val entity = createTestFolderEntity(cachedName = "Documents")
        every { folderDao.observeById(testFolderId) } returns flowOf(entity)

        folderRepository.observeFolder(testFolderId).test {
            val folder = awaitItem()
            assertNotNull(folder)
            assertEquals(testFolderId, folder!!.id)
            assertEquals("Documents", folder.name)
            awaitComplete()
        }
    }

    @Test
    fun `observeFolder emits null when folder not found`() = runTest {
        every { folderDao.observeById(testFolderId) } returns flowOf(null)

        folderRepository.observeFolder(testFolderId).test {
            val folder = awaitItem()
            assertNull(folder)
            awaitComplete()
        }
    }

    @Test
    fun `observeFolder uses default name when cachedName is null`() = runTest {
        val entity = createTestFolderEntity(cachedName = null)
        every { folderDao.observeById(testFolderId) } returns flowOf(entity)

        folderRepository.observeFolder(testFolderId).test {
            val folder = awaitItem()
            assertNotNull(folder)
            assertEquals("Folder", folder!!.name)
            awaitComplete()
        }
    }

    // ==================== observeChildFolders Tests ====================

    @Test
    fun `observeChildFolders emits list of folders`() = runTest {
        val entity1 = createTestFolderEntity(id = "child-1", cachedName = "Alpha")
        val entity2 = createTestFolderEntity(id = "child-2", cachedName = "Beta")
        every { folderDao.observeChildren(testParentId) } returns flowOf(listOf(entity1, entity2))

        folderRepository.observeChildFolders(testParentId).test {
            val folders = awaitItem()
            assertEquals(2, folders.size)
            assertEquals("Alpha", folders[0].name)
            assertEquals("Beta", folders[1].name)
            awaitComplete()
        }
    }

    @Test
    fun `observeChildFolders emits empty list when no children`() = runTest {
        every { folderDao.observeChildren(testParentId) } returns flowOf(emptyList())

        folderRepository.observeChildFolders(testParentId).test {
            val folders = awaitItem()
            assertTrue(folders.isEmpty())
            awaitComplete()
        }
    }

    @Test
    fun `observeChildFolders uses default name for null cachedName`() = runTest {
        val entity = createTestFolderEntity(id = "child-1", cachedName = null)
        every { folderDao.observeChildren(testParentId) } returns flowOf(listOf(entity))

        folderRepository.observeChildFolders(testParentId).test {
            val folders = awaitItem()
            assertEquals(1, folders.size)
            assertEquals("Folder", folders[0].name)
            awaitComplete()
        }
    }

    // ==================== Signature Verification Tests ====================

    @Test
    fun `decryptFolder verifies signature when present`() = runTest {
        val folderDto = createTestFolderDto(signature = "valid-signature-base64")
        coEvery { apiService.getRootFolder() } returns Response.success(FolderResponse(data = folderDto))
        every {
            folderKeyManager.verifyFolderSignature(
                any(), any(), any(), any(), any(), any(), any(), any(), any(), any(), any(), any()
            )
        } returns true
        every { folderKeyManager.decryptFolderKek(any(), any(), any(), any()) } returns testKek
        every { folderKeyManager.decryptMetadata(any(), any()) } returns FolderMetadata(name = testFolderName)

        val result = folderRepository.getRootFolder()

        assertTrue(result is Result.Success)
        verify {
            folderKeyManager.verifyFolderSignature(
                any(), any(), any(), any(), any(), any(), any(), any(), any(), any(), any(), any()
            )
        }
    }

    @Test
    fun `decryptFolder throws CryptoError when signature is invalid`() = runTest {
        val folderDto = createTestFolderDto(signature = "invalid-signature")
        coEvery { apiService.getRootFolder() } returns Response.success(FolderResponse(data = folderDto))
        every {
            folderKeyManager.verifyFolderSignature(
                any(), any(), any(), any(), any(), any(), any(), any(), any(), any(), any(), any()
            )
        } returns false

        val result = folderRepository.getRootFolder()

        // The exception thrown in decryptFolder is caught by the try/catch in getRootFolder,
        // resulting in a Network error wrapping the CryptoError
        assertTrue(result is Result.Error)
    }

    @Test
    fun `decryptFolder throws when owner public keys missing for signed folder`() = runTest {
        val folderDto = createTestFolderDto(signature = "some-sig", includeOwner = false)
        coEvery { apiService.getRootFolder() } returns Response.success(FolderResponse(data = folderDto))

        val result = folderRepository.getRootFolder()

        // Missing owner public keys causes CryptoError, caught as Network error
        assertTrue(result is Result.Error)
    }

    @Test
    fun `decryptFolder skips signature verification when signature is null`() = runTest {
        val folderDto = createTestFolderDto(signature = null)
        coEvery { apiService.getRootFolder() } returns Response.success(FolderResponse(data = folderDto))
        every { folderKeyManager.decryptFolderKek(any(), any(), any(), any()) } returns testKek
        every { folderKeyManager.decryptMetadata(any(), any()) } returns FolderMetadata(name = testFolderName)

        val result = folderRepository.getRootFolder()

        assertTrue(result is Result.Success)
        verify(exactly = 0) {
            folderKeyManager.verifyFolderSignature(
                any(), any(), any(), any(), any(), any(), any(), any(), any(), any(), any(), any()
            )
        }
    }

    @Test
    fun `decryptFolder skips signature verification when signature is blank`() = runTest {
        val folderDto = createTestFolderDto(signature = "")
        coEvery { apiService.getRootFolder() } returns Response.success(FolderResponse(data = folderDto))
        every { folderKeyManager.decryptFolderKek(any(), any(), any(), any()) } returns testKek
        every { folderKeyManager.decryptMetadata(any(), any()) } returns FolderMetadata(name = testFolderName)

        val result = folderRepository.getRootFolder()

        assertTrue(result is Result.Success)
        verify(exactly = 0) {
            folderKeyManager.verifyFolderSignature(
                any(), any(), any(), any(), any(), any(), any(), any(), any(), any(), any(), any()
            )
        }
    }

    // ==================== KEK Cache Management Tests ====================

    @Test
    fun `createFolder caches KEK after successful creation`() = runTest {
        val encryptionData = createTestEncryptionData()
        val folderDto = createTestFolderDto()

        every { folderKeyManager.getCachedKek(testParentId) } returns testKek
        every { folderKeyManager.createChildFolderEncryption(testFolderName, testKek) } returns encryptionData
        every {
            folderKeyManager.createFolderSignature(
                any(), any(), any(), any(), any(), any(), any(), any(), any(), any()
            )
        } returns "signature-base64"
        coEvery { apiService.createFolder(any()) } returns Response.success(
            FolderResponse(data = folderDto)
        )
        every { folderKeyManager.cacheKek(any(), any()) } just Runs

        folderRepository.createFolder(testParentId, testFolderName)

        verify { folderKeyManager.cacheKek(testFolderId, encryptionData.kek) }
    }

    @Test
    fun `createFolder does not cache KEK on API failure`() = runTest {
        val encryptionData = createTestEncryptionData()

        every { folderKeyManager.getCachedKek(testParentId) } returns testKek
        every { folderKeyManager.createChildFolderEncryption(testFolderName, testKek) } returns encryptionData
        every {
            folderKeyManager.createFolderSignature(
                any(), any(), any(), any(), any(), any(), any(), any(), any(), any()
            )
        } returns "signature-base64"
        coEvery { apiService.createFolder(any()) } returns Response.error(
            500,
            "Server Error".toResponseBody()
        )

        folderRepository.createFolder(testParentId, testFolderName)

        verify(exactly = 0) { folderKeyManager.cacheKek(any(), any()) }
    }

    // ==================== Decryption Edge Cases ====================

    @Test
    fun `decryptFolder falls back to My Files for root folder on decrypt error`() = runTest {
        val folderDto = createTestFolderDto(isRoot = true, signature = null)
        coEvery { apiService.getRootFolder() } returns Response.success(FolderResponse(data = folderDto))
        every { folderKeyManager.decryptFolderKek(any(), any(), any(), any()) } returns testKek
        every { folderKeyManager.decryptMetadata(any(), any()) } throws RuntimeException("Decrypt failed")

        val result = folderRepository.getRootFolder()

        assertTrue(result is Result.Success)
        val folder = (result as Result.Success).data
        assertEquals("My Files", folder.name)
    }

    @Test
    fun `decryptFolder falls back to Folder for non-root folder on decrypt error`() = runTest {
        val folderDto = createTestFolderDto(isRoot = false, signature = null)
        coEvery { apiService.getFolder(testFolderId) } returns Response.success(
            FolderResponse(data = folderDto)
        )
        every { folderKeyManager.decryptFolderKek(any(), any(), any(), any()) } returns testKek
        every { folderKeyManager.decryptMetadata(any(), any()) } throws RuntimeException("Decrypt failed")

        val result = folderRepository.getFolder(testFolderId)

        assertTrue(result is Result.Success)
        val folder = (result as Result.Success).data
        assertEquals("Folder", folder.name)
    }

    @Test
    fun `decryptFolder uses metadataNonce from DTO when available`() = runTest {
        val folderDto = createTestFolderDto(
            signature = "valid-sig",
            metadataNonce = "explicit-nonce"
        )
        coEvery { apiService.getRootFolder() } returns Response.success(FolderResponse(data = folderDto))
        every {
            folderKeyManager.verifyFolderSignature(
                any(), any(), any(), eq("explicit-nonce"), any(), any(), any(), any(), any(), any(), any(), any()
            )
        } returns true
        every { folderKeyManager.decryptFolderKek(any(), any(), any(), any()) } returns testKek
        every { folderKeyManager.decryptMetadata(any(), any()) } returns FolderMetadata(name = testFolderName)

        val result = folderRepository.getRootFolder()

        assertTrue(result is Result.Success)
        // Verifies that the explicit metadataNonce was passed (not extracted)
        verify(exactly = 0) { folderKeyManager.extractMetadataNonce(any<String>()) }
    }

    @Test
    fun `decryptFolder extracts nonce from metadata when DTO nonce is null`() = runTest {
        val folderDto = createTestFolderDto(
            signature = "valid-sig",
            metadataNonce = null
        )
        coEvery { apiService.getRootFolder() } returns Response.success(FolderResponse(data = folderDto))
        every { folderKeyManager.extractMetadataNonce(any<String>()) } returns "extracted-nonce"
        every {
            folderKeyManager.verifyFolderSignature(
                any(), any(), any(), eq("extracted-nonce"), any(), any(), any(), any(), any(), any(), any(), any()
            )
        } returns true
        every { folderKeyManager.decryptFolderKek(any(), any(), any(), any()) } returns testKek
        every { folderKeyManager.decryptMetadata(any(), any()) } returns FolderMetadata(name = testFolderName)

        val result = folderRepository.getRootFolder()

        assertTrue(result is Result.Success)
        verify { folderKeyManager.extractMetadataNonce(any<String>()) }
    }

    // ==================== Helper Functions ====================

    private fun createTestFolderDto(
        id: String = testFolderId,
        parentId: String? = testParentId,
        isRoot: Boolean = false,
        encryptedMetadata: String? = "encrypted-metadata-base64",
        metadataNonce: String? = "nonce-base64",
        signature: String? = "signature-base64",
        includeOwner: Boolean = true
    ): FolderDto {
        val owner = if (includeOwner) {
            FolderOwnerDto(
                id = testOwnerId,
                publicKeys = PublicKeysDto(
                    kem = "owner-kem-key",
                    sign = "owner-sign-key",
                    mlKem = "owner-ml-kem-key",
                    mlDsa = "owner-ml-dsa-key"
                )
            )
        } else null

        return FolderDto(
            id = id,
            parentId = parentId,
            ownerId = testOwnerId,
            tenantId = testTenantId,
            isRoot = isRoot,
            encryptedMetadata = encryptedMetadata,
            metadataNonce = metadataNonce,
            wrappedKek = "wrapped-kek-base64",
            kemCiphertext = "kem-ciphertext-base64",
            ownerWrappedKek = "owner-wrapped-kek-base64",
            ownerKemCiphertext = "owner-kem-ciphertext-base64",
            mlKemCiphertext = null,
            ownerMlKemCiphertext = null,
            signature = signature,
            owner = owner,
            createdAt = testTimestamp,
            updatedAt = testTimestamp
        )
    }

    private fun createTestFolderEntity(
        id: String = testFolderId,
        isRoot: Boolean = false,
        cachedName: String? = testFolderName
    ): FolderEntity {
        return FolderEntity(
            id = id,
            parentId = testParentId,
            ownerId = testOwnerId,
            tenantId = testTenantId,
            isRoot = isRoot,
            encryptedMetadata = ByteArray(32),
            wrappedKek = ByteArray(32),
            kemCiphertext = ByteArray(32),
            signature = ByteArray(32),
            cachedName = cachedName,
            insertedAt = Instant.parse(testTimestamp),
            updatedAt = Instant.parse(testTimestamp)
        )
    }

    private fun createTestEncryptionData(): FolderKeyManager.FolderEncryptionData {
        return FolderKeyManager.FolderEncryptionData(
            kek = testKek,
            wrappedKek = "wrapped-kek-base64",
            kemCiphertext = "",
            ownerWrappedKek = "owner-wrapped-kek-base64",
            ownerKemCiphertext = "owner-kem-ciphertext-base64",
            mlKemCiphertext = null,
            ownerMlKemCiphertext = null,
            encryptedMetadata = "encrypted-metadata-base64",
            metadataNonce = "nonce-base64"
        )
    }

    /**
     * Setup mocks for the common decryptFolder path (signature valid + KEK decrypt + metadata decrypt).
     */
    private fun setupDecryptFolder() {
        every {
            folderKeyManager.verifyFolderSignature(
                any(), any(), any(), any(), any(), any(), any(), any(), any(), any(), any(), any()
            )
        } returns true
        every { folderKeyManager.decryptFolderKek(any(), any(), any(), any()) } returns testKek
        every { folderKeyManager.decryptMetadata(any(), any()) } returns FolderMetadata(name = testFolderName)
    }
}
