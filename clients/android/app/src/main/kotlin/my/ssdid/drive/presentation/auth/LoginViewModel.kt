package my.ssdid.drive.presentation.auth

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import my.ssdid.drive.crypto.SecureMemory
import my.ssdid.drive.domain.model.Tenant
import my.ssdid.drive.domain.model.User
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
 * UI state for login screen with multi-tenant support.
 */
data class LoginUiState(
    val email: String = "",
    val password: String = "",
    val tenantSlug: String = "",
    val isLoading: Boolean = false,
    val isLoggedIn: Boolean = false,
    val error: String? = null,
    // Multi-tenant support
    val loggedInUser: User? = null,
    val availableTenants: List<Tenant> = emptyList(),
    val isMultiTenant: Boolean = false
)

@HiltViewModel
class LoginViewModel @Inject constructor(
    private val authRepository: AuthRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(LoginUiState())
    val uiState: StateFlow<LoginUiState> = _uiState.asStateFlow()

    fun updateEmail(email: String) {
        _uiState.update { it.copy(email = email, error = null) }
    }

    fun updatePassword(password: String) {
        _uiState.update { it.copy(password = password, error = null) }
    }

    fun updateTenantSlug(tenantSlug: String) {
        _uiState.update { it.copy(tenantSlug = tenantSlug, error = null) }
    }

    /**
     * Login with email and password.
     *
     * With multi-tenant support, the tenant slug is optional. If not provided,
     * the user will be logged into their first available tenant.
     */
    fun login() {
        val state = _uiState.value

        // Validate inputs
        if (state.email.isBlank()) {
            _uiState.update { it.copy(error = "Email is required") }
            return
        }
        if (state.password.isBlank()) {
            _uiState.update { it.copy(error = "Password is required") }
            return
        }

        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }

            // SECURITY: Convert password to CharArray for secure handling
            val passwordChars = state.password.toCharArray()

            try {
                // Tenant slug is optional - if blank, pass null
                val tenantSlug = state.tenantSlug.takeIf { it.isNotBlank() }

                when (val result = authRepository.login(state.email, passwordChars, tenantSlug)) {
                    is Result.Success -> {
                        val user = result.data
                        val tenants = user.tenants ?: emptyList()
                        val isMultiTenant = tenants.size > 1

                        _uiState.update {
                            it.copy(
                                isLoading = false,
                                isLoggedIn = true,
                                password = "",
                                loggedInUser = user,
                                availableTenants = tenants,
                                isMultiTenant = isMultiTenant
                            )
                        }
                    }
                    is Result.Error -> {
                        _uiState.update {
                            it.copy(
                                isLoading = false,
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

    /**
     * Clear sensitive data when ViewModel is cleared.
     */
    override fun onCleared() {
        super.onCleared()
        // Clear password from UI state
        _uiState.update { it.copy(password = "") }
    }
}
