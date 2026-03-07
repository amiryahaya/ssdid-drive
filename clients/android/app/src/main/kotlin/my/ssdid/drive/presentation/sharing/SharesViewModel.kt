package my.ssdid.drive.presentation.sharing

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import my.ssdid.drive.domain.model.Share
import my.ssdid.drive.domain.repository.ShareRepository
import my.ssdid.drive.util.Result
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class SharesUiState(
    val receivedShares: List<Share> = emptyList(),
    val createdShares: List<Share> = emptyList(),
    val isLoading: Boolean = false,
    val error: String? = null
)

@HiltViewModel
class SharesViewModel @Inject constructor(
    private val shareRepository: ShareRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(SharesUiState())
    val uiState: StateFlow<SharesUiState> = _uiState.asStateFlow()

    fun loadReceivedShares() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }

            when (val result = shareRepository.getReceivedShares()) {
                is Result.Success -> {
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            receivedShares = result.data
                        )
                    }
                }
                is Result.Error -> {
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            error = result.exception.message
                        )
                    }
                }
            }
        }
    }

    fun loadCreatedShares() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }

            when (val result = shareRepository.getCreatedShares()) {
                is Result.Success -> {
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            createdShares = result.data
                        )
                    }
                }
                is Result.Error -> {
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            error = result.exception.message
                        )
                    }
                }
            }
        }
    }

    fun revokeShare(shareId: String) {
        viewModelScope.launch {
            when (val result = shareRepository.revokeShare(shareId)) {
                is Result.Success -> {
                    // Remove from list
                    _uiState.update {
                        it.copy(
                            createdShares = it.createdShares.filter { s -> s.id != shareId }
                        )
                    }
                }
                is Result.Error -> {
                    _uiState.update { it.copy(error = result.exception.message) }
                }
            }
        }
    }
}
