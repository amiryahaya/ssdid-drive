package my.ssdid.drive.domain.repository

import my.ssdid.drive.domain.model.Folder
import my.ssdid.drive.util.Result
import kotlinx.coroutines.flow.Flow

/**
 * Repository interface for folder operations.
 */
interface FolderRepository {

    /**
     * Get the root folder for the current user.
     */
    suspend fun getRootFolder(): Result<Folder>

    /**
     * Observe the root folder.
     */
    fun observeRootFolder(): Flow<Folder?>

    /**
     * Get a folder by ID.
     */
    suspend fun getFolder(folderId: String): Result<Folder>

    /**
     * Observe a folder by ID.
     */
    fun observeFolder(folderId: String): Flow<Folder?>

    /**
     * Get child folders of a parent folder.
     */
    suspend fun getChildFolders(parentId: String): Result<List<Folder>>

    /**
     * Observe child folders of a parent folder.
     */
    fun observeChildFolders(parentId: String): Flow<List<Folder>>

    /**
     * Create a new folder.
     */
    suspend fun createFolder(
        parentId: String,
        name: String
    ): Result<Folder>

    /**
     * Rename a folder.
     */
    suspend fun renameFolder(
        folderId: String,
        newName: String
    ): Result<Folder>

    /**
     * Delete a folder and its contents.
     */
    suspend fun deleteFolder(folderId: String): Result<Unit>

    /**
     * Move a folder to a different parent folder.
     */
    suspend fun moveFolder(
        folderId: String,
        newParentId: String
    ): Result<Folder>

    /**
     * Sync folders from the server.
     */
    suspend fun syncFolders(): Result<Unit>

    /**
     * Get all folders for the current user.
     * Used for folder selection (e.g., move destination).
     */
    suspend fun getAllFolders(): Result<List<Folder>>
}
