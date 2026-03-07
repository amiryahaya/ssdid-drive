package my.ssdid.drive.presentation.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import my.ssdid.drive.crypto.KeyManager
import my.ssdid.drive.data.local.AutoLockTimeout
import my.ssdid.drive.data.local.PreferencesManager
import my.ssdid.drive.data.local.ThemeMode
import my.ssdid.drive.domain.model.DeviceEnrollment
import my.ssdid.drive.domain.model.PublicKeys
import my.ssdid.drive.domain.model.User
import my.ssdid.drive.domain.repository.AuthRepository
import my.ssdid.drive.domain.repository.DeviceRepository
import my.ssdid.drive.domain.repository.TenantRepository
import my.ssdid.drive.util.BiometricAuthManager
import my.ssdid.drive.util.BiometricAvailability
import my.ssdid.drive.util.CacheManager
import my.ssdid.drive.util.Result
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class SettingsUiState(
    // User data
    val user: User? = null,
    val tenantName: String = "",

    // Profile editing
    val showEditProfileDialog: Boolean = false,
    val isUpdatingProfile: Boolean = false,
    val profileUpdateError: String? = null,

    // Security settings
    val biometricEnabled: Boolean = false,
    val biometricAvailable: Boolean = false,
    val autoLockEnabled: Boolean = true,
    val autoLockTimeout: AutoLockTimeout = AutoLockTimeout.FIVE_MINUTES,
    val publicKeys: PublicKeys? = null,

    // Appearance settings
    val themeMode: ThemeMode = ThemeMode.SYSTEM,
    val compactViewEnabled: Boolean = false,
    val showFileSizes: Boolean = true,

    // Notification settings
    val notificationsEnabled: Boolean = true,
    val shareNotificationsEnabled: Boolean = true,
    val recoveryNotificationsEnabled: Boolean = true,

    // Analytics settings
    val analyticsEnabled: Boolean = false,

    // Change password state
    val isChangingPassword: Boolean = false,
    val changePasswordError: String? = null,
    val changePasswordSuccess: Boolean = false,

    // Biometric setup state
    val isEnablingBiometric: Boolean = false,
    val showBiometricPasswordDialog: Boolean = false,
    val biometricSetupError: String? = null,

    // Storage settings
    val totalCacheSize: String = "0 B",
    val previewCacheSize: String = "0 B",
    val offlineCacheSize: String = "0 B",
    val isClearingCache: Boolean = false,

    // Device enrollment
    val isDeviceEnrolled: Boolean = false,
    val currentEnrollmentId: String? = null,
    val deviceEnrollments: List<DeviceEnrollment> = emptyList(),
    val isLoadingDevices: Boolean = false,
    val isEnrollingDevice: Boolean = false,

    // General state
    val isLoading: Boolean = false,
    val isLoggedOut: Boolean = false,
    val error: String? = null
)

