package my.ssdid.drive.data.local.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import java.time.Instant

@Entity(
    tableName = "files",
    indices = [
        Index("folder_id"),
        Index("owner_id"),
        Index("tenant_id"),
        Index("status")
    ]
)
data class FileEntity(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String,

    @ColumnInfo(name = "folder_id")
    val folderId: String,

    @ColumnInfo(name = "owner_id")
    val ownerId: String,

    @ColumnInfo(name = "tenant_id")
    val tenantId: String,

    @ColumnInfo(name = "storage_path")
    val storagePath: String?,

    @ColumnInfo(name = "blob_size")
    val blobSize: Long?,

    @ColumnInfo(name = "blob_hash")
    val blobHash: String?,

    @ColumnInfo(name = "chunk_count")
    val chunkCount: Int?,

    @ColumnInfo(name = "status")
    val status: String,

    @ColumnInfo(name = "encrypted_metadata", typeAffinity = ColumnInfo.BLOB)
    val encryptedMetadata: ByteArray,

    @ColumnInfo(name = "wrapped_dek", typeAffinity = ColumnInfo.BLOB)
    val wrappedDek: ByteArray,

    @ColumnInfo(name = "kem_ciphertext", typeAffinity = ColumnInfo.BLOB)
    val kemCiphertext: ByteArray,

    @ColumnInfo(name = "signature", typeAffinity = ColumnInfo.BLOB)
    val signature: ByteArray,

    // Cached decrypted metadata (for display)
    @ColumnInfo(name = "cached_name")
    val cachedName: String?,

    @ColumnInfo(name = "cached_mime_type")
    val cachedMimeType: String?,

    @ColumnInfo(name = "inserted_at")
    val insertedAt: Instant,

    @ColumnInfo(name = "updated_at")
    val updatedAt: Instant,

    @ColumnInfo(name = "synced_at")
    val syncedAt: Instant = Instant.now()
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (javaClass != other?.javaClass) return false
        other as FileEntity
        return id == other.id
    }

    override fun hashCode(): Int = id.hashCode()
}
