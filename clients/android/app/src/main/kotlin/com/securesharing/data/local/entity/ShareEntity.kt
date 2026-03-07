package com.securesharing.data.local.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import java.time.Instant

@Entity(
    tableName = "shares",
    indices = [
        Index("grantor_id"),
        Index("grantee_id"),
        Index("resource_type", "resource_id")
    ]
)
data class ShareEntity(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String,

    @ColumnInfo(name = "grantor_id")
    val grantorId: String,

    @ColumnInfo(name = "grantee_id")
    val granteeId: String,

    @ColumnInfo(name = "resource_type")
    val resourceType: String,

    @ColumnInfo(name = "resource_id")
    val resourceId: String,

    @ColumnInfo(name = "permission")
    val permission: String,

    @ColumnInfo(name = "wrapped_key", typeAffinity = ColumnInfo.BLOB)
    val wrappedKey: ByteArray,

    @ColumnInfo(name = "kem_ciphertext", typeAffinity = ColumnInfo.BLOB)
    val kemCiphertext: ByteArray,

    @ColumnInfo(name = "signature", typeAffinity = ColumnInfo.BLOB)
    val signature: ByteArray,

    @ColumnInfo(name = "recursive")
    val recursive: Boolean?,

    @ColumnInfo(name = "expires_at")
    val expiresAt: Instant?,

    @ColumnInfo(name = "revoked_at")
    val revokedAt: Instant?,

    // Cached grantor/grantee names for display
    @ColumnInfo(name = "grantor_email")
    val grantorEmail: String?,

    @ColumnInfo(name = "grantee_email")
    val granteeEmail: String?,

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
        other as ShareEntity
        return id == other.id
    }

    override fun hashCode(): Int = id.hashCode()
}
