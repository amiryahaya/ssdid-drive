package my.ssdid.drive.presentation.auth

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import my.ssdid.drive.domain.repository.AuthRepository
import my.ssdid.drive.util.PushNotificationManager
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
    private val authRepository: AuthRepository,
    private val pushNotificationManager: PushNotificationManager
) : ViewModel() {

    private val _uiState = MutableStateFlow(LoginUiState())
    val uiState: StateFlow<LoginUiState> = _uiState.asStateFlow()

    /**
     * Initiate sign-in with SSDID Wallet.
     *
     * Same-device flow (per ssdid-drive-deeplink-protocol.md):
     * 1. POST /login/initiate → get challenge_id, subscriber_secret, qr_payload
     * 2. Build ssdid://login deep link and launch SSDID Wallet
     * 3. Wallet authenticates with server and calls back via ssdiddrive://auth/callback?session_token=...
     * 4. handleWalletCallback() saves session token
     */
    fun signInWithWallet() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }
            try {
                // 1. Create challenge on server
                val challenge = authRepository.createChallenge("authenticate")

                // 2. Launch wallet deep link
                authRepository.launchWalletAuth(challenge)

                // 3. Show waiting state — wallet will call back via deep link
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
     * ssdid-drive://auth/callback?session_token=<token>
     */
    fun handleWalletCallback(sessionToken: String) {
        viewModelScope.launch {
            try {
                authRepository.saveSession(sessionToken)
                _uiState.update { it.copy(isWaitingForWallet = false, isAuthenticated = true) }
                pushNotificationManager.requestPermission()
            } catch (e: Exception) {
                _uiState.update { it.copy(isWaitingForWallet = false, error = e.message) }
            }
        }
    }
}
