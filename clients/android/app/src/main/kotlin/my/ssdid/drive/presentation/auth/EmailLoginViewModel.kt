package my.ssdid.drive.presentation.auth

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

data class EmailLoginUiState(
    val email: String = "",
    val isLoading: Boolean = false,
    val error: String? = null,
    val navigateToTotp: String? = null
)

@HiltViewModel
class EmailLoginViewModel @Inject constructor(
    private val authRepository: AuthRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(EmailLoginUiState())
    val uiState: StateFlow<EmailLoginUiState> = _uiState.asStateFlow()

    fun updateEmail(email: String) {
        _uiState.update { it.copy(email = email, error = null) }
    }

    fun submitEmail() {
        val email = _uiState.value.email.trim()
        if (email.isBlank()) {
            _uiState.update { it.copy(error = "Email is required") }
            return
        }

        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }
            when (val result = authRepository.emailLogin(email)) {
                is Result.Success -> {
                    if (result.data) {
                        // TOTP required — navigate to TOTP verify screen
                        _uiState.update { it.copy(isLoading = false, navigateToTotp = email) }
                    } else {
                        _uiState.update {
                            it.copy(isLoading = false, error = "TOTP not set up for this account")
                        }
                    }
                }
                is Result.Error -> {
                    _uiState.update {
                        it.copy(isLoading = false, error = result.exception.message)
                    }
                }
            }
        }
    }

    fun onTotpNavigated() {
        _uiState.update { it.copy(navigateToTotp = null) }
    }
}
