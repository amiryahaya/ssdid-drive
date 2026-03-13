package my.ssdid.drive.data.remote.dto

import com.google.gson.annotations.SerializedName

// ==================== Request DTOs ====================

data class CreateFolderRequest(
    @SerializedName("parent_id") val parentId: String?,
    @SerializedName("name") val name: String? = null,
    @SerializedName("encrypted_metadata") val encryptedMetadata: String? = null,
    @SerializedName("metadata_nonce") val metadataNonce: String? = null,
    @SerializedName("wrapped_kek") val wrappedKek: String? = null,
    @SerializedName("kem_ciphertext") val kemCiphertext: String? = null,
    @SerializedName("owner_wrapped_kek") val ownerWrappedKek: String? = null,
    @SerializedName("owner_kem_ciphertext") val ownerKemCiphertext: String? = null,
    @SerializedName("ml_kem_ciphertext") val mlKemCiphertext: String? = null,
    @SerializedName("owner_ml_kem_ciphertext") val ownerMlKemCiphertext: String? = null,
    @SerializedName("signature") val signature: String? = null
)

data class UpdateFolderRequest(
    @SerializedName("encrypted_metadata") val encryptedMetadata: String? = null,
    @SerializedName("metadata_nonce") val metadataNonce: String? = null,
    @SerializedName("wrapped_kek") val wrappedKek: String? = null,
    @SerializedName("kem_ciphertext") val kemCiphertext: String? = null,
    @SerializedName("owner_wrapped_kek") val ownerWrappedKek: String? = null,
    @SerializedName("owner_kem_ciphertext") val ownerKemCiphertext: String? = null,
    @SerializedName("ml_kem_ciphertext") val mlKemCiphertext: String? = null,
    @SerializedName("owner_ml_kem_ciphertext") val ownerMlKemCiphertext: String? = null,
    @SerializedName("signature") val signature: String? = null
)

data class MoveFolderRequest(
    @SerializedName("parent_id") val parentId: String,
    @SerializedName("wrapped_kek") val wrappedKek: String,
    @SerializedName("kem_ciphertext") val kemCiphertext: String?,
    @SerializedName("signature") val signature: String?
)

// ==================== Response DTOs ====================

data class FolderResponse(
    @SerializedName("data") val data: FolderDto
)

data class FoldersResponse(
    @SerializedName("data") val data: List<FolderDto>
)

// ==================== Folder DTOs ====================

data class FolderDto(
    @SerializedName("id") val id: String,
    @SerializedName("parent_id") val parentId: String?,
    @SerializedName("owner_id") val ownerId: String,
    @SerializedName("tenant_id") val tenantId: String,
    @SerializedName("is_root") val isRoot: Boolean,
    @SerializedName("name") val name: String? = null,
    @SerializedName("encrypted_metadata") val encryptedMetadata: String?,
    @SerializedName("metadata_nonce") val metadataNonce: String?,
    @SerializedName("wrapped_kek") val wrappedKek: String,
    @SerializedName("kem_ciphertext") val kemCiphertext: String?,
    // Direct owner access (always available)
    @SerializedName("owner_wrapped_kek") val ownerWrappedKek: String,
    @SerializedName("owner_kem_ciphertext") val ownerKemCiphertext: String,
    // ML-KEM ciphertexts for NIST/HYBRID mode (optional)
    @SerializedName("ml_kem_ciphertext") val mlKemCiphertext: String? = null,
    @SerializedName("owner_ml_kem_ciphertext") val ownerMlKemCiphertext: String? = null,
    @SerializedName("signature") val signature: String?,
    @SerializedName("owner") val owner: FolderOwnerDto? = null,
    @SerializedName("created_at") val createdAt: String,
    @SerializedName("updated_at") val updatedAt: String
)

data class FolderOwnerDto(
    @SerializedName("id") val id: String,
    @SerializedName("public_keys") val publicKeys: PublicKeysDto
)
