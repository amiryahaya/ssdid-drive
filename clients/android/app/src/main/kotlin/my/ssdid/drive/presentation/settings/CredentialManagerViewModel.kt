package my.ssdid.drive.presentation.settings

import androidx.lifecycle.ViewModel
import my.ssdid.drive.domain.model.UserCredential
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject

data class CredentialManagerUiState(
    val credentials: List<UserCredential> = emptyList(),
    val isLoading: Boolean = false,
    val error: String? = null,
    val isRenaming: Boolean = false,
    val isDeleting: Boolean = false
)

/**
 * CredentialManager is no longer used since WebAuthn/passkey authentication
 * has been replaced by SSDID Wallet authentication.
 */
@HiltViewModel
class CredentialManagerViewModel @Inject constructor() : ViewModel() {

    private val _uiState = MutableStateFlow(CredentialManagerUiState(
        error = "Credential management is not available. Authentication is handled by SSDID Wallet."
    ))
    val uiState: StateFlow<CredentialManagerUiState> = _uiState.asStateFlow()

    fun loadCredentials() {
        // No-op: WebAuthn credentials are no longer used
    }

    fun renameCredential(credentialId: String, newName: String) {
        // No-op: WebAuthn credentials are no longer used
    }

    fun deleteCredential(credentialId: String) {
        // No-op: WebAuthn credentials are no longer used
    }
}
