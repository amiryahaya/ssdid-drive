package my.ssdid.drive.presentation.auth

import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import my.ssdid.drive.crypto.SecureMemory
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
    val showPasswordInput: Boolean = false,
    val error: String? = null,
    val isUnlocked: Boolean = false,
    val biometricAvailable: Boolean = true
)

/**
 * ViewModel for the Lock screen.
 *
 * Handles biometric and password-based unlocking of the app.
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
                        it.copy(
                            isUnlocking = false,
                            showPasswordInput = true
                        )
                    }
                }
                is BiometricResult.Lockout -> {
                    val message = if (result.temporary) {
                        "Too many attempts. Please try again later or use your password."
                    } else {
                        "Biometric locked. Please use your password."
                    }
                    _uiState.update {
                        it.copy(
                            isUnlocking = false,
                            error = message,
                            showPasswordInput = true
                        )
                    }
                }
                is BiometricResult.Error -> {
                    _uiState.update {
                        it.copy(
                            isUnlocking = false,
                            error = result.message,
                            showPasswordInput = true
                        )
                    }
                }
            }
        }
    }

    private suspend fun unlockKeysWithBiometric() {
        when (val result = authRepository.unlockWithBiometric()) {
            is Result.Success -> {
                _uiState.update {
                    it.copy(
                        isUnlocking = false,
                        isUnlocked = true
                    )
                }
            }
            is Result.Error -> {
                _uiState.update {
                    it.copy(
                        isUnlocking = false,
                        error = result.exception.message,
                        showPasswordInput = true
                    )
                }
            }
        }
    }

    /**
     * Unlock using password.
     * Used as fallback when biometric fails or is unavailable.
     */
    fun unlockWithPassword(password: String) {
        viewModelScope.launch {
            _uiState.update { it.copy(isUnlocking = true, error = null) }

            val passwordChars = password.toCharArray()

            try {
                when (val result = authRepository.unlockKeys(passwordChars)) {
                    is Result.Success -> {
                        _uiState.update {
                            it.copy(
                                isUnlocking = false,
                                isUnlocked = true
                            )
                        }
                    }
                    is Result.Error -> {
                        _uiState.update {
                            it.copy(
                                isUnlocking = false,
                                error = result.exception.message
                            )
                        }
                    }
                }
            } finally {
                SecureMemory.zeroize(passwordChars)
            }
        }
    }

    /**
     * Show password input instead of biometric.
     */
    fun showPasswordInput() {
        _uiState.update { it.copy(showPasswordInput = true, error = null) }
    }

    /**
     * Hide password input and try biometric again.
     */
    fun hidePasswordInput() {
        _uiState.update { it.copy(showPasswordInput = false, error = null) }
    }

    /**
     * Clear any error message.
     */
    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }
}
