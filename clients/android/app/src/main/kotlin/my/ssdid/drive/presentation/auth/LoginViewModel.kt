package my.ssdid.drive.presentation.auth

import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import my.ssdid.drive.BuildConfig
import my.ssdid.drive.domain.repository.AuthRepository
import my.ssdid.drive.util.PushNotificationManager
import my.ssdid.drive.util.Result
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * UI state for login screen with email + TOTP and OIDC authentication.
 */
data class LoginUiState(
    val email: String = "",
    val isLoading: Boolean = false,
    val isAuthenticated: Boolean = false,
    val navigateToTotp: String? = null,
    val error: String? = null,
    val pendingInviteCode: String? = null,
    val oidcLaunchUrl: String? = null
)

@HiltViewModel
class LoginViewModel @Inject constructor(
    private val authRepository: AuthRepository,
    private val pushNotificationManager: PushNotificationManager
) : ViewModel() {

    private val _uiState = MutableStateFlow(LoginUiState())
    val uiState: StateFlow<LoginUiState> = _uiState.asStateFlow()

    fun updateEmail(email: String) {
        _uiState.update { it.copy(email = email, error = null) }
    }

    /**
     * Submit email to initiate login.
     * If account has TOTP enabled, navigates to TOTP verification screen.
     */
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
                        // TOTP required — navigate to TOTP verify
                        _uiState.update {
                            it.copy(isLoading = false, navigateToTotp = email)
                        }
                    } else {
                        // TOTP not enabled — account exists but has no 2FA configured.
                        // Guide user to set up TOTP or use another login method.
                        _uiState.update {
                            it.copy(
                                isLoading = false,
                                error = "This account does not have two-factor authentication enabled. " +
                                    "Please use DID or OIDC login, or contact your administrator to enable TOTP."
                            )
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

    /**
     * Handle OIDC login result from native SDK.
     */
    fun handleOidcResult(provider: String, idToken: String) {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }
            val inviteCode = _uiState.value.pendingInviteCode?.takeIf { it.isNotBlank() }
            when (authRepository.oidcVerify(provider, idToken, inviteCode)) {
                is Result.Success -> {
                    _uiState.update { it.copy(isLoading = false, isAuthenticated = true) }
                }
                is Result.Error -> {
                    _uiState.update {
                        it.copy(isLoading = false, error = "Sign-in failed. Please try again.")
                    }
                }
            }
        }
    }

    /**
     * Build the OIDC authorize URL and set it in UI state to trigger browser launch.
     */
    fun launchOidc(provider: String) {
        val baseUrl = BuildConfig.API_BASE_URL.removeSuffix("/").removeSuffix("/api")
        val redirectUri = "ssdiddrive://auth/callback"
        var url = "$baseUrl/api/auth/oidc/$provider/authorize" +
            "?redirect_uri=${Uri.encode(redirectUri)}"

        val inviteCode = _uiState.value.pendingInviteCode
        if (!inviteCode.isNullOrBlank()) {
            url += "&invitation_token=${Uri.encode(inviteCode)}"
        }

        _uiState.update { it.copy(oidcLaunchUrl = url) }
    }

    /**
     * Clear the OIDC launch URL after the browser has been opened.
     */
    fun onOidcLaunched() {
        _uiState.update { it.copy(oidcLaunchUrl = null) }
    }

    /**
     * Handle auth callback from OIDC browser redirect or wallet deep link.
     * Saves the session token and navigates to main.
     */
    fun handleAuthCallback(sessionToken: String) {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }
            try {
                authRepository.saveSession(sessionToken, "")
                _uiState.update { it.copy(isLoading = false, isAuthenticated = true) }
            } catch (e: Exception) {
                _uiState.update {
                    it.copy(isLoading = false, error = "Sign-in failed. Please try again.")
                }
            }
        }
    }

    /**
     * Show an error message from external callback (OIDC error, wallet error).
     */
    fun showError(message: String) {
        _uiState.update { it.copy(error = message) }
    }
}
