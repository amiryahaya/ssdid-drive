package my.ssdid.drive.data.repository

import my.ssdid.drive.data.remote.ApiService
import my.ssdid.drive.data.remote.dto.ApproveRequestResponse
import my.ssdid.drive.data.remote.dto.CompleteRecoveryRequest
import my.ssdid.drive.data.remote.dto.CompleteRecoveryResponse
import my.ssdid.drive.data.remote.dto.CreateRecoveryRequestBody
import my.ssdid.drive.data.remote.dto.ListTrusteesResponse
import my.ssdid.drive.data.remote.dto.MyRecoveryRequestData
import my.ssdid.drive.data.remote.dto.MyRecoveryRequestResponse
import my.ssdid.drive.data.remote.dto.PendingRecoveryRequestDto
import my.ssdid.drive.data.remote.dto.PendingRequestsResponse
import my.ssdid.drive.data.remote.dto.RecoveryRequestResponse
import my.ssdid.drive.data.remote.dto.RecoveryStatusResponse
import my.ssdid.drive.data.remote.dto.RejectRequestResponse
import my.ssdid.drive.data.remote.dto.ReleasedShareDto
import my.ssdid.drive.data.remote.dto.ReleasedSharesResponse
import my.ssdid.drive.data.remote.dto.ServerShareResponse
import my.ssdid.drive.data.remote.dto.SetupRecoveryRequest
import my.ssdid.drive.data.remote.dto.SetupTrusteesRequest
import my.ssdid.drive.data.remote.dto.SetupTrusteesResponse
import my.ssdid.drive.data.remote.dto.TrusteeDto
import my.ssdid.drive.data.remote.dto.TrusteeShareEntry
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
 * - setupRecovery
 * - getStatus
 * - getServerShare
 * - completeRecovery
 * - deleteSetup
 * - Error handling (network, HTTP codes)
 */
@OptIn(ExperimentalCoroutinesApi::class)
class RecoveryRepositoryImplTest {

    private lateinit var apiService: ApiService
    private lateinit var repository: RecoveryRepositoryImpl

    @Before
    fun setup() {
        apiService = mockk()
        repository = RecoveryRepositoryImpl(apiService = apiService)
    }

    @After
    fun tearDown() {
        unmockkAll()
    }

    // ==================== setupRecovery Tests ====================

    @Test
    fun `setupRecovery returns success on 200`() = runTest {
        coEvery { apiService.setupRecovery(any()) } returns Response.success(Unit)

        val result = repository.setupRecovery("server_share_data", "key_proof_data")

        assertTrue(result.isSuccess)
    }

    @Test
    fun `setupRecovery passes correct request fields`() = runTest {
        val slot = slot<SetupRecoveryRequest>()
        coEvery { apiService.setupRecovery(capture(slot)) } returns Response.success(Unit)

        repository.setupRecovery("my_share", "my_proof")

        assertEquals("my_share", slot.captured.serverShare)
        assertEquals("my_proof", slot.captured.keyProof)
    }

    @Test
    fun `setupRecovery returns failure on HTTP error`() = runTest {
        coEvery { apiService.setupRecovery(any()) } returns Response.error(
            400, "Bad request".toResponseBody()
        )

        val result = repository.setupRecovery("share", "proof")

        assertTrue(result.isFailure)
        assertTrue(result.exceptionOrNull()!!.message!!.contains("400"))
    }

    @Test
    fun `setupRecovery returns failure on exception`() = runTest {
        coEvery { apiService.setupRecovery(any()) } throws java.io.IOException("No connection")

        val result = repository.setupRecovery("share", "proof")

        assertTrue(result.isFailure)
        assertTrue(result.exceptionOrNull() is java.io.IOException)
    }

    // ==================== getStatus Tests ====================

    @Test
    fun `getStatus returns status on success`() = runTest {
        val statusResponse = RecoveryStatusResponse(isActive = true, createdAt = "2024-01-01T00:00:00Z")
        coEvery { apiService.getRecoveryStatus() } returns Response.success(statusResponse)

        val result = repository.getStatus()

        assertTrue(result.isSuccess)
        val status = result.getOrNull()!!
        assertTrue(status.isActive)
        assertEquals("2024-01-01T00:00:00Z", status.createdAt)
    }

