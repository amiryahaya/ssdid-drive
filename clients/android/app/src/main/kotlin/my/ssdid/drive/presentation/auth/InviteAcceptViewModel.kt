package my.ssdid.drive.presentation.auth

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import my.ssdid.drive.crypto.SecureMemory
import my.ssdid.drive.domain.model.TokenInvitation
import my.ssdid.drive.domain.model.TokenInvitationError
import my.ssdid.drive.domain.repository.AuthRepository
import my.ssdid.drive.util.Result
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * UI state for the invitation acceptance screen.
 */
data class InviteAcceptUiState(
    // Invitation info
    val token: String = "",
    val invitation: TokenInvitation? = null,
    val isLoadingInvitation: Boolean = true,
    val invitationError: String? = null,

    // Registration form
    val displayName: String = "",
    val password: String = "",
    val confirmPassword: String = "",

    // Registration state
    val isRegistering: Boolean = false,
    val isGeneratingKeys: Boolean = false,
    val isRegistered: Boolean = false,
    val registrationError: String? = null
)

/**
 * ViewModel for handling invitation acceptance and registration.
 */
@HiltViewModel
class InviteAcceptViewModel @Inject constructor(
    private val authRepository: AuthRepository,
    savedStateHandle: SavedStateHandle
) : ViewModel() {

    private val _uiState = MutableStateFlow(InviteAcceptUiState())
    val uiState: StateFlow<InviteAcceptUiState> = _uiState.asStateFlow()

    init {
        // Get token from navigation arguments
        val token = savedStateHandle.get<String>("token") ?: ""
        _uiState.update { it.copy(token = token) }

        if (token.isNotBlank()) {
            loadInvitationInfo(token)
        } else {
            _uiState.update {
                it.copy(
                    isLoadingInvitation = false,
                    invitationError = "Invalid invitation link"
                )
            }
        }
    }

    /**
     * Load invitation info from token.
     */
    private fun loadInvitationInfo(token: String) {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoadingInvitation = true, invitationError = null) }

            when (val result = authRepository.getInvitationInfo(token)) {
                is Result.Success -> {
                    val invitation = result.data
                    if (invitation.valid) {
                        _uiState.update {
                            it.copy(
                                isLoadingInvitation = false,
                                invitation = invitation
                            )
                        }
                    } else {
                        // Invitation is invalid
                        val errorMessage = when (invitation.errorReason) {
                            TokenInvitationError.EXPIRED -> "This invitation has expired"
                            TokenInvitationError.REVOKED -> "This invitation has been revoked"
                            TokenInvitationError.ALREADY_USED -> "This invitation has already been used"
                            TokenInvitationError.NOT_FOUND -> "Invitation not found"
                            null -> "This invitation is no longer valid"
                        }
                        _uiState.update {
                            it.copy(
                                isLoadingInvitation = false,
                                invitation = invitation,
                                invitationError = errorMessage
                            )
                        }
                    }
                }
                is Result.Error -> {
                    _uiState.update {
                        it.copy(
                            isLoadingInvitation = false,
                            invitationError = result.exception.message ?: "Failed to load invitation"
                        )
                    }
                }
            }
        }
    }

    /**
     * Retry loading invitation info.
     */
    fun retryLoadInvitation() {
        val token = _uiState.value.token
        if (token.isNotBlank()) {
            loadInvitationInfo(token)
        }
    }

    fun updateDisplayName(name: String) {
        _uiState.update { it.copy(displayName = name, registrationError = null) }
    }

    fun updatePassword(password: String) {
        _uiState.update { it.copy(password = password, registrationError = null) }
    }

    fun updateConfirmPassword(confirmPassword: String) {
        _uiState.update { it.copy(confirmPassword = confirmPassword, registrationError = null) }
    }

    /**
     * Accept the invitation and register the account.
     */
    fun acceptInvitation() {
        val state = _uiState.value

        // Validate inputs
        if (state.displayName.isBlank()) {
            _uiState.update { it.copy(registrationError = "Name is required") }
            return
        }
        if (state.displayName.length > 100) {
            _uiState.update { it.copy(registrationError = "Name is too long") }
            return
        }
        if (state.password.isBlank()) {
            _uiState.update { it.copy(registrationError = "Password is required") }
            return
        }
        if (state.password.length < 8) {
            _uiState.update { it.copy(registrationError = "Password must be at least 8 characters") }
            return
        }
        if (state.password != state.confirmPassword) {
            _uiState.update { it.copy(registrationError = "Passwords do not match") }
            return
        }

        viewModelScope.launch {
            _uiState.update {
                it.copy(
                    isRegistering = true,
                    isGeneratingKeys = true,
                    registrationError = null
                )
            }

            // SECURITY: Convert password to CharArray for secure handling
            val passwordChars = state.password.toCharArray()

            try {
                when (val result = authRepository.acceptInvitation(
                    token = state.token,
                    displayName = state.displayName,
                    password = passwordChars
                )) {
                    is Result.Success -> {
                        _uiState.update {
                            it.copy(
                                isRegistering = false,
                                isGeneratingKeys = false,
                                isRegistered = true,
                                password = "",
                                confirmPassword = ""
                            )
                        }
                    }
                    is Result.Error -> {
                        _uiState.update {
                            it.copy(
                                isRegistering = false,
                                isGeneratingKeys = false,
                                registrationError = result.exception.message ?: "Registration failed"
                            )
                        }
                    }
                }
            } finally {
                // SECURITY: Zeroize password CharArray after use
                SecureMemory.zeroize(passwordChars)
            }
        }
    }

    /**
     * Clear sensitive data when ViewModel is cleared.
     */
    override fun onCleared() {
        super.onCleared()
        // Clear passwords from UI state
        _uiState.update { it.copy(password = "", confirmPassword = "") }
    }
}
