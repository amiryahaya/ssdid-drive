package com.securesharing.util

import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Manages cached decrypted files for offline access.
 *
 * Security Notes:
 * - Cached files are stored in app-private directory
 * - Cache is cleared on logout
 * - Maximum cache size is enforced
 */
@Singleton
class CacheManager @Inject constructor(
    @ApplicationContext private val context: Context
) {
    companion object {
        private const val PREVIEW_CACHE_DIR = "preview_cache"
        private const val OFFLINE_CACHE_DIR = "offline_cache"
        private const val MAX_CACHE_SIZE_BYTES = 500L * 1024 * 1024 // 500 MB
        private const val MAX_FILE_AGE_DAYS = 7L
    }

    private val previewCacheDir: File by lazy {
        File(context.cacheDir, PREVIEW_CACHE_DIR).apply {
            if (!exists()) mkdirs()
        }
    }

    private val offlineCacheDir: File by lazy {
        File(context.filesDir, OFFLINE_CACHE_DIR).apply {
            if (!exists()) mkdirs()
        }
    }

    /**
     * Get a cached preview file if it exists.
     */
    fun getPreviewCache(fileId: String, fileName: String): File? {
        val cachedFile = File(previewCacheDir, "${fileId}_$fileName")
        return if (cachedFile.exists()) cachedFile else null
    }

    /**
     * Get the path for a preview cache file.
     */
    fun getPreviewCachePath(fileId: String, fileName: String): File {
        return File(previewCacheDir, "${fileId}_$fileName")
    }

    /**
     * Get a cached offline file if it exists.
     */
    fun getOfflineCache(fileId: String, fileName: String): File? {
        val cachedFile = File(offlineCacheDir, "${fileId}_$fileName")
        return if (cachedFile.exists()) cachedFile else null
    }

    /**
     * Get the path for an offline cache file.
     */
    fun getOfflineCachePath(fileId: String, fileName: String): File {
        return File(offlineCacheDir, "${fileId}_$fileName")
    }

    /**
     * Check if a file is available offline.
     */
    fun isAvailableOffline(fileId: String, fileName: String): Boolean {
        return getOfflineCache(fileId, fileName) != null
    }

    /**
     * Save a file to the offline cache.
     */
    suspend fun saveToOfflineCache(fileId: String, fileName: String, data: ByteArray): File =
        withContext(Dispatchers.IO) {
            val cacheFile = getOfflineCachePath(fileId, fileName)
            cacheFile.writeBytes(data)

            // Enforce cache size limits
            enforceCacheLimits()

            cacheFile
        }

    /**
     * Save a file to the offline cache from source file.
     */
    suspend fun saveToOfflineCache(fileId: String, fileName: String, sourceFile: File): File =
        withContext(Dispatchers.IO) {
            val cacheFile = getOfflineCachePath(fileId, fileName)
            sourceFile.copyTo(cacheFile, overwrite = true)

            // Enforce cache size limits
            enforceCacheLimits()

            cacheFile
        }

    /**
     * Remove a file from offline cache.
     */
    suspend fun removeFromOfflineCache(fileId: String, fileName: String) = withContext(Dispatchers.IO) {
        getOfflineCache(fileId, fileName)?.delete()
    }

    /**
     * Clear all preview cache.
     */
    suspend fun clearPreviewCache() = withContext(Dispatchers.IO) {
        previewCacheDir.listFiles()?.forEach { it.delete() }
    }

    /**
     * Clear all offline cache.
     */
    suspend fun clearOfflineCache() = withContext(Dispatchers.IO) {
        offlineCacheDir.listFiles()?.forEach { it.delete() }
    }

    /**
     * Clear all caches (call on logout).
     */
    suspend fun clearAllCaches() = withContext(Dispatchers.IO) {
        clearPreviewCache()
        clearOfflineCache()
    }

    /**
     * Get total cache size in bytes.
     */
    suspend fun getTotalCacheSize(): Long = withContext(Dispatchers.IO) {
        val previewSize = previewCacheDir.listFiles()?.sumOf { it.length() } ?: 0L
        val offlineSize = offlineCacheDir.listFiles()?.sumOf { it.length() } ?: 0L
        previewSize + offlineSize
    }

    /**
     * Get preview cache size in bytes.
     */
    suspend fun getPreviewCacheSize(): Long = withContext(Dispatchers.IO) {
        previewCacheDir.listFiles()?.sumOf { it.length() } ?: 0L
    }

    /**
     * Get offline cache size in bytes.
     */
    suspend fun getOfflineCacheSize(): Long = withContext(Dispatchers.IO) {
        offlineCacheDir.listFiles()?.sumOf { it.length() } ?: 0L
    }

    /**
     * Get formatted cache size string.
     */
    suspend fun getFormattedCacheSize(): String {
        val totalSize = getTotalCacheSize()
        return formatSize(totalSize)
    }

    /**
     * Get list of all offline cached file IDs.
     */
    suspend fun getOfflineCachedFileIds(): List<String> = withContext(Dispatchers.IO) {
        offlineCacheDir.listFiles()
            ?.mapNotNull { file ->
                // Extract fileId from filename format: {fileId}_{fileName}
                file.name.substringBefore('_').takeIf { it.isNotEmpty() }
            }
            ?.distinct()
            ?: emptyList()
    }

    /**
     * Enforce cache size limits by removing oldest files.
     */
    private suspend fun enforceCacheLimits() = withContext(Dispatchers.IO) {
        // Remove old preview cache files
        val now = System.currentTimeMillis()
        val maxAge = MAX_FILE_AGE_DAYS * 24 * 60 * 60 * 1000

        previewCacheDir.listFiles()?.forEach { file ->
            if (now - file.lastModified() > maxAge) {
                file.delete()
            }
        }

        // Check total size and remove oldest files if needed
        var totalSize = getTotalCacheSize()
        if (totalSize > MAX_CACHE_SIZE_BYTES) {
            // Sort all cache files by last modified (oldest first)
            val allFiles = mutableListOf<File>()
            previewCacheDir.listFiles()?.let { allFiles.addAll(it) }
            offlineCacheDir.listFiles()?.let { allFiles.addAll(it) }

            allFiles.sortBy { it.lastModified() }

            // Delete oldest files until under limit
            for (file in allFiles) {
                if (totalSize <= MAX_CACHE_SIZE_BYTES) break
                val fileSize = file.length()
                if (file.delete()) {
                    totalSize -= fileSize
                }
            }
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
}
