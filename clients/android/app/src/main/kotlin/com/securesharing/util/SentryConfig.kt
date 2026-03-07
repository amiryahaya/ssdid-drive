package com.securesharing.util

import android.content.Context
import io.sentry.Breadcrumb
import io.sentry.Hint
import io.sentry.SentryEvent
import io.sentry.SentryLevel
import io.sentry.SentryOptions
import io.sentry.android.core.SentryAndroid
import io.sentry.protocol.SentryException
import io.sentry.protocol.User

/**
 * Sentry configuration for crash reporting and performance monitoring.
 *
 * Security considerations:
 * - Strips sensitive data (passwords, tokens, keys) from crash reports
 * - Anonymizes user data by default
 * - Disables screenshot capture for security
 * - Only enabled in release builds by default
 */
object SentryConfig {

    // Patterns for sensitive data that should be scrubbed
    private val SENSITIVE_PATTERNS = listOf(
        Regex("password", RegexOption.IGNORE_CASE),
        Regex("token", RegexOption.IGNORE_CASE),
        Regex("secret", RegexOption.IGNORE_CASE),
        Regex("key", RegexOption.IGNORE_CASE),
        Regex("auth", RegexOption.IGNORE_CASE),
        Regex("bearer", RegexOption.IGNORE_CASE),
        Regex("credential", RegexOption.IGNORE_CASE),
        Regex("private", RegexOption.IGNORE_CASE),
        Regex("master", RegexOption.IGNORE_CASE),
        Regex("dek", RegexOption.IGNORE_CASE),
        Regex("kek", RegexOption.IGNORE_CASE),
        Regex("seed", RegexOption.IGNORE_CASE),
        Regex("mnemonic", RegexOption.IGNORE_CASE)
    )

    // Keys that should always be redacted
    private val REDACTED_KEYS = setOf(
        "password",
        "accessToken",
        "refreshToken",
        "access_token",
        "refresh_token",
        "Authorization",
        "authorization",
        "Cookie",
        "cookie",
        "Set-Cookie",
        "masterKey",
        "privateKey",
        "secretKey",
        "encryptedMasterKey",
        "wrapped_dek",
        "wrapped_kek",
        "kem_ciphertext",
        "signature"
    )

    private const val REDACTED = "[REDACTED]"

    /**
     * Initialize Sentry with security-conscious configuration.
     *
     * @param context Application context
     * @param dsn Sentry DSN (Data Source Name)
     * @param environment Environment name (e.g., "production", "staging", "debug")
     * @param enableInDebug Whether to enable Sentry in debug builds (default: false)
     */
    fun initialize(
        context: Context,
        dsn: String,
        environment: String = "production",
        enableInDebug: Boolean = false
    ) {
        // Skip initialization in debug if not enabled
        if (!enableInDebug && com.securesharing.BuildConfig.DEBUG) {
            return
        }

        SentryAndroid.init(context) { options ->
            options.dsn = dsn
            options.environment = environment

            // Release tracking
            options.release = "${com.securesharing.BuildConfig.APPLICATION_ID}@${com.securesharing.BuildConfig.VERSION_NAME}+${com.securesharing.BuildConfig.VERSION_CODE}"

            // Performance monitoring
            options.tracesSampleRate = if (environment == "production") 0.1 else 1.0
            options.profilesSampleRate = if (environment == "production") 0.1 else 1.0

            // Security settings
            options.isAttachScreenshot = false  // Don't capture screenshots (sensitive data)
            options.isAttachViewHierarchy = false  // Don't capture view hierarchy
            options.isSendDefaultPii = false  // Don't send PII by default

            // Session tracking
            options.isEnableAutoSessionTracking = true
            options.sessionTrackingIntervalMillis = 30000

            // Breadcrumb settings
            options.maxBreadcrumbs = 100
            options.isEnableActivityLifecycleBreadcrumbs = true
            options.isEnableAppLifecycleBreadcrumbs = true
            options.isEnableSystemEventBreadcrumbs = true
            options.isEnableAppComponentBreadcrumbs = true
            options.isEnableUserInteractionBreadcrumbs = true

            // Network breadcrumbs (without sensitive headers)
            options.isEnableNetworkEventBreadcrumbs = true

            // Custom data scrubbing
            options.beforeSend = SentryOptions.BeforeSendCallback { event, hint ->
                scrubSensitiveData(event)
            }

            // Breadcrumb filtering
            options.beforeBreadcrumb = SentryOptions.BeforeBreadcrumbCallback { breadcrumb, hint ->
                scrubBreadcrumb(breadcrumb)
            }

            // Filter out certain exception types
            options.addIgnoredExceptionForType(java.util.concurrent.CancellationException::class.java)
            options.addIgnoredExceptionForType(kotlinx.coroutines.CancellationException::class.java)
        }
    }

    /**
     * Scrub sensitive data from Sentry event before sending.
     */
    private fun scrubSensitiveData(event: SentryEvent): SentryEvent {
        // Scrub user data
        event.user?.let { user ->
            event.user = User().apply {
                // Only keep anonymized identifier
                id = user.id?.let { hashUserId(it) }
                // Remove email, username, IP address
                email = null
                username = null
                ipAddress = null
            }
        }

        // Scrub exception messages
        event.exceptions?.forEach { exception ->
            scrubException(exception)
        }

        // Scrub tags
        event.tags?.let { tags ->
            val scrubbed = tags.mapValues { (key, value) ->
                if (shouldRedactKey(key)) REDACTED else scrubValue(value)
            }
            event.setTags(scrubbed)
        }

        // Scrub extra data
        event.contexts.forEach { (contextName, context) ->
            if (context is Map<*, *>) {
                @Suppress("UNCHECKED_CAST")
                val scrubbed = (context as Map<String, Any?>).mapValues { (key, value) ->
                    if (shouldRedactKey(key)) REDACTED else value
                }
                event.contexts[contextName] = scrubbed
            }
        }

        return event
    }

