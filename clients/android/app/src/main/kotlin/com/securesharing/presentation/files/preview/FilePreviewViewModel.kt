package com.securesharing.presentation.files.preview

import android.content.Context
import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.securesharing.domain.model.FileItem
import com.securesharing.util.FavoritesManager
import com.securesharing.domain.repository.FileRepository
import com.securesharing.util.Result
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.io.File
import javax.inject.Inject

data class FilePreviewUiState(
    val file: FileItem? = null,
    val decryptedUri: Uri? = null,
    val textContent: String? = null,
    val isLoading: Boolean = false,
    val loadingMessage: String? = null,
    val error: String? = null,
    val message: String? = null,
    val isFavorite: Boolean = false
)

@HiltViewModel
class FilePreviewViewModel @Inject constructor(
    @ApplicationContext private val context: Context,
    private val fileRepository: FileRepository,
    private val favoritesManager: FavoritesManager
) : ViewModel() {

    private val _uiState = MutableStateFlow(FilePreviewUiState())
    val uiState: StateFlow<FilePreviewUiState> = _uiState.asStateFlow()

    private val cacheDir: File = File(context.cacheDir, "preview_cache").apply {
        if (!exists()) mkdirs()
    }

    fun loadFile(fileId: String) {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null, loadingMessage = "Loading file info...") }

            // Load file metadata
            when (val result = fileRepository.getFile(fileId)) {
                is Result.Success -> {
                    val file = result.data
                    val isFavorite = favoritesManager.isFileFavorite(fileId).first()
                    _uiState.update {
                        it.copy(
                            file = file,
                            isFavorite = isFavorite,
                            loadingMessage = "Decrypting file..."
                        )
                    }

                    // Check if file is cached
                    val cachedFile = getCachedFile(fileId, file.name)
                    if (cachedFile.exists()) {
                        handleDecryptedFile(file, cachedFile)
                    } else {
                        // Download and decrypt
                        downloadAndDecrypt(fileId, file)
                    }
                }
                is Result.Error -> {
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            error = result.exception.message ?: "Failed to load file"
                        )
                    }
                }
            }
        }
    }

    private suspend fun downloadAndDecrypt(fileId: String, file: FileItem) {
        // Collect download progress
        fileRepository.downloadFile(fileId).collect { progress ->
            when (progress) {
                is com.securesharing.domain.repository.DownloadProgress.Started -> {
                    _uiState.update { it.copy(loadingMessage = "Starting download...") }
                }
                is com.securesharing.domain.repository.DownloadProgress.Progress -> {
                    val percent = (progress.bytesDownloaded * 100 / progress.totalBytes).toInt()
                    _uiState.update { it.copy(loadingMessage = "Downloading: $percent%") }
                }
                is com.securesharing.domain.repository.DownloadProgress.Completed -> {
                    // Copy to cache
                    val cachedFile = getCachedFile(fileId, file.name)
                    try {
                        context.contentResolver.openInputStream(progress.uri)?.use { input ->
                            cachedFile.outputStream().use { output ->
                                input.copyTo(output)
                            }
                        }
                        handleDecryptedFile(file, cachedFile)
                    } catch (e: Exception) {
                        _uiState.update {
                            it.copy(
                                isLoading = false,
                                error = "Failed to cache file: ${e.message}"
                            )
                        }
                    }
                }
                is com.securesharing.domain.repository.DownloadProgress.Failed -> {
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            error = progress.error.message ?: "Download failed"
                        )
                    }
                }
            }
        }
    }

    private fun handleDecryptedFile(file: FileItem, cachedFile: File) {
        val uri = Uri.fromFile(cachedFile)

        when {
            file.isText() -> {
                // Read text content
                val content = try {
                    cachedFile.readText()
                } catch (e: Exception) {
                    null
                }
                _uiState.update {
                    it.copy(
                        isLoading = false,
                        decryptedUri = uri,
                        textContent = content
                    )
                }
            }
            else -> {
                _uiState.update {
                    it.copy(
                        isLoading = false,
                        decryptedUri = uri
                    )
                }
            }
        }
    }

    private fun getCachedFile(fileId: String, fileName: String): File {
        return File(cacheDir, "${fileId}_$fileName")
    }

    fun toggleFavorite() {
        val currentFile = _uiState.value.file ?: return

        viewModelScope.launch {
            favoritesManager.toggleFileFavorite(currentFile.id)
            val newFavoriteState = favoritesManager.isFileFavorite(currentFile.id).first()
            _uiState.update {
                it.copy(
                    isFavorite = newFavoriteState,
                    message = if (newFavoriteState) "Added to favorites" else "Removed from favorites"
                )
            }
        }
    }

    fun clearMessage() {
        _uiState.update { it.copy(message = null) }
    }

    override fun onCleared() {
        super.onCleared()
        // Optionally clear cache when ViewModel is destroyed
        // cacheDir.deleteRecursively()
    }
}
