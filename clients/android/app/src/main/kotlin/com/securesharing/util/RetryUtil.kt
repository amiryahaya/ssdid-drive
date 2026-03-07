package com.securesharing.util

import kotlinx.coroutines.delay
import java.io.IOException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import javax.net.ssl.SSLException
import kotlin.math.min
import kotlin.math.pow

/**
 * Utility for retrying operations with exponential backoff.
 *
 * SECURITY: Implements retry logic for transient errors while ensuring
 * sensitive operations are not retried inappropriately.
 */
object RetryUtil {

    /**
     * Default retry configuration.
     */
    val DEFAULT_CONFIG = RetryConfig(
        maxAttempts = 3,
        initialDelayMs = 1000L,
        maxDelayMs = 30000L,
        backoffMultiplier = 2.0,
        retryableExceptions = setOf(
            IOException::class.java,
            SocketTimeoutException::class.java,
            UnknownHostException::class.java
        )
    )

    /**
     * Configuration for network-heavy operations.
     */
    val NETWORK_CONFIG = RetryConfig(
        maxAttempts = 5,
        initialDelayMs = 500L,
        maxDelayMs = 60000L,
        backoffMultiplier = 2.0,
        retryableExceptions = setOf(
            IOException::class.java,
            SocketTimeoutException::class.java,
            UnknownHostException::class.java,
            SSLException::class.java
        )
    )

    /**
     * Configuration for crypto operations (fewer retries, not network-related).
     */
    val CRYPTO_CONFIG = RetryConfig(
        maxAttempts = 2,
        initialDelayMs = 100L,
        maxDelayMs = 1000L,
        backoffMultiplier = 2.0,
        retryableExceptions = emptySet() // Crypto errors are usually not transient
    )

    /**
     * Execute an operation with retry logic.
     *
     * @param config Retry configuration
     * @param operation The operation to execute
     * @return The result of the operation
     * @throws Exception if all retries fail
     */
    suspend fun <T> withRetry(
        config: RetryConfig = DEFAULT_CONFIG,
        onRetry: ((attempt: Int, exception: Exception, delayMs: Long) -> Unit)? = null,
        operation: suspend () -> T
    ): T {
        var lastException: Exception? = null
        var currentDelay = config.initialDelayMs

        repeat(config.maxAttempts) { attempt ->
            try {
                return operation()
            } catch (e: Exception) {
                lastException = e

                // Check if this exception is retryable
                if (!isRetryable(e, config)) {
                    throw e
                }

                // Check if we have more attempts
                if (attempt == config.maxAttempts - 1) {
                    throw e
                }

                // Log retry attempt
                Logger.w(
                    "RetryUtil",
                    "Attempt ${attempt + 1}/${config.maxAttempts} failed: ${e.message}. " +
                        "Retrying in ${currentDelay}ms"
                )

                // Notify callback
                onRetry?.invoke(attempt + 1, e, currentDelay)

                // Wait before retry
                delay(currentDelay)

                // Calculate next delay with jitter
                currentDelay = calculateNextDelay(currentDelay, config)
            }
        }

        throw lastException ?: IllegalStateException("Retry failed with no exception")
    }

    /**
     * Execute an operation with retry, returning a Result instead of throwing.
     */
    suspend fun <T> withRetryResult(
        config: RetryConfig = DEFAULT_CONFIG,
        onRetry: ((attempt: Int, exception: Exception, delayMs: Long) -> Unit)? = null,
        operation: suspend () -> T
    ): kotlin.Result<T> {
        return try {
            kotlin.Result.success(withRetry(config, onRetry, operation))
        } catch (e: Exception) {
            kotlin.Result.failure(e)
        }
    }

    /**
     * Check if an exception is retryable.
     */
    fun isRetryable(exception: Exception, config: RetryConfig = DEFAULT_CONFIG): Boolean {
        // Check against configured retryable exceptions
        if (config.retryableExceptions.any { it.isInstance(exception) }) {
            return true
        }

        // Check cause chain
        var cause = exception.cause
        while (cause != null) {
            if (config.retryableExceptions.any { it.isInstance(cause) }) {
                return true
            }
            cause = cause.cause
        }

        return false
    }

    /**
     * Check if an HTTP status code indicates a retryable error.
     */
    fun isRetryableStatusCode(statusCode: Int): Boolean {
        return statusCode in RETRYABLE_STATUS_CODES
    }

    /**
     * Get a user-friendly message for transient errors.
     */
    fun getTransientErrorMessage(exception: Exception): String {
        return when (exception) {
            is SocketTimeoutException -> "The server took too long to respond. Please try again."
            is UnknownHostException -> "Unable to reach the server. Please check your internet connection."
            is SSLException -> "Secure connection failed. Please try again."
            is IOException -> "A network error occurred. Please try again."
            else -> exception.message ?: "An unexpected error occurred. Please try again."
        }
    }

    private fun calculateNextDelay(currentDelay: Long, config: RetryConfig): Long {
        // Exponential backoff with jitter
        val nextDelay = (currentDelay * config.backoffMultiplier).toLong()
        val jitter = (nextDelay * 0.1 * Math.random()).toLong() // 10% jitter
        return min(nextDelay + jitter, config.maxDelayMs)
    }

    private val RETRYABLE_STATUS_CODES = setOf(
        408, // Request Timeout
        429, // Too Many Requests
        500, // Internal Server Error
        502, // Bad Gateway
        503, // Service Unavailable
        504  // Gateway Timeout
    )
}

/**
 * Configuration for retry behavior.
 */
data class RetryConfig(
    val maxAttempts: Int,
    val initialDelayMs: Long,
    val maxDelayMs: Long,
    val backoffMultiplier: Double,
    val retryableExceptions: Set<Class<out Exception>>
)

/**
 * Result of a retried operation with metadata.
 */
data class RetryResult<T>(
    val value: T?,
    val success: Boolean,
    val attempts: Int,
    val totalDelayMs: Long,
    val lastException: Exception?
)

/**
 * Extension function for suspending operations with retry.
 */
suspend fun <T> (suspend () -> T).withRetry(
    config: RetryConfig = RetryUtil.DEFAULT_CONFIG
): T = RetryUtil.withRetry(config) { this() }

/**
 * Extension function for retrying with custom exception handling.
 */
suspend fun <T> retryOnNetworkError(
    maxAttempts: Int = 3,
    operation: suspend () -> T
): T = RetryUtil.withRetry(
    config = RetryUtil.NETWORK_CONFIG.copy(maxAttempts = maxAttempts),
    operation = operation
)
