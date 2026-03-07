package my.ssdid.drive.presentation.auth

import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import my.ssdid.drive.domain.repository.AuthRepository
import my.ssdid.drive.util.BiometricAuthManager
import my.ssdid.drive.util.BiometricAvailability
import my.ssdid.drive.util.BiometricResult
import my.ssdid.drive.util.Result
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class LockUiState(
    val isUnlocking: Boolean = false,
    val error: String? = null,
    val isUnlocked: Boolean = false,
    val biometricAvailable: Boolean = true
)

/**
 * ViewModel for the Lock screen.
 *
 * Handles biometric-based unlocking of the app.
 * Password-based unlock is not supported with SSDID Wallet authentication.
 */
@HiltViewModel
class LockViewModel @Inject constructor(
    private val authRepository: AuthRepository,
    private val biometricAuthManager: BiometricAuthManager
) : ViewModel() {

    private val _uiState = MutableStateFlow(LockUiState())
    val uiState: StateFlow<LockUiState> = _uiState.asStateFlow()

    init {
        checkBiometricAvailability()
    }

    private fun checkBiometricAvailability() {
        val availability = biometricAuthManager.isBiometricAvailable()
        val isAvailable = availability == BiometricAvailability.AVAILABLE
        _uiState.update { it.copy(biometricAvailable = isAvailable) }
    }

    /**
     * Attempt to unlock using biometric authentication.
     * Shows biometric prompt and unlocks keys on success.
     */
    fun unlockWithBiometric(activity: FragmentActivity) {
        viewModelScope.launch {
            _uiState.update { it.copy(isUnlocking = true, error = null) }

            // Show biometric prompt
            val result = biometricAuthManager.authenticate(
                activity = activity,
                title = "Unlock SSDID Drive",
                subtitle = "Use your fingerprint or face to unlock",
                description = "Your encrypted files are protected",
                allowDeviceCredential = true
            )

            when (result) {
                is BiometricResult.Success -> {
                    // Biometric success, now unlock keys
                    unlockKeysWithBiometric()
                }
                is BiometricResult.Cancelled -> {
                    _uiState.update {
                        it.copy(isUnlocking = false)
                    }
                }
                is BiometricResult.Lockout -> {
                    val message = if (result.temporary) {
                        "Too many attempts. Please try again later."
                    } else {
                        "Biometric locked. Please try again later."
                    }
                    _uiState.update {
                        it.copy(isUnlocking = false, error = message)
                    }
                }
                is BiometricResult.Error -> {
                    _uiState.update {
                        it.copy(isUnlocking = false, error = result.message)
                    }
                }
            }
        }
    }

    private suspend fun unlockKeysWithBiometric() {
        when (val result = authRepository.unlockWithBiometric()) {
            is Result.Success -> {
                _uiState.update {
                    it.copy(isUnlocking = false, isUnlocked = true)
                }
            }
            is Result.Error -> {
                _uiState.update {
                    it.copy(isUnlocking = false, error = result.exception.message)
                }
            }
        }
    }

    /**
     * Clear any error message.
     */
    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }
}
