package my.ssdid.drive.data.local.dao

import androidx.room.*
import my.ssdid.drive.data.local.entity.ShareEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface ShareDao {

    @Query("SELECT * FROM shares WHERE id = :id")
    suspend fun getById(id: String): ShareEntity?

    @Query("SELECT * FROM shares WHERE id = :id")
    fun observeById(id: String): Flow<ShareEntity?>

    @Query("SELECT * FROM shares WHERE grantee_id = :granteeId AND revoked_at IS NULL ORDER BY inserted_at DESC")
    suspend fun getReceivedShares(granteeId: String): List<ShareEntity>

    @Query("SELECT * FROM shares WHERE grantee_id = :granteeId AND revoked_at IS NULL ORDER BY inserted_at DESC")
    fun observeReceivedShares(granteeId: String): Flow<List<ShareEntity>>

    @Query("SELECT * FROM shares WHERE grantor_id = :grantorId ORDER BY inserted_at DESC")
    suspend fun getCreatedShares(grantorId: String): List<ShareEntity>

    @Query("SELECT * FROM shares WHERE grantor_id = :grantorId ORDER BY inserted_at DESC")
    fun observeCreatedShares(grantorId: String): Flow<List<ShareEntity>>

    @Query("SELECT * FROM shares WHERE resource_type = :resourceType AND resource_id = :resourceId AND revoked_at IS NULL")
    suspend fun getSharesForResource(resourceType: String, resourceId: String): List<ShareEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(share: ShareEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(shares: List<ShareEntity>)

    @Update
    suspend fun update(share: ShareEntity)

    @Delete
    suspend fun delete(share: ShareEntity)

    @Query("DELETE FROM shares WHERE id = :id")
    suspend fun deleteById(id: String)

    @Query("DELETE FROM shares")
    suspend fun deleteAll()
}
