package com.securesharing.util

/**
 * Validation utilities for input sanitization and security checks.
 *
 * SECURITY: These functions help prevent various attacks including:
 * - Buffer overflow via oversized inputs
 * - Injection attacks via malformed strings
 * - DoS attacks via resource exhaustion
 */
object Validation {

    // ==================== Size Limits ====================

    /** Maximum file size: 100MB */
    const val MAX_FILE_SIZE = 100L * 1024 * 1024

    /** Maximum file name length */
    const val MAX_FILENAME_LENGTH = 255

    /** Maximum email length */
    const val MAX_EMAIL_LENGTH = 254

    /** Maximum password length (to prevent DoS) */
    const val MAX_PASSWORD_LENGTH = 128

    /** Minimum password length */
    const val MIN_PASSWORD_LENGTH = 8

    /** Maximum tenant ID length */
    const val MAX_TENANT_LENGTH = 64

    /** Maximum folder/file ID length */
    const val MAX_ID_LENGTH = 64

    /** Maximum encrypted data length (Base64): 10MB */
    const val MAX_ENCRYPTED_DATA_LENGTH = 10 * 1024 * 1024

    /** Maximum number of items in a list request */
    const val MAX_LIST_SIZE = 1000

    /** Maximum share recipients */
    const val MAX_SHARE_RECIPIENTS = 100

    /** Maximum recovery trustees */
    const val MAX_RECOVERY_TRUSTEES = 10

    // ==================== Validation Functions ====================

    /**
     * Validate an email address.
     *
     * @param email The email to validate
     * @return ValidationResult
     */
    fun validateEmail(email: String?): ValidationResult {
        if (email.isNullOrBlank()) {
            return ValidationResult.Invalid("Email is required")
        }
        if (email.length > MAX_EMAIL_LENGTH) {
            return ValidationResult.Invalid("Email is too long (max $MAX_EMAIL_LENGTH characters)")
        }
        if (!android.util.Patterns.EMAIL_ADDRESS.matcher(email).matches()) {
            return ValidationResult.Invalid("Invalid email format")
        }
        return ValidationResult.Valid
    }

    /**
     * Validate a password.
     *
     * @param password The password to validate
     * @return ValidationResult
     */
    fun validatePassword(password: String?): ValidationResult {
        if (password.isNullOrBlank()) {
            return ValidationResult.Invalid("Password is required")
        }
        if (password.length < MIN_PASSWORD_LENGTH) {
            return ValidationResult.Invalid("Password must be at least $MIN_PASSWORD_LENGTH characters")
        }
        if (password.length > MAX_PASSWORD_LENGTH) {
            return ValidationResult.Invalid("Password is too long (max $MAX_PASSWORD_LENGTH characters)")
        }
        return ValidationResult.Valid
    }

    /**
     * Validate a tenant ID.
     *
     * @param tenant The tenant ID to validate
     * @return ValidationResult
     */
    fun validateTenant(tenant: String?): ValidationResult {
        if (tenant.isNullOrBlank()) {
            return ValidationResult.Invalid("Organization is required")
        }
        if (tenant.length > MAX_TENANT_LENGTH) {
            return ValidationResult.Invalid("Organization ID is too long")
        }
        // Only allow alphanumeric, dash, and underscore
        if (!tenant.matches(Regex("^[a-zA-Z0-9_-]+$"))) {
            return ValidationResult.Invalid("Organization ID contains invalid characters")
        }
        return ValidationResult.Valid
    }

    /**
     * Validate a resource ID (file, folder, share, etc.).
     *
     * @param id The ID to validate
     * @param fieldName Name of the field for error messages
     * @return ValidationResult
     */
    fun validateId(id: String?, fieldName: String = "ID"): ValidationResult {
        if (id.isNullOrBlank()) {
            return ValidationResult.Invalid("$fieldName is required")
        }
        if (id.length > MAX_ID_LENGTH) {
            return ValidationResult.Invalid("$fieldName is too long")
        }
        // UUIDs and similar IDs - alphanumeric with dashes
        if (!id.matches(Regex("^[a-zA-Z0-9_-]+$"))) {
            return ValidationResult.Invalid("$fieldName contains invalid characters")
        }
        return ValidationResult.Valid
    }