    /**
     * Scrub sensitive data from exception.
     */
    private fun scrubException(exception: SentryException) {
        exception.value?.let { message ->
            exception.value = scrubValue(message)
        }
    }

    /**
     * Scrub sensitive data from breadcrumb.
     */
    private fun scrubBreadcrumb(breadcrumb: Breadcrumb): Breadcrumb? {
        // Remove breadcrumbs with sensitive categories
        if (breadcrumb.category in listOf("http", "xhr") &&
            breadcrumb.data?.keys?.any { shouldRedactKey(it) } == true) {
            // Scrub sensitive data values by setting them individually
            breadcrumb.data?.forEach { (key, value) ->
                if (shouldRedactKey(key)) {
                    breadcrumb.setData(key, REDACTED)
                }
            }
        }

        // Scrub message
        breadcrumb.message?.let { message ->
            breadcrumb.message = scrubValue(message)
        }

        return breadcrumb
    }

    /**
     * Check if a key should be redacted.
     */
    private fun shouldRedactKey(key: String): Boolean {
        return key in REDACTED_KEYS || SENSITIVE_PATTERNS.any { it.containsMatchIn(key) }
    }

    /**
     * Scrub sensitive patterns from a string value.
     */
    private fun scrubValue(value: String): String {
        var result = value

        // Redact Bearer tokens
        result = result.replace(Regex("Bearer\\s+[A-Za-z0-9\\-_\\.]+"), "Bearer $REDACTED")

        // Redact base64-encoded data that looks like keys/tokens (long strings)
        result = result.replace(Regex("[A-Za-z0-9+/=]{64,}"), REDACTED)

        // Redact hex-encoded data that looks like keys
        result = result.replace(Regex("[a-fA-F0-9]{64,}"), REDACTED)

        // Redact anything that looks like a password field value
        result = result.replace(Regex("(password|pwd|pass)[\"']?\\s*[:=]\\s*[\"']?[^\"'\\s]+", RegexOption.IGNORE_CASE), "password=$REDACTED")

        return result
    }

    /**
     * Hash user ID for anonymization.
     */
    private fun hashUserId(userId: String): String {
        return try {
            val digest = java.security.MessageDigest.getInstance("SHA-256")
            val hash = digest.digest(userId.toByteArray())
            hash.take(8).joinToString("") { "%02x".format(it) }
        } catch (e: Exception) {
            "anonymous"
        }
    }

    // ==================== Public API for Breadcrumbs ====================

    /**
     * Add a breadcrumb for crypto operations.
     * Sensitive data is automatically scrubbed.
     */
    fun addCryptoBreadcrumb(
        message: String,
        operation: String,
        algorithm: String? = null,
        success: Boolean = true
    ) {
        val breadcrumb = Breadcrumb().apply {
            this.message = message
            category = "crypto"
            type = "info"
            level = if (success) SentryLevel.INFO else SentryLevel.ERROR
            setData("operation", operation)
            algorithm?.let { setData("algorithm", it) }
            setData("success", success)
        }
        io.sentry.Sentry.addBreadcrumb(breadcrumb)
    }

    /**
     * Add a breadcrumb for file operations.
     */
    fun addFileBreadcrumb(
        message: String,
        operation: String,
        fileType: String? = null,
        sizeBytes: Long? = null
    ) {
        val breadcrumb = Breadcrumb().apply {
            this.message = message
            category = "file"
            type = "info"
            level = SentryLevel.INFO
            setData("operation", operation)
            fileType?.let { setData("fileType", it) }
            sizeBytes?.let { setData("sizeBytes", it) }
        }
        io.sentry.Sentry.addBreadcrumb(breadcrumb)
    }

    /**
     * Add a breadcrumb for sharing operations.
     */
    fun addShareBreadcrumb(
        message: String,
        operation: String,
        shareType: String? = null
    ) {
        val breadcrumb = Breadcrumb().apply {
            this.message = message
            category = "share"
            type = "info"
            level = SentryLevel.INFO
            setData("operation", operation)
            shareType?.let { setData("shareType", it) }
        }
        io.sentry.Sentry.addBreadcrumb(breadcrumb)
    }

    /**
     * Add a breadcrumb for navigation events.
     */
    fun addNavigationBreadcrumb(
        from: String,
        to: String
    ) {
        val breadcrumb = Breadcrumb().apply {
            message = "Navigation: $from -> $to"
            category = "navigation"
            type = "navigation"
            level = SentryLevel.INFO
            setData("from", from)
            setData("to", to)
        }
        io.sentry.Sentry.addBreadcrumb(breadcrumb)
    }

    /**
     * Set anonymous user identifier.
     */
    fun setAnonymousUser(userId: String) {
        io.sentry.Sentry.setUser(User().apply {
            id = hashUserId(userId)
        })
    }

    /**
     * Clear user on logout.
     */
    fun clearUser() {
        io.sentry.Sentry.setUser(null)
    }

    /**
     * Capture exception with additional context.
     */
    fun captureException(
        throwable: Throwable,
        context: Map<String, Any> = emptyMap()
    ) {
        io.sentry.Sentry.withScope { scope ->
            context.forEach { (key, value) ->
                if (!shouldRedactKey(key)) {
                    scope.setExtra(key, value.toString())
                }
            }
            io.sentry.Sentry.captureException(throwable)
        }
    }

    /**
     * Capture a message with level.
     */
    fun captureMessage(
        message: String,
        level: SentryLevel = SentryLevel.INFO
    ) {
        io.sentry.Sentry.captureMessage(scrubValue(message), level)
    }
}
