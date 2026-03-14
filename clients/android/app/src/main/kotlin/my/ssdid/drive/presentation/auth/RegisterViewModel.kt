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
 * UI state for register screen with SSDID Wallet authentication.
 */
data class RegisterUiState(
    val isLoading: Boolean = false,
    val isWaitingForWallet: Boolean = false,
    val isRegistered: Boolean = false,
    val error: String? = null
)

@HiltViewModel
class RegisterViewModel @Inject constructor(
    private val authRepository: AuthRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(RegisterUiState())
    val uiState: StateFlow<RegisterUiState> = _uiState.asStateFlow()

    /**
     * Initiate registration with SSDID Wallet.
     *
     * Creates a challenge on the server with action "register",
     * then launches the wallet app via deep link. The wallet handles
     * DID creation and service registration, then calls back with
     * a session token.
     */
    fun registerWithWallet() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }
            try {
                // 1. Get server info and create challenge for registration
                val challenge = authRepository.createChallenge("register")

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
                authRepository.saveSession(sessionToken, "")
                _uiState.update { it.copy(isWaitingForWallet = false, isRegistered = true) }
            } catch (e: Exception) {
                _uiState.update { it.copy(isWaitingForWallet = false, error = e.message) }
            }
        }
    }
}
