package my.ssdid.drive.presentation.sharing

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import my.ssdid.drive.domain.model.FileItem
import my.ssdid.drive.domain.model.SharePermission
import my.ssdid.drive.domain.model.User
import my.ssdid.drive.domain.repository.FileRepository
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

data class ShareFileUiState(
    val file: FileItem? = null,
    val searchQuery: String = "",
    val searchResults: List<User> = emptyList(),
    val selectedUser: User? = null,
    val selectedPermission: SharePermission = SharePermission.READ,
    val expiryDays: Int? = null,
    val isLoading: Boolean = false,
    val isSearching: Boolean = false,
    val isSharing: Boolean = false,
    val error: String? = null,
    val shareSuccess: Boolean = false
)

@HiltViewModel
class ShareFileViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val fileRepository: FileRepository,
    private val shareRepository: ShareRepository
) : ViewModel() {

    private val fileId: String = checkNotNull(savedStateHandle[Screen.ARG_FILE_ID])

    private val _uiState = MutableStateFlow(ShareFileUiState())
    val uiState: StateFlow<ShareFileUiState> = _uiState.asStateFlow()

    private var searchJob: Job? = null

    init {
        loadFile()
    }

    private fun loadFile() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }

            fileRepository.getFile(fileId).fold(
                onSuccess = { file ->
                    _uiState.update { it.copy(file = file, isLoading = false) }
                },
                onFailure = { exception ->
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            error = exception.message ?: "Failed to load file"
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

    fun onExpiryChanged(days: Int?) {
        _uiState.update { it.copy(expiryDays = days) }
    }

    fun shareFile() {
        val user = _uiState.value.selectedUser ?: return

        viewModelScope.launch {
            _uiState.update { it.copy(isSharing = true, error = null) }

            val expiresAt = _uiState.value.expiryDays?.let {
                Instant.now().plus(it.toLong(), ChronoUnit.DAYS)
            }

            shareRepository.shareFile(
                fileId = fileId,
                grantee = user,
                permission = _uiState.value.selectedPermission,
                expiresAt = expiresAt
            ).fold(
                onSuccess = {
                    _uiState.update { it.copy(isSharing = false, shareSuccess = true) }
                },
                onFailure = { exception ->
                    _uiState.update {
                        it.copy(
                            isSharing = false,
                            error = exception.message ?: "Failed to share file"
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