    @Test
    fun `getStatus returns inactive status when not configured`() = runTest {
        val statusResponse = RecoveryStatusResponse(isActive = false, createdAt = null)
        coEvery { apiService.getRecoveryStatus() } returns Response.success(statusResponse)

        val result = repository.getStatus()

        assertTrue(result.isSuccess)
        assertFalse(result.getOrNull()!!.isActive)
        assertNull(result.getOrNull()!!.createdAt)
    }

    @Test
    fun `getStatus returns failure on HTTP error`() = runTest {
        coEvery { apiService.getRecoveryStatus() } returns Response.error(
            500, "Server error".toResponseBody()
        )

        val result = repository.getStatus()

        assertTrue(result.isFailure)
        assertTrue(result.exceptionOrNull()!!.message!!.contains("500"))
    }

    @Test
    fun `getStatus returns failure on exception`() = runTest {
        coEvery { apiService.getRecoveryStatus() } throws java.io.IOException("Timeout")

        val result = repository.getStatus()

        assertTrue(result.isFailure)
        assertTrue(result.exceptionOrNull() is java.io.IOException)
    }

    // ==================== getServerShare Tests ====================

    @Test
    fun `getServerShare returns share on success`() = runTest {
        val shareResponse = ServerShareResponse(serverShare = "share_data_base64", shareIndex = 1)
        coEvery { apiService.getRecoveryShare("did:example:123") } returns Response.success(shareResponse)

        val result = repository.getServerShare("did:example:123")

        assertTrue(result.isSuccess)
        val share = result.getOrNull()!!
        assertEquals("share_data_base64", share.serverShare)
        assertEquals(1, share.shareIndex)
    }

    @Test
    fun `getServerShare passes did as query parameter`() = runTest {
        val slot = slot<String>()
        coEvery { apiService.getRecoveryShare(capture(slot)) } returns Response.success(
            ServerShareResponse(serverShare = "share", shareIndex = 1)
        )

        repository.getServerShare("did:ssdid:abc")

        assertEquals("did:ssdid:abc", slot.captured)
    }

    @Test
    fun `getServerShare returns failure on 404`() = runTest {
        coEvery { apiService.getRecoveryShare(any()) } returns Response.error(
            404, "Not found".toResponseBody()
        )

        val result = repository.getServerShare("did:example:missing")

        assertTrue(result.isFailure)
        assertTrue(result.exceptionOrNull()!!.message!!.contains("404"))
    }

    @Test
    fun `getServerShare returns failure on exception`() = runTest {
        coEvery { apiService.getRecoveryShare(any()) } throws java.io.IOException("Network")

        val result = repository.getServerShare("did:example:123")

        assertTrue(result.isFailure)
        assertTrue(result.exceptionOrNull() is java.io.IOException)
    }

    // ==================== completeRecovery Tests ====================

    @Test
    fun `completeRecovery returns response on success`() = runTest {
        val response = CompleteRecoveryResponse(token = "new_token", userId = "user-123")
        coEvery { apiService.completeRecovery(any()) } returns Response.success(response)

        val result = repository.completeRecovery("old_did", "new_did", "key_proof", "kem_pk")

        assertTrue(result.isSuccess)
        val resp = result.getOrNull()!!
        assertEquals("new_token", resp.token)
        assertEquals("user-123", resp.userId)
    }

    @Test
    fun `completeRecovery passes correct request fields`() = runTest {
        val slot = slot<CompleteRecoveryRequest>()
        coEvery { apiService.completeRecovery(capture(slot)) } returns Response.success(
            CompleteRecoveryResponse(token = "tok", userId = "uid")
        )

        repository.completeRecovery("old", "new", "proof", "kemkey")

        assertEquals("old", slot.captured.oldDid)
        assertEquals("new", slot.captured.newDid)
        assertEquals("proof", slot.captured.keyProof)
        assertEquals("kemkey", slot.captured.kemPublicKey)
    }

