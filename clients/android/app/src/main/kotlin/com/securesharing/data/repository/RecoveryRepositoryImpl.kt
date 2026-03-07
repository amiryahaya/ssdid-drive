package com.securesharing.data.repository

import android.util.Base64
import com.securesharing.crypto.CryptoManager
import com.securesharing.crypto.KeyManager
import com.securesharing.crypto.RecoveryKeyManager
import com.securesharing.crypto.ShamirSecretSharing
import com.securesharing.data.local.SecureStorage
import com.securesharing.data.remote.ApiService
import com.securesharing.data.remote.dto.ApproveRecoveryRequest
import com.securesharing.data.remote.dto.CompleteRecoveryRequest
import com.securesharing.data.remote.dto.CreateRecoveryRequestRequest
import com.securesharing.data.remote.dto.CreateRecoveryShareRequest
import com.securesharing.data.remote.dto.PublicKeysDto
import com.securesharing.data.remote.dto.RecoveryShareDto
import com.securesharing.data.remote.dto.SetupRecoveryRequest
import com.securesharing.domain.model.PublicKeys
import com.securesharing.domain.model.RecoveryApproval
import com.securesharing.domain.model.RecoveryConfig
import com.securesharing.domain.model.RecoveryConfigStatus
import com.securesharing.domain.model.RecoveryProgress
import com.securesharing.domain.model.RecoveryRequest
import com.securesharing.domain.model.RecoveryRequestStatus
import com.securesharing.domain.model.RecoveryShare
import com.securesharing.domain.model.RecoveryShareStatus
import com.securesharing.domain.model.User
import com.securesharing.domain.model.UserRole
import com.securesharing.domain.repository.RecoveryRepository
import com.securesharing.util.AppException
import com.securesharing.util.Result
import java.time.Instant
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class RecoveryRepositoryImpl @Inject constructor(
    private val apiService: ApiService,
    private val secureStorage: SecureStorage,
    private val cryptoManager: CryptoManager,
    private val keyManager: KeyManager,
    private val recoveryKeyManager: RecoveryKeyManager
) : RecoveryRepository {

    // Cache for shares during setup (cleared after all shares distributed)
    private var pendingShares: List<ShamirSecretSharing.Share>? = null

    override suspend fun getRecoveryConfig(): Result<RecoveryConfig?> {
        return try {
            val response = apiService.getRecoveryConfig()

            if (response.isSuccessful) {
                val config = response.body()?.data?.toDomain()
                Result.success(config)
            } else {
                when (response.code()) {
                    404 -> Result.success(null) // No config exists
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
        return try {
            // Validate parameters
            if (threshold < 2) {
                return Result.error(AppException.ValidationError("Threshold must be at least 2"))
            }
            if (totalShares < threshold) {
                return Result.error(AppException.ValidationError("Total shares must be at least threshold"))
            }

            // Get master key from key manager
            val masterKey = keyManager.getUnlockedKeys().masterKey

            // Split master key using Shamir
            val splitResult = recoveryKeyManager.splitMasterKey(masterKey, threshold, totalShares)

            // Store shares temporarily for distribution
            pendingShares = splitResult.shares

            // Create recovery config on server
            val request = SetupRecoveryRequest(
                threshold = threshold,
                totalShares = totalShares
            )

            val response = apiService.setupRecovery(request)

            if (response.isSuccessful) {
                val config = response.body()!!.data?.toDomain()
                    ?: return Result.error(AppException.Unknown("No recovery config in response"))
                Result.success(config)
            } else {
                pendingShares = null
                when (response.code()) {
                    409 -> Result.error(AppException.ValidationError("Recovery already configured"))
                    else -> Result.error(AppException.Unknown("Failed to setup recovery"))
                }
            }
        } catch (e: Exception) {
            pendingShares = null
            Result.error(AppException.Network("Failed to setup recovery", e))
        }
    }

    override suspend fun disableRecovery(): Result<Unit> {
        return try {
            val response = apiService.disableRecovery()

            if (response.isSuccessful) {
                pendingShares = null
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
        return try {
            // Get the pending share for this index
            val shares = pendingShares
                ?: return Result.error(AppException.CryptoError("No pending shares - call setupRecovery first"))

            if (shareIndex < 1 || shareIndex > shares.size) {
                return Result.error(AppException.ValidationError("Invalid share index"))
            }

            val share = shares[shareIndex - 1]

            // Verify trustee has public keys
            val trusteePublicKeys = trustee.publicKeys
                ?: return Result.error(AppException.ValidationError("Trustee has no public keys"))

            val userId = secureStorage.getUserId()
                ?: return Result.error(AppException.Unauthorized("User not logged in"))

            // Encrypt share for trustee
            val encryptedResult = recoveryKeyManager.encryptShareForTrustee(
                share = share,
                trusteePublicKeys = trusteePublicKeys,
                grantorId = userId,
                trusteeId = trustee.id
            )

            // Create share on server
            val request = CreateRecoveryShareRequest(
                trusteeId = trustee.id,
                shareIndex = shareIndex,
                encryptedShare = encryptedResult.encryptedShare,
                kemCiphertext = encryptedResult.kemCiphertext,
                mlKemCiphertext = encryptedResult.mlKemCiphertext,
                signature = encryptedResult.signature
            )

            val response = apiService.createRecoveryShare(request)

            if (response.isSuccessful) {
                val recoveryShare = response.body()!!.data.toDomain()

                // Clear pending shares if all distributed
                if (shareIndex == shares.size) {
                    pendingShares = null
                }

                Result.success(recoveryShare)
            } else {
                when (response.code()) {
                    409 -> Result.error(AppException.ValidationError("Share already exists for this trustee"))
                    else -> Result.error(AppException.Unknown("Failed to create share"))
                }
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to create share", e))
        }
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
        return try {
            // Generate new key pairs
            val keyBundle = keyManager.generateKeyBundle()

            // Store new keys temporarily (will be used during completion)
            // We need to save these somewhere secure temporarily

            // Create request with new public key
            val newPublicKeysDto = PublicKeysDto(
                kem = Base64.encodeToString(keyBundle.kazKemPublicKey, Base64.NO_WRAP),
                sign = Base64.encodeToString(keyBundle.kazSignPublicKey, Base64.NO_WRAP),
                mlKem = keyBundle.mlKemPublicKey.takeIf { it.isNotEmpty() }?.let { Base64.encodeToString(it, Base64.NO_WRAP) },
                mlDsa = keyBundle.mlDsaPublicKey.takeIf { it.isNotEmpty() }?.let { Base64.encodeToString(it, Base64.NO_WRAP) }
            )

            val request = CreateRecoveryRequestRequest(
                newPublicKey = Base64.encodeToString(keyBundle.kazKemPublicKey, Base64.NO_WRAP),
                reason = reason
            )

            val response = apiService.createRecoveryRequest(request)

            if (response.isSuccessful) {
                val recoveryRequest = response.body()!!.data.toDomain()
                Result.success(recoveryRequest)
            } else {
                when (response.code()) {
                    404 -> Result.error(AppException.NotFound("No recovery config found"))
                    409 -> Result.error(AppException.ValidationError("Recovery request already pending"))
                    else -> Result.error(AppException.Unknown("Failed to initiate recovery"))
                }
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to initiate recovery", e))
        }
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
        return try {
            // Get the recovery request to get the requester's new public keys
            val requestResponse = apiService.getRecoveryRequest(requestId)
            if (!requestResponse.isSuccessful) {
                return Result.error(AppException.NotFound("Recovery request not found"))
            }

            val recoveryRequest = requestResponse.body()!!.data.request

            // Get the share to decrypt
            val sharesResponse = apiService.getTrusteeShares()
            if (!sharesResponse.isSuccessful) {
                return Result.error(AppException.Unknown("Failed to get shares"))
            }

            val shareDto = sharesResponse.body()!!.data.find { it.id == shareId }
                ?: return Result.error(AppException.NotFound("Share not found"))

            // Decrypt the share
            val share = recoveryKeyManager.decryptShareAsTrustee(
                encryptedShare = shareDto.encryptedShare,
                kemCiphertext = shareDto.kemCiphertext,
                mlKemCiphertext = shareDto.mlKemCiphertext
            )

            // Get requester's new public keys (from the request)
            val requesterPublicKey = Base64.decode(recoveryRequest.newPublicKey, Base64.NO_WRAP)
            // For simplicity, we'll use just the KEM key here
            // In production, the full PublicKeysDto should be sent with the request
            val requesterPublicKeys = PublicKeys(
                kem = requesterPublicKey,
                sign = requesterPublicKey, // Placeholder
                mlKem = null,
                mlDsa = null
            )

            // Re-encrypt share for requester
            val reencryptedResult = recoveryKeyManager.reencryptShareForRequester(
                share = share,
                requesterPublicKeys = requesterPublicKeys,
                requestId = requestId,
                shareId = shareId
            )

            // Submit approval
            val request = ApproveRecoveryRequest(
                shareId = shareId,
                reencryptedShare = reencryptedResult.encryptedShare,
                kemCiphertext = reencryptedResult.kemCiphertext,
                mlKemCiphertext = reencryptedResult.mlKemCiphertext,
                signature = reencryptedResult.signature
            )

            val response = apiService.approveRecoveryRequest(requestId, request)

            if (response.isSuccessful) {
                val approval = response.body()!!.data
                Result.success(RecoveryApproval(
                    id = approval.id,
                    requestId = approval.requestId,
                    shareId = approval.shareId,
                    approverId = approval.approverId,
                    createdAt = Instant.parse(approval.insertedAt)
                ))
            } else {
                when (response.code()) {
                    404 -> Result.error(AppException.NotFound("Request or share not found"))
                    409 -> Result.error(AppException.ValidationError("Already approved"))
                    else -> Result.error(AppException.Unknown("Failed to approve request"))
                }
            }
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to approve request", e))
        }
    }

    override suspend fun completeRecovery(
        requestId: String,
        password: String
    ): Result<Unit> {
        return try {
            // This would:
            // 1. Fetch all approvals with re-encrypted shares
            // 2. Decrypt each share using the new private keys
            // 3. Reconstruct the master key using Shamir
            // 4. Generate new key material encrypted with password
            // 5. Submit to server to update user credentials

            // For now, return not implemented
            Result.error(AppException.Unknown("Recovery completion not fully implemented"))
        } catch (e: Exception) {
            Result.error(AppException.Network("Failed to complete recovery", e))
        }
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

    private fun com.securesharing.data.remote.dto.RecoveryConfigDto.toDomain(): RecoveryConfig {
        return RecoveryConfig(
            id = id,
            userId = userId,
            threshold = threshold,
            totalShares = totalShares,
            status = RecoveryConfigStatus.fromString(status),
            createdAt = Instant.parse(insertedAt),
            updatedAt = Instant.parse(updatedAt)
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
            createdAt = Instant.parse(insertedAt),
            updatedAt = Instant.parse(updatedAt)
        )
    }

    private fun com.securesharing.data.remote.dto.RecoveryRequestDto.toDomain(): RecoveryRequest {
        return RecoveryRequest(
            id = id,
            userId = userId,
            status = RecoveryRequestStatus.fromString(status),
            reason = reason,
            user = user?.toDomain(),
            progress = null,
            createdAt = Instant.parse(insertedAt),
            updatedAt = Instant.parse(updatedAt)
        )
    }

    private fun com.securesharing.data.remote.dto.UserDto.toDomain(): User {
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
