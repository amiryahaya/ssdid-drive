package my.ssdid.drive.data.repository

import android.util.Base64
import my.ssdid.drive.crypto.KeyManager
import my.ssdid.drive.data.local.SecureStorage
import my.ssdid.drive.data.remote.ApiService
import my.ssdid.drive.data.remote.dto.PublicKeysDto
import my.ssdid.drive.data.remote.dto.RecoveryConfigDto
import my.ssdid.drive.data.remote.dto.RecoveryConfigResponse
import my.ssdid.drive.data.remote.dto.RecoveryProgressDto
import my.ssdid.drive.data.remote.dto.RecoveryRequestDetailDto
import my.ssdid.drive.data.remote.dto.RecoveryRequestDetailResponse
import my.ssdid.drive.data.remote.dto.RecoveryRequestDto
import my.ssdid.drive.data.remote.dto.RecoveryRequestsResponse
import my.ssdid.drive.data.remote.dto.RecoveryShareDto
import my.ssdid.drive.data.remote.dto.RecoveryShareResponse
import my.ssdid.drive.data.remote.dto.RecoverySharesResponse
import my.ssdid.drive.data.remote.dto.UserDto
import my.ssdid.drive.domain.model.RecoveryConfigStatus
import my.ssdid.drive.domain.model.RecoveryRequestStatus
import my.ssdid.drive.domain.model.RecoveryShareStatus
import my.ssdid.drive.util.AppException
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

/**
 * Unit tests for RecoveryRepositoryImpl.
 *
 * Tests cover:
 * - getRecoveryConfig
 * - getCreatedShares / getTrusteeShares
 * - acceptShare / rejectShare / revokeShare
 * - getMyRecoveryRequests / getPendingApprovalRequests
 * - cancelRecoveryRequest
 * - disableRecovery
 * - Wallet-delegated method errors
 * - Error handling (network, HTTP codes)
 */
@OptIn(ExperimentalCoroutinesApi::class)
class RecoveryRepositoryImplTest {

    private lateinit var apiService: ApiService
    private lateinit var secureStorage: SecureStorage
    private lateinit var keyManager: KeyManager
    private lateinit var repository: RecoveryRepositoryImpl

    @Before
    fun setup() {
        mockkStatic(Base64::class)
        every { Base64.decode(any<String>(), any()) } returns ByteArray(32)
        every { Base64.encodeToString(any(), any()) } returns "base64encoded"

        apiService = mockk()
        secureStorage = mockk(relaxed = true)
        keyManager = mockk(relaxed = true)

        repository = RecoveryRepositoryImpl(
            apiService = apiService,
            secureStorage = secureStorage,
            keyManager = keyManager
        )
    }

    @After
    fun tearDown() {
        unmockkStatic(Base64::class)
        unmockkAll()
    }

    // ==================== getRecoveryConfig Tests ====================

    @Test
    fun `getRecoveryConfig returns config on success`() = runTest {
        val configDto = createTestConfigDto()
        coEvery { apiService.getRecoveryConfig() } returns Response.success(
            RecoveryConfigResponse(data = configDto)
        )

        val result = repository.getRecoveryConfig()

        assertTrue(result is Result.Success)
        val config = (result as Result.Success).data
        assertNotNull(config)
        assertEquals("config-1", config!!.id)
        assertEquals("user-1", config.userId)
        assertEquals(2, config.threshold)
        assertEquals(3, config.totalShares)
        assertEquals(RecoveryConfigStatus.ACTIVE, config.status)
    }

    @Test
    fun `getRecoveryConfig returns null on 404`() = runTest {
        coEvery { apiService.getRecoveryConfig() } returns Response.error(
            404, "Not found".toResponseBody()
        )

        val result = repository.getRecoveryConfig()

        assertTrue(result is Result.Success)
        assertNull((result as Result.Success).data)
    }

