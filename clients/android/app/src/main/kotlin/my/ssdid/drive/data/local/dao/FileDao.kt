package my.ssdid.drive.data.local.dao

import androidx.paging.PagingSource
import androidx.room.*
import my.ssdid.drive.data.local.entity.FileEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface FileDao {

    @Query("SELECT * FROM files WHERE id = :id")
    suspend fun getById(id: String): FileEntity?

    @Query("SELECT * FROM files WHERE id = :id")
    fun observeById(id: String): Flow<FileEntity?>

    @Query("SELECT * FROM files WHERE folder_id = :folderId ORDER BY cached_name ASC")
    suspend fun getByFolderId(folderId: String): List<FileEntity>

    @Query("SELECT * FROM files WHERE folder_id = :folderId ORDER BY cached_name ASC")
    fun observeByFolderId(folderId: String): Flow<List<FileEntity>>

    // Paginated query for large folders
    @Query("SELECT * FROM files WHERE folder_id = :folderId ORDER BY cached_name ASC")
    fun getByFolderIdPaged(folderId: String): PagingSource<Int, FileEntity>

    // Paginated query sorted by date
    @Query("SELECT * FROM files WHERE folder_id = :folderId ORDER BY updated_at DESC")
    fun getByFolderIdPagedByDate(folderId: String): PagingSource<Int, FileEntity>

    // Paginated query sorted by size
    @Query("SELECT * FROM files WHERE folder_id = :folderId ORDER BY blob_size DESC")
    fun getByFolderIdPagedBySize(folderId: String): PagingSource<Int, FileEntity>

    @Query("SELECT * FROM files WHERE owner_id = :ownerId ORDER BY updated_at DESC")
    suspend fun getByOwnerId(ownerId: String): List<FileEntity>

    // Paginated by owner
    @Query("SELECT * FROM files WHERE owner_id = :ownerId ORDER BY updated_at DESC")
    fun getByOwnerIdPaged(ownerId: String): PagingSource<Int, FileEntity>

    @Query("SELECT * FROM files WHERE status = :status ORDER BY updated_at DESC")
    suspend fun getByStatus(status: String): List<FileEntity>

    // Optimized search query with LIKE pattern
    @Query("SELECT * FROM files WHERE cached_name LIKE '%' || :query || '%' COLLATE NOCASE ORDER BY cached_name ASC")
    suspend fun searchByName(query: String): List<FileEntity>

    // Paginated search
    @Query("SELECT * FROM files WHERE cached_name LIKE '%' || :query || '%' COLLATE NOCASE ORDER BY cached_name ASC")
    fun searchByNamePaged(query: String): PagingSource<Int, FileEntity>

    // Count query for UI without loading full list
    @Query("SELECT COUNT(*) FROM files WHERE folder_id = :folderId")
    suspend fun countByFolderId(folderId: String): Int

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(file: FileEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(files: List<FileEntity>)

    @Update
    suspend fun update(file: FileEntity)

    @Delete
    suspend fun delete(file: FileEntity)

    @Query("DELETE FROM files WHERE id = :id")
    suspend fun deleteById(id: String)

    // Transaction for deleting folder and its files together
    @Transaction
    @Query("DELETE FROM files WHERE folder_id = :folderId")
    suspend fun deleteByFolderId(folderId: String)

    @Query("DELETE FROM files")
    suspend fun deleteAll()

    // Batch operations with transaction
    @Transaction
    suspend fun replaceAllInFolder(folderId: String, files: List<FileEntity>) {
        deleteByFolderId(folderId)
        insertAll(files)
    }
}
