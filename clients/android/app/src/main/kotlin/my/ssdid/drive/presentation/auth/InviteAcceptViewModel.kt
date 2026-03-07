package my.ssdid.drive.presentation.auth

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import my.ssdid.drive.domain.model.TokenInvitation
import my.ssdid.drive.domain.model.TokenInvitationError
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
 * UI state for the invitation acceptance screen.
 */
data class InviteAcceptUiState(
    // Invitation info
    val token: String = "",
    val invitation: TokenInvitation? = null,
    val isLoadingInvitation: Boolean = true,
    val invitationError: String? = null,

    // Registration state (via SSDID Wallet)
    val isLoading: Boolean = false,
    val isWaitingForWallet: Boolean = false,
    val isRegistered: Boolean = false,
    val registrationError: String? = null
)

/**
 * ViewModel for handling invitation acceptance via SSDID Wallet.
 *
 * The flow is:
 * 1. Load invitation info from token
 * 2. User taps "Accept with SSDID Wallet"
 * 3. App creates a challenge and launches wallet via deep link
 * 4. Wallet handles DID creation and service registration
 * 5. Wallet calls back with session token
 */
@HiltViewModel
class InviteAcceptViewModel @Inject constructor(
    private val authRepository: AuthRepository,
    savedStateHandle: SavedStateHandle
) : ViewModel() {

    private val _uiState = MutableStateFlow(InviteAcceptUiState())
    val uiState: StateFlow<InviteAcceptUiState> = _uiState.asStateFlow()

    init {
        // Get token from navigation arguments
        val token = savedStateHandle.get<String>("token") ?: ""
        _uiState.update { it.copy(token = token) }

        if (token.isNotBlank()) {
            loadInvitationInfo(token)
        } else {
            _uiState.update {
                it.copy(
                    isLoadingInvitation = false,
                    invitationError = "Invalid invitation link"
                )
            }
        }
    }

    /**
     * Load invitation info from token.
     */
    private fun loadInvitationInfo(token: String) {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoadingInvitation = true, invitationError = null) }

            when (val result = authRepository.getInvitationInfo(token)) {
                is Result.Success -> {
                    val invitation = result.data
                    if (invitation.valid) {
                        _uiState.update {
                            it.copy(
                                isLoadingInvitation = false,
                                invitation = invitation
                            )
                        }
                    } else {
                        val errorMessage = when (invitation.errorReason) {
                            TokenInvitationError.EXPIRED -> "This invitation has expired"
                            TokenInvitationError.REVOKED -> "This invitation has been revoked"
                            TokenInvitationError.ALREADY_USED -> "This invitation has already been used"
                            TokenInvitationError.NOT_FOUND -> "Invitation not found"
                            null -> "This invitation is no longer valid"
                        }
                        _uiState.update {
                            it.copy(
                                isLoadingInvitation = false,
                                invitation = invitation,
                                invitationError = errorMessage
                            )
                        }
                    }
                }
                is Result.Error -> {
                    _uiState.update {
                        it.copy(
                            isLoadingInvitation = false,
                            invitationError = result.exception.message ?: "Failed to load invitation"
                        )
                    }
                }
            }
        }
    }

    /**
     * Retry loading invitation info.
     */
    fun retryLoadInvitation() {
        val token = _uiState.value.token
        if (token.isNotBlank()) {
            loadInvitationInfo(token)
        }
    }

    /**
     * Accept the invitation via SSDID Wallet.
     * Launches the wallet with a "register" action and the invitation token.
     */
    fun acceptWithWallet() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, registrationError = null) }
            try {
                // Create a challenge for registration (includes invitation context)
                val challenge = authRepository.createChallenge("register")

                // Launch wallet
                authRepository.launchWalletAuth(challenge)

                _uiState.update { it.copy(isLoading = false, isWaitingForWallet = true) }
            } catch (e: Exception) {
                _uiState.update {
                    it.copy(isLoading = false, registrationError = e.message)
                }
            }
        }
    }

    /**
     * Handle the callback from SSDID Wallet with the session token.
     */
    fun handleWalletCallback(sessionToken: String) {
        viewModelScope.launch {
            try {
                authRepository.saveSession(sessionToken)
                _uiState.update { it.copy(isWaitingForWallet = false, isRegistered = true) }
            } catch (e: Exception) {
                _uiState.update {
                    it.copy(isWaitingForWallet = false, registrationError = e.message)
                }
            }
        }
    }
}
