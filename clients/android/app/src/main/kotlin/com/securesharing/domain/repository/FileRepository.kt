package com.securesharing.domain.repository

import android.net.Uri
import com.securesharing.domain.model.FileItem
import com.securesharing.util.Result
import kotlinx.coroutines.flow.Flow

/**
 * Repository interface for file operations.
 */
interface FileRepository {

    /**
     * Get files in a folder.
     */
    suspend fun getFiles(folderId: String): Result<List<FileItem>>

    /**
     * Observe files in a folder.
     */
    fun observeFiles(folderId: String): Flow<List<FileItem>>

    /**
     * Get a file by ID.
     */
    suspend fun getFile(fileId: String): Result<FileItem>

    /**
     * Observe a file by ID.
     */
    fun observeFile(fileId: String): Flow<FileItem?>

    /**
     * Upload a file to a folder.
     * Returns a flow that emits progress updates.
     */
    fun uploadFile(
        folderId: String,
        uri: Uri,
        fileName: String
    ): Flow<UploadProgress>

    /**
     * Download a file.
     * Returns a flow that emits progress updates.
     */
    fun downloadFile(fileId: String): Flow<DownloadProgress>

    /**
     * Delete a file.
     */
    suspend fun deleteFile(fileId: String): Result<Unit>

    /**
     * Move a file to a different folder.
     */
    suspend fun moveFile(
        fileId: String,
        newFolderId: String
    ): Result<FileItem>

    /**
     * Rename a file.
     */
    suspend fun renameFile(
        fileId: String,
        newName: String
    ): Result<FileItem>

    /**
     * Upload a file from a local path (for background sync).
     * Uses a callback for progress updates instead of a Flow.
     */
    suspend fun uploadFile(
        localPath: String,
        folderId: String,
        fileName: String,
        mimeType: String,
        onProgress: (Int) -> Unit = {}
    ): Result<FileItem>

    /**
     * Sync files in a folder from the server.
     */
    suspend fun syncFiles(folderId: String): Result<Unit>

    /**
     * Search for files by name across all folders.
     */
    suspend fun searchFiles(query: String): Result<List<FileItem>>
}

sealed class UploadProgress {
    data class Started(val fileId: String) : UploadProgress()
    data class Progress(val bytesUploaded: Long, val totalBytes: Long) : UploadProgress()
    data class Completed(val file: FileItem) : UploadProgress()
    data class Failed(val error: Throwable) : UploadProgress()
}

sealed class DownloadProgress {
    data object Started : DownloadProgress()
    data class Progress(val bytesDownloaded: Long, val totalBytes: Long) : DownloadProgress()
    data class Completed(val uri: Uri) : DownloadProgress()
    data class Failed(val error: Throwable) : DownloadProgress()
}
