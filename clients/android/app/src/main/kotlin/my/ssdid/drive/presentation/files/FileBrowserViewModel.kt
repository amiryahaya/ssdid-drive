package my.ssdid.drive.presentation.files

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import my.ssdid.drive.data.sync.SyncManager
import my.ssdid.drive.data.sync.SyncState
import my.ssdid.drive.data.sync.SyncStatus
import my.ssdid.drive.domain.model.FileItem
import my.ssdid.drive.domain.model.Folder
import android.net.Uri
import my.ssdid.drive.domain.repository.DownloadProgress
import my.ssdid.drive.domain.repository.FileRepository
import my.ssdid.drive.domain.repository.FolderRepository
import my.ssdid.drive.domain.repository.UploadProgress
import my.ssdid.drive.util.FavoritesManager
import my.ssdid.drive.util.Result
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

enum class SortOption(val displayName: String) {
    NAME_ASC("Name (A-Z)"),
    NAME_DESC("Name (Z-A)"),
    DATE_NEW("Newest first"),
    DATE_OLD("Oldest first"),
    SIZE_LARGE("Largest first"),
    SIZE_SMALL("Smallest first"),
    TYPE("Type")
}

enum class ViewMode {
    LIST,
    GRID
}

data class FileBrowserUiState(
    val currentFolder: Folder? = null,
    val folders: List<Folder> = emptyList(),
    val files: List<FileItem> = emptyList(),
    val isLoading: Boolean = false,
    val error: String? = null,
    val showCreateFolderDialog: Boolean = false,
    // Multi-select state
    val isSelectionMode: Boolean = false,
    val selectedFolderIds: Set<String> = emptySet(),
    val selectedFileIds: Set<String> = emptySet(),
    // Bulk operations state
    val isBulkOperationInProgress: Boolean = false,
    val bulkOperationProgress: Int = 0,
    val bulkOperationTotal: Int = 0,
    val showMoveDialog: Boolean = false,
    val availableFoldersForMove: List<Folder> = emptyList(),
    val bulkOperationMessage: String? = null,
    // Search state
    val isSearchMode: Boolean = false,
    val searchQuery: String = "",
    val searchResults: List<FileItem> = emptyList(),
    val isSearching: Boolean = false,
    // Sort state
    val sortOption: SortOption = SortOption.NAME_ASC,
    // View mode
    val viewMode: ViewMode = ViewMode.LIST,
    // Favorites
    val favoriteFolderIds: Set<String> = emptySet(),
    val favoriteFileIds: Set<String> = emptySet(),
    val showFavoritesOnly: Boolean = false,
    // Upload state
    val isUploading: Boolean = false,
    val uploadProgress: Int = 0,
    val uploadFileName: String? = null
) {
    val selectedCount: Int get() = selectedFolderIds.size + selectedFileIds.size
    val hasSelection: Boolean get() = selectedCount > 0

    // Filtered and sorted folders
    val displayFolders: List<Folder> get() {
        var filtered = if (isSearchMode && searchQuery.isNotBlank()) {
            folders.filter { it.name.contains(searchQuery, ignoreCase = true) }
        } else {
            folders
        }
        // Apply favorites filter
        if (showFavoritesOnly) {
            filtered = filtered.filter { it.id in favoriteFolderIds }
        }
        return sortFolders(filtered)
    }

    // Filtered and sorted files
    val displayFiles: List<FileItem> get() {
        var filtered = if (isSearchMode && searchQuery.isNotBlank()) {
            if (searchResults.isNotEmpty()) searchResults
            else files.filter { it.name.contains(searchQuery, ignoreCase = true) }
        } else {
            files
        }
        // Apply favorites filter
        if (showFavoritesOnly) {
            filtered = filtered.filter { it.id in favoriteFileIds }
        }
        return sortFiles(filtered)
    }

    // Check if an item is a favorite
    fun isFolderFavorite(folderId: String): Boolean = folderId in favoriteFolderIds
    fun isFileFavorite(fileId: String): Boolean = fileId in favoriteFileIds

    private fun sortFolders(folders: List<Folder>): List<Folder> {
        return when (sortOption) {
            SortOption.NAME_ASC -> folders.sortedBy { it.name.lowercase() }
            SortOption.NAME_DESC -> folders.sortedByDescending { it.name.lowercase() }
            SortOption.DATE_NEW -> folders.sortedByDescending { it.updatedAt }
            SortOption.DATE_OLD -> folders.sortedBy { it.updatedAt }
            else -> folders.sortedBy { it.name.lowercase() }
        }
    }

    private fun sortFiles(files: List<FileItem>): List<FileItem> {
        return when (sortOption) {
            SortOption.NAME_ASC -> files.sortedBy { it.name.lowercase() }
            SortOption.NAME_DESC -> files.sortedByDescending { it.name.lowercase() }
            SortOption.DATE_NEW -> files.sortedByDescending { it.updatedAt }
            SortOption.DATE_OLD -> files.sortedBy { it.updatedAt }
            SortOption.SIZE_LARGE -> files.sortedByDescending { it.size }
            SortOption.SIZE_SMALL -> files.sortedBy { it.size }
            SortOption.TYPE -> files.sortedBy { it.mimeType }
        }
    }
}

