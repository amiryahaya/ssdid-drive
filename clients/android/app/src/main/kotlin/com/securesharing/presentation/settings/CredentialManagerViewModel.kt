package com.securesharing.presentation.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.securesharing.domain.model.UserCredential
import com.securesharing.domain.repository.WebAuthnRepository
import com.securesharing.util.Result
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class CredentialManagerUiState(
    val credentials: List<UserCredential> = emptyList(),
    val isLoading: Boolean = false,
    val error: String? = null,
    val isRenaming: Boolean = false,
    val isDeleting: Boolean = false
)

@HiltViewModel
class CredentialManagerViewModel @Inject constructor(
    private val webAuthnRepository: WebAuthnRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(CredentialManagerUiState())
    val uiState: StateFlow<CredentialManagerUiState> = _uiState.asStateFlow()

    init {
        loadCredentials()
    }

    fun loadCredentials() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }
            when (val result = webAuthnRepository.getCredentials()) {
                is Result.Success -> {
                    _uiState.update {
                        it.copy(isLoading = false, credentials = result.data)
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

    fun renameCredential(credentialId: String, newName: String) {
        viewModelScope.launch {
            _uiState.update { it.copy(isRenaming = true, error = null) }
            when (val result = webAuthnRepository.renameCredential(credentialId, newName)) {
                is Result.Success -> {
                    _uiState.update { state ->
                        val updated = state.credentials.map { cred ->
                            if (cred.id == credentialId) result.data else cred
                        }
                        state.copy(isRenaming = false, credentials = updated)
                    }
                }
                is Result.Error -> {
                    _uiState.update {
                        it.copy(isRenaming = false, error = result.exception.message)
                    }
                }
            }
        }
    }

    fun deleteCredential(credentialId: String) {
        viewModelScope.launch {
            _uiState.update { it.copy(isDeleting = true, error = null) }
            when (val result = webAuthnRepository.deleteCredential(credentialId)) {
                is Result.Success -> {
                    _uiState.update { state ->
                        state.copy(
                            isDeleting = false,
                            credentials = state.credentials.filter { it.id != credentialId }
                        )
                    }
                }
                is Result.Error -> {
                    _uiState.update {
                        it.copy(isDeleting = false, error = result.exception.message)
                    }
                }
            }
        }
    }
}
