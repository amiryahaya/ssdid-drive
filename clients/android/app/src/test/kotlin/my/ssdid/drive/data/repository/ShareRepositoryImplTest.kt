package my.ssdid.drive.data.repository

import android.util.Base64
import my.ssdid.drive.crypto.FileDecryptor
import my.ssdid.drive.crypto.FolderKeyManager
import my.ssdid.drive.crypto.KeyEncapsulation
import my.ssdid.drive.data.local.SecureStorage
import my.ssdid.drive.data.local.dao.ShareDao
import my.ssdid.drive.data.local.dao.UserDao
import my.ssdid.drive.data.remote.ApiService
import my.ssdid.drive.data.remote.dto.FileDto
import my.ssdid.drive.data.remote.dto.FileResponse
import my.ssdid.drive.data.remote.dto.PublicKeysDto
import my.ssdid.drive.data.remote.dto.SetExpiryRequest
import my.ssdid.drive.data.remote.dto.ShareDto
import my.ssdid.drive.data.remote.dto.ShareResponse
import my.ssdid.drive.data.remote.dto.SharesResponse
import my.ssdid.drive.data.remote.dto.UserDto
import my.ssdid.drive.data.remote.dto.UserResponse
import my.ssdid.drive.data.remote.dto.UsersResponse
import my.ssdid.drive.domain.model.PublicKeys
import my.ssdid.drive.domain.model.SharePermission
import my.ssdid.drive.domain.model.User
import my.ssdid.drive.util.AnalyticsManager
import my.ssdid.drive.util.AppException
import my.ssdid.drive.util.Logger
import my.ssdid.drive.util.Result
import io.mockk.*
import kotlinx.coroutines.ExperimentalCoroutinesApi
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
 * Unit tests for ShareRepositoryImpl.
 *
 * Tests cover:
 * - shareFile success and error paths
 * - shareFolder success and error paths
 * - getReceivedShares success and error
 * - getCreatedShares success and error
 * - getShare success and error with HTTP code mapping
 * - updatePermission success and error
 * - setExpiry success and error
 * - revokeShare success and error
 * - searchUsers success and error
 * - syncShares
 * - HTTP error mapping (403, 404, 409)
 */
@OptIn(ExperimentalCoroutinesApi::class)
class ShareRepositoryImplTest {

    private lateinit var apiService: ApiService
    private lateinit var shareDao: ShareDao
    private lateinit var userDao: UserDao
    private lateinit var secureStorage: SecureStorage
    private lateinit var keyEncapsulation: KeyEncapsulation
    private lateinit var fileDecryptor: FileDecryptor
    private lateinit var folderKeyManager: FolderKeyManager
    private lateinit var analyticsManager: AnalyticsManager
    private lateinit var shareRepository: ShareRepositoryImpl

    private val testShareId = "share-123"
    private val testFileId = "file-456"
    private val testFolderId = "folder-789"
    private val testGrantorId = "user-grantor"
    private val testGranteeId = "user-grantee"
    private val testTimestamp = "2024-01-01T00:00:00Z"

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

        apiService = mockk()
        shareDao = mockk(relaxed = true)
        userDao = mockk(relaxed = true)
        secureStorage = mockk(relaxed = true)
        keyEncapsulation = mockk()
        fileDecryptor = mockk()
        folderKeyManager = mockk(relaxed = true)
        analyticsManager = mockk(relaxed = true)

