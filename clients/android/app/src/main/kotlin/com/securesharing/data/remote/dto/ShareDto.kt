package com.securesharing.data.remote.dto

import com.google.gson.annotations.SerializedName

// ==================== Request DTOs ====================

data class ShareFileRequest(
    @SerializedName("file_id") val fileId: String,
    @SerializedName("grantee_id") val granteeId: String,
    @SerializedName("wrapped_key") val wrappedKey: String,
    @SerializedName("kem_ciphertext") val kemCiphertext: String,
    @SerializedName("ml_kem_ciphertext") val mlKemCiphertext: String?,
    @SerializedName("signature") val signature: String,
    @SerializedName("permission") val permission: String,
    @SerializedName("expires_at") val expiresAt: String? = null
)

data class ShareFolderRequest(
    @SerializedName("folder_id") val folderId: String,
    @SerializedName("grantee_id") val granteeId: String,
    @SerializedName("wrapped_key") val wrappedKey: String,
    @SerializedName("kem_ciphertext") val kemCiphertext: String,
    @SerializedName("ml_kem_ciphertext") val mlKemCiphertext: String?,
    @SerializedName("signature") val signature: String,
    @SerializedName("permission") val permission: String,
    @SerializedName("recursive") val recursive: Boolean = true,
    @SerializedName("expires_at") val expiresAt: String? = null
)

data class UpdatePermissionRequest(
    @SerializedName("permission") val permission: String,
    @SerializedName("signature") val signature: String
)

data class SetExpiryRequest(
    @SerializedName("expires_at") val expiresAt: String?
)

// ==================== Response DTOs ====================

data class ShareResponse(
    @SerializedName("data") val data: ShareDto
)

data class SharesResponse(
    @SerializedName("data") val data: List<ShareDto>
)

// ==================== Share DTOs ====================

data class ShareDto(
    @SerializedName("id") val id: String,
    @SerializedName("grantor_id") val grantorId: String,
    @SerializedName("grantee_id") val granteeId: String,
    @SerializedName("resource_type") val resourceType: String,
    @SerializedName("resource_id") val resourceId: String,
    @SerializedName("permission") val permission: String,
    @SerializedName("wrapped_key") val wrappedKey: String,
    @SerializedName("kem_ciphertext") val kemCiphertext: String,
    @SerializedName("ml_kem_ciphertext") val mlKemCiphertext: String?,
    @SerializedName("signature") val signature: String,
    @SerializedName("recursive") val recursive: Boolean?,
    @SerializedName("expires_at") val expiresAt: String?,
    @SerializedName("revoked_at") val revokedAt: String?,
    @SerializedName("grantor") val grantor: UserDto?,
    @SerializedName("grantee") val grantee: UserDto?,
    @SerializedName("grantor_public_keys") val grantorPublicKeys: PublicKeysDto?,
    @SerializedName("inserted_at") val insertedAt: String,
    @SerializedName("updated_at") val updatedAt: String
)
