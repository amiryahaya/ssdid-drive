package my.ssdid.drive.data.repository

import android.util.Base64
import my.ssdid.drive.crypto.CryptoManager
import my.ssdid.drive.crypto.KeyManager
import my.ssdid.drive.data.local.SecureStorage
import my.ssdid.drive.data.remote.ApiService
import my.ssdid.drive.data.remote.dto.ApproveRecoveryRequest
import my.ssdid.drive.data.remote.dto.CompleteRecoveryRequest
import my.ssdid.drive.data.remote.dto.CreateRecoveryRequestRequest
import my.ssdid.drive.data.remote.dto.CreateRecoveryShareRequest
import my.ssdid.drive.data.remote.dto.PublicKeysDto
import my.ssdid.drive.data.remote.dto.RecoveryShareDto
import my.ssdid.drive.data.remote.dto.SetupRecoveryRequest
import my.ssdid.drive.domain.model.PublicKeys
import my.ssdid.drive.domain.model.RecoveryApproval
import my.ssdid.drive.domain.model.RecoveryConfig
import my.ssdid.drive.domain.model.RecoveryConfigStatus
import my.ssdid.drive.domain.model.RecoveryProgress
import my.ssdid.drive.domain.model.RecoveryRequest
import my.ssdid.drive.domain.model.RecoveryRequestStatus
import my.ssdid.drive.domain.model.RecoveryShare
import my.ssdid.drive.domain.model.RecoveryShareStatus
import my.ssdid.drive.domain.model.User
import my.ssdid.drive.domain.model.UserRole
import my.ssdid.drive.domain.repository.RecoveryRepository
import my.ssdid.drive.util.AppException
import my.ssdid.drive.util.Result
import java.time.Instant
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Recovery operations are now managed by the SSDID Wallet.
 *
 * This implementation retains read-only server queries (get config, list shares,
 * list requests) but delegates all crypto-intensive operations (setup, share
 * creation, approval, completion) to the wallet via deep links.
 */
