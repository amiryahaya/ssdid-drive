package com.securesharing.presentation.tenant

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.securesharing.domain.model.InviteCodeInfo
import com.securesharing.domain.repository.TenantRepository
import com.securesharing.util.Result
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * UI state for the Join Tenant screen.
 */
data class JoinTenantUiState(
    val code: String = "",
    val isLookingUp: Boolean = false,
    val inviteInfo: InviteCodeInfo? = null,
    val lookupError: String? = null,
    val isJoining: Boolean = false,
    val joinError: String? = null,
    val isJoined: Boolean = false
)

/**
 * ViewModel for the "Enter Invite Code" / "Join Tenant" screen.
 *
 * Two-step flow:
 * 1. User enters short code -> lookupCode() -> shows preview card
 * 2. User confirms -> joinTenant() -> accepts invitation
 */
@HiltViewModel
class JoinTenantViewModel @Inject constructor(
    private val tenantRepository: TenantRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(JoinTenantUiState())
    val uiState: StateFlow<JoinTenantUiState> = _uiState.asStateFlow()

    /**
     * Update the invite code text field.
     * Auto-uppercases and trims whitespace.
     */
    fun updateCode(code: String) {
        _uiState.update {
            it.copy(
                code = code.uppercase().trim(),
                lookupError = null,
                joinError = null
            )
        }
    }

    /**
     * Look up the invite code to show a preview.
     */
    fun lookupCode() {
        val code = _uiState.value.code
        if (code.isBlank()) {
            _uiState.update { it.copy(lookupError = "Please enter an invite code") }
            return
        }

        viewModelScope.launch {
            _uiState.update {
                it.copy(
                    isLookingUp = true,
                    lookupError = null,
                    inviteInfo = null
                )
            }

            when (val result = tenantRepository.lookupInviteCode(code)) {
                is Result.Success -> {
                    _uiState.update {
                        it.copy(
                            isLookingUp = false,
                            inviteInfo = result.data
                        )
                    }
                }
                is Result.Error -> {
                    _uiState.update {
                        it.copy(
                            isLookingUp = false,
                            lookupError = result.exception.message ?: "Invalid invite code"
                        )
                    }
                }
            }
        }
    }

    /**
     * Accept the invitation and join the tenant.
     * Requires the user to be logged in.
     */
    fun joinTenant() {
        val info = _uiState.value.inviteInfo ?: return

        viewModelScope.launch {
            _uiState.update {
                it.copy(isJoining = true, joinError = null)
            }

            when (val result = tenantRepository.acceptInvitationById(info.id)) {
                is Result.Success -> {
                    _uiState.update {
                        it.copy(
                            isJoining = false,
                            isJoined = true
                        )
                    }
                }
                is Result.Error -> {
                    _uiState.update {
                        it.copy(
                            isJoining = false,
                            joinError = result.exception.message ?: "Failed to join tenant"
                        )
                    }
                }
            }
        }
    }

    /**
     * Clear the preview and go back to code entry.
     */
    fun clearPreview() {
        _uiState.update {
            it.copy(
                inviteInfo = null,
                lookupError = null,
                joinError = null
            )
        }
    }
}