@HiltViewModel
class FileBrowserViewModel @Inject constructor(
    private val folderRepository: FolderRepository,
    private val fileRepository: FileRepository,
    private val syncManager: SyncManager,
    private val favoritesManager: FavoritesManager
) : ViewModel() {

    private val _uiState = MutableStateFlow(FileBrowserUiState())
    val uiState: StateFlow<FileBrowserUiState> = _uiState.asStateFlow()

    val syncStatus: StateFlow<SyncStatus> = syncManager.observeSyncStatus()
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5000),
            initialValue = SyncStatus(SyncState.IDLE, 0, false)
        )

    init {
        // Schedule periodic sync when ViewModel is created
        syncManager.schedulePeriodicSync()

        // Observe favorites changes
        viewModelScope.launch {
            combine(
                favoritesManager.favoriteFolderIds,
                favoritesManager.favoriteFileIds
            ) { folderIds, fileIds ->
                Pair(folderIds, fileIds)
            }.collect { (folderIds, fileIds) ->
                _uiState.update {
                    it.copy(
                        favoriteFolderIds = folderIds,
                        favoriteFileIds = fileIds
                    )
                }
            }
        }
    }

    fun loadFolder(folderId: String?) {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }

            // Load folder (root or specific)
            val folderResult = if (folderId == null) {
                folderRepository.getRootFolder()
            } else {
                folderRepository.getFolder(folderId)
            }

            when (folderResult) {
                is Result.Success -> {
                    val folder = folderResult.data
                    _uiState.update { it.copy(currentFolder = folder) }

                    // Load children and files
                    loadFolderContents(folder.id)
                }
                is Result.Error -> {
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            error = folderResult.exception.message ?: DEFAULT_ERROR_MESSAGE
                        )
                    }
                }
            }
        }
    }

    private suspend fun loadFolderContents(folderId: String) {
        // Load child folders
        val foldersResult = folderRepository.getChildFolders(folderId)
        val folders = when (foldersResult) {
            is Result.Success -> foldersResult.data
            is Result.Error -> emptyList()
        }

        // Load files
        val filesResult = fileRepository.getFiles(folderId)
        val files = when (filesResult) {
            is Result.Success -> filesResult.data
            is Result.Error -> emptyList()
        }

        _uiState.update {
            it.copy(
                isLoading = false,
                folders = folders,
                files = files
            )
        }
    }

    fun showCreateFolderDialog() {
        _uiState.update { it.copy(showCreateFolderDialog = true) }
    }

    fun hideCreateFolderDialog() {
        _uiState.update { it.copy(showCreateFolderDialog = false) }
    }

    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }

    fun createFolder(name: String) {
        val currentFolder = _uiState.value.currentFolder ?: return

        viewModelScope.launch {
            _uiState.update { it.copy(showCreateFolderDialog = false) }

            when (val result = folderRepository.createFolder(currentFolder.id, name)) {
                is Result.Success -> {
                    // Reload folder contents
                    loadFolderContents(currentFolder.id)
                }
                is Result.Error -> {
                    _uiState.update {
                        it.copy(error = result.exception.message ?: "Failed to create folder")
                    }
                }
            }
        }
    }

    fun deleteFolder(folderId: String) {
        viewModelScope.launch {
            when (val result = folderRepository.deleteFolder(folderId)) {
                is Result.Success -> {
                    _uiState.value.currentFolder?.let { loadFolderContents(it.id) }
                }
                is Result.Error -> {
                    _uiState.update {
                        it.copy(error = result.exception.message ?: "Failed to delete folder")
                    }
                }
            }
        }
    }

    fun deleteFile(fileId: String) {
        viewModelScope.launch {
            when (val result = fileRepository.deleteFile(fileId)) {
                is Result.Success -> {
                    _uiState.value.currentFolder?.let { loadFolderContents(it.id) }
                }
                is Result.Error -> {
                    _uiState.update {
                        it.copy(error = result.exception.message ?: "Failed to delete file")
                    }
                }
            }
        }
    }

    // ==================== Sync Operations ====================

    fun triggerSync() {
        syncManager.triggerSync()
    }

    fun retryFailedSync() {
        viewModelScope.launch {
            syncManager.retryAllFailed()
        }
    }

    // ==================== Multi-Select Operations ====================

    fun enterSelectionMode() {
        _uiState.update { it.copy(isSelectionMode = true) }
    }

    fun exitSelectionMode() {
        _uiState.update {
            it.copy(
                isSelectionMode = false,
                selectedFolderIds = emptySet(),
                selectedFileIds = emptySet()
            )
        }
    }

    fun toggleFolderSelection(folderId: String) {
        _uiState.update { state ->
            val newSelection = if (folderId in state.selectedFolderIds) {
                state.selectedFolderIds - folderId
            } else {
                state.selectedFolderIds + folderId
            }
            state.copy(
                selectedFolderIds = newSelection,
                isSelectionMode = newSelection.isNotEmpty() || state.selectedFileIds.isNotEmpty()
            )
        }
    }

    fun toggleFileSelection(fileId: String) {
        _uiState.update { state ->
            val newSelection = if (fileId in state.selectedFileIds) {
                state.selectedFileIds - fileId
            } else {
                state.selectedFileIds + fileId
            }
            state.copy(
                selectedFileIds = newSelection,
                isSelectionMode = newSelection.isNotEmpty() || state.selectedFolderIds.isNotEmpty()
            )
        }
    }

    fun selectAll() {
        _uiState.update { state ->
            state.copy(
                selectedFolderIds = state.folders.map { it.id }.toSet(),
                selectedFileIds = state.files.map { it.id }.toSet(),
                isSelectionMode = true
            )
        }
    }

    fun clearSelection() {
        _uiState.update {
            it.copy(
                selectedFolderIds = emptySet(),
                selectedFileIds = emptySet()
            )
        }
    }

    fun deleteSelected() {
        viewModelScope.launch {
            val state = _uiState.value
            val currentFolderId = state.currentFolder?.id ?: return@launch

            var hasError = false

            // Delete selected folders
            for (folderId in state.selectedFolderIds) {
                when (folderRepository.deleteFolder(folderId)) {
                    is Result.Success -> { /* success */ }
                    is Result.Error -> { hasError = true }
                }
            }

            // Delete selected files
            for (fileId in state.selectedFileIds) {
                when (fileRepository.deleteFile(fileId)) {
                    is Result.Success -> { /* success */ }
                    is Result.Error -> { hasError = true }
                }
            }

            // Clear selection and reload
            exitSelectionMode()
            loadFolderContents(currentFolderId)

            if (hasError) {
                _uiState.update {
                    it.copy(error = "Some items could not be deleted")
                }
            }
        }
    }

    /**
     * Download all selected files.
     * Files are downloaded sequentially to avoid overwhelming the device.
     */
    fun downloadSelected() {
        viewModelScope.launch {
            val state = _uiState.value
            val selectedFileIds = state.selectedFileIds.toList()

            if (selectedFileIds.isEmpty()) {
                _uiState.update { it.copy(error = "No files selected for download") }
                return@launch
            }

            _uiState.update {
                it.copy(
                    isBulkOperationInProgress = true,
                    bulkOperationProgress = 0,
                    bulkOperationTotal = selectedFileIds.size,
                    bulkOperationMessage = "Downloading files..."
                )
            }

            var successCount = 0
            var failCount = 0

            selectedFileIds.forEachIndexed { index, fileId ->
                _uiState.update { it.copy(bulkOperationProgress = index + 1) }

                // Collect the download flow and wait for completion
                try {
                    fileRepository.downloadFile(fileId).collect { progress ->
                        when (progress) {
                            is DownloadProgress.Completed -> successCount++
                            is DownloadProgress.Failed -> failCount++
                            else -> { /* ignore intermediate states */ }
                        }
                    }
                } catch (e: Exception) {
                    failCount++
                }
            }

            // Clear selection and show result
            exitSelectionMode()
            _uiState.update {
                it.copy(
                    isBulkOperationInProgress = false,
                    bulkOperationMessage = null,
                    error = if (failCount > 0) {
                        "Downloaded $successCount files, $failCount failed"
                    } else {
                        null
                    }
                )
            }

            if (failCount == 0 && successCount > 0) {
                _uiState.update {
                    it.copy(bulkOperationMessage = "$successCount files downloaded successfully")
                }
            }
        }
    }

    /**
     * Show the move dialog with available destination folders.
     */
    fun showMoveDialog() {
        viewModelScope.launch {
            // Load all folders for selection
            when (val result = folderRepository.getAllFolders()) {
                is Result.Success -> {
                    val currentFolderId = _uiState.value.currentFolder?.id
                    // Filter out selected folders and current folder as destinations
                    val availableFolders = result.data.filter { folder ->
                        folder.id !in _uiState.value.selectedFolderIds &&
                        folder.id != currentFolderId
                    }
                    _uiState.update {
                        it.copy(
                            showMoveDialog = true,
                            availableFoldersForMove = availableFolders
                        )
                    }
                }
                is Result.Error -> {
                    _uiState.update {
                        it.copy(error = "Failed to load folders")
                    }
                }
            }
        }
    }

    /**
     * Hide the move dialog.
     */
    fun hideMoveDialog() {
        _uiState.update {
            it.copy(
                showMoveDialog = false,
                availableFoldersForMove = emptyList()
            )
        }
    }

    /**
     * Move all selected files and folders to the specified destination folder.
     */
    fun moveSelected(destinationFolderId: String) {
        viewModelScope.launch {
            val state = _uiState.value
            val currentFolderId = state.currentFolder?.id ?: return@launch
            val selectedFolders = state.selectedFolderIds.toList()
            val selectedFiles = state.selectedFileIds.toList()
            val totalItems = selectedFolders.size + selectedFiles.size

            if (totalItems == 0) {
                hideMoveDialog()
                return@launch
            }

            _uiState.update {
                it.copy(
                    showMoveDialog = false,
                    isBulkOperationInProgress = true,
                    bulkOperationProgress = 0,
                    bulkOperationTotal = totalItems,
                    bulkOperationMessage = "Moving items..."
                )
            }

            var successCount = 0
            var failCount = 0
            var progress = 0

            // Move selected folders
            for (folderId in selectedFolders) {
                progress++
                _uiState.update { it.copy(bulkOperationProgress = progress) }

                when (folderRepository.moveFolder(folderId, destinationFolderId)) {
                    is Result.Success -> successCount++
                    is Result.Error -> failCount++
                }
            }

            // Move selected files
            for (fileId in selectedFiles) {
                progress++
                _uiState.update { it.copy(bulkOperationProgress = progress) }

                when (fileRepository.moveFile(fileId, destinationFolderId)) {
                    is Result.Success -> successCount++
                    is Result.Error -> failCount++
                }
            }

            // Clear selection and reload
            exitSelectionMode()
            loadFolderContents(currentFolderId)

            _uiState.update {
                it.copy(
                    isBulkOperationInProgress = false,
                    bulkOperationMessage = null,
                    availableFoldersForMove = emptyList(),
                    error = if (failCount > 0) {
                        "Moved $successCount items, $failCount failed"
                    } else {
                        null
                    }
                )
            }
        }
    }

    /**
     * Get the list of selected file IDs for sharing.
     * Returns null if no files are selected (only folders).
     */
    fun getSelectedFileIdsForShare(): List<String>? {
        val state = _uiState.value
        val fileIds = state.selectedFileIds.toList()
        return if (fileIds.isEmpty()) null else fileIds
    }

    /**
     * Get the list of selected folder IDs for sharing.
     * Returns null if no folders are selected.
     */
    fun getSelectedFolderIdsForShare(): List<String>? {
        val state = _uiState.value
        val folderIds = state.selectedFolderIds.toList()
        return if (folderIds.isEmpty()) null else folderIds
    }

    /**
     * Clear bulk operation message.
     */
    fun clearBulkOperationMessage() {
        _uiState.update { it.copy(bulkOperationMessage = null) }
    }

    fun isFolderSelected(folderId: String): Boolean =
        _uiState.value.selectedFolderIds.contains(folderId)

    fun isFileSelected(fileId: String): Boolean =
        _uiState.value.selectedFileIds.contains(fileId)

    // ==================== Upload Operations ====================

    fun uploadFile(uri: Uri, fileName: String) {
        val currentFolderId = _uiState.value.currentFolder?.id ?: return

        viewModelScope.launch {
            _uiState.update {
                it.copy(
                    isUploading = true,
                    uploadProgress = 0,
                    uploadFileName = fileName
                )
            }

            fileRepository.uploadFile(currentFolderId, uri, fileName).collect { progress ->
                when (progress) {
                    is UploadProgress.Started -> {
                        _uiState.update { it.copy(uploadProgress = 0) }
                    }
                    is UploadProgress.Progress -> {
                        val percent = if (progress.totalBytes > 0) {
                            ((progress.bytesUploaded * 100) / progress.totalBytes).toInt()
                        } else 0
                        _uiState.update { it.copy(uploadProgress = percent) }
                    }
                    is UploadProgress.Completed -> {
                        _uiState.update {
                            it.copy(
                                isUploading = false,
                                uploadProgress = 0,
                                uploadFileName = null,
                                files = it.files + progress.file,
                                bulkOperationMessage = "File uploaded successfully"
                            )
                        }
                    }
                    is UploadProgress.Failed -> {
                        _uiState.update {
                            it.copy(
                                isUploading = false,
                                uploadProgress = 0,
                                uploadFileName = null,
                                error = progress.error.message ?: "Upload failed"
                            )
                        }
                    }
                }
            }
        }
    }

    // ==================== Search Operations ====================

    fun enterSearchMode() {
        _uiState.update { it.copy(isSearchMode = true, searchQuery = "") }
    }

    fun exitSearchMode() {
        _uiState.update {
            it.copy(
                isSearchMode = false,
                searchQuery = "",
                searchResults = emptyList()
            )
        }
    }

    fun updateSearchQuery(query: String) {
        _uiState.update { it.copy(searchQuery = query) }

        // If query is long enough, perform global search
        if (query.length >= 2) {
            searchFiles(query)
        } else {
            _uiState.update { it.copy(searchResults = emptyList()) }
        }
    }

    private fun searchFiles(query: String) {
        viewModelScope.launch {
            _uiState.update { it.copy(isSearching = true) }

            // Search across all files
            when (val result = fileRepository.searchFiles(query)) {
                is Result.Success -> {
                    _uiState.update {
                        it.copy(
                            searchResults = result.data,
                            isSearching = false
                        )
                    }
                }
                is Result.Error -> {
                    // Fall back to local filtering only
                    _uiState.update { it.copy(isSearching = false) }
                }
            }
        }
    }

    // ==================== Sort Operations ====================

    fun setSortOption(option: SortOption) {
        _uiState.update { it.copy(sortOption = option) }
    }

    // ==================== View Mode Operations ====================

    fun setViewMode(mode: ViewMode) {
        _uiState.update { it.copy(viewMode = mode) }
    }

    fun toggleViewMode() {
        _uiState.update {
            it.copy(viewMode = if (it.viewMode == ViewMode.LIST) ViewMode.GRID else ViewMode.LIST)
        }
    }

    // ==================== Favorites Operations ====================

    fun toggleFolderFavorite(folderId: String) {
        viewModelScope.launch {
            favoritesManager.toggleFolderFavorite(folderId)
        }
    }

    fun toggleFileFavorite(fileId: String) {
        viewModelScope.launch {
            favoritesManager.toggleFileFavorite(fileId)
        }
    }

    fun setShowFavoritesOnly(show: Boolean) {
        _uiState.update { it.copy(showFavoritesOnly = show) }
    }

    fun toggleShowFavoritesOnly() {
        _uiState.update { it.copy(showFavoritesOnly = !it.showFavoritesOnly) }
    }

    companion object {
        private const val DEFAULT_ERROR_MESSAGE = "An unexpected error occurred. Please try again."
    }
}
