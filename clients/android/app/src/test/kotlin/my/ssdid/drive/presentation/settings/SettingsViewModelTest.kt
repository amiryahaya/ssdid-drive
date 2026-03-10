package my.ssdid.drive.presentation.settings

import app.cash.turbine.test
import my.ssdid.drive.crypto.KeyManager
import my.ssdid.drive.data.local.AutoLockTimeout
import my.ssdid.drive.data.local.PreferencesManager
import my.ssdid.drive.data.local.ThemeMode
import my.ssdid.drive.domain.model.DeviceEnrollment
import my.ssdid.drive.domain.model.DeviceEnrollmentStatus
import my.ssdid.drive.domain.model.DeviceKeyAlgorithm
import my.ssdid.drive.domain.model.TenantConfig
import my.ssdid.drive.domain.model.User
import my.ssdid.drive.domain.repository.AuthRepository
import my.ssdid.drive.domain.repository.DeviceRepository
import my.ssdid.drive.domain.repository.TenantRepository
import my.ssdid.drive.util.AppException
import my.ssdid.drive.util.BiometricAuthManager
import my.ssdid.drive.util.BiometricAvailability
import my.ssdid.drive.util.CacheManager
import my.ssdid.drive.util.Result
import io.mockk.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

/**
 * Unit tests for SettingsViewModel.
 *
 * Tests cover:
 * - User profile loading
 * - Profile updates
 * - Biometric enable/disable
 * - Device enrollment loading and revocation
 * - Cache operations
 * - Logout
 * - Error handling
 */
@OptIn(ExperimentalCoroutinesApi::class)
class SettingsViewModelTest {

    private lateinit var authRepository: AuthRepository
    private lateinit var tenantRepository: TenantRepository
    private lateinit var deviceRepository: DeviceRepository
    private lateinit var preferencesManager: PreferencesManager
    private lateinit var keyManager: KeyManager
    private lateinit var cacheManager: CacheManager
    private lateinit var biometricAuthManager: BiometricAuthManager
    private lateinit var viewModel: SettingsViewModel
    private val testDispatcher = StandardTestDispatcher()

    private val testUser = User(
        id = "user-123",
        email = "test@example.com",
        displayName = "Test User",
        tenantId = "tenant-123"
    )

    private val testEnrollment = DeviceEnrollment(
        id = "enrollment-1",
        deviceId = "device-1",
        deviceName = "Test Phone",
        status = DeviceEnrollmentStatus.ACTIVE,
        keyAlgorithm = DeviceKeyAlgorithm.KAZ_SIGN,
        enrolledAt = "2026-01-01T00:00:00Z",
        lastUsedAt = null,
        device = null
    )

    @Before
    fun setup() {
        Dispatchers.setMain(testDispatcher)
        authRepository = mockk(relaxed = true)
        tenantRepository = mockk(relaxed = true)
        deviceRepository = mockk(relaxed = true)
        preferencesManager = mockk(relaxed = true)
        keyManager = mockk(relaxed = true)
        cacheManager = mockk(relaxed = true)
        biometricAuthManager = mockk(relaxed = true)

        // Default stubs for init-triggered methods
        coEvery { authRepository.getCurrentUser() } returns Result.success(testUser)
        coEvery { tenantRepository.getTenantConfig() } returns Result.success(
            mockk { every { name } returns "Test Tenant" }
        )
        coEvery { authRepository.isBiometricUnlockEnabled() } returns false
        every { biometricAuthManager.isBiometricAvailable() } returns BiometricAvailability.AVAILABLE
        coEvery { cacheManager.getFormattedCacheSize() } returns "10 MB"
        coEvery { cacheManager.getPreviewCacheSize() } returns 5_000_000L
        coEvery { cacheManager.getOfflineCacheSize() } returns 3_000_000L
        coEvery { deviceRepository.isDeviceEnrolled() } returns true
        coEvery { deviceRepository.getEnrollmentId() } returns "enrollment-1"
        coEvery { deviceRepository.listEnrollments() } returns Result.success(listOf(testEnrollment))

        // Preferences flows
        every { preferencesManager.themeMode } returns flowOf(ThemeMode.SYSTEM)
        every { preferencesManager.biometricEnabled } returns flowOf(false)
        every { preferencesManager.autoLockEnabled } returns flowOf(true)
        every { preferencesManager.autoLockTimeout } returns flowOf(AutoLockTimeout.FIVE_MINUTES)
        every { preferencesManager.compactViewEnabled } returns flowOf(false)
        every { preferencesManager.showFileSizes } returns flowOf(true)
        every { preferencesManager.notificationsEnabled } returns flowOf(true)
        every { preferencesManager.shareNotificationsEnabled } returns flowOf(true)
        every { preferencesManager.recoveryNotificationsEnabled } returns flowOf(true)
        every { preferencesManager.analyticsEnabled } returns flowOf(false)
    }

