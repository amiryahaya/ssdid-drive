package my.ssdid.drive.data.remote.dto

import com.google.gson.annotations.SerializedName

// ==================== Request DTOs ====================

data class SetupRecoveryRequest(
    @SerializedName("server_share") val serverShare: String,
    @SerializedName("key_proof") val keyProof: String
)

data class CompleteRecoveryRequest(
    @SerializedName("old_did") val oldDid: String,
    @SerializedName("new_did") val newDid: String,
    @SerializedName("key_proof") val keyProof: String,
    @SerializedName("kem_public_key") val kemPublicKey: String
)

data class TrusteeShareEntry(
    @SerializedName("trustee_user_id") val trusteeUserId: String,
    @SerializedName("encrypted_share") val encryptedShare: String,
    @SerializedName("share_index") val shareIndex: Int
)

data class SetupTrusteesRequest(
    @SerializedName("threshold") val threshold: Int,
    @SerializedName("shares") val shares: List<TrusteeShareEntry>
)

data class CreateRecoveryRequestBody(
    @SerializedName("did") val did: String
)

// ==================== Response DTOs ====================

data class RecoveryStatusResponse(
    @SerializedName("is_active") val isActive: Boolean,
    @SerializedName("created_at") val createdAt: String?
)

data class ServerShareResponse(
    @SerializedName("server_share") val serverShare: String,
    @SerializedName("share_index") val shareIndex: Int
)

data class CompleteRecoveryResponse(
    val token: String,
    @SerializedName("user_id") val userId: String
)

data class SetupTrusteesResponse(
    @SerializedName("trustee_count") val trusteeCount: Int,
    @SerializedName("threshold") val threshold: Int
)

data class TrusteeDto(
    @SerializedName("id") val id: String,
    @SerializedName("trustee_user_id") val trusteeUserId: String,
    @SerializedName("display_name") val displayName: String?,
    @SerializedName("email") val email: String?,
    @SerializedName("share_index") val shareIndex: Int,
    @SerializedName("created_at") val createdAt: String
)

data class ListTrusteesResponse(
    @SerializedName("trustees") val trustees: List<TrusteeDto>,
    @SerializedName("threshold") val threshold: Int
)

data class RecoveryRequestResponse(
    @SerializedName("request_id") val requestId: String,
    @SerializedName("status") val status: String,
    @SerializedName("required_count") val requiredCount: Int,
    @SerializedName("expires_at") val expiresAt: String
)

data class MyRecoveryRequestData(
    @SerializedName("id") val id: String,
    @SerializedName("status") val status: String,
    @SerializedName("approved_shares") val approvedShares: Int,
    @SerializedName("required_shares") val requiredShares: Int,
    @SerializedName("expires_at") val expiresAt: String,
    @SerializedName("created_at") val createdAt: String
)

data class MyRecoveryRequestResponse(
    @SerializedName("request") val request: MyRecoveryRequestData?
)

data class PendingRecoveryRequestDto(
    @SerializedName("id") val id: String,
    @SerializedName("requester_name") val requesterName: String?,
    @SerializedName("requester_email") val requesterEmail: String?,
    @SerializedName("status") val status: String,
    @SerializedName("approved_count") val approvedCount: Int,
    @SerializedName("required_count") val requiredCount: Int,
    @SerializedName("expires_at") val expiresAt: String,
    @SerializedName("created_at") val createdAt: String
)

data class PendingRequestsResponse(
    @SerializedName("requests") val requests: List<PendingRecoveryRequestDto>
)

data class ApproveRequestResponse(
    @SerializedName("request_id") val requestId: String,
    @SerializedName("status") val status: String,
    @SerializedName("approved_count") val approvedCount: Int,
    @SerializedName("required_count") val requiredCount: Int
)

data class RejectRequestResponse(
    @SerializedName("request_id") val requestId: String,
    @SerializedName("status") val status: String,
    @SerializedName("decision") val decision: String
)

data class ReleasedShareDto(
    @SerializedName("trustee_user_id") val trusteeUserId: String,
    @SerializedName("encrypted_share") val encryptedShare: String,
    @SerializedName("share_index") val shareIndex: Int
)

data class ReleasedSharesResponse(
    @SerializedName("request_id") val requestId: String,
    @SerializedName("status") val status: String,
    @SerializedName("shares") val shares: List<ReleasedShareDto>
)
