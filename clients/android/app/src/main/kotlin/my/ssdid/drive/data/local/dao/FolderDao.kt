package my.ssdid.drive.data.local.dao

import androidx.paging.PagingSource
import androidx.room.*
import my.ssdid.drive.data.local.entity.FolderEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface FolderDao {

    @Query("SELECT * FROM folders WHERE id = :id")
    suspend fun getById(id: String): FolderEntity?

    @Query("SELECT * FROM folders WHERE id = :id")
    fun observeById(id: String): Flow<FolderEntity?>

    @Query("SELECT * FROM folders WHERE is_root = 1 LIMIT 1")
    suspend fun getRootFolder(): FolderEntity?

    @Query("SELECT * FROM folders WHERE is_root = 1 LIMIT 1")
    fun observeRootFolder(): Flow<FolderEntity?>

    @Query("SELECT * FROM folders WHERE parent_id = :parentId ORDER BY cached_name ASC")
    suspend fun getChildren(parentId: String): List<FolderEntity>

    @Query("SELECT * FROM folders WHERE parent_id = :parentId ORDER BY cached_name ASC")
    fun observeChildren(parentId: String): Flow<List<FolderEntity>>

    // Paginated children query for large directories
    @Query("SELECT * FROM folders WHERE parent_id = :parentId ORDER BY cached_name ASC")
    fun getChildrenPaged(parentId: String): PagingSource<Int, FolderEntity>

    // Paginated children sorted by date
    @Query("SELECT * FROM folders WHERE parent_id = :parentId ORDER BY updated_at DESC")
    fun getChildrenPagedByDate(parentId: String): PagingSource<Int, FolderEntity>

    @Query("SELECT * FROM folders WHERE tenant_id = :tenantId ORDER BY cached_name ASC")
    suspend fun getAllForTenant(tenantId: String): List<FolderEntity>

    // Paginated tenant folders
    @Query("SELECT * FROM folders WHERE tenant_id = :tenantId ORDER BY cached_name ASC")
    fun getAllForTenantPaged(tenantId: String): PagingSource<Int, FolderEntity>

    // Search folders by name
    @Query("SELECT * FROM folders WHERE cached_name LIKE '%' || :query || '%' COLLATE NOCASE ORDER BY cached_name ASC")
    suspend fun searchByName(query: String): List<FolderEntity>

    // Paginated search
    @Query("SELECT * FROM folders WHERE cached_name LIKE '%' || :query || '%' COLLATE NOCASE ORDER BY cached_name ASC")
    fun searchByNamePaged(query: String): PagingSource<Int, FolderEntity>

    // Count children without loading full list
    @Query("SELECT COUNT(*) FROM folders WHERE parent_id = :parentId")
    suspend fun countChildren(parentId: String): Int

    // Get folder path (for breadcrumbs) - uses recursive CTE
    @Query("""
        WITH RECURSIVE ancestors AS (
            SELECT id, parent_id, cached_name, 0 as depth FROM folders WHERE id = :folderId
            UNION ALL
            SELECT f.id, f.parent_id, f.cached_name, a.depth + 1
            FROM folders f
            JOIN ancestors a ON f.id = a.parent_id
        )
        SELECT * FROM folders WHERE id IN (SELECT id FROM ancestors) ORDER BY (SELECT depth FROM ancestors WHERE ancestors.id = folders.id) DESC
    """)
    suspend fun getFolderPath(folderId: String): List<FolderEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(folder: FolderEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(folders: List<FolderEntity>)

    @Update
    suspend fun update(folder: FolderEntity)

    @Delete
    suspend fun delete(folder: FolderEntity)

    @Query("DELETE FROM folders WHERE id = :id")
    suspend fun deleteById(id: String)

    // Transaction for deleting children
    @Transaction
    @Query("DELETE FROM folders WHERE parent_id = :parentId")
    suspend fun deleteChildren(parentId: String)

    @Query("DELETE FROM folders")
    suspend fun deleteAll()

    // Batch operations with transaction
    @Transaction
    suspend fun replaceChildren(parentId: String, folders: List<FolderEntity>) {
        deleteChildren(parentId)
        insertAll(folders)
    }
}