    @Test
    fun `completeRecovery returns failure on HTTP error`() = runTest {
        coEvery { apiService.completeRecovery(any()) } returns Response.error(
            422, "Unprocessable entity".toResponseBody()
        )

        val result = repository.completeRecovery("old", "new", "proof", "kemkey")

        assertTrue(result.isFailure)
        assertTrue(result.exceptionOrNull()!!.message!!.contains("422"))
    }

    @Test
    fun `completeRecovery returns failure on exception`() = runTest {
        coEvery { apiService.completeRecovery(any()) } throws java.io.IOException("Timeout")

        val result = repository.completeRecovery("old", "new", "proof", "kemkey")

        assertTrue(result.isFailure)
        assertTrue(result.exceptionOrNull() is java.io.IOException)
    }

    // ==================== deleteSetup Tests ====================

    @Test
    fun `deleteSetup returns success on 200`() = runTest {
        coEvery { apiService.deleteRecoverySetup() } returns Response.success(Unit)

        val result = repository.deleteSetup()

        assertTrue(result.isSuccess)
    }

    @Test
    fun `deleteSetup returns failure on 404`() = runTest {
        coEvery { apiService.deleteRecoverySetup() } returns Response.error(
            404, "Not found".toResponseBody()
        )

        val result = repository.deleteSetup()

        assertTrue(result.isFailure)
        assertTrue(result.exceptionOrNull()!!.message!!.contains("404"))
    }

    @Test
    fun `deleteSetup returns failure on exception`() = runTest {
        coEvery { apiService.deleteRecoverySetup() } throws java.io.IOException("Network")

        val result = repository.deleteSetup()

        assertTrue(result.isFailure)
        assertTrue(result.exceptionOrNull() is java.io.IOException)
    }

    // ==================== setupTrustees Tests ====================

    @Test
    fun `setupTrustees returns success on 200`() = runTest {
        val response = SetupTrusteesResponse(trusteeCount = 2, threshold = 2)
        coEvery { apiService.setupTrustees(any()) } returns Response.success(response)

        val request = SetupTrusteesRequest(
            threshold = 2,
            shares = listOf(
                TrusteeShareEntry("user-1", "encShare1", 1),
                TrusteeShareEntry("user-2", "encShare2", 2)
            )
        )
        val result = repository.setupTrustees(request)

        assertTrue(result.isSuccess)
        assertEquals(2, result.getOrNull()!!.trusteeCount)
        assertEquals(2, result.getOrNull()!!.threshold)
    }

    @Test
    fun `setupTrustees returns failure on HTTP error`() = runTest {
        coEvery { apiService.setupTrustees(any()) } returns Response.error(
            400, "Bad request".toResponseBody()
        )

        val result = repository.setupTrustees(SetupTrusteesRequest(2, emptyList()))

        assertTrue(result.isFailure)
        assertTrue(result.exceptionOrNull()!!.message!!.contains("400"))
    }

    @Test
    fun `setupTrustees returns failure on exception`() = runTest {
        coEvery { apiService.setupTrustees(any()) } throws java.io.IOException("Network")

        val result = repository.setupTrustees(SetupTrusteesRequest(2, emptyList()))

        assertTrue(result.isFailure)
        assertTrue(result.exceptionOrNull() is java.io.IOException)
    }

    // ==================== getTrustees Tests ====================

    @Test
    fun `getTrustees returns list on success`() = runTest {
        val trustee = TrusteeDto(
            id = "t-1",
            trusteeUserId = "user-1",
            displayName = "Alice",
            email = "alice@example.com",
            shareIndex = 1,
            createdAt = "2024-01-01T00:00:00Z"
        )
        val response = ListTrusteesResponse(trustees = listOf(trustee), threshold = 2)
        coEvery { apiService.getTrustees() } returns Response.success(response)

        val result = repository.getTrustees()

        assertTrue(result.isSuccess)
        assertEquals(1, result.getOrNull()!!.trustees.size)
        assertEquals(2, result.getOrNull()!!.threshold)
    }

