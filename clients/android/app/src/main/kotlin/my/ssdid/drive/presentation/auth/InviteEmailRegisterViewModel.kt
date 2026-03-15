package my.ssdid.drive.presentation.auth

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
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
 * UI state for invitation email registration.
 */
data class InviteEmailRegisterUiState(
    val token: String = "",
    val email: String = "",
    val code: String = "",
    val isLoading: Boolean = false,
    val isOtpSent: Boolean = false,
    val isRegistered: Boolean = false,
    val error: String? = null
)

/**
 * ViewModel for email-based invitation registration.
 *
 * Flow:
 * 1. User enters email
 * 2. App calls emailRegister(email, invitationToken) to send OTP
 * 3. User enters OTP code
 * 4. App calls emailRegisterVerify(email, code, invitationToken) to complete registration
 */
@HiltViewModel
class InviteEmailRegisterViewModel @Inject constructor(
    private val authRepository: AuthRepository,
    savedStateHandle: SavedStateHandle
) : ViewModel() {

    private val _uiState = MutableStateFlow(InviteEmailRegisterUiState())
    val uiState: StateFlow<InviteEmailRegisterUiState> = _uiState.asStateFlow()

    init {
        val token = savedStateHandle.get<String>("token") ?: ""
        _uiState.update { it.copy(token = token) }
    }

    fun updateEmail(email: String) {
        _uiState.update { it.copy(email = email, error = null) }
    }

    fun updateCode(code: String) {
        _uiState.update { it.copy(code = code, error = null) }
    }

    /**
     * Send OTP to the entered email for invitation registration.
     */
    fun submitEmail() {
        val state = _uiState.value
        if (state.email.isBlank()) return

        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }
            when (val result = authRepository.emailRegister(state.email, state.token)) {
                is Result.Success -> {
                    _uiState.update { it.copy(isLoading = false, isOtpSent = true) }
                }
                is Result.Error -> {
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            error = result.exception.message ?: "Failed to send verification code"
                        )
                    }
                }
            }
        }
    }

    /**
     * Verify the OTP code to complete email registration with invitation.
     */
    fun submitCode() {
        val state = _uiState.value
        if (state.code.isBlank()) return

        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }
            when (val result = authRepository.emailRegisterVerify(state.email, state.code, state.token)) {
                is Result.Success -> {
                    _uiState.update { it.copy(isLoading = false, isRegistered = true) }
                }
                is Result.Error -> {
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            error = result.exception.message ?: "Verification failed"
                        )
                    }
                }
            }
        }
    }
}
