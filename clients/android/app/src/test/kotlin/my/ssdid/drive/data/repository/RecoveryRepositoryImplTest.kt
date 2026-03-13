package my.ssdid.drive.data.repository

import my.ssdid.drive.data.remote.ApiService
import my.ssdid.drive.data.remote.dto.CompleteRecoveryRequest
import my.ssdid.drive.data.remote.dto.CompleteRecoveryResponse
import my.ssdid.drive.data.remote.dto.RecoveryStatusResponse
import my.ssdid.drive.data.remote.dto.ServerShareResponse
import my.ssdid.drive.data.remote.dto.SetupRecoveryRequest
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
}
