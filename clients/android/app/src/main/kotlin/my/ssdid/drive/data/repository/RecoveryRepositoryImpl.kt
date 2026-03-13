package my.ssdid.drive.data.repository

import my.ssdid.drive.data.remote.ApiService
import my.ssdid.drive.data.remote.dto.CompleteRecoveryRequest
import my.ssdid.drive.data.remote.dto.CompleteRecoveryResponse
import my.ssdid.drive.data.remote.dto.RecoveryStatusResponse
import my.ssdid.drive.data.remote.dto.ServerShareResponse
import my.ssdid.drive.data.remote.dto.SetupRecoveryRequest
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
}
