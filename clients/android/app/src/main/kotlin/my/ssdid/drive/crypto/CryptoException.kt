package my.ssdid.drive.crypto

/**
 * Base exception for all cryptographic operations.
 *
 * SECURITY: These exceptions provide specific error types to help
 * diagnose crypto issues while not leaking sensitive information.
 */
sealed class CryptoException(
    message: String,
    cause: Throwable? = null
) : Exception(message, cause) {

    /**
     * Get a user-friendly message for display.
     */
    abstract val userMessage: String

    /**
     * Get recovery suggestions for the user.
     */
    abstract val recoverySuggestions: List<String>

    /**
     * Whether this error might be recoverable with user action.
     */
    abstract val isRecoverable: Boolean
}

// ==================== Key-related Exceptions ====================

/**
 * Exception when key generation fails.
 */
class KeyGenerationException(
    message: String,
    cause: Throwable? = null,
    val keyType: KeyType? = null
) : CryptoException(message, cause) {

    override val userMessage: String
        get() = "Failed to generate encryption keys"

    override val recoverySuggestions: List<String>
        get() = listOf(
            "Try restarting the app",
            "Ensure your device has enough storage space",
            "If the problem persists, contact support"
        )

    override val isRecoverable: Boolean = true
}

/**
 * Exception when key derivation fails.
 */
class KeyDerivationException(
    message: String,
    cause: Throwable? = null
) : CryptoException(message, cause) {

    override val userMessage: String
        get() = "Failed to derive encryption key from password"

    override val recoverySuggestions: List<String>
        get() = listOf(
            "Double-check your password",
            "Try again in a moment"
        )

    override val isRecoverable: Boolean = true
}

/**
 * Exception when keys cannot be unlocked (wrong password).
 */
class KeyUnlockException(
    message: String,
    cause: Throwable? = null
) : CryptoException(message, cause) {

    override val userMessage: String
        get() = "Unable to unlock your encryption keys"

    override val recoverySuggestions: List<String>
        get() = listOf(
            "Make sure you entered the correct password",
            "If you forgot your password, use account recovery"
        )

    override val isRecoverable: Boolean = true
}

/**
 * Exception when keys are not available (user not logged in).
 */
class KeysNotAvailableException(
    message: String = "Encryption keys not available"
) : CryptoException(message) {

    override val userMessage: String
        get() = "Your encryption keys are not available"

    override val recoverySuggestions: List<String>
        get() = listOf(
            "Please log in again",
            "Your session may have expired"
        )

    override val isRecoverable: Boolean = true
}

/**
 * Exception when a key is corrupted or invalid.
 */
class InvalidKeyException(
    message: String,
    cause: Throwable? = null,
    val keyType: KeyType? = null
) : CryptoException(message, cause) {

    override val userMessage: String
        get() = "An encryption key appears to be invalid"

    override val recoverySuggestions: List<String>
        get() = listOf(
            "Try logging out and back in",
            "If the problem persists, you may need to use account recovery"
        )

    override val isRecoverable: Boolean = false
}

// ==================== Encryption/Decryption Exceptions ====================

/**
 * Exception when encryption fails.
 */
class EncryptionException(
    message: String,
    cause: Throwable? = null,
    val algorithm: String? = null
) : CryptoException(message, cause) {

    override val userMessage: String
        get() = "Failed to encrypt data"

    override val recoverySuggestions: List<String>
        get() = listOf(
            "Try the operation again",
            "If encrypting a file, ensure it's not corrupted"
        )

    override val isRecoverable: Boolean = true
}

/**
 * Exception when decryption fails.
 */
class DecryptionException(
    message: String,
    cause: Throwable? = null,
    val algorithm: String? = null
) : CryptoException(message, cause) {

    override val userMessage: String
        get() = "Failed to decrypt data"

    override val recoverySuggestions: List<String>
        get() = listOf(
            "The data may have been corrupted",
            "Try downloading the file again",
            "Contact the file owner if the problem persists"
        )

    override val isRecoverable: Boolean = false
}

/**
 * Exception when authentication tag verification fails (tampering detected).
 */
class AuthenticationException(
    message: String = "Data authentication failed - possible tampering detected",
    cause: Throwable? = null
) : CryptoException(message, cause) {

    override val userMessage: String
        get() = "Data integrity check failed"

    override val recoverySuggestions: List<String>
        get() = listOf(
            "The data may have been modified or corrupted",
            "Try downloading the file again",
            "If this keeps happening, the file may have been tampered with"
        )

    override val isRecoverable: Boolean = false
}

