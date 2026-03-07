package com.securesharing.util

import android.util.Log
import com.securesharing.BuildConfig

/**
 * Secure logging utility that strips sensitive data before logging.
 *
 * SECURITY: This logger:
 * - Only logs in debug builds by default
 * - Strips sensitive data (tokens, passwords, keys) from messages
 * - Provides structured logging for crash reporting integration
 * - Tracks breadcrumbs for debugging
 */
object Logger {
    private const val TAG_PREFIX = "SecureSharing"
    private const val MAX_BREADCRUMBS = 100

    // Breadcrumbs for debugging (circular buffer)
    private val breadcrumbs = ArrayDeque<Breadcrumb>(MAX_BREADCRUMBS)

    // Patterns to redact from log messages
    private val sensitivePatterns = listOf(
        Regex("(password|passwd|pwd)[\"':\\s=]*[\"']?[^\"'\\s,}]+", RegexOption.IGNORE_CASE),
        Regex("(token|bearer|jwt|auth)[\"':\\s=]*[\"']?[A-Za-z0-9._-]+", RegexOption.IGNORE_CASE),
        Regex("(key|secret|private)[\"':\\s=]*[\"']?[A-Za-z0-9+/=]+", RegexOption.IGNORE_CASE),
        Regex("(email)[\"':\\s=]*[\"']?[\\w.+-]+@[\\w.-]+", RegexOption.IGNORE_CASE),
        Regex("[A-Za-z0-9+/]{40,}={0,2}"), // Long base64 strings (likely keys)
    )

    /**
     * Log a debug message.
     */
    fun d(tag: String, message: String, throwable: Throwable? = null) {
        if (BuildConfig.DEBUG) {
            val sanitized = sanitize(message)
            if (throwable != null) {
                Log.d("$TAG_PREFIX:$tag", sanitized, throwable)
            } else {
                Log.d("$TAG_PREFIX:$tag", sanitized)
            }
        }
        addBreadcrumb(LogLevel.DEBUG, tag, message)
    }

    /**
     * Log an info message.
     */
    fun i(tag: String, message: String, throwable: Throwable? = null) {
        if (BuildConfig.DEBUG) {
            val sanitized = sanitize(message)
            if (throwable != null) {
                Log.i("$TAG_PREFIX:$tag", sanitized, throwable)
            } else {
                Log.i("$TAG_PREFIX:$tag", sanitized)
            }
        }
        addBreadcrumb(LogLevel.INFO, tag, message)
    }

    /**
     * Log a warning message.
     */
    fun w(tag: String, message: String, throwable: Throwable? = null) {
        val sanitized = sanitize(message)
        if (BuildConfig.DEBUG) {
            if (throwable != null) {
                Log.w("$TAG_PREFIX:$tag", sanitized, throwable)
            } else {
                Log.w("$TAG_PREFIX:$tag", sanitized)
            }
        }
        addBreadcrumb(LogLevel.WARNING, tag, message, throwable)
    }

    /**
     * Log an error message.
     * Errors are always logged (even in release) for crash reporting.
     */
    fun e(tag: String, message: String, throwable: Throwable? = null) {
        val sanitized = sanitize(message)
        // Always log errors for crash reporting integration
        if (throwable != null) {
            Log.e("$TAG_PREFIX:$tag", sanitized, throwable)
        } else {
            Log.e("$TAG_PREFIX:$tag", sanitized)
        }
        addBreadcrumb(LogLevel.ERROR, tag, message, throwable)

        // In production, send to crash reporting service
        if (!BuildConfig.DEBUG) {
            reportError(tag, sanitized, throwable)
        }
    }

    /**
     * Log a security-related event.
     * These are always logged for audit purposes.
     */
    fun security(tag: String, event: String, details: Map<String, Any?> = emptyMap()) {
        val sanitizedDetails = details.mapValues { (_, v) ->
            when (v) {
                is String -> sanitize(v)
                else -> v
            }
        }
        val message = "SECURITY: $event | ${sanitizedDetails.entries.joinToString(", ") { "${it.key}=${it.value}" }}"

        Log.w("$TAG_PREFIX:$tag", message)
        addBreadcrumb(LogLevel.SECURITY, tag, message)

        // Always report security events in production
        if (!BuildConfig.DEBUG) {
            reportSecurityEvent(tag, event, sanitizedDetails)
        }
    }

