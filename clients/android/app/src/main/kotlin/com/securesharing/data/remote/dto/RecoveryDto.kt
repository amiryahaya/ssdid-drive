package com.securesharing.data.remote.dto

import com.google.gson.annotations.SerializedName

// ==================== Request DTOs ====================

data class SetupRecoveryRequest(
    @SerializedName("threshold") val threshold: Int,
    @SerializedName("total_shares") val totalShares: Int
)

data class CreateRecoveryShareRequest(
    @SerializedName("trustee_id") val trusteeId: String,
    @SerializedName("share_index") val shareIndex: Int,
    @SerializedName("encrypted_share") val encryptedShare: String,
    @SerializedName("kem_ciphertext") val kemCiphertext: String,
    @SerializedName("ml_kem_ciphertext") val mlKemCiphertext: String?,
    @SerializedName("signature") val signature: String
)

data class CreateRecoveryRequestRequest(
    @SerializedName("new_public_key") val newPublicKey: String,
    @SerializedName("reason") val reason: String?
)

data class ApproveRecoveryRequest(
    @SerializedName("share_id") val shareId: String,
    @SerializedName("reencrypted_share") val reencryptedShare: String,
    @SerializedName("kem_ciphertext") val kemCiphertext: String,
    @SerializedName("ml_kem_ciphertext") val mlKemCiphertext: String?,
    @SerializedName("signature") val signature: String
)

data class CompleteRecoveryRequest(
    @SerializedName("encrypted_master_key") val encryptedMasterKey: String,
    @SerializedName("encrypted_private_keys") val encryptedPrivateKeys: String,
    @SerializedName("key_derivation_salt") val keyDerivationSalt: String,
    @SerializedName("public_keys") val publicKeys: PublicKeysDto
)

// ==================== Response DTOs ====================

data class RecoveryConfigResponse(
    @SerializedName("data") val data: RecoveryConfigDto?
)

data class RecoveryShareResponse(
    @SerializedName("data") val data: RecoveryShareDto
)

data class RecoverySharesResponse(
    @SerializedName("data") val data: List<RecoveryShareDto>
)

data class RecoveryRequestResponse(
    @SerializedName("data") val data: RecoveryRequestDto
)

data class RecoveryRequestsResponse(
    @SerializedName("data") val data: List<RecoveryRequestDto>
)

data class RecoveryRequestDetailResponse(
    @SerializedName("data") val data: RecoveryRequestDetailDto
)

data class RecoveryApprovalResponse(
    @SerializedName("data") val data: RecoveryApprovalDto
)

// ==================== Recovery DTOs ====================

data class RecoveryConfigDto(
    @SerializedName("id") val id: String,
    @SerializedName("user_id") val userId: String,
    @SerializedName("threshold") val threshold: Int,
    @SerializedName("total_shares") val totalShares: Int,
    @SerializedName("status") val status: String,
    @SerializedName("inserted_at") val insertedAt: String,
    @SerializedName("updated_at") val updatedAt: String
)

data class RecoveryShareDto(
    @SerializedName("id") val id: String,
    @SerializedName("config_id") val configId: String,
    @SerializedName("grantor_id") val grantorId: String,
    @SerializedName("trustee_id") val trusteeId: String,
    @SerializedName("share_index") val shareIndex: Int,
    @SerializedName("encrypted_share") val encryptedShare: String,
    @SerializedName("kem_ciphertext") val kemCiphertext: String,
    @SerializedName("ml_kem_ciphertext") val mlKemCiphertext: String?,
    @SerializedName("signature") val signature: String,
    @SerializedName("status") val status: String,
    @SerializedName("grantor") val grantor: UserDto?,
    @SerializedName("trustee") val trustee: UserDto?,
    @SerializedName("grantor_public_keys") val grantorPublicKeys: PublicKeysDto?,
    @SerializedName("inserted_at") val insertedAt: String,
    @SerializedName("updated_at") val updatedAt: String
)

data class RecoveryRequestDto(
    @SerializedName("id") val id: String,
    @SerializedName("user_id") val userId: String,
    @SerializedName("status") val status: String,
    @SerializedName("new_public_key") val newPublicKey: String,
    @SerializedName("reason") val reason: String?,
    @SerializedName("user") val user: UserDto?,
    @SerializedName("inserted_at") val insertedAt: String,
    @SerializedName("updated_at") val updatedAt: String
)

data class RecoveryRequestDetailDto(
    @SerializedName("request") val request: RecoveryRequestDto,
    @SerializedName("progress") val progress: RecoveryProgressDto
)

data class RecoveryProgressDto(
    @SerializedName("threshold") val threshold: Int,
    @SerializedName("approvals") val approvals: Int,
    @SerializedName("remaining") val remaining: Int
)

data class RecoveryApprovalDto(
    @SerializedName("id") val id: String,
    @SerializedName("request_id") val requestId: String,
    @SerializedName("share_id") val shareId: String,
    @SerializedName("approver_id") val approverId: String,
    @SerializedName("reencrypted_share") val reencryptedShare: String,
    @SerializedName("kem_ciphertext") val kemCiphertext: String,
    @SerializedName("ml_kem_ciphertext") val mlKemCiphertext: String?,
    @SerializedName("signature") val signature: String,
    @SerializedName("inserted_at") val insertedAt: String
)
