package my.ssdid.drive.presentation.navigation

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import my.ssdid.drive.data.local.PreferencesManager
import my.ssdid.drive.domain.repository.AuthRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * ViewModel for handling app-level navigation state.
 * Determines the start destination based on onboarding, authentication status, and lock state.
 */
@HiltViewModel
class NavigationViewModel @Inject constructor(
    private val authRepository: AuthRepository,
    private val preferencesManager: PreferencesManager
) : ViewModel() {

    private val _startDestination = MutableStateFlow<String?>(null)
    val startDestination: StateFlow<String?> = _startDestination.asStateFlow()

    private val _shouldShowLock = MutableStateFlow(false)
    val shouldShowLock: StateFlow<Boolean> = _shouldShowLock.asStateFlow()

    init {
        determineStartDestination()
    }

    private fun determineStartDestination() {
        viewModelScope.launch {
            // Check if onboarding has been completed
            val hasCompletedOnboarding = preferencesManager.hasCompletedOnboardingSync()

            if (!hasCompletedOnboarding) {
                _startDestination.value = Screen.Onboarding.route
                return@launch
            }

            val isAuthenticated = authRepository.isAuthenticated()

            if (!isAuthenticated) {
                _startDestination.value = Screen.Login.route
                return@launch
            }

            // User is authenticated, check if we need to show lock screen
            val biometricEnabled = authRepository.isBiometricUnlockEnabled()
            val keysUnlocked = authRepository.areKeysUnlocked()

            _startDestination.value = when {
                // Biometric enabled but keys not unlocked -> show lock screen
                biometricEnabled && !keysUnlocked -> Screen.Lock.route
                // Otherwise go to files
                else -> Screen.Files.route
            }
        }
    }

    /**
     * Called when onboarding is completed.
     */
    fun completeOnboarding() {
        viewModelScope.launch {
            preferencesManager.setOnboardingCompleted()
        }
    }

    /**
     * Called when the app should be locked (e.g., after auto-lock timeout).
     * Navigates to lock screen if biometric is enabled.
     */
    fun lockApp() {
        viewModelScope.launch {
            val biometricEnabled = authRepository.isBiometricUnlockEnabled()
            if (biometricEnabled) {
                authRepository.lockKeys()
                _shouldShowLock.value = true
            }
        }
    }

    /**
     * Reset the lock flag after navigation to lock screen.
     */
    fun onLockScreenShown() {
        _shouldShowLock.value = false
    }
}
