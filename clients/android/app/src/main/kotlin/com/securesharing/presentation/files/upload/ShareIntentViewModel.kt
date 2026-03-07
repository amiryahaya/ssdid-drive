package com.securesharing.presentation.files.upload

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.securesharing.domain.model.Folder
import com.securesharing.domain.repository.FileRepository
import com.securesharing.domain.repository.FolderRepository
import com.securesharing.domain.repository.UploadProgress
import com.securesharing.util.Result
import com.securesharing.util.ShareIntentManager
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class PendingFile(
    val uri: Uri,
    val name: String,
    val size: Long,
    val mimeType: String
)

data class ShareIntentUiState(
    val pendingFiles: List<PendingFile> = emptyList(),
    val folders: List<Folder> = emptyList(),
    val selectedFolderId: String? = null,
    val selectedFolderName: String = "Select folder",
    val isLoadingFolders: Boolean = false,
    val isUploading: Boolean = false,
    val uploadProgress: Int = 0,
    val uploadTotal: Int = 0,
    val currentFileName: String? = null,
    val uploadComplete: Boolean = false,
    val successCount: Int = 0,
    val failCount: Int = 0,
    val error: String? = null,
    val showFolderPicker: Boolean = false
)

@HiltViewModel
class ShareIntentViewModel @Inject constructor(
    @ApplicationContext private val context: Context,
    private val shareIntentManager: ShareIntentManager,
    private val fileRepository: FileRepository,
    private val folderRepository: FolderRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(ShareIntentUiState())
    val uiState: StateFlow<ShareIntentUiState> = _uiState.asStateFlow()

    init {
        loadPendingFiles()
        loadFolders()
    }

    private fun loadPendingFiles() {
        val uris = shareIntentManager.pendingUris.value
        val pendingFiles = uris.mapNotNull { uri ->
            getFileInfo(uri)
        }
        _uiState.update {
            it.copy(
                pendingFiles = pendingFiles,
                uploadTotal = pendingFiles.size
            )
        }
    }

    private fun getFileInfo(uri: Uri): PendingFile? {
        return try {
            context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)

                    val name = if (nameIndex >= 0) cursor.getString(nameIndex) else "Unknown"
                    val size = if (sizeIndex >= 0) cursor.getLong(sizeIndex) else 0L
                    val mimeType = context.contentResolver.getType(uri) ?: "*/*"

                    PendingFile(
                        uri = uri,
                        name = name,
                        size = size,
                        mimeType = mimeType
                    )
                } else null
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun loadFolders() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoadingFolders = true) }

            // First get the root folder as default
            when (val rootResult = folderRepository.getRootFolder()) {
                is Result.Success -> {
                    _uiState.update {
                        it.copy(
                            selectedFolderId = rootResult.data.id,
                            selectedFolderName = rootResult.data.name
                        )
                    }
                }
                is Result.Error -> {
                    // Continue without default
                }
            }

            // Load all folders for picker
            when (val result = folderRepository.getAllFolders()) {
                is Result.Success -> {
                    _uiState.update {
                        it.copy(
                            folders = result.data,
                            isLoadingFolders = false
                        )
                    }
                }
                is Result.Error -> {
                    _uiState.update {
                        it.copy(
                            isLoadingFolders = false,
                            error = "Failed to load folders"
                        )
                    }
                }
            }
        }
    }

    fun showFolderPicker() {
        _uiState.update { it.copy(showFolderPicker = true) }
    }

    fun hideFolderPicker() {
        _uiState.update { it.copy(showFolderPicker = false) }
    }

    fun selectFolder(folder: Folder) {
        _uiState.update {
            it.copy(
                selectedFolderId = folder.id,
                selectedFolderName = folder.name,
                showFolderPicker = false
            )
        }
    }

    fun removeFile(uri: Uri) {
        _uiState.update { state ->
            val updated = state.pendingFiles.filter { it.uri != uri }
            state.copy(
                pendingFiles = updated,
                uploadTotal = updated.size
            )
        }
    }

    fun uploadFiles() {
        val folderId = _uiState.value.selectedFolderId
        if (folderId == null) {
            _uiState.update { it.copy(error = "Please select a destination folder") }
            return
        }

        val files = _uiState.value.pendingFiles
        if (files.isEmpty()) {
            _uiState.update { it.copy(error = "No files to upload") }
            return
        }

        viewModelScope.launch {
            _uiState.update {
                it.copy(
                    isUploading = true,
                    uploadProgress = 0,
                    error = null
                )
            }

            var successCount = 0
            var failCount = 0

            files.forEachIndexed { index, file ->
                _uiState.update {
                    it.copy(
                        uploadProgress = index + 1,
                        currentFileName = file.name
                    )
                }

                try {
                    fileRepository.uploadFile(folderId, file.uri, file.name).collect { progress ->
                        when (progress) {
                            is UploadProgress.Completed -> successCount++
                            is UploadProgress.Failed -> failCount++
                            else -> { /* progress updates */ }
                        }
                    }
                } catch (e: Exception) {
                    failCount++
                }
            }

            // Clear pending files from manager
            shareIntentManager.clearPendingFiles()

            _uiState.update {
                it.copy(
                    isUploading = false,
                    uploadComplete = true,
                    successCount = successCount,
                    failCount = failCount,
                    currentFileName = null,
                    error = if (failCount > 0) "$failCount file(s) failed to upload" else null
                )
            }
        }
    }

    fun cancel() {
        shareIntentManager.clearPendingFiles()
    }

    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }

    fun formatFileSize(bytes: Long): String {
        return when {
            bytes < 1024 -> "$bytes B"
            bytes < 1024 * 1024 -> "${bytes / 1024} KB"
            bytes < 1024 * 1024 * 1024 -> "${bytes / (1024 * 1024)} MB"
            else -> "${bytes / (1024 * 1024 * 1024)} GB"
        }
    }
}
