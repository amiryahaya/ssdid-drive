package my.ssdid.drive.util

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringSetPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

private val Context.favoritesDataStore: DataStore<Preferences> by preferencesDataStore(name = "favorites")

/**
 * Manages favorite files and folders.
 *
 * Favorites are stored locally on the device using DataStore.
 * This is a client-side feature for quick access to frequently used items.
 */
@Singleton
class FavoritesManager @Inject constructor(
    @ApplicationContext private val context: Context
) {
    companion object {
        private val FAVORITE_FILES_KEY = stringSetPreferencesKey("favorite_files")
        private val FAVORITE_FOLDERS_KEY = stringSetPreferencesKey("favorite_folders")
    }

    /**
     * Flow of favorite file IDs.
     */
    val favoriteFileIds: Flow<Set<String>> = context.favoritesDataStore.data
        .map { preferences ->
            preferences[FAVORITE_FILES_KEY] ?: emptySet()
        }

    /**
     * Flow of favorite folder IDs.
     */
    val favoriteFolderIds: Flow<Set<String>> = context.favoritesDataStore.data
        .map { preferences ->
            preferences[FAVORITE_FOLDERS_KEY] ?: emptySet()
        }

    /**
     * Add a file to favorites.
     */
    suspend fun addFileFavorite(fileId: String) {
        context.favoritesDataStore.edit { preferences ->
            val current = preferences[FAVORITE_FILES_KEY] ?: emptySet()
            preferences[FAVORITE_FILES_KEY] = current + fileId
        }
    }

    /**
     * Remove a file from favorites.
     */
    suspend fun removeFileFavorite(fileId: String) {
        context.favoritesDataStore.edit { preferences ->
            val current = preferences[FAVORITE_FILES_KEY] ?: emptySet()
            preferences[FAVORITE_FILES_KEY] = current - fileId
        }
    }

    /**
     * Toggle a file's favorite status.
     */
    suspend fun toggleFileFavorite(fileId: String) {
        context.favoritesDataStore.edit { preferences ->
            val current = preferences[FAVORITE_FILES_KEY] ?: emptySet()
            preferences[FAVORITE_FILES_KEY] = if (fileId in current) {
                current - fileId
            } else {
                current + fileId
            }
        }
    }

    /**
     * Add a folder to favorites.
     */
    suspend fun addFolderFavorite(folderId: String) {
        context.favoritesDataStore.edit { preferences ->
            val current = preferences[FAVORITE_FOLDERS_KEY] ?: emptySet()
            preferences[FAVORITE_FOLDERS_KEY] = current + folderId
        }
    }

    /**
     * Remove a folder from favorites.
     */
    suspend fun removeFolderFavorite(folderId: String) {
        context.favoritesDataStore.edit { preferences ->
            val current = preferences[FAVORITE_FOLDERS_KEY] ?: emptySet()
            preferences[FAVORITE_FOLDERS_KEY] = current - folderId
        }
    }

    /**
     * Toggle a folder's favorite status.
     */
    suspend fun toggleFolderFavorite(folderId: String) {
        context.favoritesDataStore.edit { preferences ->
            val current = preferences[FAVORITE_FOLDERS_KEY] ?: emptySet()
            preferences[FAVORITE_FOLDERS_KEY] = if (folderId in current) {
                current - folderId
            } else {
                current + folderId
            }
        }
    }

    /**
     * Check if a file is a favorite.
     */
    fun isFileFavorite(fileId: String): Flow<Boolean> {
        return favoriteFileIds.map { it.contains(fileId) }
    }

    /**
     * Check if a folder is a favorite.
     */
    fun isFolderFavorite(folderId: String): Flow<Boolean> {
        return favoriteFolderIds.map { it.contains(folderId) }
    }

    /**
     * Clear all favorites (e.g., on logout).
     */
    suspend fun clearAll() {
        context.favoritesDataStore.edit { preferences ->
            preferences.remove(FAVORITE_FILES_KEY)
            preferences.remove(FAVORITE_FOLDERS_KEY)
        }
    }
}
