package my.ssdid.drive.presentation.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import my.ssdid.drive.domain.model.CreatedInvitation
import my.ssdid.drive.domain.model.UserRole
import my.ssdid.drive.domain.repository.TenantRepository
import my.ssdid.drive.util.Result
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class CreateInvitationUiState(
    val email: String = "",
    val emailError: String? = null,
    val selectedRole: UserRole = UserRole.USER,
    val message: String = "",
    val isCreating: Boolean = false,
    val error: String? = null,
    val createdInvitation: CreatedInvitation? = null,
    val currentUserRole: UserRole = UserRole.USER
)

@HiltViewModel
class CreateInvitationViewModel @Inject constructor(
    private val tenantRepository: TenantRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(CreateInvitationUiState())
    val uiState: StateFlow<CreateInvitationUiState> = _uiState.asStateFlow()

    init {
        loadCurrentUserRole()
    }

    private fun loadCurrentUserRole() {
        viewModelScope.launch {
            val context = tenantRepository.getCurrentTenantContext()
            context?.let {
                _uiState.update { state ->
                    state.copy(currentUserRole = it.currentRole)
                }
            }
        }
    }

    fun updateEmail(email: String) {
        _uiState.update {
            it.copy(
                email = email,
                emailError = null
            )
        }
    }

    fun updateRole(role: UserRole) {
        _uiState.update { it.copy(selectedRole = role) }
    }

    fun updateMessage(message: String) {
        if (message.length <= 500) {
            _uiState.update { it.copy(message = message) }
        }
    }

    fun createInvitation() {
        val state = _uiState.value

        // Validate email if provided
        if (state.email.isNotBlank()) {
            val emailRegex = "^[A-Za-z0-9+_.-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$".toRegex()
            if (!emailRegex.matches(state.email)) {
                _uiState.update { it.copy(emailError = "Invalid email format") }
                return
            }
        }

        viewModelScope.launch {
            _uiState.update { it.copy(isCreating = true, error = null) }

            val email = state.email.ifBlank { null }
            val message = state.message.ifBlank { null }

            when (val result = tenantRepository.createInvitation(
                email = email,
                role = state.selectedRole,
                message = message
            )) {
                is Result.Success -> {
                    _uiState.update {
                        it.copy(
                            isCreating = false,
                            createdInvitation = result.data
                        )
                    }
                }
                is Result.Error -> {
                    _uiState.update {
                        it.copy(
                            isCreating = false,
                            error = result.exception.message ?: "Failed to create invitation"
                        )
                    }
                }
            }
        }
    }

    fun resetForm() {
        _uiState.update {
            CreateInvitationUiState(currentUserRole = it.currentUserRole)
        }
    }

    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }
}
