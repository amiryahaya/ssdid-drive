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