    /**
     * Log a network request/response (debug only, heavily sanitized).
     */
    fun network(tag: String, method: String, url: String, statusCode: Int? = null, error: String? = null) {
        if (!BuildConfig.DEBUG) return

        val sanitizedUrl = sanitizeUrl(url)
        val message = buildString {
            append("$method $sanitizedUrl")
            statusCode?.let { append(" -> $it") }
            error?.let { append(" ERROR: ${sanitize(it)}") }
        }
        Log.d("$TAG_PREFIX:$tag", message)
        addBreadcrumb(LogLevel.DEBUG, tag, message)
    }

    /**
     * Log a crypto operation (for debugging crypto issues).
     */
    fun crypto(tag: String, operation: String, success: Boolean, details: String? = null) {
        val message = buildString {
            append("CRYPTO: $operation ")
            append(if (success) "SUCCESS" else "FAILED")
            details?.let { append(" - ${sanitize(it)}") }
        }

        if (success) {
            d(tag, message)
        } else {
            w(tag, message)
        }
    }

    /**
     * Get recent breadcrumbs for crash reporting.
     */
    fun getBreadcrumbs(): List<Breadcrumb> {
        return synchronized(breadcrumbs) {
            breadcrumbs.toList()
        }
    }

    /**
     * Clear breadcrumbs (e.g., on logout).
     */
    fun clearBreadcrumbs() {
        synchronized(breadcrumbs) {
            breadcrumbs.clear()
        }
    }

    // ==================== Private Helpers ====================

    private fun sanitize(message: String): String {
        var sanitized = message
        for (pattern in sensitivePatterns) {
            sanitized = sanitized.replace(pattern, "[REDACTED]")
        }
        return sanitized
    }

    private fun sanitizeUrl(url: String): String {
        // Remove query parameters that might contain sensitive data
        return url.substringBefore("?") +
            if (url.contains("?")) "?[params redacted]" else ""
    }

    private fun addBreadcrumb(
        level: LogLevel,
        tag: String,
        message: String,
        throwable: Throwable? = null
    ) {
        synchronized(breadcrumbs) {
            if (breadcrumbs.size >= MAX_BREADCRUMBS) {
                breadcrumbs.removeFirst()
            }
            breadcrumbs.addLast(
                Breadcrumb(
                    timestamp = System.currentTimeMillis(),
                    level = level,
                    tag = tag,
                    message = sanitize(message),
                    throwableClass = throwable?.javaClass?.simpleName
                )
            )
        }
    }

    private fun reportError(tag: String, message: String, throwable: Throwable?) {
        // Report to Sentry
        if (throwable != null) {
            SentryConfig.captureException(
                throwable = throwable,
                context = mapOf("tag" to tag, "message" to message)
            )
        } else {
            SentryConfig.captureMessage(
                message = "$tag: $message",
                level = io.sentry.SentryLevel.ERROR
            )
        }
    }

    private fun reportSecurityEvent(tag: String, event: String, details: Map<String, Any?>) {
        // Report security events to Sentry with SECURITY category
        io.sentry.Sentry.withScope { scope ->
            scope.setTag("category", "security")
            scope.setTag("security_event", event)
            details.forEach { (key, value) ->
                scope.setExtra(key, value?.toString() ?: "null")
            }
            SentryConfig.captureMessage(
                message = "SECURITY: $tag - $event",
                level = io.sentry.SentryLevel.WARNING
            )
        }
    }
}

/**
 * Log levels for breadcrumbs.
 */
enum class LogLevel {
    DEBUG,
    INFO,
    WARNING,
    ERROR,
    SECURITY
}

/**
 * A breadcrumb for tracking events leading up to an error.
 */
data class Breadcrumb(
    val timestamp: Long,
    val level: LogLevel,
    val tag: String,
    val message: String,
    val throwableClass: String? = null
) {
    override fun toString(): String {
        val time = java.text.SimpleDateFormat("HH:mm:ss.SSS", java.util.Locale.US)
            .format(java.util.Date(timestamp))
        return "[$time] ${level.name} $tag: $message${throwableClass?.let { " ($it)" } ?: ""}"
    }
}

/**
 * Extension function for easy logging from any class.
 */
fun Any.logD(message: String, throwable: Throwable? = null) {
    Logger.d(this::class.java.simpleName, message, throwable)
}

fun Any.logI(message: String, throwable: Throwable? = null) {
    Logger.i(this::class.java.simpleName, message, throwable)
}

fun Any.logW(message: String, throwable: Throwable? = null) {
    Logger.w(this::class.java.simpleName, message, throwable)
}

fun Any.logE(message: String, throwable: Throwable? = null) {
    Logger.e(this::class.java.simpleName, message, throwable)
}
