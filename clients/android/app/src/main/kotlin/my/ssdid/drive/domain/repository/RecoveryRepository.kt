package my.ssdid.drive.domain.repository

import my.ssdid.drive.data.remote.dto.CompleteRecoveryResponse
import my.ssdid.drive.data.remote.dto.RecoveryStatusResponse
import my.ssdid.drive.data.remote.dto.ServerShareResponse

interface RecoveryRepository {
    suspend fun setupRecovery(serverShare: String, keyProof: String): Result<Unit>
    suspend fun getStatus(): Result<RecoveryStatusResponse>
    suspend fun getServerShare(did: String): Result<ServerShareResponse>
    suspend fun completeRecovery(oldDid: String, newDid: String, keyProof: String, kemPublicKey: String): Result<CompleteRecoveryResponse>
    suspend fun deleteSetup(): Result<Unit>
}
