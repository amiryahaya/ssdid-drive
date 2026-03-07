package my.ssdid.drive.data.remote.dto

import com.google.gson.annotations.SerializedName

// ==================== Request DTOs ====================

data class UploadUrlRequest(
    @SerializedName("folder_id") val folderId: String,
    @SerializedName("blob_size") val blobSize: Long,
    @SerializedName("encrypted_metadata") val encryptedMetadata: String,
    @SerializedName("wrapped_dek") val wrappedDek: String,
    @SerializedName("kem_ciphertext") val kemCiphertext: String?,
    @SerializedName("ml_kem_ciphertext") val mlKemCiphertext: String?,
    @SerializedName("signature") val signature: String,
    @SerializedName("chunk_count") val chunkCount: Int
)

data class UpdateFileRequest(
    @SerializedName("status") val status: String? = null,
    @SerializedName("blob_hash") val blobHash: String? = null,
    @SerializedName("blob_size") val blobSize: Long? = null,
    @SerializedName("chunk_count") val chunkCount: Int? = null,
    @SerializedName("encrypted_metadata") val encryptedMetadata: String? = null,
    @SerializedName("signature") val signature: String? = null
)

data class MoveFileRequest(
    @SerializedName("folder_id") val folderId: String,
    @SerializedName("wrapped_dek") val wrappedDek: String,
    @SerializedName("kem_ciphertext") val kemCiphertext: String?,
    @SerializedName("ml_kem_ciphertext") val mlKemCiphertext: String?,
    @SerializedName("signature") val signature: String
)

// ==================== Response DTOs ====================

data class FileResponse(
    @SerializedName("data") val data: FileDto
)

data class FilesResponse(
    @SerializedName("data") val data: List<FileDto>
)

data class UploadUrlResponse(
    @SerializedName("data") val data: UploadUrlData
)

data class UploadUrlData(
    @SerializedName("file") val file: FileDto,
    @SerializedName("upload_url") val uploadUrl: String
)

data class DownloadUrlResponse(
    @SerializedName("data") val data: DownloadUrlData
)

data class DownloadUrlData(
    @SerializedName("file") val file: FileDto,
    @SerializedName("download_url") val downloadUrl: String
)

// ==================== File DTOs ====================

data class FileDto(
    @SerializedName("id") val id: String,
    @SerializedName("folder_id") val folderId: String,
    @SerializedName("owner_id") val ownerId: String,
    @SerializedName("tenant_id") val tenantId: String,
    @SerializedName("storage_path") val storagePath: String?,
    @SerializedName("blob_size") val blobSize: Long?,
    @SerializedName("blob_hash") val blobHash: String?,
    @SerializedName("chunk_count") val chunkCount: Int?,
    @SerializedName("status") val status: String,
    @SerializedName("encrypted_metadata") val encryptedMetadata: String,
    @SerializedName("wrapped_dek") val wrappedDek: String,
    @SerializedName("kem_ciphertext") val kemCiphertext: String?,
    @SerializedName("ml_kem_ciphertext") val mlKemCiphertext: String?,
    @SerializedName("signature") val signature: String,
    @SerializedName("inserted_at") val insertedAt: String,
    @SerializedName("updated_at") val updatedAt: String,
    // Uploader's public keys for signature verification
    @SerializedName("uploader_public_keys") val uploaderPublicKeys: PublicKeysDto?
)
