package com.securesharing.data.local.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import java.time.Instant

@Entity(
    tableName = "users",
    indices = [
        Index("tenant_id"),
        Index("email")
    ]
)
data class UserEntity(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String,

    @ColumnInfo(name = "email")
    val email: String,

    @ColumnInfo(name = "tenant_id")
    val tenantId: String,

    @ColumnInfo(name = "role")
    val role: String,

    @ColumnInfo(name = "public_key_kem")
    val publicKeyKem: String?,

    @ColumnInfo(name = "public_key_sign")
    val publicKeySign: String?,

    @ColumnInfo(name = "public_key_ml_kem")
    val publicKeyMlKem: String?,

    @ColumnInfo(name = "public_key_ml_dsa")
    val publicKeyMlDsa: String?,

    @ColumnInfo(name = "synced_at")
    val syncedAt: Instant = Instant.now()
)