@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val authRepository: AuthRepository,
    private val tenantRepository: TenantRepository,
    private val deviceRepository: DeviceRepository,
    private val preferencesManager: PreferencesManager,
    private val keyManager: KeyManager,
    private val cacheManager: CacheManager,
    private val biometricAuthManager: BiometricAuthManager
) : ViewModel() {

    private val _uiState = MutableStateFlow(SettingsUiState())
    val uiState: StateFlow<SettingsUiState> = _uiState.asStateFlow()

    init {
        loadUserData()
        loadPreferences()
        checkBiometricAvailability()
        loadCacheInfo()
        loadDeviceEnrollments()
    }

    private fun loadUserData() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }

            when (val result = authRepository.getCurrentUser()) {
                is Result.Success -> {
                    val user = result.data
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            user = user,
                            publicKeys = user.publicKeys
                        )
                    }

                    // Load tenant name
                    loadTenantInfo()
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
        }
    }

    private fun loadTenantInfo() {
        viewModelScope.launch {
            when (val result = tenantRepository.getTenantConfig()) {
                is Result.Success -> {
                    _uiState.update {
                        it.copy(tenantName = result.data.name)
                    }
                }
                is Result.Error -> {
                    // Use tenant ID as fallback
                    _uiState.update {
                        it.copy(tenantName = it.user?.tenantId ?: "Unknown")
                    }
                }
            }
        }
    }

    private fun loadPreferences() {
        viewModelScope.launch {
            // Theme
            preferencesManager.themeMode.collect { mode ->
                _uiState.update { it.copy(themeMode = mode) }
            }
        }

        viewModelScope.launch {
            // Biometric
            preferencesManager.biometricEnabled.collect { enabled ->
                _uiState.update { it.copy(biometricEnabled = enabled) }
            }
        }

        viewModelScope.launch {
            // Auto lock
            preferencesManager.autoLockEnabled.collect { enabled ->
                _uiState.update { it.copy(autoLockEnabled = enabled) }
            }
        }

        viewModelScope.launch {
            preferencesManager.autoLockTimeout.collect { timeout ->
                _uiState.update { it.copy(autoLockTimeout = timeout) }
            }
        }

        viewModelScope.launch {
            // Display
            preferencesManager.compactViewEnabled.collect { enabled ->
                _uiState.update { it.copy(compactViewEnabled = enabled) }
            }
        }

        viewModelScope.launch {
            preferencesManager.showFileSizes.collect { enabled ->
                _uiState.update { it.copy(showFileSizes = enabled) }
            }
        }

        viewModelScope.launch {
            // Notifications
            preferencesManager.notificationsEnabled.collect { enabled ->
                _uiState.update { it.copy(notificationsEnabled = enabled) }
            }
        }

        viewModelScope.launch {
            preferencesManager.shareNotificationsEnabled.collect { enabled ->
                _uiState.update { it.copy(shareNotificationsEnabled = enabled) }
            }
        }

        viewModelScope.launch {
            preferencesManager.recoveryNotificationsEnabled.collect { enabled ->
                _uiState.update { it.copy(recoveryNotificationsEnabled = enabled) }
            }
        }

        viewModelScope.launch {
            // Analytics
            preferencesManager.analyticsEnabled.collect { enabled ->
                _uiState.update { it.copy(analyticsEnabled = enabled) }
            }
        }
    }

    private fun checkBiometricAvailability() {
        val availability = biometricAuthManager.isBiometricAvailable()
        val isAvailable = availability == BiometricAvailability.AVAILABLE
        _uiState.update { it.copy(biometricAvailable = isAvailable) }

        // Also check if biometric unlock is already enabled
        viewModelScope.launch {
            val biometricEnabled = authRepository.isBiometricUnlockEnabled()
            _uiState.update { it.copy(biometricEnabled = biometricEnabled) }
        }
    }

    // ==================== Security Actions ====================

    // Password change is not supported with SSDID Wallet authentication.
    // Authentication is managed by the SSDID Wallet app.

    /**
     * Called when user toggles biometric switch.
     * If enabling, shows password dialog first.
     * If disabling, disables biometric unlock directly.
     */
    fun setBiometricEnabled(enabled: Boolean) {
        if (enabled) {
            // Enable biometric directly (no password needed with SSDID Wallet auth)
            enableBiometric()
        } else {
            // Disable biometric unlock
            viewModelScope.launch {
                when (val result = authRepository.disableBiometricUnlock()) {
                    is Result.Success -> {
                        _uiState.update { it.copy(biometricEnabled = false) }
                        preferencesManager.setBiometricEnabled(false)
                    }
                    is Result.Error -> {
                        _uiState.update { it.copy(error = result.exception.message) }
                    }
                }
            }
        }
    }

    /**
     * Enable biometric unlock.
     * No password required with SSDID Wallet authentication - keys are already unlocked.
     */
    fun enableBiometric() {
        viewModelScope.launch {
            _uiState.update {
                it.copy(
                    isEnablingBiometric = true,
                    showBiometricPasswordDialog = false,
                    biometricSetupError = null
                )
            }

            when (val result = authRepository.enableBiometricUnlock()) {
                is Result.Success -> {
                    _uiState.update {
                        it.copy(
                            isEnablingBiometric = false,
                            biometricEnabled = true
                        )
                    }
                    preferencesManager.setBiometricEnabled(true)
                }
                is Result.Error -> {
                    _uiState.update {
                        it.copy(
                            isEnablingBiometric = false,
                            biometricSetupError = result.exception.message
                        )
                    }
                }
            }
        }
    }

    /**
     * Called when user cancels the biometric enable dialog.
     */
    fun cancelBiometricSetup() {
        _uiState.update {
            it.copy(
                showBiometricPasswordDialog = false,
                biometricSetupError = null
            )
        }
    }

    /**
     * Clear biometric setup error.
     */
    fun clearBiometricSetupError() {
        _uiState.update { it.copy(biometricSetupError = null) }
    }

    fun setAutoLockEnabled(enabled: Boolean) {
        viewModelScope.launch {
            preferencesManager.setAutoLockEnabled(enabled)
        }
    }

    fun setAutoLockTimeout(timeout: AutoLockTimeout) {
        viewModelScope.launch {
            preferencesManager.setAutoLockTimeout(timeout)
        }
    }

    // ==================== Appearance Actions ====================

    fun setThemeMode(mode: ThemeMode) {
        viewModelScope.launch {
            preferencesManager.setThemeMode(mode)
        }
    }

    fun setCompactViewEnabled(enabled: Boolean) {
        viewModelScope.launch {
            preferencesManager.setCompactViewEnabled(enabled)
        }
    }

    fun setShowFileSizes(enabled: Boolean) {
        viewModelScope.launch {
            preferencesManager.setShowFileSizes(enabled)
        }
    }

    // ==================== Notification Actions ====================

    fun setNotificationsEnabled(enabled: Boolean) {
        viewModelScope.launch {
            preferencesManager.setNotificationsEnabled(enabled)
        }
    }

    fun setShareNotificationsEnabled(enabled: Boolean) {
        viewModelScope.launch {
            preferencesManager.setShareNotificationsEnabled(enabled)
        }
    }

    fun setRecoveryNotificationsEnabled(enabled: Boolean) {
        viewModelScope.launch {
            preferencesManager.setRecoveryNotificationsEnabled(enabled)
        }
    }

    // ==================== Analytics Actions ====================

    fun setAnalyticsEnabled(enabled: Boolean) {
        viewModelScope.launch {
            preferencesManager.setAnalyticsEnabled(enabled)
        }
    }

    // ==================== General Actions ====================

    fun logout() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }

            when (authRepository.logout()) {
                is Result.Success -> {
                    // Clear preferences too
                    preferencesManager.clearAll()
                    _uiState.update { it.copy(isLoggedOut = true) }
                }
                is Result.Error -> {
                    // Still log out locally even if API fails
                    preferencesManager.clearAll()
                    _uiState.update { it.copy(isLoggedOut = true) }
                }
            }
        }
    }

    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }

    fun clearChangePasswordState() {
        _uiState.update {
            it.copy(
                changePasswordError = null,
                changePasswordSuccess = false
            )
        }
    }

    fun refreshUserData() {
        loadUserData()
    }

    // ==================== Profile Actions ====================

    fun showEditProfileDialog() {
        _uiState.update { it.copy(showEditProfileDialog = true) }
    }

    fun hideEditProfileDialog() {
        _uiState.update {
            it.copy(
                showEditProfileDialog = false,
                profileUpdateError = null
            )
        }
    }

    fun updateProfile(displayName: String) {
        viewModelScope.launch {
            _uiState.update { it.copy(isUpdatingProfile = true, profileUpdateError = null) }

            when (val result = authRepository.updateProfile(displayName.ifBlank { null })) {
                is Result.Success -> {
                    _uiState.update {
                        it.copy(
                            isUpdatingProfile = false,
                            showEditProfileDialog = false,
                            user = result.data
                        )
                    }
                }
                is Result.Error -> {
                    _uiState.update {
                        it.copy(
                            isUpdatingProfile = false,
                            profileUpdateError = result.exception.message
                        )
                    }
                }
            }
        }
    }

    // ==================== Storage Actions ====================

    private fun loadCacheInfo() {
        viewModelScope.launch {
            val totalSize = cacheManager.getFormattedCacheSize()
            val previewSize = formatSize(cacheManager.getPreviewCacheSize())
            val offlineSize = formatSize(cacheManager.getOfflineCacheSize())

            _uiState.update {
                it.copy(
                    totalCacheSize = totalSize,
                    previewCacheSize = previewSize,
                    offlineCacheSize = offlineSize
                )
            }
        }
    }

    fun clearPreviewCache() {
        viewModelScope.launch {
            _uiState.update { it.copy(isClearingCache = true) }
            cacheManager.clearPreviewCache()
            loadCacheInfo()
            _uiState.update { it.copy(isClearingCache = false) }
        }
    }

    fun clearOfflineCache() {
        viewModelScope.launch {
            _uiState.update { it.copy(isClearingCache = true) }
            cacheManager.clearOfflineCache()
            loadCacheInfo()
            _uiState.update { it.copy(isClearingCache = false) }
        }
    }

    fun clearAllCaches() {
        viewModelScope.launch {
            _uiState.update { it.copy(isClearingCache = true) }
            cacheManager.clearAllCaches()
            loadCacheInfo()
            _uiState.update { it.copy(isClearingCache = false) }
        }
    }

    private fun formatSize(bytes: Long): String {
        return when {
            bytes < 1024 -> "$bytes B"
            bytes < 1024 * 1024 -> "${bytes / 1024} KB"
            bytes < 1024 * 1024 * 1024 -> "${bytes / (1024 * 1024)} MB"
            else -> "${"%.2f".format(bytes / (1024.0 * 1024.0 * 1024.0))} GB"
        }
    }

    // ==================== Device Enrollment Actions ====================

    private fun loadDeviceEnrollments() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoadingDevices = true) }

            // Check if current device is enrolled
            val isEnrolled = deviceRepository.isDeviceEnrolled()
            val enrollmentId = deviceRepository.getEnrollmentId()

            // Load all enrollments
            when (val result = deviceRepository.listEnrollments()) {
                is Result.Success -> {
                    _uiState.update {
                        it.copy(
                            isLoadingDevices = false,
                            isDeviceEnrolled = isEnrolled,
                            currentEnrollmentId = enrollmentId,
                            deviceEnrollments = result.data
                        )
                    }

                    // Register for push notifications if device is already enrolled
                    if (isEnrolled) {
                        _uiState.value.user?.id?.let { userId ->
                            deviceRepository.registerPushNotifications(userId)
                        }
                    }
                }
                is Result.Error -> {
                    _uiState.update {
                        it.copy(
                            isLoadingDevices = false,
                            isDeviceEnrolled = isEnrolled,
                            currentEnrollmentId = enrollmentId,
                            error = "Failed to load devices: ${result.exception.message}"
                        )
                    }
                }
            }
        }
    }

    fun enrollDevice() {
        viewModelScope.launch {
            _uiState.update { it.copy(isEnrollingDevice = true) }

            when (val result = deviceRepository.enrollDevice()) {
                is Result.Success -> {
                    _uiState.update {
                        it.copy(
                            isEnrollingDevice = false,
                            isDeviceEnrolled = true,
                            currentEnrollmentId = result.data.id
                        )
                    }

                    // Register for push notifications after successful enrollment
                    _uiState.value.user?.id?.let { userId ->
                        deviceRepository.registerPushNotifications(userId)
                    }

                    // Reload enrollments
                    loadDeviceEnrollments()
                }
                is Result.Error -> {
                    _uiState.update {
                        it.copy(
                            isEnrollingDevice = false,
                            error = "Failed to enroll device: ${result.exception.message}"
                        )
                    }
                }
            }
        }
    }

    fun revokeDevice(enrollmentId: String) {
        viewModelScope.launch {
            when (val result = deviceRepository.revokeEnrollment(enrollmentId)) {
                is Result.Success -> {
                    // Reload enrollments
                    loadDeviceEnrollments()
                }
                is Result.Error -> {
                    _uiState.update {
                        it.copy(error = "Failed to revoke device: ${result.exception.message}")
                    }
                }
            }
        }
    }

    fun renameDevice(enrollmentId: String, newName: String) {
        viewModelScope.launch {
            when (val result = deviceRepository.updateEnrollment(enrollmentId, newName)) {
                is Result.Success -> {
                    // Reload enrollments
                    loadDeviceEnrollments()
                }
                is Result.Error -> {
                    _uiState.update {
                        it.copy(error = "Failed to rename device: ${result.exception.message}")
                    }
                }
            }
        }
    }

    fun refreshDevices() {
        loadDeviceEnrollments()
    }
}
