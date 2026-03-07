package com.securesharing.presentation.auth

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.securesharing.crypto.SecureMemory
import com.securesharing.domain.repository.AuthRepository
import com.securesharing.util.Result
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class RegisterUiState(
    val email: String = "",
    val password: String = "",
    val confirmPassword: String = "",
    val tenantSlug: String = "",
    val isLoading: Boolean = false,
    val isGeneratingKeys: Boolean = false,
    val isRegistered: Boolean = false,
    val error: String? = null
)

@HiltViewModel
class RegisterViewModel @Inject constructor(
    private val authRepository: AuthRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(RegisterUiState())
    val uiState: StateFlow<RegisterUiState> = _uiState.asStateFlow()

    fun updateEmail(email: String) {
        _uiState.update { it.copy(email = email, error = null) }
    }

    fun updatePassword(password: String) {
        _uiState.update { it.copy(password = password, error = null) }
    }

    fun updateConfirmPassword(confirmPassword: String) {
        _uiState.update { it.copy(confirmPassword = confirmPassword, error = null) }
    }

    fun updateTenantSlug(tenantSlug: String) {
        _uiState.update { it.copy(tenantSlug = tenantSlug, error = null) }
    }

    fun register() {
        val state = _uiState.value

        // Validate inputs
        if (state.tenantSlug.isBlank()) {
            _uiState.update { it.copy(error = "Organization is required") }
            return
        }
        if (state.email.isBlank()) {
            _uiState.update { it.copy(error = "Email is required") }
            return
        }
        if (!isValidEmail(state.email)) {
            _uiState.update { it.copy(error = "Invalid email format") }
            return
        }
        if (state.password.isBlank()) {
            _uiState.update { it.copy(error = "Password is required") }
            return
        }
        if (state.password.length < 8) {
            _uiState.update { it.copy(error = "Password must be at least 8 characters") }
            return
        }
        if (state.password != state.confirmPassword) {
            _uiState.update { it.copy(error = "Passwords do not match") }
            return
        }

        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, isGeneratingKeys = true, error = null) }

            // SECURITY: Convert password to CharArray for secure handling
            val passwordChars = state.password.toCharArray()

            try {
                when (val result = authRepository.register(state.email, passwordChars, state.tenantSlug)) {
                    is Result.Success -> {
                        _uiState.update {
                            it.copy(
                                isLoading = false,
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
                                isLoading = false,
                                isGeneratingKeys = false,
                                error = result.exception.message
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

    private fun isValidEmail(email: String): Boolean {
        return android.util.Patterns.EMAIL_ADDRESS.matcher(email).matches()
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
