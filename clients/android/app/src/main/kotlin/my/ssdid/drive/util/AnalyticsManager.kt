package my.ssdid.drive.util

import my.ssdid.drive.BuildConfig
import my.ssdid.drive.data.local.PreferencesManager
import io.sentry.SentryLevel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Privacy-preserving analytics facade.
 *
 * All events are opt-in (analytics disabled by default) and only sent
 * when both the user preference and build config allow it. Events are
 * sent as Sentry messages with structured tags for Discover/Issues
 * dashboard querying.
 *
 * SECURITY: No PII (file names, user emails, IPs) is ever included
 * in analytics events. Only anonymous, aggregate-safe data is sent.
 */
@Singleton
class AnalyticsManager @Inject constructor(
    preferencesManager: PreferencesManager
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /**
     * Eagerly cached preference value. Reads from in-memory StateFlow,
     * never blocks the calling thread. Defaults to false until the first
     * real value is emitted from DataStore.
     */
    private val analyticsEnabledFlow: StateFlow<Boolean> =
        preferencesManager.analyticsEnabled
            .stateIn(scope, SharingStarted.Eagerly, initialValue = false)

    /**
     * Check if analytics is allowed (build flag + user opt-in).
     * Non-blocking — reads from in-memory StateFlow.
     */
    private fun isEnabled(): Boolean {
        if (!BuildConfig.ENABLE_CRASH_REPORTING) return false
        return analyticsEnabledFlow.value
    }

    // ==================== Feature Usage Events ====================

    fun trackLogin(method: String) {
        sendEvent("login", mapOf("auth_method" to method))
    }

    fun trackFileUpload(mimeType: String, sizeBytes: Long) {
        sendEvent("file_upload", mapOf(
            "mime_category" to mimeCategory(mimeType),
            "size_bucket" to sizeBucket(sizeBytes)
        ))
    }

    fun trackFileDownload(mimeType: String, sizeBytes: Long) {
        sendEvent("file_download", mapOf(
            "mime_category" to mimeCategory(mimeType),
            "size_bucket" to sizeBucket(sizeBytes)
        ))
    }

    fun trackShare(resourceType: String, permission: String) {
        sendEvent("share", mapOf(
            "resource_type" to resourceType,
            "permission" to permission
        ))
    }

    fun trackFolderCreate() {
        sendEvent("folder_create")
    }

    fun trackSearch() {
        sendEvent("search")
    }

    fun trackRecoverySetup() {
        sendEvent("recovery_setup")
    }

    // ==================== Crypto Timing ====================

    fun trackCryptoTiming(operation: String, durationMs: Long, algorithm: String) {
        sendEvent("crypto_timing", mapOf(
            "operation" to operation,
            "duration_ms" to durationMs.toString(),
            "algorithm" to algorithm
        ))
    }

    // ==================== Navigation ====================

    fun trackNavigation(from: String, to: String) {
        sendEvent("navigation", mapOf("from" to from, "to" to to))
    }

    // ==================== User Identity ====================

    fun setUser(userId: String) {
        if (!isEnabled()) return
        SentryConfig.setAnonymousUser(userId)
    }

    fun clearUser() {
        // Always clear user on logout regardless of analytics preference.
        // Sentry.setUser(null) is idempotent when no user is set.
        SentryConfig.clearUser()
    }

    // ==================== Internal ====================

    private fun sendEvent(name: String, tags: Map<String, String> = emptyMap()) {
        if (!isEnabled()) return

        io.sentry.Sentry.withScope { scope ->
            scope.setTag("event_type", name)
            tags.forEach { (key, value) -> scope.setTag(key, value) }
            SentryConfig.captureMessage("analytics:$name", SentryLevel.INFO)
        }
    }

    /**
     * Generalize MIME type to a category to avoid leaking file content info.
     * e.g., "image/png" -> "image", "application/pdf" -> "document"
     */
    private fun mimeCategory(mimeType: String): String {
        return when {
            mimeType.startsWith("image/") -> "image"
            mimeType.startsWith("video/") -> "video"
            mimeType.startsWith("audio/") -> "audio"
            mimeType.startsWith("text/") -> "text"
            mimeType == "application/pdf" -> "document"
            mimeType.contains("spreadsheet") || mimeType.contains("excel") -> "spreadsheet"
            mimeType.contains("presentation") || mimeType.contains("powerpoint") -> "presentation"
            mimeType.contains("document") || mimeType.contains("word") -> "document"
            mimeType.contains("zip") || mimeType.contains("tar") || mimeType.contains("compressed") -> "archive"
            else -> "other"
        }
    }

    /**
     * Bucket file sizes to avoid leaking exact sizes.
     */
    private fun sizeBucket(sizeBytes: Long): String {
        return when {
            sizeBytes < 1024 -> "<1KB"
            sizeBytes < 1024 * 1024 -> "1KB-1MB"
            sizeBytes < 10 * 1024 * 1024 -> "1MB-10MB"
            sizeBytes < 100 * 1024 * 1024 -> "10MB-100MB"
            else -> ">100MB"
        }
    }
}
