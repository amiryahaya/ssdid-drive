package my.ssdid.drive.presentation.auth

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import my.ssdid.drive.domain.repository.AuthRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * UI state for login screen with SSDID Wallet authentication.
 */
data class LoginUiState(
    val isLoading: Boolean = false,
    val isWaitingForWallet: Boolean = false,
    val isAuthenticated: Boolean = false,
    val error: String? = null
)

@HiltViewModel
class LoginViewModel @Inject constructor(
    private val authRepository: AuthRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(LoginUiState())
    val uiState: StateFlow<LoginUiState> = _uiState.asStateFlow()

    /**
     * Initiate sign-in with SSDID Wallet.
     *
     * Creates a challenge on the server, then launches the wallet app
     * via deep link. The wallet will authenticate the user and call back
     * with a session token.
     */
    fun signInWithWallet() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }
            try {
                // 1. Get server info and create challenge
                val challenge = authRepository.createChallenge("authenticate")

                // 2. Launch deep link to wallet
                authRepository.launchWalletAuth(challenge)

                // 3. Update state to show waiting UI
                _uiState.update { it.copy(isLoading = false, isWaitingForWallet = true) }
            } catch (e: Exception) {
                _uiState.update { it.copy(isLoading = false, error = e.message) }
            }
        }
    }

    /**
     * Handle the callback from SSDID Wallet with the session token.
     *
     * Called when the wallet redirects back to the app via deep link:
     * ssdiddrive://auth/callback?session_token=...
     *
     * @param sessionToken The session token from the wallet
     */
    fun handleWalletCallback(sessionToken: String) {
        viewModelScope.launch {
            try {
                authRepository.saveSession(sessionToken)
                _uiState.update { it.copy(isWaitingForWallet = false, isAuthenticated = true) }
            } catch (e: Exception) {
                _uiState.update { it.copy(isWaitingForWallet = false, error = e.message) }
            }
        }
    }
}
