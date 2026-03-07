package my.ssdid.drive.util

/**
 * A generic class that holds a value or an error.
 */
sealed class Result<out T> {

    /**
     * Represents a successful result with data.
     */
    data class Success<out T>(val data: T) : Result<T>()

    /**
     * Represents a failed result with an error.
     */
    data class Error(val exception: AppException) : Result<Nothing>()

    /**
     * Returns true if this is a Success result.
     */
    val isSuccess: Boolean get() = this is Success

    /**
     * Returns true if this is an Error result.
     */
    val isError: Boolean get() = this is Error

    /**
     * Returns the data if Success, null otherwise.
     */
    fun getOrNull(): T? = when (this) {
        is Success -> data
        is Error -> null
    }

    /**
     * Returns the exception if Error, null otherwise.
     */
    fun exceptionOrNull(): AppException? = when (this) {
        is Success -> null
        is Error -> exception
    }

    /**
     * Maps the success value to a new type.
     */
    inline fun <R> map(transform: (T) -> R): Result<R> = when (this) {
        is Success -> Success(transform(data))
        is Error -> this
    }

    /**
     * Maps the success value to a new Result.
     */
    inline fun <R> flatMap(transform: (T) -> Result<R>): Result<R> = when (this) {
        is Success -> transform(data)
        is Error -> this
    }

    /**
     * Executes the given block if this is a Success.
     */
    inline fun onSuccess(action: (T) -> Unit): Result<T> {
        if (this is Success) action(data)
        return this
    }

    /**
     * Executes the given block if this is an Error.
     */
    inline fun onError(action: (AppException) -> Unit): Result<T> {
        if (this is Error) action(exception)
        return this
    }

    /**
     * Folds the Result into a single value by applying one of two functions.
     *
     * @param onSuccess function to apply if this is a Success
     * @param onFailure function to apply if this is an Error
     * @return the result of applying the appropriate function
     */
    inline fun <R> fold(
        onSuccess: (T) -> R,
        onFailure: (AppException) -> R
    ): R = when (this) {
        is Success -> onSuccess(data)
        is Error -> onFailure(exception)
    }

    companion object {
        /**
         * Creates a Success result.
         */
        fun <T> success(data: T): Result<T> = Success(data)

        /**
         * Creates an Error result.
         */
        fun <T> error(exception: AppException): Result<T> = Error(exception)

        /**
         * Creates an Error result from a message.
         */
        fun <T> error(message: String): Result<T> = Error(AppException.Unknown(message))
    }
}

/**
 * Application-specific exceptions.
 */
sealed class AppException(
    override val message: String,
    override val cause: Throwable? = null
) : Exception(message, cause) {

    class Network(message: String = "Network error", cause: Throwable? = null) :
        AppException(message, cause)

    class Unauthorized(message: String = "Unauthorized") :
        AppException(message)

    class Forbidden(message: String = "Access denied") :
        AppException(message)

    class NotFound(message: String = "Not found") :
        AppException(message)

    class Conflict(message: String = "Conflict") :
        AppException(message)

    class QuotaExceeded(message: String = "Storage quota exceeded") :
        AppException(message)

    class CryptoError(message: String, cause: Throwable? = null) :
        AppException(message, cause)

    class SignatureInvalid(message: String = "Signature verification failed") :
        AppException(message)

    class ValidationError(message: String) :
        AppException(message)

    class Unknown(message: String = "Unknown error", cause: Throwable? = null) :
        AppException(message, cause)
}