    @Test
    fun `getTrustees returns failure on HTTP error`() = runTest {
        coEvery { apiService.getTrustees() } returns Response.error(
            401, "Unauthorized".toResponseBody()
        )

        val result = repository.getTrustees()

        assertTrue(result.isFailure)
        assertTrue(result.exceptionOrNull()!!.message!!.contains("401"))
    }

    // ==================== initiateRecoveryRequest Tests ====================

    @Test
    fun `initiateRecoveryRequest returns response on success`() = runTest {
        val response = RecoveryRequestResponse(
            requestId = "req-1",
            status = "pending",
            requiredCount = 2,
            expiresAt = "2024-01-03T00:00:00Z"
        )
        coEvery { apiService.initiateRecoveryRequest() } returns Response.success(response)

        val result = repository.initiateRecoveryRequest()

        assertTrue(result.isSuccess)
        assertEquals("req-1", result.getOrNull()!!.requestId)
        assertEquals("pending", result.getOrNull()!!.status)
    }

    @Test
    fun `initiateRecoveryRequest returns failure on HTTP error`() = runTest {
        coEvery { apiService.initiateRecoveryRequest() } returns Response.error(
            404, "Not found".toResponseBody()
        )

        val result = repository.initiateRecoveryRequest()

        assertTrue(result.isFailure)
        assertTrue(result.exceptionOrNull()!!.message!!.contains("404"))
    }

    // ==================== getMyRecoveryRequest Tests ====================

    @Test
    fun `getMyRecoveryRequest returns null request when none active`() = runTest {
        coEvery { apiService.getMyRecoveryRequest() } returns Response.success(
            MyRecoveryRequestResponse(request = null)
        )

        val result = repository.getMyRecoveryRequest()

        assertTrue(result.isSuccess)
        assertNull(result.getOrNull()!!.request)
    }

    @Test
    fun `getMyRecoveryRequest returns active request`() = runTest {
        val requestData = MyRecoveryRequestData(
            id = "req-1",
            status = "pending",
            approvedShares = 1,
            requiredShares = 2,
            expiresAt = "2024-01-03T00:00:00Z",
            createdAt = "2024-01-01T00:00:00Z"
        )
        coEvery { apiService.getMyRecoveryRequest() } returns Response.success(
            MyRecoveryRequestResponse(request = requestData)
        )

        val result = repository.getMyRecoveryRequest()

        assertTrue(result.isSuccess)
        assertNotNull(result.getOrNull()!!.request)
        assertEquals("req-1", result.getOrNull()!!.request!!.id)
    }

    // ==================== getPendingRecoveryRequests Tests ====================

    @Test
    fun `getPendingRecoveryRequests returns list on success`() = runTest {
        val pending = PendingRecoveryRequestDto(
            id = "req-1",
            requesterName = "Bob",
            requesterEmail = "bob@example.com",
            status = "pending",
            approvedCount = 0,
            requiredCount = 2,
            expiresAt = "2024-01-03T00:00:00Z",
            createdAt = "2024-01-01T00:00:00Z"
        )
        coEvery { apiService.getPendingRecoveryRequests() } returns Response.success(
            PendingRequestsResponse(requests = listOf(pending))
        )

        val result = repository.getPendingRecoveryRequests()

        assertTrue(result.isSuccess)
        assertEquals(1, result.getOrNull()!!.requests.size)
        assertEquals("Bob", result.getOrNull()!!.requests[0].requesterName)
    }

    @Test
    fun `getPendingRecoveryRequests returns empty list when no requests`() = runTest {
        coEvery { apiService.getPendingRecoveryRequests() } returns Response.success(
            PendingRequestsResponse(requests = emptyList())
        )

        val result = repository.getPendingRecoveryRequests()

        assertTrue(result.isSuccess)
        assertTrue(result.getOrNull()!!.requests.isEmpty())
    }

    // ==================== approveRecoveryRequest Tests ====================