    @Test
    fun `getRecoveryConfig returns error on other HTTP errors`() = runTest {
        coEvery { apiService.getRecoveryConfig() } returns Response.error(
            500, "Server error".toResponseBody()
        )

        val result = repository.getRecoveryConfig()

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Unknown)
    }

    @Test
    fun `getRecoveryConfig returns network error on exception`() = runTest {
        coEvery { apiService.getRecoveryConfig() } throws java.io.IOException("No connection")

        val result = repository.getRecoveryConfig()

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Network)
        assertTrue(error.message.contains("Failed to get recovery config"))
    }

    // ==================== disableRecovery Tests ====================

    @Test
    fun `disableRecovery returns success on 200`() = runTest {
        coEvery { apiService.disableRecovery() } returns Response.success(Unit)

        val result = repository.disableRecovery()

        assertTrue(result is Result.Success)
    }

    @Test
    fun `disableRecovery returns NotFound on 404`() = runTest {
        coEvery { apiService.disableRecovery() } returns Response.error(
            404, "Not found".toResponseBody()
        )

        val result = repository.disableRecovery()

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.NotFound)
    }

    @Test
    fun `disableRecovery returns error on other HTTP errors`() = runTest {
        coEvery { apiService.disableRecovery() } returns Response.error(
            500, "Server error".toResponseBody()
        )

        val result = repository.disableRecovery()

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Unknown)
    }

    @Test
    fun `disableRecovery returns network error on exception`() = runTest {
        coEvery { apiService.disableRecovery() } throws java.io.IOException("Timeout")

        val result = repository.disableRecovery()

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Network)
    }

    // ==================== getCreatedShares Tests ====================

    @Test
    fun `getCreatedShares returns mapped shares on success`() = runTest {
        val shares = listOf(
            createTestShareDto(id = "s1", shareIndex = 1),
            createTestShareDto(id = "s2", shareIndex = 2)
        )
        coEvery { apiService.getCreatedRecoveryShares() } returns Response.success(
            RecoverySharesResponse(data = shares)
        )

        val result = repository.getCreatedShares()

        assertTrue(result is Result.Success)
        val resultShares = (result as Result.Success).data
        assertEquals(2, resultShares.size)
        assertEquals("s1", resultShares[0].id)
        assertEquals(1, resultShares[0].shareIndex)
        assertEquals("s2", resultShares[1].id)
        assertEquals(2, resultShares[1].shareIndex)
    }

    @Test
    fun `getCreatedShares returns error on HTTP failure`() = runTest {
        coEvery { apiService.getCreatedRecoveryShares() } returns Response.error(
            500, "Server error".toResponseBody()
        )

        val result = repository.getCreatedShares()

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Unknown)
    }

    @Test
    fun `getCreatedShares returns network error on exception`() = runTest {
        coEvery { apiService.getCreatedRecoveryShares() } throws java.io.IOException("Network")

        val result = repository.getCreatedShares()

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Network)
    }

    // ==================== getTrusteeShares Tests ====================

    @Test
    fun `getTrusteeShares returns mapped shares on success`() = runTest {
        val shares = listOf(createTestShareDto(id = "ts1", status = "accepted"))
        coEvery { apiService.getTrusteeShares() } returns Response.success(
            RecoverySharesResponse(data = shares)
        )

        val result = repository.getTrusteeShares()

        assertTrue(result is Result.Success)
        val resultShares = (result as Result.Success).data
        assertEquals(1, resultShares.size)
        assertEquals("ts1", resultShares[0].id)
        assertEquals(RecoveryShareStatus.ACCEPTED, resultShares[0].status)
    }

    @Test
    fun `getTrusteeShares returns error on HTTP failure`() = runTest {
        coEvery { apiService.getTrusteeShares() } returns Response.error(
            500, "Server error".toResponseBody()
        )

        val result = repository.getTrusteeShares()

        assertTrue(result is Result.Error)
    }

    @Test
    fun `getTrusteeShares returns network error on exception`() = runTest {
        coEvery { apiService.getTrusteeShares() } throws java.io.IOException("Timeout")

        val result = repository.getTrusteeShares()

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Network)
    }

    // ==================== acceptShare Tests ====================

    @Test
    fun `acceptShare returns mapped share on success`() = runTest {
        val shareDto = createTestShareDto(id = "s1", status = "accepted")
        coEvery { apiService.acceptRecoveryShare("s1") } returns Response.success(
            RecoveryShareResponse(data = shareDto)
        )

        val result = repository.acceptShare("s1")

        assertTrue(result is Result.Success)
        val share = (result as Result.Success).data
        assertEquals("s1", share.id)
        assertEquals(RecoveryShareStatus.ACCEPTED, share.status)
    }

    @Test
    fun `acceptShare returns NotFound on 404`() = runTest {
        coEvery { apiService.acceptRecoveryShare("s1") } returns Response.error(
            404, "Not found".toResponseBody()
        )

        val result = repository.acceptShare("s1")

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.NotFound)
        assertTrue(error.message.contains("Share not found"))
    }

    @Test
    fun `acceptShare returns error on other HTTP errors`() = runTest {
        coEvery { apiService.acceptRecoveryShare("s1") } returns Response.error(
            500, "Server error".toResponseBody()
        )

        val result = repository.acceptShare("s1")

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Unknown)
    }

    @Test
    fun `acceptShare returns network error on exception`() = runTest {
        coEvery { apiService.acceptRecoveryShare("s1") } throws java.io.IOException("Network")

        val result = repository.acceptShare("s1")

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Network)
    }

    // ==================== rejectShare Tests ====================

    @Test
    fun `rejectShare returns success on 200`() = runTest {
        coEvery { apiService.rejectRecoveryShare("s1") } returns Response.success(Unit)

        val result = repository.rejectShare("s1")

        assertTrue(result is Result.Success)
    }

    @Test
    fun `rejectShare returns NotFound on 404`() = runTest {
        coEvery { apiService.rejectRecoveryShare("s1") } returns Response.error(
            404, "Not found".toResponseBody()
        )

        val result = repository.rejectShare("s1")

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.NotFound)
    }

    @Test
    fun `rejectShare returns Unauthorized on 403`() = runTest {
        coEvery { apiService.rejectRecoveryShare("s1") } returns Response.error(
            403, "Forbidden".toResponseBody()
        )

        val result = repository.rejectShare("s1")

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Unauthorized)
        assertTrue(error.message.contains("Not authorized"))
    }

    @Test
    fun `rejectShare returns error on other HTTP errors`() = runTest {
        coEvery { apiService.rejectRecoveryShare("s1") } returns Response.error(
            500, "Server error".toResponseBody()
        )

        val result = repository.rejectShare("s1")

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Unknown)
    }

    @Test
    fun `rejectShare returns network error on exception`() = runTest {
        coEvery { apiService.rejectRecoveryShare("s1") } throws java.io.IOException("Network")

        val result = repository.rejectShare("s1")

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Network)
    }

    // ==================== revokeShare Tests ====================

    @Test
    fun `revokeShare returns success on 200`() = runTest {
        coEvery { apiService.revokeRecoveryShare("s1") } returns Response.success(Unit)

        val result = repository.revokeShare("s1")

        assertTrue(result is Result.Success)
    }

    @Test
    fun `revokeShare returns NotFound on 404`() = runTest {
        coEvery { apiService.revokeRecoveryShare("s1") } returns Response.error(
            404, "Not found".toResponseBody()
        )

        val result = repository.revokeShare("s1")

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.NotFound)
    }

    @Test
    fun `revokeShare returns Unauthorized on 403`() = runTest {
        coEvery { apiService.revokeRecoveryShare("s1") } returns Response.error(
            403, "Forbidden".toResponseBody()
        )

        val result = repository.revokeShare("s1")

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Unauthorized)
    }

    @Test
    fun `revokeShare returns network error on exception`() = runTest {
        coEvery { apiService.revokeRecoveryShare("s1") } throws java.io.IOException("Network")

        val result = repository.revokeShare("s1")

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Network)
    }

    // ==================== getMyRecoveryRequests Tests ====================

    @Test
    fun `getMyRecoveryRequests returns mapped requests on success`() = runTest {
        val requests = listOf(
            createTestRequestDto(id = "req1", status = "pending"),
            createTestRequestDto(id = "req2", status = "approved")
        )
        coEvery { apiService.getRecoveryRequests() } returns Response.success(
            RecoveryRequestsResponse(data = requests)
        )

        val result = repository.getMyRecoveryRequests()

        assertTrue(result is Result.Success)
        val resultRequests = (result as Result.Success).data
        assertEquals(2, resultRequests.size)
        assertEquals("req1", resultRequests[0].id)
        assertEquals(RecoveryRequestStatus.PENDING, resultRequests[0].status)
        assertEquals("req2", resultRequests[1].id)
        assertEquals(RecoveryRequestStatus.APPROVED, resultRequests[1].status)
    }

    @Test
    fun `getMyRecoveryRequests returns error on HTTP failure`() = runTest {
        coEvery { apiService.getRecoveryRequests() } returns Response.error(
            500, "Server error".toResponseBody()
        )

        val result = repository.getMyRecoveryRequests()

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Unknown)
    }

    @Test
    fun `getMyRecoveryRequests returns network error on exception`() = runTest {
        coEvery { apiService.getRecoveryRequests() } throws java.io.IOException("Network")

        val result = repository.getMyRecoveryRequests()

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Network)
    }

    // ==================== getPendingApprovalRequests Tests ====================

    @Test
    fun `getPendingApprovalRequests returns mapped requests on success`() = runTest {
        val requests = listOf(createTestRequestDto(id = "preq1", status = "pending"))
        coEvery { apiService.getPendingRecoveryRequests() } returns Response.success(
            RecoveryRequestsResponse(data = requests)
        )

        val result = repository.getPendingApprovalRequests()

        assertTrue(result is Result.Success)
        val resultRequests = (result as Result.Success).data
        assertEquals(1, resultRequests.size)
        assertEquals("preq1", resultRequests[0].id)
        assertEquals(RecoveryRequestStatus.PENDING, resultRequests[0].status)
    }

    @Test
    fun `getPendingApprovalRequests returns error on HTTP failure`() = runTest {
        coEvery { apiService.getPendingRecoveryRequests() } returns Response.error(
            500, "Server error".toResponseBody()
        )

        val result = repository.getPendingApprovalRequests()

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Unknown)
    }

    @Test
    fun `getPendingApprovalRequests returns network error on exception`() = runTest {
        coEvery { apiService.getPendingRecoveryRequests() } throws java.io.IOException("Net")

        val result = repository.getPendingApprovalRequests()

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Network)
    }

    // ==================== getRecoveryRequest Tests ====================

    @Test
    fun `getRecoveryRequest returns request with progress on success`() = runTest {
        val requestDto = createTestRequestDto(id = "req1", status = "pending")
        val progressDto = RecoveryProgressDto(threshold = 3, approvals = 1, remaining = 2)
        val detailDto = RecoveryRequestDetailDto(request = requestDto, progress = progressDto)
        coEvery { apiService.getRecoveryRequest("req1") } returns Response.success(
            RecoveryRequestDetailResponse(data = detailDto)
        )

        val result = repository.getRecoveryRequest("req1")

        assertTrue(result is Result.Success)
        val request = (result as Result.Success).data
        assertEquals("req1", request.id)
        assertNotNull(request.progress)
        assertEquals(3, request.progress!!.threshold)
        assertEquals(1, request.progress!!.approvals)
        assertEquals(2, request.progress!!.remaining)
    }

    @Test
    fun `getRecoveryRequest returns NotFound on 404`() = runTest {
        coEvery { apiService.getRecoveryRequest("req1") } returns Response.error(
            404, "Not found".toResponseBody()
        )

        val result = repository.getRecoveryRequest("req1")

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.NotFound)
    }

    @Test
    fun `getRecoveryRequest returns error on other HTTP errors`() = runTest {
        coEvery { apiService.getRecoveryRequest("req1") } returns Response.error(
            500, "Server error".toResponseBody()
        )

        val result = repository.getRecoveryRequest("req1")

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Unknown)
    }

    @Test
    fun `getRecoveryRequest returns network error on exception`() = runTest {
        coEvery { apiService.getRecoveryRequest("req1") } throws java.io.IOException("Net")

        val result = repository.getRecoveryRequest("req1")

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Network)
    }

    // ==================== cancelRecoveryRequest Tests ====================

    @Test
    fun `cancelRecoveryRequest returns success on 200`() = runTest {
        coEvery { apiService.cancelRecoveryRequest("req1") } returns Response.success(Unit)

        val result = repository.cancelRecoveryRequest("req1")

        assertTrue(result is Result.Success)
    }

    @Test
    fun `cancelRecoveryRequest returns NotFound on 404`() = runTest {
        coEvery { apiService.cancelRecoveryRequest("req1") } returns Response.error(
            404, "Not found".toResponseBody()
        )

        val result = repository.cancelRecoveryRequest("req1")

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.NotFound)
    }

    @Test
    fun `cancelRecoveryRequest returns Unauthorized on 403`() = runTest {
        coEvery { apiService.cancelRecoveryRequest("req1") } returns Response.error(
            403, "Forbidden".toResponseBody()
        )

        val result = repository.cancelRecoveryRequest("req1")

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Unauthorized)
    }

    @Test
    fun `cancelRecoveryRequest returns ValidationError on 409`() = runTest {
        coEvery { apiService.cancelRecoveryRequest("req1") } returns Response.error(
            409, "Conflict".toResponseBody()
        )

        val result = repository.cancelRecoveryRequest("req1")

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.ValidationError)
        assertTrue(error.message.contains("cannot be cancelled"))
    }

    @Test
    fun `cancelRecoveryRequest returns error on other HTTP errors`() = runTest {
        coEvery { apiService.cancelRecoveryRequest("req1") } returns Response.error(
            500, "Server error".toResponseBody()
        )

        val result = repository.cancelRecoveryRequest("req1")

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Unknown)
    }

    @Test
    fun `cancelRecoveryRequest returns network error on exception`() = runTest {
        coEvery { apiService.cancelRecoveryRequest("req1") } throws java.io.IOException("Net")

        val result = repository.cancelRecoveryRequest("req1")

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Network)
    }

    // ==================== Wallet-Delegated Methods Tests ====================

    @Test
    fun `setupRecovery returns error - delegated to wallet`() = runTest {
        val result = repository.setupRecovery(threshold = 2, totalShares = 3)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error.message.contains("SSDID Wallet"))
    }

    @Test
    fun `createShare returns error - delegated to wallet`() = runTest {
        val user = my.ssdid.drive.domain.model.User(
            id = "u1",
            email = "test@test.com"
        )

        val result = repository.createShare(user, 1)

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error.message.contains("SSDID Wallet"))
    }

    @Test
    fun `initiateRecovery returns error - delegated to wallet`() = runTest {
        val result = repository.initiateRecovery("newpassword", "Lost device")

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error.message.contains("SSDID Wallet"))
    }

    @Test
    fun `approveRecoveryRequest returns error - delegated to wallet`() = runTest {
        val result = repository.approveRecoveryRequest("req1", "share1")

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error.message.contains("SSDID Wallet"))
    }

    @Test
    fun `completeRecovery returns error - delegated to wallet`() = runTest {
        val result = repository.completeRecovery("req1", "password")

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error.message.contains("SSDID Wallet"))
    }

    // ==================== DTO-to-Domain Mapping Tests ====================

    @Test
    fun `RecoveryShareDto toDomain maps all fields correctly`() = runTest {
        val shareDto = createTestShareDto(
            id = "share-map",
            configId = "config-map",
            grantorId = "grantor-map",
            trusteeId = "trustee-map",
            shareIndex = 3,
            status = "revoked"
        )
        coEvery { apiService.getCreatedRecoveryShares() } returns Response.success(
            RecoverySharesResponse(data = listOf(shareDto))
        )

        val result = repository.getCreatedShares()

        assertTrue(result is Result.Success)
        val share = (result as Result.Success).data[0]
        assertEquals("share-map", share.id)
        assertEquals("config-map", share.configId)
        assertEquals("grantor-map", share.grantorId)
        assertEquals("trustee-map", share.trusteeId)
        assertEquals(3, share.shareIndex)
        assertEquals(RecoveryShareStatus.REVOKED, share.status)
    }

    @Test
    fun `RecoveryRequestDto toDomain maps fields including reason and user`() = runTest {
        val requestDto = createTestRequestDto(
            id = "req-map",
            userId = "user-map",
            status = "completed",
            reason = "Lost my phone"
        )
        coEvery { apiService.getRecoveryRequests() } returns Response.success(
            RecoveryRequestsResponse(data = listOf(requestDto))
        )

        val result = repository.getMyRecoveryRequests()

        assertTrue(result is Result.Success)
        val request = (result as Result.Success).data[0]
        assertEquals("req-map", request.id)
        assertEquals("user-map", request.userId)
        assertEquals(RecoveryRequestStatus.COMPLETED, request.status)
        assertEquals("Lost my phone", request.reason)
        assertNull(request.progress) // progress is only set via getRecoveryRequest detail
    }

    @Test
    fun `RecoveryShareDto toDomain includes embedded user when present`() = runTest {
        val grantorDto = UserDto(
            id = "grantor-1",
            email = "grantor@test.com",
            tenantId = "t1",
            role = "user",
            publicKeys = PublicKeysDto(
                kem = "kemkey",
                sign = "signkey",
                mlKem = null,
                mlDsa = null
            ),
            storageQuota = 1000,
            storageUsed = 100
        )
        val shareDto = createTestShareDto(grantor = grantorDto)
        coEvery { apiService.getCreatedRecoveryShares() } returns Response.success(
            RecoverySharesResponse(data = listOf(shareDto))
        )

        val result = repository.getCreatedShares()

        assertTrue(result is Result.Success)
        val share = (result as Result.Success).data[0]
        assertNotNull(share.grantor)
        assertEquals("grantor-1", share.grantor!!.id)
        assertEquals("grantor@test.com", share.grantor!!.email)
    }

    // ==================== Helper Functions ====================

    private fun createTestConfigDto(
        id: String = "config-1",
        userId: String = "user-1",
        threshold: Int = 2,
        totalShares: Int = 3,
        status: String = "active"
    ) = RecoveryConfigDto(
        id = id,
        userId = userId,
        threshold = threshold,
        totalShares = totalShares,
        status = status,
        insertedAt = "2024-01-01T00:00:00Z",
        updatedAt = "2024-01-01T00:00:00Z"
    )

    private fun createTestShareDto(
        id: String = "share-1",
        configId: String = "config-1",
        grantorId: String = "grantor-1",
        trusteeId: String = "trustee-1",
        shareIndex: Int = 1,
        status: String = "pending",
        grantor: UserDto? = null,
        trustee: UserDto? = null
    ) = RecoveryShareDto(
        id = id,
        configId = configId,
        grantorId = grantorId,
        trusteeId = trusteeId,
        shareIndex = shareIndex,
        encryptedShare = "encshare",
        kemCiphertext = "kemct",
        mlKemCiphertext = null,
        signature = "sig",
        status = status,
        grantor = grantor,
        trustee = trustee,
        grantorPublicKeys = null,
        insertedAt = "2024-01-01T00:00:00Z",
        updatedAt = "2024-01-01T00:00:00Z"
    )

    private fun createTestRequestDto(
        id: String = "req-1",
        userId: String = "user-1",
        status: String = "pending",
        reason: String? = null
    ) = RecoveryRequestDto(
        id = id,
        userId = userId,
        status = status,
        newPublicKey = "newpubkey",
        reason = reason,
        user = null,
        insertedAt = "2024-01-01T00:00:00Z",
        updatedAt = "2024-01-01T00:00:00Z"
    )
}