@Singleton
class RecoveryRepositoryImpl @Inject constructor(
    private val apiService: ApiService,
    private val secureStorage: SecureStorage,
    private val keyManager: KeyManager
) : RecoveryRepository {

    override suspend fun getRecoveryConfig(): Result<RecoveryConfig?> {
        return try {
            val response = apiService.getRecoveryConfig()

            if (response.isSuccessful) {
                val config = response.body()?.data?.toDomain()
                Result.success(config)
            } else {
                when (response.code()) {
                    404 -> Result.success(null)
                    else -> Result.error(AppException.Unknown("Failed to get recovery config"))
                }
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to get recovery config", e))
        }
    }

    override suspend fun setupRecovery(
        threshold: Int,
        totalShares: Int
    ): Result<RecoveryConfig> {
        // Recovery setup (Shamir splitting) is now handled by the SSDID Wallet
        return Result.error(AppException.Unknown("Recovery setup is managed by the SSDID Wallet"))
    }

    override suspend fun disableRecovery(): Result<Unit> {
        return try {
            val response = apiService.disableRecovery()

            if (response.isSuccessful) {
                Result.success(Unit)
            } else {
                when (response.code()) {
                    404 -> Result.error(AppException.NotFound("No recovery config found"))
                    else -> Result.error(AppException.Unknown("Failed to disable recovery"))
                }
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to disable recovery", e))
        }
    }

    override suspend fun createShare(
        trustee: User,
        shareIndex: Int
    ): Result<RecoveryShare> {
        // Share creation (encryption with trustee keys) is now handled by the SSDID Wallet
        return Result.error(AppException.Unknown("Share creation is managed by the SSDID Wallet"))
    }

    override suspend fun getCreatedShares(): Result<List<RecoveryShare>> {
        return try {
            val response = apiService.getCreatedRecoveryShares()

            if (response.isSuccessful) {
                val shares = response.body()!!.data.map { it.toDomain() }
                Result.success(shares)
            } else {
                Result.error(AppException.Unknown("Failed to get created shares"))
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to get created shares", e))
        }
    }

    override suspend fun getTrusteeShares(): Result<List<RecoveryShare>> {
        return try {
            val response = apiService.getTrusteeShares()

            if (response.isSuccessful) {
                val shares = response.body()!!.data.map { it.toDomain() }
                Result.success(shares)
            } else {
                Result.error(AppException.Unknown("Failed to get trustee shares"))
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to get trustee shares", e))
        }
    }

    override suspend fun acceptShare(shareId: String): Result<RecoveryShare> {
        return try {
            val response = apiService.acceptRecoveryShare(shareId)

            if (response.isSuccessful) {
                val share = response.body()!!.data.toDomain()
                Result.success(share)
            } else {
                when (response.code()) {
                    404 -> Result.error(AppException.NotFound("Share not found"))
                    else -> Result.error(AppException.Unknown("Failed to accept share"))
                }
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to accept share", e))
        }
    }

    override suspend fun rejectShare(shareId: String): Result<Unit> {
        return try {
            val response = apiService.rejectRecoveryShare(shareId)

            if (response.isSuccessful) {
                Result.success(Unit)
            } else {
                when (response.code()) {
                    404 -> Result.error(AppException.NotFound("Share not found"))
                    403 -> Result.error(AppException.Unauthorized("Not authorized to reject this share"))
                    else -> Result.error(AppException.Unknown("Failed to reject share"))
                }
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to reject share", e))
        }
    }

    override suspend fun revokeShare(shareId: String): Result<Unit> {
        return try {
            val response = apiService.revokeRecoveryShare(shareId)

            if (response.isSuccessful) {
                Result.success(Unit)
            } else {
                when (response.code()) {
                    404 -> Result.error(AppException.NotFound("Share not found"))
                    403 -> Result.error(AppException.Unauthorized("Not authorized to revoke this share"))
                    else -> Result.error(AppException.Unknown("Failed to revoke share"))
                }
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to revoke share", e))
        }
    }

    override suspend fun initiateRecovery(
        password: String,
        reason: String?
    ): Result<RecoveryRequest> {
        // Recovery initiation (new key generation) is now handled by the SSDID Wallet
        return Result.error(AppException.Unknown("Recovery initiation is managed by the SSDID Wallet"))
    }

    override suspend fun getMyRecoveryRequests(): Result<List<RecoveryRequest>> {
        return try {
            val response = apiService.getRecoveryRequests()

            if (response.isSuccessful) {
                val requests = response.body()!!.data.map { it.toDomain() }
                Result.success(requests)
            } else {
                Result.error(AppException.Unknown("Failed to get recovery requests"))
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to get recovery requests", e))
        }
    }

    override suspend fun getPendingApprovalRequests(): Result<List<RecoveryRequest>> {
        return try {
            val response = apiService.getPendingRecoveryRequests()

            if (response.isSuccessful) {
                val requests = response.body()!!.data.map { it.toDomain() }
                Result.success(requests)
            } else {
                Result.error(AppException.Unknown("Failed to get pending requests"))
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to get pending requests", e))
        }
    }

    override suspend fun getRecoveryRequest(requestId: String): Result<RecoveryRequest> {
        return try {
            val response = apiService.getRecoveryRequest(requestId)

            if (response.isSuccessful) {
                val detail = response.body()!!.data
                val request = detail.request.toDomain().copy(
                    progress = RecoveryProgress(
                        threshold = detail.progress.threshold,
                        approvals = detail.progress.approvals,
                        remaining = detail.progress.remaining
                    )
                )
                Result.success(request)
            } else {
                when (response.code()) {
                    404 -> Result.error(AppException.NotFound("Request not found"))
                    else -> Result.error(AppException.Unknown("Failed to get recovery request"))
                }
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to get recovery request", e))
        }
    }

    override suspend fun approveRecoveryRequest(
        requestId: String,
        shareId: String
    ): Result<RecoveryApproval> {
        // Recovery approval (share decryption/re-encryption) is now handled by the SSDID Wallet
        return Result.error(AppException.Unknown("Recovery approval is managed by the SSDID Wallet"))
    }

    override suspend fun completeRecovery(
        requestId: String,
        password: String
    ): Result<Unit> {
        // Recovery completion is now handled by the SSDID Wallet
        return Result.error(AppException.Unknown("Recovery completion is managed by the SSDID Wallet"))
    }

    override suspend fun cancelRecoveryRequest(requestId: String): Result<Unit> {
        return try {
            val response = apiService.cancelRecoveryRequest(requestId)

            if (response.isSuccessful) {
                Result.success(Unit)
            } else {
                when (response.code()) {
                    404 -> Result.error(AppException.NotFound("Request not found"))
                    403 -> Result.error(AppException.Unauthorized("Not authorized to cancel this request"))
                    409 -> Result.error(AppException.ValidationError("Request cannot be cancelled"))
                    else -> Result.error(AppException.Unknown("Failed to cancel recovery request"))
                }
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to cancel recovery request", e))
        }
    }

    // ==================== Conversion Functions ====================

    private fun my.ssdid.drive.data.remote.dto.RecoveryConfigDto.toDomain(): RecoveryConfig {
        return RecoveryConfig(
            id = id,
            userId = userId,
            threshold = threshold,
            totalShares = totalShares,
            status = RecoveryConfigStatus.fromString(status),
            createdAt = java.time.OffsetDateTime.parse(insertedAt).toInstant(),
            updatedAt = java.time.OffsetDateTime.parse(updatedAt).toInstant()
        )
    }

    private fun RecoveryShareDto.toDomain(): RecoveryShare {
        return RecoveryShare(
            id = id,
            configId = configId,
            grantorId = grantorId,
            trusteeId = trusteeId,
            shareIndex = shareIndex,
            status = RecoveryShareStatus.fromString(status),
            grantor = grantor?.toDomain(),
            trustee = trustee?.toDomain(),
            createdAt = java.time.OffsetDateTime.parse(insertedAt).toInstant(),
            updatedAt = java.time.OffsetDateTime.parse(updatedAt).toInstant()
        )
    }

    private fun my.ssdid.drive.data.remote.dto.RecoveryRequestDto.toDomain(): RecoveryRequest {
        return RecoveryRequest(
            id = id,
            userId = userId,
            status = RecoveryRequestStatus.fromString(status),
            reason = reason,
            user = user?.toDomain(),
            progress = null,
            createdAt = java.time.OffsetDateTime.parse(insertedAt).toInstant(),
            updatedAt = java.time.OffsetDateTime.parse(updatedAt).toInstant()
        )
    }

    private fun my.ssdid.drive.data.remote.dto.UserDto.toDomain(): User {
        return User(
            id = id,
            email = email,
            tenantId = tenantId,
            role = role?.let { UserRole.fromString(it) },
            publicKeys = publicKeys?.let {
                PublicKeys(
                    kem = Base64.decode(it.kem, Base64.NO_WRAP),
                    sign = Base64.decode(it.sign, Base64.NO_WRAP),
                    mlKem = it.mlKem?.let { pk -> Base64.decode(pk, Base64.NO_WRAP) },
                    mlDsa = it.mlDsa?.let { pk -> Base64.decode(pk, Base64.NO_WRAP) }
                )
            },
            storageQuota = storageQuota,
            storageUsed = storageUsed
        )
    }
}
