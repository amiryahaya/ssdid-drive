package my.ssdid.drive.data.local

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.core.stringSetPreferencesKey
import kotlinx.coroutines.flow.first
import androidx.datastore.preferences.preferencesDataStore
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

private val Context.dataStore: DataStore<Preferences> by preferencesDataStore(name = "settings")

/**
 * App preferences for non-sensitive settings using DataStore.
 */
@Singleton
class PreferencesManager @Inject constructor(
    @ApplicationContext private val context: Context
) {
    private val dataStore = context.dataStore

    // ==================== Onboarding ====================

    val hasCompletedOnboarding: Flow<Boolean> = dataStore.data.map { preferences ->
        preferences[HAS_COMPLETED_ONBOARDING] ?: false
    }

    suspend fun hasCompletedOnboardingSync(): Boolean {
        return dataStore.data.first()[HAS_COMPLETED_ONBOARDING] ?: false
    }

    suspend fun setOnboardingCompleted() {
        dataStore.edit { preferences ->
            preferences[HAS_COMPLETED_ONBOARDING] = true
        }
    }

    // ==================== Theme Settings ====================

    val darkModeEnabled: Flow<Boolean> = dataStore.data.map { preferences ->
        preferences[DARK_MODE_ENABLED] ?: false
    }

    suspend fun setDarkModeEnabled(enabled: Boolean) {
        dataStore.edit { preferences ->
            preferences[DARK_MODE_ENABLED] = enabled
        }
    }

    val themeMode: Flow<ThemeMode> = dataStore.data.map { preferences ->
        val value = preferences[THEME_MODE] ?: ThemeMode.SYSTEM.name
        ThemeMode.valueOf(value)
    }

    suspend fun setThemeMode(mode: ThemeMode) {
        dataStore.edit { preferences ->
            preferences[THEME_MODE] = mode.name
        }
    }

    // ==================== Security Settings ====================

    val biometricEnabled: Flow<Boolean> = dataStore.data.map { preferences ->
        preferences[BIOMETRIC_ENABLED] ?: false
    }

    suspend fun setBiometricEnabled(enabled: Boolean) {
        dataStore.edit { preferences ->
            preferences[BIOMETRIC_ENABLED] = enabled
        }
    }

    val autoLockEnabled: Flow<Boolean> = dataStore.data.map { preferences ->
        preferences[AUTO_LOCK_ENABLED] ?: true
    }

    suspend fun setAutoLockEnabled(enabled: Boolean) {
        dataStore.edit { preferences ->
            preferences[AUTO_LOCK_ENABLED] = enabled
        }
    }

    val autoLockTimeout: Flow<AutoLockTimeout> = dataStore.data.map { preferences ->
        val value = preferences[AUTO_LOCK_TIMEOUT] ?: AutoLockTimeout.FIVE_MINUTES.name
        AutoLockTimeout.valueOf(value)
    }

    suspend fun setAutoLockTimeout(timeout: AutoLockTimeout) {
        dataStore.edit { preferences ->
            preferences[AUTO_LOCK_TIMEOUT] = timeout.name
        }
    }

    // ==================== Notification Settings ====================

    val notificationsEnabled: Flow<Boolean> = dataStore.data.map { preferences ->
        preferences[NOTIFICATIONS_ENABLED] ?: true
    }

    suspend fun setNotificationsEnabled(enabled: Boolean) {
        dataStore.edit { preferences ->
            preferences[NOTIFICATIONS_ENABLED] = enabled
        }
    }

    val shareNotificationsEnabled: Flow<Boolean> = dataStore.data.map { preferences ->
        preferences[SHARE_NOTIFICATIONS_ENABLED] ?: true
    }

    suspend fun setShareNotificationsEnabled(enabled: Boolean) {
        dataStore.edit { preferences ->
            preferences[SHARE_NOTIFICATIONS_ENABLED] = enabled
        }
    }

    val recoveryNotificationsEnabled: Flow<Boolean> = dataStore.data.map { preferences ->
        preferences[RECOVERY_NOTIFICATIONS_ENABLED] ?: true
    }

    suspend fun setRecoveryNotificationsEnabled(enabled: Boolean) {
        dataStore.edit { preferences ->
            preferences[RECOVERY_NOTIFICATIONS_ENABLED] = enabled
        }
    }

    // ==================== Analytics Settings ====================

    val analyticsEnabled: Flow<Boolean> = dataStore.data.map { preferences ->
        preferences[ANALYTICS_ENABLED] ?: false
    }

    suspend fun setAnalyticsEnabled(enabled: Boolean) {
        dataStore.edit { preferences ->
            preferences[ANALYTICS_ENABLED] = enabled
        }
    }

    // ==================== Display Settings ====================

    val compactViewEnabled: Flow<Boolean> = dataStore.data.map { preferences ->
        preferences[COMPACT_VIEW_ENABLED] ?: false
    }

    suspend fun setCompactViewEnabled(enabled: Boolean) {
        dataStore.edit { preferences ->
            preferences[COMPACT_VIEW_ENABLED] = enabled
        }
    }

    val showFileSizes: Flow<Boolean> = dataStore.data.map { preferences ->
        preferences[SHOW_FILE_SIZES] ?: true
    }

    suspend fun setShowFileSizes(enabled: Boolean) {
        dataStore.edit { preferences ->
            preferences[SHOW_FILE_SIZES] = enabled
        }
    }

    // ==================== Favorites ====================

    val favoriteFileIds: Flow<Set<String>> = dataStore.data.map { preferences ->
        preferences[FAVORITE_FILE_IDS] ?: emptySet()
    }

    suspend fun isFavorite(fileId: String): Boolean {
        return dataStore.data.first()[FAVORITE_FILE_IDS]?.contains(fileId) ?: false
    }

    suspend fun addFavorite(fileId: String) {
        dataStore.edit { preferences ->
            val currentFavorites = preferences[FAVORITE_FILE_IDS] ?: emptySet()
            preferences[FAVORITE_FILE_IDS] = currentFavorites + fileId
        }
    }

    suspend fun removeFavorite(fileId: String) {
        dataStore.edit { preferences ->
            val currentFavorites = preferences[FAVORITE_FILE_IDS] ?: emptySet()
            preferences[FAVORITE_FILE_IDS] = currentFavorites - fileId
        }
    }

    suspend fun toggleFavorite(fileId: String): Boolean {
        val isFavorite = isFavorite(fileId)
        if (isFavorite) {
            removeFavorite(fileId)
        } else {
            addFavorite(fileId)
        }
        return !isFavorite
    }

    // ==================== Clear All ====================

    suspend fun clearAll() {
        dataStore.edit { it.clear() }
    }

    companion object {
        // Onboarding
        private val HAS_COMPLETED_ONBOARDING = booleanPreferencesKey("has_completed_onboarding")

        // Theme
        private val DARK_MODE_ENABLED = booleanPreferencesKey("dark_mode_enabled")
        private val THEME_MODE = stringPreferencesKey("theme_mode")

        // Security
        private val BIOMETRIC_ENABLED = booleanPreferencesKey("biometric_enabled")
        private val AUTO_LOCK_ENABLED = booleanPreferencesKey("auto_lock_enabled")
        private val AUTO_LOCK_TIMEOUT = stringPreferencesKey("auto_lock_timeout")

        // Notifications
        private val NOTIFICATIONS_ENABLED = booleanPreferencesKey("notifications_enabled")
        private val SHARE_NOTIFICATIONS_ENABLED = booleanPreferencesKey("share_notifications_enabled")
        private val RECOVERY_NOTIFICATIONS_ENABLED = booleanPreferencesKey("recovery_notifications_enabled")

        // Analytics
        private val ANALYTICS_ENABLED = booleanPreferencesKey("analytics_enabled")

        // Display
        private val COMPACT_VIEW_ENABLED = booleanPreferencesKey("compact_view_enabled")
        private val SHOW_FILE_SIZES = booleanPreferencesKey("show_file_sizes")

        // Favorites
        private val FAVORITE_FILE_IDS = stringSetPreferencesKey("favorite_file_ids")
    }
}

enum class ThemeMode {
    LIGHT,
    DARK,
    SYSTEM
}

enum class AutoLockTimeout(val minutes: Int, val displayName: String) {
    IMMEDIATELY(0, "Immediately"),
    ONE_MINUTE(1, "1 minute"),
    FIVE_MINUTES(5, "5 minutes"),
    FIFTEEN_MINUTES(15, "15 minutes"),
    THIRTY_MINUTES(30, "30 minutes"),
    NEVER(-1, "Never")
}