    /**
     * Validate a file name.
     *
     * @param fileName The file name to validate
     * @return ValidationResult
     */
    fun validateFileName(fileName: String?): ValidationResult {
        if (fileName.isNullOrBlank()) {
            return ValidationResult.Invalid("File name is required")
        }
        if (fileName.length > MAX_FILENAME_LENGTH) {
            return ValidationResult.Invalid("File name is too long (max $MAX_FILENAME_LENGTH characters)")
        }
        // Prevent path traversal
        if (fileName.contains("..") || fileName.contains("/") || fileName.contains("\\")) {
            return ValidationResult.Invalid("File name contains invalid characters")
        }
        // Prevent null bytes
        if (fileName.contains("\u0000")) {
            return ValidationResult.Invalid("File name contains invalid characters")
        }
        return ValidationResult.Valid
    }

    /**
     * Validate file size.
     *
     * @param size The file size in bytes
     * @return ValidationResult
     */
    fun validateFileSize(size: Long): ValidationResult {
        if (size <= 0) {
            return ValidationResult.Invalid("File size must be positive")
        }
        if (size > MAX_FILE_SIZE) {
            return ValidationResult.Invalid("File is too large (max ${MAX_FILE_SIZE / (1024 * 1024)}MB)")
        }
        return ValidationResult.Valid
    }

    /**
     * Validate encrypted data length (Base64 encoded).
     *
     * @param data The encrypted data string
     * @param fieldName Name of the field for error messages
     * @return ValidationResult
     */
    fun validateEncryptedData(data: String?, fieldName: String = "Encrypted data"): ValidationResult {
        if (data.isNullOrBlank()) {
            return ValidationResult.Invalid("$fieldName is required")
        }
        if (data.length > MAX_ENCRYPTED_DATA_LENGTH) {
            return ValidationResult.Invalid("$fieldName is too large")
        }
        // Basic Base64 validation
        if (!data.matches(Regex("^[A-Za-z0-9+/=]+$"))) {
            return ValidationResult.Invalid("$fieldName has invalid encoding")
        }
        return ValidationResult.Valid
    }

    /**
     * Validate a list size.
     *
     * @param size The list size
     * @param fieldName Name of the field for error messages
     * @return ValidationResult
     */
    fun validateListSize(size: Int, fieldName: String = "List"): ValidationResult {
        if (size < 0) {
            return ValidationResult.Invalid("$fieldName size cannot be negative")
        }
        if (size > MAX_LIST_SIZE) {
            return ValidationResult.Invalid("$fieldName is too large (max $MAX_LIST_SIZE items)")
        }
        return ValidationResult.Valid
    }

    /**
     * Validate MIME type.
     *
     * @param mimeType The MIME type to validate
     * @return ValidationResult
     */
    fun validateMimeType(mimeType: String?): ValidationResult {
        if (mimeType.isNullOrBlank()) {
            return ValidationResult.Invalid("MIME type is required")
        }
        if (mimeType.length > 128) {
            return ValidationResult.Invalid("MIME type is too long")
        }
        // Basic MIME type format validation
        if (!mimeType.matches(Regex("^[a-zA-Z0-9][a-zA-Z0-9!#\$&\\-^_.+]*\\/[a-zA-Z0-9][a-zA-Z0-9!#\$&\\-^_.+]*$"))) {
            return ValidationResult.Invalid("Invalid MIME type format")
        }
        return ValidationResult.Valid
    }

    // ==================== Helper Functions ====================

    /**
     * Sanitize a string by removing potentially dangerous characters.
     *
     * @param input The input string
     * @param maxLength Maximum allowed length
     * @return Sanitized string
     */
    fun sanitizeString(input: String?, maxLength: Int = 1000): String {
        if (input == null) return ""
        return input
            .take(maxLength)
            .replace(Regex("[\\x00-\\x08\\x0B\\x0C\\x0E-\\x1F]"), "") // Remove control chars except \t \n \r
            .trim()
    }

    /**
     * Check if all validations pass.
     *
     * @param results Validation results to check
     * @return True if all are valid
     */
    fun allValid(vararg results: ValidationResult): Boolean {
        return results.all { it is ValidationResult.Valid }
    }

    /**
     * Get the first error message from validation results.
     *
     * @param results Validation results to check
     * @return First error message or null if all valid
     */
    fun firstError(vararg results: ValidationResult): String? {
        return results.filterIsInstance<ValidationResult.Invalid>().firstOrNull()?.message
    }
}

/**
 * Result of a validation check.
 */
sealed class ValidationResult {
    object Valid : ValidationResult()
    data class Invalid(val message: String) : ValidationResult()

    val isValid: Boolean get() = this is Valid
    val isInvalid: Boolean get() = this is Invalid
}

/**
 * Extension function to throw if validation fails.
 */
fun ValidationResult.throwIfInvalid() {
    if (this is ValidationResult.Invalid) {
        throw IllegalArgumentException(message)
    }
}
