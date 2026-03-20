package my.ssdid.drive.domain.repository

import my.ssdid.drive.data.remote.dto.ApproveRequestResponse
import my.ssdid.drive.data.remote.dto.CompleteRecoveryResponse
import my.ssdid.drive.data.remote.dto.ListTrusteesResponse
import my.ssdid.drive.data.remote.dto.MyRecoveryRequestResponse
import my.ssdid.drive.data.remote.dto.PendingRequestsResponse
import my.ssdid.drive.data.remote.dto.RecoveryRequestResponse
import my.ssdid.drive.data.remote.dto.RecoveryStatusResponse
import my.ssdid.drive.data.remote.dto.RejectRequestResponse
import my.ssdid.drive.data.remote.dto.ReleasedSharesResponse
import my.ssdid.drive.data.remote.dto.ServerShareResponse
import my.ssdid.drive.data.remote.dto.SetupTrusteesRequest
import my.ssdid.drive.data.remote.dto.SetupTrusteesResponse

interface RecoveryRepository {
    suspend fun setupRecovery(serverShare: String, keyProof: String): Result<Unit>
    suspend fun getStatus(): Result<RecoveryStatusResponse>
    suspend fun getServerShare(did: String): Result<ServerShareResponse>
    suspend fun completeRecovery(oldDid: String, newDid: String, keyProof: String, kemPublicKey: String): Result<CompleteRecoveryResponse>
    suspend fun deleteSetup(): Result<Unit>

    // Trustee management
    suspend fun setupTrustees(request: SetupTrusteesRequest): Result<SetupTrusteesResponse>
    suspend fun getTrustees(): Result<ListTrusteesResponse>

    // Recovery requests — authenticated
    suspend fun initiateRecoveryRequest(): Result<RecoveryRequestResponse>
    suspend fun getMyRecoveryRequest(): Result<MyRecoveryRequestResponse>
    suspend fun getPendingRecoveryRequests(): Result<PendingRequestsResponse>
    suspend fun approveRecoveryRequest(requestId: String): Result<ApproveRequestResponse>
    suspend fun rejectRecoveryRequest(requestId: String): Result<RejectRequestResponse>

    // Recovery requests — unauthenticated
    suspend fun createRecoveryRequest(did: String): Result<RecoveryRequestResponse>
    suspend fun getReleasedShares(requestId: String, did: String): Result<ReleasedSharesResponse>
}
