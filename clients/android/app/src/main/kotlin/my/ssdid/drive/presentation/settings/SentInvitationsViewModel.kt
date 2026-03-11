package my.ssdid.drive.presentation.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import my.ssdid.drive.domain.model.SentInvitation
import my.ssdid.drive.domain.repository.TenantRepository
import my.ssdid.drive.util.Result
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class SentInvitationsUiState(
    val invitations: List<SentInvitation> = emptyList(),
    val isLoading: Boolean = false,
    val isRevoking: Boolean = false,
    val error: String? = null,
    val successMessage: String? = null
)

@HiltViewModel
class SentInvitationsViewModel @Inject constructor(
    private val tenantRepository: TenantRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(SentInvitationsUiState())
    val uiState: StateFlow<SentInvitationsUiState> = _uiState.asStateFlow()

    init {
        loadSentInvitations()
    }

    fun loadSentInvitations() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }

            when (val result = tenantRepository.getSentInvitations()) {
                is Result.Success -> {
                    _uiState.update {
                        it.copy(
                            invitations = result.data,
                            isLoading = false
                        )
                    }
                }
                is Result.Error -> {
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            error = result.exception.message ?: "Failed to load sent invitations"
                        )
                    }
                }
            }
        }
    }

    fun revokeInvitation(invitationId: String) {
        viewModelScope.launch {
            _uiState.update { it.copy(isRevoking = true, error = null) }

            when (val result = tenantRepository.revokeInvitation(invitationId)) {
                is Result.Success -> {
                    _uiState.update {
                        it.copy(
                            isRevoking = false,
                            successMessage = "Invitation revoked"
                        )
                    }
                    loadSentInvitations()
                }
                is Result.Error -> {
                    _uiState.update {
                        it.copy(
                            isRevoking = false,
                            error = result.exception.message ?: "Failed to revoke invitation"
                        )
                    }
                }
            }
        }
    }

    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }

    fun clearSuccessMessage() {
        _uiState.update { it.copy(successMessage = null) }
    }

    fun showCopiedMessage() {
        _uiState.update { it.copy(successMessage = "Code copied to clipboard") }
    }
}
