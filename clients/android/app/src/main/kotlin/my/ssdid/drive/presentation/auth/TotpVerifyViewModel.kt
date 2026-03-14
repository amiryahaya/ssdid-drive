package my.ssdid.drive.presentation.auth

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import my.ssdid.drive.domain.repository.AuthRepository
import my.ssdid.drive.presentation.navigation.Screen
import my.ssdid.drive.util.Result
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class TotpVerifyUiState(
    val email: String = "",
    val code: String = "",
    val isLoading: Boolean = false,
    val isAuthenticated: Boolean = false,
    val error: String? = null
)

@HiltViewModel
class TotpVerifyViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val authRepository: AuthRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(
        TotpVerifyUiState(
            email = savedStateHandle.get<String>(Screen.ARG_EMAIL) ?: ""
        )
    )
    val uiState: StateFlow<TotpVerifyUiState> = _uiState.asStateFlow()

    fun updateCode(code: String) {
        if (code.length <= 6 && code.all { it.isDigit() }) {
            _uiState.update { it.copy(code = code, error = null) }
            if (code.length == 6) {
                submitCode()
            }
        }
    }

    fun submitCode() {
        val state = _uiState.value
        if (state.code.length != 6) {
            _uiState.update { it.copy(error = "Enter a 6-digit code") }
            return
        }

        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }
            when (val result = authRepository.totpVerify(state.email, state.code)) {
                is Result.Success -> {
                    _uiState.update { it.copy(isLoading = false, isAuthenticated = true) }
                }
                is Result.Error -> {
                    _uiState.update {
                        it.copy(isLoading = false, code = "", error = result.exception.message)
                    }
                }
            }
        }
    }
}
