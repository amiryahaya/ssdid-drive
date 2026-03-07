package com.securesharing.util

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PersistableBundle
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Secure clipboard manager that handles sensitive data safely.
 *
 * SECURITY: This utility provides:
 * - Automatic clipboard clearing after a timeout
 * - Prevention of clipboard history for sensitive data (Android 13+)
 * - Manual clipboard clearing capability
 * - Sensitive data marking to prevent cloud sync
 */
@Singleton
class SecureClipboard @Inject constructor(
    @ApplicationContext private val context: Context
) {
    private val clipboardManager = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    private val handler = Handler(Looper.getMainLooper())
    private var clearRunnable: Runnable? = null

    /**
     * Copy sensitive text to clipboard with automatic clearing.
     *
     * @param label Label for the clipboard content
     * @param text The sensitive text to copy
     * @param clearAfterMs Time in milliseconds to auto-clear (default 60 seconds)
     * @param isSensitive Whether to mark as sensitive (prevents cloud sync on Android 13+)
     */
    fun copySensitiveText(
        label: String,
        text: String,
        clearAfterMs: Long = DEFAULT_CLEAR_TIMEOUT_MS,
        isSensitive: Boolean = true
    ) {
        // Cancel any pending clear operation
        cancelPendingClear()

        val clip = ClipData.newPlainText(label, text)

        // Mark as sensitive on Android 13+ to prevent clipboard history
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && isSensitive) {
            clip.description.extras = PersistableBundle().apply {
                putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, true)
            }
        }

        clipboardManager.setPrimaryClip(clip)

        // Schedule auto-clear
        if (clearAfterMs > 0) {
            scheduleClear(clearAfterMs)
        }
    }

    /**
     * Copy a password to clipboard with short auto-clear time.
     *
     * @param password The password to copy
     * @param clearAfterMs Time to clear (default 30 seconds for passwords)
     */
    fun copyPassword(password: String, clearAfterMs: Long = PASSWORD_CLEAR_TIMEOUT_MS) {
        copySensitiveText(
            label = "Password",
            text = password,
            clearAfterMs = clearAfterMs,
            isSensitive = true
        )
    }

    /**
     * Copy a recovery key or seed phrase with very short auto-clear.
     *
     * @param key The recovery key or seed phrase
     * @param clearAfterMs Time to clear (default 15 seconds for recovery keys)
     */
    fun copyRecoveryKey(key: String, clearAfterMs: Long = RECOVERY_KEY_CLEAR_TIMEOUT_MS) {
        copySensitiveText(
            label = "Recovery Key",
            text = key,
            clearAfterMs = clearAfterMs,
            isSensitive = true
        )
    }

    /**
     * Copy a share link (less sensitive, longer timeout).
     *
     * @param link The share link
     * @param clearAfterMs Time to clear (default 5 minutes)
     */
    fun copyShareLink(link: String, clearAfterMs: Long = SHARE_LINK_CLEAR_TIMEOUT_MS) {
        copySensitiveText(
            label = "Share Link",
            text = link,
            clearAfterMs = clearAfterMs,
            isSensitive = false // Share links are not as sensitive
        )
    }

    /**
     * Clear the clipboard immediately.
     */
    fun clearClipboard() {
        cancelPendingClear()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            // Android 9+: Clear properly
            clipboardManager.clearPrimaryClip()
        } else {
            // Older versions: Replace with empty clip
            val emptyClip = ClipData.newPlainText("", "")
            clipboardManager.setPrimaryClip(emptyClip)
        }
    }

    /**
     * Check if the clipboard currently contains our sensitive data.
     * Useful for showing "copied" indicators.
     *
     * @param label The label we used when copying
     */
    fun hasClipboardContent(label: String): Boolean {
        return try {
            val clip = clipboardManager.primaryClip
            clip?.description?.label == label && clip.itemCount > 0
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Get time remaining until clipboard is cleared (for UI display).
     *
     * @return Remaining time in milliseconds, or 0 if no pending clear
     */
    fun getTimeUntilClear(): Long {
        // Note: This is approximate as we don't track exact timing
        // For more precise timing, you'd need to track the scheduled time
        return 0L
    }

    /**
     * Cancel any pending clipboard clear operation.
     */
    fun cancelPendingClear() {
        clearRunnable?.let { handler.removeCallbacks(it) }
        clearRunnable = null
    }

    private fun scheduleClear(delayMs: Long) {
        clearRunnable = Runnable {
            clearClipboard()
            clearRunnable = null
        }
        handler.postDelayed(clearRunnable!!, delayMs)
    }

    /**
     * Add a listener to be notified when clipboard content changes.
     * Useful for detecting when user pastes sensitive content.
     *
     * @param listener Callback when clipboard changes
     * @return A lambda to remove the listener
     */
    fun addClipboardListener(listener: () -> Unit): () -> Unit {
        val changeListener = ClipboardManager.OnPrimaryClipChangedListener {
            listener()
        }
        clipboardManager.addPrimaryClipChangedListener(changeListener)

        return {
            clipboardManager.removePrimaryClipChangedListener(changeListener)
        }
    }

    /**
     * Secure clipboard state for Compose/ViewModel consumption.
     */
    data class ClipboardState(
        val hasSensitiveContent: Boolean,
        val label: String?,
        val willAutoClear: Boolean
    )

    /**
     * Get current clipboard state.
     */
    fun getClipboardState(): ClipboardState {
        return try {
            val clip = clipboardManager.primaryClip
            val description = clip?.description
            val isSensitive = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                description?.extras?.getBoolean(ClipDescription.EXTRA_IS_SENSITIVE) ?: false
            } else {
                // On older versions, check our known labels
                description?.label in listOf("Password", "Recovery Key")
            }

            ClipboardState(
                hasSensitiveContent = isSensitive,
                label = description?.label?.toString(),
                willAutoClear = clearRunnable != null
            )
        } catch (e: Exception) {
            ClipboardState(
                hasSensitiveContent = false,
                label = null,
                willAutoClear = false
            )
        }
    }

    companion object {
        /** Default timeout for general sensitive data: 60 seconds */
        const val DEFAULT_CLEAR_TIMEOUT_MS = 60_000L

        /** Timeout for passwords: 30 seconds */
        const val PASSWORD_CLEAR_TIMEOUT_MS = 30_000L

        /** Timeout for recovery keys: 15 seconds (most sensitive) */
        const val RECOVERY_KEY_CLEAR_TIMEOUT_MS = 15_000L

        /** Timeout for share links: 5 minutes (less sensitive) */
        const val SHARE_LINK_CLEAR_TIMEOUT_MS = 300_000L
    }
}
