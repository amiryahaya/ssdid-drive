package com.securesharing.presentation.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.securesharing.domain.model.Invitation
import com.securesharing.domain.repository.TenantRepository
import com.securesharing.util.Result
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class InvitationsUiState(
    val invitations: List<Invitation> = emptyList(),
    val isLoading: Boolean = false,
    val isProcessing: Boolean = false,
    val error: String? = null,
    val successMessage: String? = null
)

@HiltViewModel
class InvitationsViewModel @Inject constructor(
    private val tenantRepository: TenantRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(InvitationsUiState())
    val uiState: StateFlow<InvitationsUiState> = _uiState.asStateFlow()

    init {
        loadInvitations()
    }

    fun loadInvitations() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }

            when (val result = tenantRepository.getPendingInvitations()) {
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
                            error = result.exception.message ?: "Failed to load invitations"
                        )
                    }
                }
            }
        }
    }

    fun acceptInvitation(invitationId: String) {
        viewModelScope.launch {
            _uiState.update { it.copy(isProcessing = true, error = null) }

            when (val result = tenantRepository.acceptInvitation(invitationId)) {
                is Result.Success -> {
                    _uiState.update {
                        it.copy(
                            isProcessing = false,
                            successMessage = "Invitation accepted! You can now switch to the new organization."
                        )
                    }
                    // Reload invitations
                    loadInvitations()
                }
                is Result.Error -> {
                    _uiState.update {
                        it.copy(
                            isProcessing = false,
                            error = result.exception.message ?: "Failed to accept invitation"
                        )
                    }
                }
            }
        }
    }

    fun declineInvitation(invitationId: String) {
        viewModelScope.launch {
            _uiState.update { it.copy(isProcessing = true, error = null) }

            when (val result = tenantRepository.declineInvitation(invitationId)) {
                is Result.Success -> {
                    _uiState.update {
                        it.copy(
                            isProcessing = false,
                            successMessage = "Invitation declined"
                        )
                    }
                    // Reload invitations
                    loadInvitations()
                }
                is Result.Error -> {
                    _uiState.update {
                        it.copy(
                            isProcessing = false,
                            error = result.exception.message ?: "Failed to decline invitation"
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
}