    private fun createViewModel(): SettingsViewModel {
        return SettingsViewModel(
            authRepository = authRepository,
            tenantRepository = tenantRepository,
            deviceRepository = deviceRepository,
            preferencesManager = preferencesManager,
            keyManager = keyManager,
            cacheManager = cacheManager,
            biometricAuthManager = biometricAuthManager
        )
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    // ==================== User Profile Loading Tests ====================

    @Test
    fun `loadUserData sets user on success`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals(testUser, state.user)
            assertFalse(state.isLoading)
            assertNull(state.error)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `loadUserData sets error on failure`() = runTest {
        coEvery { authRepository.getCurrentUser() } returns Result.error(
            AppException.Network("Connection failed")
        )

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertNull(state.user)
            assertEquals("Connection failed", state.error)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `loadUserData loads tenant name`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals("Test Tenant", state.tenantName)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `loadUserData uses tenant id as fallback when tenant config fails`() = runTest {
        coEvery { tenantRepository.getTenantConfig() } returns Result.error(
            AppException.Network("Server error")
        )

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals("tenant-123", state.tenantName)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `refreshUserData reloads user data`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.refreshUserData()
        advanceUntilIdle()

        coVerify(atLeast = 2) { authRepository.getCurrentUser() }
    }

    // ==================== Profile Update Tests ====================

    @Test
    fun `updateProfile success updates user and hides dialog`() = runTest {
        val updatedUser = testUser.copy(displayName = "New Name")
        coEvery { authRepository.updateProfile("New Name") } returns Result.success(updatedUser)

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.updateProfile("New Name")
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals("New Name", state.user?.displayName)
            assertFalse(state.showEditProfileDialog)
            assertFalse(state.isUpdatingProfile)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `updateProfile failure sets profileUpdateError`() = runTest {
        coEvery { authRepository.updateProfile(any()) } returns Result.error(
            AppException.ValidationError("Name too long")
        )

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.updateProfile("Very Long Name")
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals("Name too long", state.profileUpdateError)
            assertFalse(state.isUpdatingProfile)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `updateProfile with blank name sends null`() = runTest {
        coEvery { authRepository.updateProfile(null) } returns Result.success(testUser)

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.updateProfile("")
        advanceUntilIdle()

        coVerify { authRepository.updateProfile(null) }
    }

    @Test
    fun `showEditProfileDialog sets flag`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.showEditProfileDialog()

        viewModel.uiState.test {
            val state = awaitItem()
            assertTrue(state.showEditProfileDialog)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `hideEditProfileDialog clears flag and error`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.showEditProfileDialog()
        viewModel.hideEditProfileDialog()

        viewModel.uiState.test {
            val state = awaitItem()
            assertFalse(state.showEditProfileDialog)
            assertNull(state.profileUpdateError)
            cancelAndIgnoreRemainingEvents()
        }
    }

    // ==================== Biometric Enable/Disable Tests ====================

    @Test
    fun `enableBiometric success updates state and preferences`() = runTest {
        coEvery { authRepository.enableBiometricUnlock() } returns Result.success(Unit)

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.enableBiometric()
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertTrue(state.biometricEnabled)
            assertFalse(state.isEnablingBiometric)
            cancelAndIgnoreRemainingEvents()
        }

        coVerify { preferencesManager.setBiometricEnabled(true) }
    }

    @Test
    fun `enableBiometric failure sets biometricSetupError`() = runTest {
        coEvery { authRepository.enableBiometricUnlock() } returns Result.error(
            AppException.CryptoError("Biometric hardware failure")
        )

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.enableBiometric()
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals("Biometric hardware failure", state.biometricSetupError)
            assertFalse(state.isEnablingBiometric)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `setBiometricEnabled true calls enableBiometric`() = runTest {
        coEvery { authRepository.enableBiometricUnlock() } returns Result.success(Unit)

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.setBiometricEnabled(true)
        advanceUntilIdle()

        coVerify { authRepository.enableBiometricUnlock() }
    }

    @Test
    fun `setBiometricEnabled false disables biometric`() = runTest {
        coEvery { authRepository.disableBiometricUnlock() } returns Result.success(Unit)

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.setBiometricEnabled(false)
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertFalse(state.biometricEnabled)
            cancelAndIgnoreRemainingEvents()
        }

        coVerify { preferencesManager.setBiometricEnabled(false) }
    }

    @Test
    fun `disableBiometric failure sets error`() = runTest {
        coEvery { authRepository.disableBiometricUnlock() } returns Result.error(
            AppException.Unknown("Failed to disable")
        )

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.setBiometricEnabled(false)
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals("Failed to disable", state.error)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `cancelBiometricSetup clears dialog and error`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.cancelBiometricSetup()

        viewModel.uiState.test {
            val state = awaitItem()
            assertFalse(state.showBiometricPasswordDialog)
            assertNull(state.biometricSetupError)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `clearBiometricSetupError clears error`() = runTest {
        coEvery { authRepository.enableBiometricUnlock() } returns Result.error(
            AppException.CryptoError("Error")
        )

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.enableBiometric()
        advanceUntilIdle()

        viewModel.clearBiometricSetupError()

        viewModel.uiState.test {
            val state = awaitItem()
            assertNull(state.biometricSetupError)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `biometricAvailable is true when hardware available`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertTrue(state.biometricAvailable)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `biometricAvailable is false when no hardware`() = runTest {
        every { biometricAuthManager.isBiometricAvailable() } returns BiometricAvailability.NO_HARDWARE

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertFalse(state.biometricAvailable)
            cancelAndIgnoreRemainingEvents()
        }
    }

    // ==================== Device Enrollment Tests ====================

    @Test
    fun `loadDeviceEnrollments sets devices on success`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertTrue(state.isDeviceEnrolled)
            assertEquals("enrollment-1", state.currentEnrollmentId)
            assertEquals(1, state.deviceEnrollments.size)
            assertFalse(state.isLoadingDevices)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `loadDeviceEnrollments sets error on failure`() = runTest {
        coEvery { deviceRepository.listEnrollments() } returns Result.error(
            AppException.Network("Server error")
        )

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertNotNull(state.error)
            assertTrue(state.error!!.contains("Failed to load devices"))
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `revokeDevice success reloads enrollments`() = runTest {
        coEvery { deviceRepository.revokeEnrollment("enrollment-1") } returns Result.success(Unit)

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.revokeDevice("enrollment-1")
        advanceUntilIdle()

        coVerify { deviceRepository.revokeEnrollment("enrollment-1") }
        coVerify(atLeast = 2) { deviceRepository.listEnrollments() }
    }

    @Test
    fun `revokeDevice failure sets error`() = runTest {
        coEvery { deviceRepository.revokeEnrollment("enrollment-1") } returns Result.error(
            AppException.Forbidden("Cannot revoke")
        )

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.revokeDevice("enrollment-1")
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertNotNull(state.error)
            assertTrue(state.error!!.contains("Failed to revoke device"))
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `enrollDevice success updates state and registers push`() = runTest {
        val newEnrollment = testEnrollment.copy(id = "enrollment-new")
        coEvery { deviceRepository.enrollDevice() } returns Result.success(newEnrollment)

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.enrollDevice()
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertTrue(state.isDeviceEnrolled)
            assertFalse(state.isEnrollingDevice)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `enrollDevice failure sets error`() = runTest {
        coEvery { deviceRepository.enrollDevice() } returns Result.error(
            AppException.Conflict("Already enrolled")
        )

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.enrollDevice()
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertNotNull(state.error)
            assertTrue(state.error!!.contains("Failed to enroll device"))
            assertFalse(state.isEnrollingDevice)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `renameDevice success reloads enrollments`() = runTest {
        coEvery { deviceRepository.updateEnrollment("enrollment-1", "New Name") } returns
            Result.success(testEnrollment.copy(deviceName = "New Name"))

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.renameDevice("enrollment-1", "New Name")
        advanceUntilIdle()

        coVerify { deviceRepository.updateEnrollment("enrollment-1", "New Name") }
        coVerify(atLeast = 2) { deviceRepository.listEnrollments() }
    }

    @Test
    fun `renameDevice failure sets error`() = runTest {
        coEvery { deviceRepository.updateEnrollment("enrollment-1", "New Name") } returns
            Result.error(AppException.NotFound("Enrollment not found"))

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.renameDevice("enrollment-1", "New Name")
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertNotNull(state.error)
            assertTrue(state.error!!.contains("Failed to rename device"))
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `refreshDevices reloads enrollments`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.refreshDevices()
        advanceUntilIdle()

        coVerify(atLeast = 2) { deviceRepository.listEnrollments() }
    }

    // ==================== Logout Tests ====================

    @Test
    fun `logout success clears preferences and sets isLoggedOut`() = runTest {
        coEvery { authRepository.logout() } returns Result.success(Unit)

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.logout()
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertTrue(state.isLoggedOut)
            cancelAndIgnoreRemainingEvents()
        }

        coVerify { preferencesManager.clearAll() }
    }

    @Test
    fun `logout failure still clears preferences and logs out locally`() = runTest {
        coEvery { authRepository.logout() } returns Result.error(
            AppException.Network("Server unreachable")
        )

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.logout()
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertTrue(state.isLoggedOut)
            cancelAndIgnoreRemainingEvents()
        }

        coVerify { preferencesManager.clearAll() }
    }

    // ==================== Error Handling Tests ====================

    @Test
    fun `clearError clears error state`() = runTest {
        coEvery { authRepository.getCurrentUser() } returns Result.error(
            AppException.Unknown("Some error")
        )

        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.clearError()

        viewModel.uiState.test {
            val state = awaitItem()
            assertNull(state.error)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `clearChangePasswordState clears password state`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.clearChangePasswordState()

        viewModel.uiState.test {
            val state = awaitItem()
            assertNull(state.changePasswordError)
            assertFalse(state.changePasswordSuccess)
            cancelAndIgnoreRemainingEvents()
        }
    }

    // ==================== Cache Tests ====================

    @Test
    fun `loadCacheInfo sets cache sizes`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.uiState.test {
            val state = awaitItem()
            assertEquals("10 MB", state.totalCacheSize)
            cancelAndIgnoreRemainingEvents()
        }
    }

    @Test
    fun `clearPreviewCache clears and reloads`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.clearPreviewCache()
        advanceUntilIdle()

        coVerify { cacheManager.clearPreviewCache() }
    }

    @Test
    fun `clearOfflineCache clears and reloads`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.clearOfflineCache()
        advanceUntilIdle()

        coVerify { cacheManager.clearOfflineCache() }
    }

    @Test
    fun `clearAllCaches clears and reloads`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.clearAllCaches()
        advanceUntilIdle()

        coVerify { cacheManager.clearAllCaches() }
    }

    // ==================== Preference Setting Tests ====================

    @Test
    fun `setThemeMode delegates to preferencesManager`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.setThemeMode(ThemeMode.DARK)
        advanceUntilIdle()

        coVerify { preferencesManager.setThemeMode(ThemeMode.DARK) }
    }

    @Test
    fun `setAutoLockEnabled delegates to preferencesManager`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.setAutoLockEnabled(false)
        advanceUntilIdle()

        coVerify { preferencesManager.setAutoLockEnabled(false) }
    }

    @Test
    fun `setAutoLockTimeout delegates to preferencesManager`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.setAutoLockTimeout(AutoLockTimeout.FIFTEEN_MINUTES)
        advanceUntilIdle()

        coVerify { preferencesManager.setAutoLockTimeout(AutoLockTimeout.FIFTEEN_MINUTES) }
    }

    @Test
    fun `setNotificationsEnabled delegates to preferencesManager`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.setNotificationsEnabled(false)
        advanceUntilIdle()

        coVerify { preferencesManager.setNotificationsEnabled(false) }
    }

    @Test
    fun `setAnalyticsEnabled delegates to preferencesManager`() = runTest {
        viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.setAnalyticsEnabled(true)
        advanceUntilIdle()

        coVerify { preferencesManager.setAnalyticsEnabled(true) }
    }
}
