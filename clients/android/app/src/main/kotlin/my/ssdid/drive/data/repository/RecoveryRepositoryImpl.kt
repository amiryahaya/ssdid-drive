package my.ssdid.drive.data.repository

import my.ssdid.drive.data.remote.ApiService
import my.ssdid.drive.data.remote.dto.ApproveRequestResponse
import my.ssdid.drive.data.remote.dto.CompleteRecoveryRequest
import my.ssdid.drive.data.remote.dto.CompleteRecoveryResponse
import my.ssdid.drive.data.remote.dto.CreateRecoveryRequestBody
import my.ssdid.drive.data.remote.dto.ListTrusteesResponse
import my.ssdid.drive.data.remote.dto.MyRecoveryRequestResponse
import my.ssdid.drive.data.remote.dto.PendingRequestsResponse
import my.ssdid.drive.data.remote.dto.RecoveryRequestResponse
import my.ssdid.drive.data.remote.dto.RecoveryStatusResponse
import my.ssdid.drive.data.remote.dto.RejectRequestResponse
import my.ssdid.drive.data.remote.dto.ReleasedSharesResponse
import my.ssdid.drive.data.remote.dto.ServerShareResponse
import my.ssdid.drive.data.remote.dto.SetupRecoveryRequest
import my.ssdid.drive.data.remote.dto.SetupTrusteesRequest
import my.ssdid.drive.data.remote.dto.SetupTrusteesResponse
import my.ssdid.drive.domain.repository.RecoveryRepository
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class RecoveryRepositoryImpl @Inject constructor(
    private val apiService: ApiService
) : RecoveryRepository {

    override suspend fun setupRecovery(serverShare: String, keyProof: String): Result<Unit> = try {
        val response = apiService.setupRecovery(SetupRecoveryRequest(serverShare, keyProof))
        if (response.isSuccessful) Result.success(Unit)
        else Result.failure(Exception("Setup failed: ${response.code()}"))
    } catch (e: Exception) {
        Result.failure(e)
    }

    override suspend fun getStatus(): Result<RecoveryStatusResponse> = try {
        val response = apiService.getRecoveryStatus()
        if (response.isSuccessful) Result.success(response.body()!!)
        else Result.failure(Exception("Status check failed: ${response.code()}"))
    } catch (e: Exception) {
        Result.failure(e)
    }

    override suspend fun getServerShare(did: String): Result<ServerShareResponse> = try {
        val response = apiService.getRecoveryShare(did)
        if (response.isSuccessful) Result.success(response.body()!!)
        else Result.failure(Exception("Share retrieval failed: ${response.code()}"))
    } catch (e: Exception) {
        Result.failure(e)
    }

    override suspend fun completeRecovery(
        oldDid: String, newDid: String, keyProof: String, kemPublicKey: String
    ): Result<CompleteRecoveryResponse> = try {
        val response = apiService.completeRecovery(
            CompleteRecoveryRequest(oldDid, newDid, keyProof, kemPublicKey)
        )
        if (response.isSuccessful) Result.success(response.body()!!)
        else Result.failure(Exception("Recovery failed: ${response.code()}"))
    } catch (e: Exception) {
        Result.failure(e)
    }

    override suspend fun deleteSetup(): Result<Unit> = try {
        val response = apiService.deleteRecoverySetup()
        if (response.isSuccessful) Result.success(Unit)
        else Result.failure(Exception("Delete failed: ${response.code()}"))
    } catch (e: Exception) {
        Result.failure(e)
    }

    // ==================== Trustee Management ====================

    override suspend fun setupTrustees(request: SetupTrusteesRequest): Result<SetupTrusteesResponse> = try {
        val response = apiService.setupTrustees(request)
        if (response.isSuccessful) Result.success(response.body()!!)
        else Result.failure(Exception("Trustee setup failed: ${response.code()}"))
    } catch (e: Exception) {
        Result.failure(e)
    }

    override suspend fun getTrustees(): Result<ListTrusteesResponse> = try {
        val response = apiService.getTrustees()
        if (response.isSuccessful) Result.success(response.body()!!)
        else Result.failure(Exception("Get trustees failed: ${response.code()}"))
    } catch (e: Exception) {
        Result.failure(e)
    }

    // ==================== Recovery Requests — Authenticated ====================

    override suspend fun initiateRecoveryRequest(): Result<RecoveryRequestResponse> = try {
        val response = apiService.initiateRecoveryRequest()
        if (response.isSuccessful) Result.success(response.body()!!)
        else Result.failure(Exception("Initiate recovery failed: ${response.code()}"))
    } catch (e: Exception) {
        Result.failure(e)
    }

    override suspend fun getMyRecoveryRequest(): Result<MyRecoveryRequestResponse> = try {
        val response = apiService.getMyRecoveryRequest()
        if (response.isSuccessful) Result.success(response.body()!!)
        else Result.failure(Exception("Get my recovery request failed: ${response.code()}"))
    } catch (e: Exception) {
        Result.failure(e)
    }

    override suspend fun getPendingRecoveryRequests(): Result<PendingRequestsResponse> = try {
        val response = apiService.getPendingRecoveryRequests()
        if (response.isSuccessful) Result.success(response.body()!!)
        else Result.failure(Exception("Get pending requests failed: ${response.code()}"))
    } catch (e: Exception) {
        Result.failure(e)
    }

    override suspend fun approveRecoveryRequest(requestId: String): Result<ApproveRequestResponse> = try {
        val response = apiService.approveRecoveryRequest(requestId)
        if (response.isSuccessful) Result.success(response.body()!!)
        else Result.failure(Exception("Approve request failed: ${response.code()}"))
    } catch (e: Exception) {
        Result.failure(e)
    }

    override suspend fun rejectRecoveryRequest(requestId: String): Result<RejectRequestResponse> = try {
        val response = apiService.rejectRecoveryRequest(requestId)
        if (response.isSuccessful) Result.success(response.body()!!)
        else Result.failure(Exception("Reject request failed: ${response.code()}"))
    } catch (e: Exception) {
        Result.failure(e)
    }

    // ==================== Recovery Requests — Unauthenticated ====================

    override suspend fun createRecoveryRequest(did: String): Result<RecoveryRequestResponse> = try {
        val response = apiService.createRecoveryRequest(CreateRecoveryRequestBody(did))
        if (response.isSuccessful) Result.success(response.body()!!)
        else Result.failure(Exception("Create recovery request failed: ${response.code()}"))
    } catch (e: Exception) {
        Result.failure(e)
    }

    override suspend fun getReleasedShares(requestId: String, did: String): Result<ReleasedSharesResponse> = try {
        val response = apiService.getReleasedShares(requestId, did)
        if (response.isSuccessful) Result.success(response.body()!!)
        else Result.failure(Exception("Get released shares failed: ${response.code()}"))
    } catch (e: Exception) {
        Result.failure(e)
    }
}
