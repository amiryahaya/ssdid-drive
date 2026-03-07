package my.ssdid.drive.presentation.sharing

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import my.ssdid.drive.domain.model.Folder
import my.ssdid.drive.domain.model.SharePermission
import my.ssdid.drive.domain.model.User
import my.ssdid.drive.domain.repository.FolderRepository
import my.ssdid.drive.domain.repository.ShareRepository
import my.ssdid.drive.presentation.navigation.Screen
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.temporal.ChronoUnit
import javax.inject.Inject

data class ShareFolderUiState(
    val folder: Folder? = null,
    val searchQuery: String = "",
    val searchResults: List<User> = emptyList(),
    val selectedUser: User? = null,
    val selectedPermission: SharePermission = SharePermission.READ,
    val recursive: Boolean = true,
    val expiryDays: Int? = null,
    val isLoading: Boolean = false,
    val isSearching: Boolean = false,
    val isSharing: Boolean = false,
    val error: String? = null,
    val shareSuccess: Boolean = false
)

@HiltViewModel
class ShareFolderViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val folderRepository: FolderRepository,
    private val shareRepository: ShareRepository
) : ViewModel() {

    private val folderId: String = checkNotNull(savedStateHandle[Screen.ARG_FOLDER_ID])

    private val _uiState = MutableStateFlow(ShareFolderUiState())
    val uiState: StateFlow<ShareFolderUiState> = _uiState.asStateFlow()

    private var searchJob: Job? = null

    init {
        loadFolder()
    }

    private fun loadFolder() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }

            folderRepository.getFolder(folderId).fold(
                onSuccess = { folder ->
                    _uiState.update { it.copy(folder = folder, isLoading = false) }
                },
                onFailure = { exception ->
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            error = exception.message ?: "Failed to load folder"
                        )
                    }
                }
            )
        }
    }

    fun onSearchQueryChanged(query: String) {
        _uiState.update { it.copy(searchQuery = query) }

        // Cancel previous search
        searchJob?.cancel()

        if (query.length < 2) {
            _uiState.update { it.copy(searchResults = emptyList(), isSearching = false) }
            return
        }

        searchJob = viewModelScope.launch {
            // Debounce search
            delay(300)

            _uiState.update { it.copy(isSearching = true) }

            shareRepository.searchUsers(query).fold(
                onSuccess = { users ->
                    _uiState.update { it.copy(searchResults = users, isSearching = false) }
                },
                onFailure = {
                    _uiState.update { it.copy(searchResults = emptyList(), isSearching = false) }
                }
            )
        }
    }

    fun onUserSelected(user: User) {
        _uiState.update {
            it.copy(
                selectedUser = user,
                searchQuery = "",
                searchResults = emptyList()
            )
        }
    }

    fun onUserCleared() {
        _uiState.update { it.copy(selectedUser = null) }
    }

    fun onPermissionSelected(permission: SharePermission) {
        _uiState.update { it.copy(selectedPermission = permission) }
    }

    fun onRecursiveChanged(recursive: Boolean) {
        _uiState.update { it.copy(recursive = recursive) }
    }

    fun onExpiryChanged(days: Int?) {
        _uiState.update { it.copy(expiryDays = days) }
    }

    fun shareFolder() {
        val user = _uiState.value.selectedUser ?: return

        viewModelScope.launch {
            _uiState.update { it.copy(isSharing = true, error = null) }

            val expiresAt = _uiState.value.expiryDays?.let {
                Instant.now().plus(it.toLong(), ChronoUnit.DAYS)
            }

            shareRepository.shareFolder(
                folderId = folderId,
                grantee = user,
                permission = _uiState.value.selectedPermission,
                recursive = _uiState.value.recursive,
                expiresAt = expiresAt
            ).fold(
                onSuccess = {
                    _uiState.update { it.copy(isSharing = false, shareSuccess = true) }
                },
                onFailure = { exception ->
                    _uiState.update {
                        it.copy(
                            isSharing = false,
                            error = exception.message ?: "Failed to share folder"
                        )
                    }
                }
            )
        }
    }

    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }
}
