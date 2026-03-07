package com.securesharing.presentation.auth

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.securesharing.domain.repository.WebAuthnRepository
import com.securesharing.util.Result
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class PasskeyUiState(
    val isLoading: Boolean = false,
    val isLoggedIn: Boolean = false,
    val optionsJson: String? = null,
    val challengeId: String? = null,
    val error: String? = null
)

@HiltViewModel
class PasskeyLoginViewModel @Inject constructor(
    private val webAuthnRepository: WebAuthnRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(PasskeyUiState())
    val uiState: StateFlow<PasskeyUiState> = _uiState.asStateFlow()

    fun beginLogin(email: String? = null) {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }
            when (val result = webAuthnRepository.loginBegin(email)) {
                is Result.Success -> {
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            optionsJson = result.data.optionsJson,
                            challengeId = result.data.challengeId
                        )
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

    fun completeLogin(assertionJson: String, prfOutput: String? = null) {
        val challengeId = _uiState.value.challengeId ?: return

        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }
            when (val result = webAuthnRepository.loginComplete(challengeId, assertionJson, prfOutput)) {
                is Result.Success -> {
                    _uiState.update {
                        it.copy(isLoading = false, isLoggedIn = true)
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
}