// ==================== Signature Exceptions ====================

/**
 * Exception when signature generation fails.
 */
class SignatureException(
    message: String,
    cause: Throwable? = null,
    val algorithm: String? = null
) : CryptoException(message, cause) {

    override val userMessage: String
        get() = "Failed to sign data"

    override val recoverySuggestions: List<String>
        get() = listOf(
            "Try the operation again",
            "If the problem persists, try logging out and back in"
        )

    override val isRecoverable: Boolean = true
}

/**
 * Exception when signature verification fails.
 */
class SignatureVerificationException(
    message: String = "Signature verification failed",
    cause: Throwable? = null,
    val algorithm: String? = null
) : CryptoException(message, cause) {

    override val userMessage: String
        get() = "Could not verify the authenticity of this data"

    override val recoverySuggestions: List<String>
        get() = listOf(
            "The data may have been modified since it was signed",
            "Contact the sender to verify the content",
            "Do not trust this data until verified"
        )

    override val isRecoverable: Boolean = false
}

// ==================== KEM Exceptions ====================

/**
 * Exception when KEM encapsulation fails.
 */
class EncapsulationException(
    message: String,
    cause: Throwable? = null,
    val algorithm: String? = null
) : CryptoException(message, cause) {

    override val userMessage: String
        get() = "Failed to establish secure key exchange"

    override val recoverySuggestions: List<String>
        get() = listOf(
            "Try the operation again",
            "The recipient's public key may be invalid"
        )

    override val isRecoverable: Boolean = true
}

/**
 * Exception when KEM decapsulation fails.
 */
class DecapsulationException(
    message: String,
    cause: Throwable? = null,
    val algorithm: String? = null
) : CryptoException(message, cause) {

    override val userMessage: String
        get() = "Failed to decrypt the shared key"

    override val recoverySuggestions: List<String>
        get() = listOf(
            "You may not have permission to access this content",
            "Try logging out and back in",
            "Contact the file owner for assistance"
        )

    override val isRecoverable: Boolean = false
}

// ==================== Recovery Exceptions ====================

/**
 * Exception when secret sharing fails.
 */
class SecretSharingException(
    message: String,
    cause: Throwable? = null
) : CryptoException(message, cause) {

    override val userMessage: String
        get() = "Failed to split or reconstruct your recovery key"

    override val recoverySuggestions: List<String>
        get() = listOf(
            "Ensure you have the required number of recovery shares",
            "Verify that all shares are valid and undamaged"
        )

    override val isRecoverable: Boolean = true
}

/**
 * Exception when not enough shares are available for reconstruction.
 */
class InsufficientSharesException(
    val required: Int,
    val available: Int
) : CryptoException("Need $required shares but only have $available") {

    override val userMessage: String
        get() = "Not enough recovery shares to restore your account"

    override val recoverySuggestions: List<String>
        get() = listOf(
            "You need $required shares but only have $available",
            "Contact more of your designated trustees",
            "Each trustee needs to provide their share"
        )

    override val isRecoverable: Boolean = true
}

// ==================== Algorithm Exceptions ====================

/**
 * Exception when an algorithm is not supported.
 */
class UnsupportedAlgorithmException(
    val algorithm: String,
    message: String = "Algorithm not supported: $algorithm"
) : CryptoException(message) {

    override val userMessage: String
        get() = "This encryption method is not supported"

    override val recoverySuggestions: List<String>
        get() = listOf(
            "Update the app to the latest version",
            "This content may require a newer version of the app"
        )

    override val isRecoverable: Boolean = false
}

/**
 * Exception when native library fails to load.
 */
class NativeLibraryException(
    val libraryName: String,
    cause: Throwable? = null
) : CryptoException("Failed to load native library: $libraryName", cause) {

    override val userMessage: String
        get() = "A required security component failed to load"

    override val recoverySuggestions: List<String>
        get() = listOf(
            "Try restarting the app",
            "Reinstall the app if the problem persists",
            "Make sure you're using a supported device"
        )

    override val isRecoverable: Boolean = false
}

// ==================== Key Types ====================

/**
 * Types of cryptographic keys.
 */
enum class KeyType {
    MASTER_KEY,
    KEM_PUBLIC,
    KEM_PRIVATE,
    SIGN_PUBLIC,
    SIGN_PRIVATE,
    ML_KEM_PUBLIC,
    ML_KEM_PRIVATE,
    ML_DSA_PUBLIC,
    ML_DSA_PRIVATE,
    FOLDER_KEK,
    FILE_DEK
}
