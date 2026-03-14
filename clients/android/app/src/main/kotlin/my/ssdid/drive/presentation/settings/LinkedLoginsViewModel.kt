package my.ssdid.drive.presentation.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import my.ssdid.drive.domain.model.LinkedLogin
import my.ssdid.drive.domain.repository.AuthRepository
import my.ssdid.drive.util.Result
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class LinkedLoginsUiState(
    val logins: List<LinkedLogin> = emptyList(),
    val isLoading: Boolean = true,
    val isRemoving: String? = null,
    val error: String? = null,
    val successMessage: String? = null
)

@HiltViewModel
class LinkedLoginsViewModel @Inject constructor(
    private val authRepository: AuthRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(LinkedLoginsUiState())
    val uiState: StateFlow<LinkedLoginsUiState> = _uiState.asStateFlow()

    init {
        loadLogins()
    }

    fun loadLogins() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }
            when (val result = authRepository.getLinkedLogins()) {
                is Result.Success -> {
                    _uiState.update { it.copy(isLoading = false, logins = result.data) }
                }
                is Result.Error -> {
                    _uiState.update {
                        it.copy(isLoading = false, error = result.exception.message)
                    }
                }
            }
        }
    }

    fun removeLogin(loginId: String) {
        viewModelScope.launch {
            _uiState.update { it.copy(isRemoving = loginId, error = null) }
            when (authRepository.unlinkLogin(loginId)) {
                is Result.Success -> {
                    _uiState.update {
                        it.copy(
                            isRemoving = null,
                            successMessage = "Login removed"
                        )
                    }
                    loadLogins()
                }
                is Result.Error -> {
                    _uiState.update {
                        it.copy(isRemoving = null, error = "Failed to remove login")
                    }
                }
            }
        }
    }

    fun linkOidc(provider: String, idToken: String) {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }
            when (authRepository.linkOidc(provider, idToken)) {
                is Result.Success -> {
                    _uiState.update {
                        it.copy(isLoading = false, successMessage = "Login linked")
                    }
                    loadLogins()
                }
                is Result.Error -> {
                    _uiState.update {
                        it.copy(isLoading = false, error = "Failed to link login")
                    }
                }
            }
        }
    }

    fun clearMessage() {
        _uiState.update { it.copy(successMessage = null, error = null) }
    }
}