    @Test
    fun `approveRecoveryRequest returns response on success`() = runTest {
        val response = ApproveRequestResponse(
            requestId = "req-1",
            status = "pending",
            approvedCount = 1,
            requiredCount = 2
        )
        coEvery { apiService.approveRecoveryRequest("req-1") } returns Response.success(response)

        val result = repository.approveRecoveryRequest("req-1")

        assertTrue(result.isSuccess)
        assertEquals(1, result.getOrNull()!!.approvedCount)
    }

    @Test
    fun `approveRecoveryRequest returns failure on 403`() = runTest {
        coEvery { apiService.approveRecoveryRequest(any()) } returns Response.error(
            403, "Forbidden".toResponseBody()
        )

        val result = repository.approveRecoveryRequest("req-1")

        assertTrue(result.isFailure)
        assertTrue(result.exceptionOrNull()!!.message!!.contains("403"))
    }

    // ==================== rejectRecoveryRequest Tests ====================

    @Test
    fun `rejectRecoveryRequest returns response on success`() = runTest {
        val response = RejectRequestResponse(
            requestId = "req-1",
            status = "pending",
            decision = "rejected"
        )
        coEvery { apiService.rejectRecoveryRequest("req-1") } returns Response.success(response)

        val result = repository.rejectRecoveryRequest("req-1")

        assertTrue(result.isSuccess)
        assertEquals("rejected", result.getOrNull()!!.decision)
    }

    @Test
    fun `rejectRecoveryRequest returns failure on exception`() = runTest {
        coEvery { apiService.rejectRecoveryRequest(any()) } throws java.io.IOException("Network")

        val result = repository.rejectRecoveryRequest("req-1")

        assertTrue(result.isFailure)
        assertTrue(result.exceptionOrNull() is java.io.IOException)
    }

    // ==================== createRecoveryRequest Tests ====================

    @Test
    fun `createRecoveryRequest returns response on success`() = runTest {
        val response = RecoveryRequestResponse(
            requestId = "req-1",
            status = "pending",
            requiredCount = 2,
            expiresAt = "2024-01-03T00:00:00Z"
        )
        val slot = slot<CreateRecoveryRequestBody>()
        coEvery { apiService.createRecoveryRequest(capture(slot)) } returns Response.success(response)

        val result = repository.createRecoveryRequest("did:ssdid:abc")

        assertTrue(result.isSuccess)
        assertEquals("did:ssdid:abc", slot.captured.did)
        assertEquals("req-1", result.getOrNull()!!.requestId)
    }

    @Test
    fun `createRecoveryRequest returns failure on 404`() = runTest {
        coEvery { apiService.createRecoveryRequest(any()) } returns Response.error(
            404, "Not found".toResponseBody()
        )

        val result = repository.createRecoveryRequest("did:ssdid:unknown")

        assertTrue(result.isFailure)
        assertTrue(result.exceptionOrNull()!!.message!!.contains("404"))
    }

    // ==================== getReleasedShares Tests ====================

    @Test
    fun `getReleasedShares returns shares on success`() = runTest {
        val share = ReleasedShareDto(
            trusteeUserId = "user-1",
            encryptedShare = "encShareBase64",
            shareIndex = 1
        )
        val response = ReleasedSharesResponse(
            requestId = "req-1",
            status = "approved",
            shares = listOf(share)
        )
        coEvery { apiService.getReleasedShares("req-1", "did:ssdid:abc") } returns Response.success(response)

        val result = repository.getReleasedShares("req-1", "did:ssdid:abc")

        assertTrue(result.isSuccess)
        assertEquals(1, result.getOrNull()!!.shares.size)
        assertEquals("encShareBase64", result.getOrNull()!!.shares[0].encryptedShare)
    }

    @Test
    fun `getReleasedShares returns failure on 403 wrong DID`() = runTest {
        coEvery { apiService.getReleasedShares(any(), any()) } returns Response.error(
            403, "Forbidden".toResponseBody()
        )

        val result = repository.getReleasedShares("req-1", "did:ssdid:wrong")

        assertTrue(result.isFailure)
        assertTrue(result.exceptionOrNull()!!.message!!.contains("403"))
    }
}