        shareRepository = ShareRepositoryImpl(
            apiService = apiService,
            shareDao = shareDao,
            userDao = userDao,
            secureStorage = secureStorage,
            keyEncapsulation = keyEncapsulation,
            fileDecryptor = fileDecryptor,
            folderKeyManager = folderKeyManager,
            analyticsManager = analyticsManager
        )
    }

    @After
    fun tearDown() {
        unmockkStatic(Base64::class)
        unmockkObject(Logger)
    }

    // ==================== getReceivedShares Tests ====================

    @Test
    fun `getReceivedShares returns shares on success`() = runTest {
        val sharesResponse = SharesResponse(data = listOf(createTestShareDto()))
        coEvery { apiService.getReceivedShares() } returns Response.success(sharesResponse)

        val result = shareRepository.getReceivedShares()

        assertTrue(result is Result.Success)
        val shares = (result as Result.Success).data
        assertEquals(1, shares.size)
        assertEquals(testShareId, shares[0].id)
    }

    @Test
    fun `getReceivedShares returns empty list on success with no shares`() = runTest {
        val sharesResponse = SharesResponse(data = emptyList())
        coEvery { apiService.getReceivedShares() } returns Response.success(sharesResponse)

        val result = shareRepository.getReceivedShares()

        assertTrue(result is Result.Success)
        val shares = (result as Result.Success).data
        assertTrue(shares.isEmpty())
    }

    @Test
    fun `getReceivedShares returns error on API failure`() = runTest {
        coEvery { apiService.getReceivedShares() } returns Response.error(
            500,
            "Internal Server Error".toResponseBody()
        )

        val result = shareRepository.getReceivedShares()

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Unknown)
    }

    @Test
    fun `getReceivedShares returns network error on exception`() = runTest {
        coEvery { apiService.getReceivedShares() } throws IOException("Network error")

        val result = shareRepository.getReceivedShares()

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Network)
    }

    // ==================== getCreatedShares Tests ====================

    @Test
    fun `getCreatedShares returns shares on success`() = runTest {
        val sharesResponse = SharesResponse(data = listOf(createTestShareDto()))
        coEvery { apiService.getCreatedShares() } returns Response.success(sharesResponse)

        val result = shareRepository.getCreatedShares()

        assertTrue(result is Result.Success)
        val shares = (result as Result.Success).data
        assertEquals(1, shares.size)
        assertEquals(testShareId, shares[0].id)
    }

    @Test
    fun `getCreatedShares returns error on API failure`() = runTest {
        coEvery { apiService.getCreatedShares() } returns Response.error(
            500,
            "Internal Server Error".toResponseBody()
        )

        val result = shareRepository.getCreatedShares()

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Unknown)
    }

    @Test
    fun `getCreatedShares returns network error on exception`() = runTest {
        coEvery { apiService.getCreatedShares() } throws IOException("Network error")

        val result = shareRepository.getCreatedShares()

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Network)
    }

    // ==================== getShare Tests ====================

    @Test
    fun `getShare returns share on success`() = runTest {
        val shareResponse = ShareResponse(data = createTestShareDto())
        coEvery { apiService.getShare(testShareId) } returns Response.success(shareResponse)

        val result = shareRepository.getShare(testShareId)

        assertTrue(result is Result.Success)
        val share = (result as Result.Success).data
        assertEquals(testShareId, share.id)
    }

    @Test
    fun `getShare returns not found on 404`() = runTest {
        coEvery { apiService.getShare(testShareId) } returns Response.error(
            404,
            "Not Found".toResponseBody()
        )

        val result = shareRepository.getShare(testShareId)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.NotFound)
    }

    @Test
    fun `getShare returns forbidden on 403`() = runTest {
        coEvery { apiService.getShare(testShareId) } returns Response.error(
            403,
            "Forbidden".toResponseBody()
        )

        val result = shareRepository.getShare(testShareId)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Forbidden)
    }

    @Test
    fun `getShare returns unknown error on other HTTP codes`() = runTest {
        coEvery { apiService.getShare(testShareId) } returns Response.error(
            500,
            "Server Error".toResponseBody()
        )

        val result = shareRepository.getShare(testShareId)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Unknown)
    }

    @Test
    fun `getShare returns network error on exception`() = runTest {
        coEvery { apiService.getShare(testShareId) } throws IOException("Connection timeout")

        val result = shareRepository.getShare(testShareId)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Network)
    }

    // ==================== shareFile (with User) Tests ====================

    @Test
    fun `shareFile returns success when all crypto and API succeed`() = runTest {
        val grantee = createTestUser()
        val fileDto = createTestFileDto()
        val encapsulationResult = createTestEncapsulationResult()
        val shareResponse = ShareResponse(data = createTestShareDto())

        coEvery { apiService.getFile(testFileId) } returns Response.success(FileResponse(data = fileDto))
        every { fileDecryptor.verifySignature(any(), any(), any(), any(), any(), any(), any()) } returns true
        every { fileDecryptor.unwrapDek(any(), any()) } returns ByteArray(32)
        every {
            keyEncapsulation.encapsulateForFileShare(any(), any(), any(), any())
        } returns encapsulationResult
        coEvery { apiService.shareFile(any()) } returns Response.success(shareResponse)

        val result = shareRepository.shareFile(testFileId, grantee, SharePermission.READ)

        assertTrue(result is Result.Success)
        val share = (result as Result.Success).data
        assertEquals(testShareId, share.id)
        verify { analyticsManager.trackShare("file", "read") }
    }

    @Test
    fun `shareFile returns validation error when grantee has no public keys`() = runTest {
        val grantee = createTestUser().copy(publicKeys = null)

        val result = shareRepository.shareFile(testFileId, grantee, SharePermission.READ)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.ValidationError)
        assertTrue(error.message.contains("public keys"))
    }

    @Test
    fun `shareFile returns not found when file does not exist`() = runTest {
        val grantee = createTestUser()
        coEvery { apiService.getFile(testFileId) } returns Response.error(
            404,
            "Not Found".toResponseBody()
        )

        val result = shareRepository.shareFile(testFileId, grantee, SharePermission.READ)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.NotFound)
    }

    @Test
    fun `shareFile returns crypto error when uploader public keys missing`() = runTest {
        val grantee = createTestUser()
        val fileDto = createTestFileDto().copy(uploaderPublicKeys = null)

        coEvery { apiService.getFile(testFileId) } returns Response.success(FileResponse(data = fileDto))

        val result = shareRepository.shareFile(testFileId, grantee, SharePermission.READ)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.CryptoError)
        assertTrue(error.message.contains("uploader public keys"))
    }

    @Test
    fun `shareFile returns crypto error when blob hash is missing`() = runTest {
        val grantee = createTestUser()
        val fileDto = createTestFileDto().copy(blobHash = null)

        coEvery { apiService.getFile(testFileId) } returns Response.success(FileResponse(data = fileDto))

        val result = shareRepository.shareFile(testFileId, grantee, SharePermission.READ)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.CryptoError)
        assertTrue(error.message.contains("blob hash"))
    }

    @Test
    fun `shareFile returns crypto error when blob size is missing`() = runTest {
        val grantee = createTestUser()
        val fileDto = createTestFileDto().copy(blobSize = null)

        coEvery { apiService.getFile(testFileId) } returns Response.success(FileResponse(data = fileDto))

        val result = shareRepository.shareFile(testFileId, grantee, SharePermission.READ)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.CryptoError)
        assertTrue(error.message.contains("blob size"))
    }

    @Test
    fun `shareFile returns crypto error when chunk count is missing`() = runTest {
        val grantee = createTestUser()
        val fileDto = createTestFileDto().copy(chunkCount = null)

        coEvery { apiService.getFile(testFileId) } returns Response.success(FileResponse(data = fileDto))

        val result = shareRepository.shareFile(testFileId, grantee, SharePermission.READ)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.CryptoError)
        assertTrue(error.message.contains("chunk count"))
    }

    @Test
    fun `shareFile returns crypto error when signature verification fails`() = runTest {
        val grantee = createTestUser()
        val fileDto = createTestFileDto()

        coEvery { apiService.getFile(testFileId) } returns Response.success(FileResponse(data = fileDto))
        every { fileDecryptor.verifySignature(any(), any(), any(), any(), any(), any(), any()) } returns false

        val result = shareRepository.shareFile(testFileId, grantee, SharePermission.READ)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.CryptoError)
        assertTrue(error.message.contains("signature verification"))
    }

    @Test
    fun `shareFile returns forbidden on 403`() = runTest {
        val grantee = createTestUser()
        val fileDto = createTestFileDto()
        val encapsulationResult = createTestEncapsulationResult()

        coEvery { apiService.getFile(testFileId) } returns Response.success(FileResponse(data = fileDto))
        every { fileDecryptor.verifySignature(any(), any(), any(), any(), any(), any(), any()) } returns true
        every { fileDecryptor.unwrapDek(any(), any()) } returns ByteArray(32)
        every {
            keyEncapsulation.encapsulateForFileShare(any(), any(), any(), any())
        } returns encapsulationResult
        coEvery { apiService.shareFile(any()) } returns Response.error(
            403,
            "Forbidden".toResponseBody()
        )

        val result = shareRepository.shareFile(testFileId, grantee, SharePermission.READ)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Forbidden)
    }

    @Test
    fun `shareFile returns not found on 404 from share API`() = runTest {
        val grantee = createTestUser()
        val fileDto = createTestFileDto()
        val encapsulationResult = createTestEncapsulationResult()

        coEvery { apiService.getFile(testFileId) } returns Response.success(FileResponse(data = fileDto))
        every { fileDecryptor.verifySignature(any(), any(), any(), any(), any(), any(), any()) } returns true
        every { fileDecryptor.unwrapDek(any(), any()) } returns ByteArray(32)
        every {
            keyEncapsulation.encapsulateForFileShare(any(), any(), any(), any())
        } returns encapsulationResult
        coEvery { apiService.shareFile(any()) } returns Response.error(
            404,
            "Not Found".toResponseBody()
        )

        val result = shareRepository.shareFile(testFileId, grantee, SharePermission.READ)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.NotFound)
    }

    @Test
    fun `shareFile returns validation error on 409 conflict`() = runTest {
        val grantee = createTestUser()
        val fileDto = createTestFileDto()
        val encapsulationResult = createTestEncapsulationResult()

        coEvery { apiService.getFile(testFileId) } returns Response.success(FileResponse(data = fileDto))
        every { fileDecryptor.verifySignature(any(), any(), any(), any(), any(), any(), any()) } returns true
        every { fileDecryptor.unwrapDek(any(), any()) } returns ByteArray(32)
        every {
            keyEncapsulation.encapsulateForFileShare(any(), any(), any(), any())
        } returns encapsulationResult
        coEvery { apiService.shareFile(any()) } returns Response.error(
            409,
            "Conflict".toResponseBody()
        )

        val result = shareRepository.shareFile(testFileId, grantee, SharePermission.READ)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.ValidationError)
        assertTrue(error.message.contains("already exists"))
    }

    @Test
    fun `shareFile returns network error on exception`() = runTest {
        val grantee = createTestUser()
        coEvery { apiService.getFile(testFileId) } throws IOException("Network error")

        val result = shareRepository.shareFile(testFileId, grantee, SharePermission.READ)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Network)
    }

    @Test
    fun `shareFile zeroizes DEK after use`() = runTest {
        val grantee = createTestUser()
        val fileDto = createTestFileDto()
        val encapsulationResult = createTestEncapsulationResult()
        val shareResponse = ShareResponse(data = createTestShareDto())
        val dek = ByteArray(32) { 0xFF.toByte() }

        coEvery { apiService.getFile(testFileId) } returns Response.success(FileResponse(data = fileDto))
        every { fileDecryptor.verifySignature(any(), any(), any(), any(), any(), any(), any()) } returns true
        every { fileDecryptor.unwrapDek(any(), any()) } returns dek
        every {
            keyEncapsulation.encapsulateForFileShare(any(), any(), any(), any())
        } returns encapsulationResult
        coEvery { apiService.shareFile(any()) } returns Response.success(shareResponse)

        shareRepository.shareFile(testFileId, grantee, SharePermission.READ)

        // DEK should be zeroized after use
        assertTrue(dek.all { it == 0.toByte() })
    }

    // ==================== shareFile (with recipientId String) Tests ====================

    @Test
    fun `shareFile by recipientId returns not found when user not found`() = runTest {
        coEvery { apiService.getUser(testGranteeId) } returns Response.error(
            404,
            "Not Found".toResponseBody()
        )

        val result = shareRepository.shareFile(testFileId, testGranteeId, "read")

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.NotFound)
        assertTrue(error.message.contains("Recipient"))
    }

    @Test
    fun `shareFile by recipientId returns network error on exception`() = runTest {
        coEvery { apiService.getUser(testGranteeId) } throws IOException("Network error")

        val result = shareRepository.shareFile(testFileId, testGranteeId, "read")

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Network)
    }

    // ==================== shareFolder (with User) Tests ====================

    @Test
    fun `shareFolder returns success when all crypto and API succeed`() = runTest {
        val grantee = createTestUser()
        val kek = ByteArray(32)
        val encapsulationResult = createTestEncapsulationResult()
        val shareResponse = ShareResponse(data = createTestShareDto(resourceType = "folder"))

        every { folderKeyManager.getCachedKek(testFolderId) } returns kek
        every {
            keyEncapsulation.encapsulateForFolderShare(any(), any(), any(), any(), any())
        } returns encapsulationResult
        coEvery { apiService.shareFolder(any()) } returns Response.success(shareResponse)

        val result = shareRepository.shareFolder(
            testFolderId, grantee, SharePermission.WRITE, recursive = true
        )

        assertTrue(result is Result.Success)
        verify { analyticsManager.trackShare("folder", "write") }
    }

    @Test
    fun `shareFolder returns validation error when grantee has no public keys`() = runTest {
        val grantee = createTestUser().copy(publicKeys = null)

        val result = shareRepository.shareFolder(
            testFolderId, grantee, SharePermission.READ, recursive = true
        )

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.ValidationError)
        assertTrue(error.message.contains("public keys"))
    }

    @Test
    fun `shareFolder returns crypto error when KEK not available`() = runTest {
        val grantee = createTestUser()
        every { folderKeyManager.getCachedKek(testFolderId) } returns null

        val result = shareRepository.shareFolder(
            testFolderId, grantee, SharePermission.READ, recursive = true
        )

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.CryptoError)
        assertTrue(error.message.contains("KEK"))
    }

    @Test
    fun `shareFolder returns forbidden on 403`() = runTest {
        val grantee = createTestUser()
        val encapsulationResult = createTestEncapsulationResult()

        every { folderKeyManager.getCachedKek(testFolderId) } returns ByteArray(32)
        every {
            keyEncapsulation.encapsulateForFolderShare(any(), any(), any(), any(), any())
        } returns encapsulationResult
        coEvery { apiService.shareFolder(any()) } returns Response.error(
            403,
            "Forbidden".toResponseBody()
        )

        val result = shareRepository.shareFolder(
            testFolderId, grantee, SharePermission.READ, recursive = true
        )

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Forbidden)
    }

    @Test
    fun `shareFolder returns not found on 404`() = runTest {
        val grantee = createTestUser()
        val encapsulationResult = createTestEncapsulationResult()

        every { folderKeyManager.getCachedKek(testFolderId) } returns ByteArray(32)
        every {
            keyEncapsulation.encapsulateForFolderShare(any(), any(), any(), any(), any())
        } returns encapsulationResult
        coEvery { apiService.shareFolder(any()) } returns Response.error(
            404,
            "Not Found".toResponseBody()
        )

        val result = shareRepository.shareFolder(
            testFolderId, grantee, SharePermission.READ, recursive = true
        )

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.NotFound)
    }

    @Test
    fun `shareFolder returns validation error on 409 conflict`() = runTest {
        val grantee = createTestUser()
        val encapsulationResult = createTestEncapsulationResult()

        every { folderKeyManager.getCachedKek(testFolderId) } returns ByteArray(32)
        every {
            keyEncapsulation.encapsulateForFolderShare(any(), any(), any(), any(), any())
        } returns encapsulationResult
        coEvery { apiService.shareFolder(any()) } returns Response.error(
            409,
            "Conflict".toResponseBody()
        )

        val result = shareRepository.shareFolder(
            testFolderId, grantee, SharePermission.READ, recursive = true
        )

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.ValidationError)
        assertTrue(error.message.contains("already exists"))
    }

    @Test
    fun `shareFolder returns network error on exception`() = runTest {
        val grantee = createTestUser()
        every { folderKeyManager.getCachedKek(testFolderId) } returns ByteArray(32)
        every {
            keyEncapsulation.encapsulateForFolderShare(any(), any(), any(), any(), any())
        } throws IOException("Network error")

        val result = shareRepository.shareFolder(
            testFolderId, grantee, SharePermission.READ, recursive = true
        )

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Network)
    }

    // ==================== shareFolder (with recipientId String) Tests ====================

    @Test
    fun `shareFolder by recipientId returns not found when user not found`() = runTest {
        coEvery { apiService.getUser(testGranteeId) } returns Response.error(
            404,
            "Not Found".toResponseBody()
        )

        val result = shareRepository.shareFolder(testFolderId, testGranteeId, "read")

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.NotFound)
        assertTrue(error.message.contains("Recipient"))
    }

    @Test
    fun `shareFolder by recipientId returns network error on exception`() = runTest {
        coEvery { apiService.getUser(testGranteeId) } throws IOException("Network error")

        val result = shareRepository.shareFolder(testFolderId, testGranteeId, "read")

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Network)
    }

    // ==================== updatePermission (SharePermission) Tests ====================

    @Test
    fun `updatePermission returns share on success`() = runTest {
        val shareResponse = ShareResponse(data = createTestShareDto(permission = "write"))
        every { keyEncapsulation.signPermissionUpdate(testShareId, "write") } returns "sig-base64"
        coEvery { apiService.updateSharePermission(testShareId, any()) } returns Response.success(shareResponse)

        val result = shareRepository.updatePermission(testShareId, SharePermission.WRITE)

        assertTrue(result is Result.Success)
        val share = (result as Result.Success).data
        assertEquals(SharePermission.WRITE, share.permission)
    }

    @Test
    fun `updatePermission returns forbidden on 403`() = runTest {
        every { keyEncapsulation.signPermissionUpdate(testShareId, "write") } returns "sig-base64"
        coEvery { apiService.updateSharePermission(testShareId, any()) } returns Response.error(
            403,
            "Forbidden".toResponseBody()
        )

        val result = shareRepository.updatePermission(testShareId, SharePermission.WRITE)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Forbidden)
    }

    @Test
    fun `updatePermission returns not found on 404`() = runTest {
        every { keyEncapsulation.signPermissionUpdate(testShareId, "read") } returns "sig-base64"
        coEvery { apiService.updateSharePermission(testShareId, any()) } returns Response.error(
            404,
            "Not Found".toResponseBody()
        )

        val result = shareRepository.updatePermission(testShareId, SharePermission.READ)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.NotFound)
    }

    @Test
    fun `updatePermission returns unknown error on other HTTP codes`() = runTest {
        every { keyEncapsulation.signPermissionUpdate(testShareId, "admin") } returns "sig-base64"
        coEvery { apiService.updateSharePermission(testShareId, any()) } returns Response.error(
            500,
            "Server Error".toResponseBody()
        )

        val result = shareRepository.updatePermission(testShareId, SharePermission.ADMIN)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Unknown)
    }

    @Test
    fun `updatePermission returns network error on exception`() = runTest {
        every { keyEncapsulation.signPermissionUpdate(testShareId, "read") } throws IOException("Network error")

        val result = shareRepository.updatePermission(testShareId, SharePermission.READ)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Network)
    }

    // ==================== updatePermission (String) Tests ====================

    @Test
    fun `updatePermission with string delegates to enum overload`() = runTest {
        val shareResponse = ShareResponse(data = createTestShareDto(permission = "write"))
        every { keyEncapsulation.signPermissionUpdate(testShareId, "write") } returns "sig-base64"
        coEvery { apiService.updateSharePermission(testShareId, any()) } returns Response.success(shareResponse)

        val result = shareRepository.updatePermission(testShareId, "write")

        assertTrue(result is Result.Success)
    }

    // ==================== setExpiry Tests ====================

    @Test
    fun `setExpiry returns share on success`() = runTest {
        val expiry = Instant.parse("2025-12-31T23:59:59Z")
        val shareDto = createTestShareDto().copy(expiresAt = "2025-12-31T23:59:59Z")
        val shareResponse = ShareResponse(data = shareDto)
        coEvery { apiService.setShareExpiry(testShareId, any()) } returns Response.success(shareResponse)

        val result = shareRepository.setExpiry(testShareId, expiry)

        assertTrue(result is Result.Success)
        val share = (result as Result.Success).data
        assertNotNull(share.expiresAt)
    }

    @Test
    fun `setExpiry with null removes expiry`() = runTest {
        val shareResponse = ShareResponse(data = createTestShareDto())
        coEvery { apiService.setShareExpiry(testShareId, any()) } returns Response.success(shareResponse)

        val result = shareRepository.setExpiry(testShareId, null)

        assertTrue(result is Result.Success)
        coVerify {
            apiService.setShareExpiry(testShareId, match { it.expiresAt == null })
        }
    }

    @Test
    fun `setExpiry returns forbidden on 403`() = runTest {
        coEvery { apiService.setShareExpiry(testShareId, any()) } returns Response.error(
            403,
            "Forbidden".toResponseBody()
        )

        val result = shareRepository.setExpiry(testShareId, Instant.now())

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Forbidden)
    }

    @Test
    fun `setExpiry returns not found on 404`() = runTest {
        coEvery { apiService.setShareExpiry(testShareId, any()) } returns Response.error(
            404,
            "Not Found".toResponseBody()
        )

        val result = shareRepository.setExpiry(testShareId, Instant.now())

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.NotFound)
    }

    @Test
    fun `setExpiry returns unknown error on other HTTP codes`() = runTest {
        coEvery { apiService.setShareExpiry(testShareId, any()) } returns Response.error(
            500,
            "Server Error".toResponseBody()
        )

        val result = shareRepository.setExpiry(testShareId, Instant.now())

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Unknown)
    }

    @Test
    fun `setExpiry returns network error on exception`() = runTest {
        coEvery { apiService.setShareExpiry(testShareId, any()) } throws IOException("Network error")

        val result = shareRepository.setExpiry(testShareId, Instant.now())

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Network)
    }

    // ==================== revokeShare Tests ====================

    @Test
    fun `revokeShare returns success and deletes from local DB`() = runTest {
        coEvery { apiService.revokeShare(testShareId) } returns Response.success(Unit)

        val result = shareRepository.revokeShare(testShareId)

        assertTrue(result is Result.Success)
        coVerify { shareDao.deleteById(testShareId) }
    }

    @Test
    fun `revokeShare returns error on API failure`() = runTest {
        coEvery { apiService.revokeShare(testShareId) } returns Response.error(
            500,
            "Server Error".toResponseBody()
        )

        val result = shareRepository.revokeShare(testShareId)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Unknown)
        coVerify(exactly = 0) { shareDao.deleteById(any()) }
    }

    @Test
    fun `revokeShare returns network error on exception`() = runTest {
        coEvery { apiService.revokeShare(testShareId) } throws IOException("Network error")

        val result = shareRepository.revokeShare(testShareId)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Network)
    }

    // ==================== searchUsers Tests ====================

    @Test
    fun `searchUsers returns users on success`() = runTest {
        val usersResponse = UsersResponse(data = listOf(createTestUserDto()))
        coEvery { apiService.searchUsers("test") } returns Response.success(usersResponse)

        val result = shareRepository.searchUsers("test")

        assertTrue(result is Result.Success)
        val users = (result as Result.Success).data
        assertEquals(1, users.size)
        assertEquals(testGranteeId, users[0].id)
    }

    @Test
    fun `searchUsers returns empty list on success with no matches`() = runTest {
        val usersResponse = UsersResponse(data = emptyList())
        coEvery { apiService.searchUsers("nonexistent") } returns Response.success(usersResponse)

        val result = shareRepository.searchUsers("nonexistent")

        assertTrue(result is Result.Success)
        val users = (result as Result.Success).data
        assertTrue(users.isEmpty())
    }

    @Test
    fun `searchUsers returns error on API failure`() = runTest {
        coEvery { apiService.searchUsers("test") } returns Response.error(
            500,
            "Server Error".toResponseBody()
        )

        val result = shareRepository.searchUsers("test")

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Unknown)
    }

    @Test
    fun `searchUsers returns network error on exception`() = runTest {
        coEvery { apiService.searchUsers("test") } throws IOException("Network error")

        val result = shareRepository.searchUsers("test")

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Network)
    }

    // ==================== syncShares Tests ====================

    @Test
    fun `syncShares inserts received and created shares into local DB`() = runTest {
        val receivedSharesResponse = SharesResponse(data = listOf(createTestShareDto()))
        val createdSharesResponse = SharesResponse(data = listOf(createTestShareDto(id = "share-created")))

        coEvery { apiService.getReceivedShares() } returns Response.success(receivedSharesResponse)
        coEvery { apiService.getCreatedShares() } returns Response.success(createdSharesResponse)

        val result = shareRepository.syncShares()

        assertTrue(result is Result.Success)
        coVerify(exactly = 2) { shareDao.insertAll(any()) }
    }

    @Test
    fun `syncShares succeeds even if one API call fails`() = runTest {
        coEvery { apiService.getReceivedShares() } returns Response.error(
            500,
            "Error".toResponseBody()
        )
        val createdSharesResponse = SharesResponse(data = listOf(createTestShareDto()))
        coEvery { apiService.getCreatedShares() } returns Response.success(createdSharesResponse)

        val result = shareRepository.syncShares()

        assertTrue(result is Result.Success)
        coVerify(exactly = 1) { shareDao.insertAll(any()) }
    }

    @Test
    fun `syncShares returns network error on exception`() = runTest {
        coEvery { apiService.getReceivedShares() } throws IOException("Network error")

        val result = shareRepository.syncShares()

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Network)
    }

    // ==================== Helper Functions ====================

    private fun createTestShareDto(
        id: String = testShareId,
        resourceType: String = "file",
        permission: String = "read"
    ) = ShareDto(
        id = id,
        grantorId = testGrantorId,
        granteeId = testGranteeId,
        resourceType = resourceType,
        resourceId = testFileId,
        permission = permission,
        wrappedKey = "base64wrappedkey",
        kemCiphertext = "base64kemciphertext",
        mlKemCiphertext = "base64mlkemciphertext",
        signature = "base64signature",
        recursive = null,
        expiresAt = null,
        revokedAt = null,
        grantor = null,
        grantee = null,
        grantorPublicKeys = null,
        insertedAt = testTimestamp,
        updatedAt = testTimestamp
    )

    private fun createTestUser() = User(
        id = testGranteeId,
        email = "grantee@example.com",
        tenantId = "test-tenant",
        publicKeys = PublicKeys(
            kem = ByteArray(32),
            sign = ByteArray(32),
            mlKem = ByteArray(32),
            mlDsa = ByteArray(32)
        )
    )

    private fun createTestUserDto() = UserDto(
        id = testGranteeId,
        email = "grantee@example.com",
        tenantId = "test-tenant",
        role = "user",
        publicKeys = PublicKeysDto(
            kem = "base64encodedkey",
            sign = "base64encodedkey",
            mlKem = "base64encodedkey",
            mlDsa = "base64encodedkey"
        ),
        encryptedMasterKey = "encrypted",
        encryptedPrivateKeys = "encrypted",
        keyDerivationSalt = "salt",
        storageQuota = 1073741824,
        storageUsed = 0,
        insertedAt = testTimestamp,
        updatedAt = testTimestamp
    )

    private fun createTestFileDto() = FileDto(
        id = testFileId,
        folderId = testFolderId,
        ownerId = testGrantorId,
        tenantId = "test-tenant",
        storagePath = "/path/to/file",
        blobSize = 1024,
        blobHash = "sha256hash",
        chunkCount = 1,
        status = "active",
        encryptedMetadata = "base64metadata",
        wrappedDek = "base64wrappeddek",
        kemCiphertext = "base64kemciphertext",
        mlKemCiphertext = "base64mlkemciphertext",
        signature = "base64signature",
        insertedAt = testTimestamp,
        updatedAt = testTimestamp,
        uploaderPublicKeys = PublicKeysDto(
            kem = "base64encodedkey",
            sign = "base64encodedkey",
            mlKem = "base64encodedkey",
            mlDsa = "base64encodedkey"
        )
    )

    private fun createTestEncapsulationResult() = KeyEncapsulation.EncapsulationResult(
        wrappedKey = "base64wrappedkey",
        kemCiphertext = "base64kemciphertext",
        mlKemCiphertext = "base64mlkemciphertext",
        signature = "base64signature"
    )
}
