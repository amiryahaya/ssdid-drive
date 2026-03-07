package com.securesharing.data.local.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import java.time.Instant

@Entity(
    tableName = "folders",
    indices = [
        Index("parent_id"),
        Index("owner_id"),
        Index("tenant_id")
    ]
)
data class FolderEntity(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String,

    @ColumnInfo(name = "parent_id")
    val parentId: String?,

    @ColumnInfo(name = "owner_id")
    val ownerId: String,

    @ColumnInfo(name = "tenant_id")
    val tenantId: String,

    @ColumnInfo(name = "is_root")
    val isRoot: Boolean,

    @ColumnInfo(name = "encrypted_metadata", typeAffinity = ColumnInfo.BLOB)
    val encryptedMetadata: ByteArray,

    @ColumnInfo(name = "wrapped_kek", typeAffinity = ColumnInfo.BLOB)
    val wrappedKek: ByteArray,

    @ColumnInfo(name = "kem_ciphertext", typeAffinity = ColumnInfo.BLOB)
    val kemCiphertext: ByteArray,

    @ColumnInfo(name = "signature", typeAffinity = ColumnInfo.BLOB)
    val signature: ByteArray,

    // Cached decrypted name (for display)
    @ColumnInfo(name = "cached_name")
    val cachedName: String?,

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
        other as FolderEntity
        return id == other.id
    }

    override fun hashCode(): Int = id.hashCode()
}
