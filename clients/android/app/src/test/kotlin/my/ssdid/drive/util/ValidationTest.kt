package my.ssdid.drive.util

import android.util.Patterns
import org.junit.Assume.assumeNotNull
import org.junit.Assert.*
import org.junit.Test

/**
 * Unit tests for Validation utility.
 *
 * Tests cover all 11 validation functions plus helper/sanitization methods.
 * Email format tests that depend on android.util.Patterns.EMAIL_ADDRESS
 * are skipped in pure JVM unit tests (field is null without Android framework).
 */
class ValidationTest {

    // ==================== validateEmail Tests ====================

    @Test
    fun `validateEmail returns Valid for valid email`() {
        assumeNotNull(Patterns.EMAIL_ADDRESS) // null in pure JVM tests
        val result = Validation.validateEmail("user@example.com")
        assertTrue(result.isValid)
    }

    @Test
    fun `validateEmail returns Valid for email with subdomain`() {
        assumeNotNull(Patterns.EMAIL_ADDRESS)
        val result = Validation.validateEmail("user@mail.example.com")
        assertTrue(result.isValid)
    }

    @Test
    fun `validateEmail returns Valid for email with plus addressing`() {
        assumeNotNull(Patterns.EMAIL_ADDRESS)
        val result = Validation.validateEmail("user+tag@example.com")
        assertTrue(result.isValid)
    }

    @Test
    fun `validateEmail returns Invalid for null`() {
        val result = Validation.validateEmail(null)
        assertTrue(result.isInvalid)
        assertEquals("Email is required", (result as ValidationResult.Invalid).message)
    }

    @Test
    fun `validateEmail returns Invalid for blank`() {
        val result = Validation.validateEmail("   ")
        assertTrue(result.isInvalid)
        assertEquals("Email is required", (result as ValidationResult.Invalid).message)
    }

    @Test
    fun `validateEmail returns Invalid for empty`() {
        val result = Validation.validateEmail("")
        assertTrue(result.isInvalid)
    }

    @Test
    fun `validateEmail returns Invalid for too long email`() {
        val longLocal = "a".repeat(250)
        val longEmail = "$longLocal@example.com"
        assertTrue(longEmail.length > Validation.MAX_EMAIL_LENGTH)
        val result = Validation.validateEmail(longEmail)
        assertTrue(result.isInvalid)
        assertTrue((result as ValidationResult.Invalid).message.contains("too long"))
    }

    @Test
    fun `validateEmail returns Invalid for missing at sign`() {
        assumeNotNull(Patterns.EMAIL_ADDRESS)
        val result = Validation.validateEmail("userexample.com")
        assertTrue(result.isInvalid)
        assertEquals("Invalid email format", (result as ValidationResult.Invalid).message)
    }

    @Test
    fun `validateEmail returns Invalid for missing domain`() {
        assumeNotNull(Patterns.EMAIL_ADDRESS)
        val result = Validation.validateEmail("user@")
        assertTrue(result.isInvalid)
    }

    // ==================== validatePassword Tests ====================

    @Test
    fun `validatePassword returns Valid for valid password`() {
        val result = Validation.validatePassword("secureP@ss1")
        assertTrue(result.isValid)
    }

    @Test
    fun `validatePassword returns Valid for minimum length password`() {
        val result = Validation.validatePassword("a".repeat(Validation.MIN_PASSWORD_LENGTH))
        assertTrue(result.isValid)
    }

    @Test
    fun `validatePassword returns Valid for maximum length password`() {
        val result = Validation.validatePassword("a".repeat(Validation.MAX_PASSWORD_LENGTH))
        assertTrue(result.isValid)
    }

    @Test
    fun `validatePassword returns Invalid for null`() {
        val result = Validation.validatePassword(null)
        assertTrue(result.isInvalid)
        assertEquals("Password is required", (result as ValidationResult.Invalid).message)
    }

    @Test
    fun `validatePassword returns Invalid for blank`() {
        val result = Validation.validatePassword("   ")
        assertTrue(result.isInvalid)
    }

    @Test
    fun `validatePassword returns Invalid for too short password`() {
        val result = Validation.validatePassword("a".repeat(Validation.MIN_PASSWORD_LENGTH - 1))
        assertTrue(result.isInvalid)
        assertTrue((result as ValidationResult.Invalid).message.contains("at least"))
    }

    @Test
    fun `validatePassword returns Invalid for too long password`() {
        val result = Validation.validatePassword("a".repeat(Validation.MAX_PASSWORD_LENGTH + 1))
        assertTrue(result.isInvalid)
        assertTrue((result as ValidationResult.Invalid).message.contains("too long"))
    }

    // ==================== validateTenant Tests ====================

    @Test
    fun `validateTenant returns Valid for alphanumeric tenant`() {
        val result = Validation.validateTenant("myOrg123")
        assertTrue(result.isValid)
    }

    @Test
    fun `validateTenant returns Valid for tenant with dashes`() {
        val result = Validation.validateTenant("my-org")
        assertTrue(result.isValid)
    }

    @Test
    fun `validateTenant returns Valid for tenant with underscores`() {
        val result = Validation.validateTenant("my_org")
        assertTrue(result.isValid)
    }

    @Test
    fun `validateTenant returns Invalid for null`() {
        val result = Validation.validateTenant(null)
        assertTrue(result.isInvalid)
        assertEquals("Organization is required", (result as ValidationResult.Invalid).message)
    }

    @Test
    fun `validateTenant returns Invalid for blank`() {
        val result = Validation.validateTenant("  ")
        assertTrue(result.isInvalid)
    }

    @Test
    fun `validateTenant returns Invalid for too long tenant`() {
        val result = Validation.validateTenant("a".repeat(Validation.MAX_TENANT_LENGTH + 1))
        assertTrue(result.isInvalid)
        assertTrue((result as ValidationResult.Invalid).message.contains("too long"))
    }

    @Test
    fun `validateTenant returns Invalid for tenant with spaces`() {
        val result = Validation.validateTenant("my org")
        assertTrue(result.isInvalid)
        assertTrue((result as ValidationResult.Invalid).message.contains("invalid characters"))
    }

    @Test
    fun `validateTenant returns Invalid for tenant with special characters`() {
        val result = Validation.validateTenant("my@org!")
        assertTrue(result.isInvalid)
    }

    @Test
    fun `validateTenant rejects SQL injection attempt`() {
        val result = Validation.validateTenant("org'; DROP TABLE users;--")
        assertTrue(result.isInvalid)
    }

    @Test
    fun `validateTenant rejects path traversal attempt`() {
        val result = Validation.validateTenant("../../../etc")
        assertTrue(result.isInvalid)
    }

    // ==================== validateId Tests ====================

    @Test
    fun `validateId returns Valid for UUID-like ID`() {
        val result = Validation.validateId("550e8400-e29b-41d4-a716-446655440000")
        assertTrue(result.isValid)
    }

    @Test
    fun `validateId returns Valid for alphanumeric ID`() {
        val result = Validation.validateId("user123")
        assertTrue(result.isValid)
    }

    @Test
    fun `validateId returns Invalid for null`() {
        val result = Validation.validateId(null)
        assertTrue(result.isInvalid)
        assertEquals("ID is required", (result as ValidationResult.Invalid).message)
    }

    @Test
    fun `validateId uses custom field name in error`() {
        val result = Validation.validateId(null, "User ID")
        assertTrue(result.isInvalid)
        assertEquals("User ID is required", (result as ValidationResult.Invalid).message)
    }

    @Test
    fun `validateId returns Invalid for too long ID`() {
        val result = Validation.validateId("a".repeat(Validation.MAX_ID_LENGTH + 1))
        assertTrue(result.isInvalid)
        assertTrue((result as ValidationResult.Invalid).message.contains("too long"))
    }

    @Test
    fun `validateId returns Invalid for ID with special characters`() {
        val result = Validation.validateId("id/../../root")
        assertTrue(result.isInvalid)
    }

    @Test
    fun `validateId rejects injection attempt`() {
        val result = Validation.validateId("id'; DROP TABLE files;--")
        assertTrue(result.isInvalid)
    }

    // ==================== validateFileName Tests ====================

    @Test
    fun `validateFileName returns Valid for normal filename`() {
        val result = Validation.validateFileName("document.pdf")
        assertTrue(result.isValid)
    }

    @Test
    fun `validateFileName returns Valid for filename with spaces`() {
        val result = Validation.validateFileName("my document.pdf")
        assertTrue(result.isValid)
    }

    @Test
    fun `validateFileName returns Valid for filename with dots`() {
        val result = Validation.validateFileName("file.v2.backup.tar.gz")
        assertTrue(result.isValid)
    }

    @Test
    fun `validateFileName returns Invalid for null`() {
        val result = Validation.validateFileName(null)
        assertTrue(result.isInvalid)
        assertEquals("File name is required", (result as ValidationResult.Invalid).message)
    }

    @Test
    fun `validateFileName returns Invalid for blank`() {
        val result = Validation.validateFileName("  ")
        assertTrue(result.isInvalid)
    }

    @Test
    fun `validateFileName returns Invalid for too long filename`() {
        val result = Validation.validateFileName("a".repeat(Validation.MAX_FILENAME_LENGTH + 1))
        assertTrue(result.isInvalid)
        assertTrue((result as ValidationResult.Invalid).message.contains("too long"))
    }

    @Test
    fun `validateFileName rejects path traversal with double dots`() {
        val result = Validation.validateFileName("../../etc/passwd")
        assertTrue(result.isInvalid)
        assertTrue((result as ValidationResult.Invalid).message.contains("invalid characters"))
    }

    @Test
    fun `validateFileName rejects forward slashes`() {
        val result = Validation.validateFileName("path/to/file.txt")
        assertTrue(result.isInvalid)
    }

    @Test
    fun `validateFileName rejects backslashes`() {
        val result = Validation.validateFileName("path\\to\\file.txt")
        assertTrue(result.isInvalid)
    }

    @Test
    fun `validateFileName rejects null bytes`() {
        val result = Validation.validateFileName("file\u0000.txt")
        assertTrue(result.isInvalid)
    }

    @Test
    fun `validateFileName rejects double dot without path separators`() {
        val result = Validation.validateFileName("..hidden")
        assertTrue(result.isInvalid)
    }

    // ==================== validateFileSize Tests ====================

    @Test
    fun `validateFileSize returns Valid for normal size`() {
        val result = Validation.validateFileSize(1024L)
        assertTrue(result.isValid)
    }

    @Test
    fun `validateFileSize returns Valid for 1 byte`() {
        val result = Validation.validateFileSize(1L)
        assertTrue(result.isValid)
    }

    @Test
    fun `validateFileSize returns Valid for exactly max size`() {
        val result = Validation.validateFileSize(Validation.MAX_FILE_SIZE)
        assertTrue(result.isValid)
    }

    @Test
    fun `validateFileSize returns Invalid for zero`() {
        val result = Validation.validateFileSize(0L)
        assertTrue(result.isInvalid)
        assertTrue((result as ValidationResult.Invalid).message.contains("positive"))
    }

    @Test
    fun `validateFileSize returns Invalid for negative`() {
        val result = Validation.validateFileSize(-1L)
        assertTrue(result.isInvalid)
    }

    @Test
    fun `validateFileSize returns Invalid for exceeding max`() {
        val result = Validation.validateFileSize(Validation.MAX_FILE_SIZE + 1)
        assertTrue(result.isInvalid)
        assertTrue((result as ValidationResult.Invalid).message.contains("too large"))
    }

    // ==================== validateMimeType Tests ====================

    @Test
    fun `validateMimeType returns Valid for application-pdf`() {
        val result = Validation.validateMimeType("application/pdf")
        assertTrue(result.isValid)
    }

    @Test
    fun `validateMimeType returns Valid for image-jpeg`() {
        val result = Validation.validateMimeType("image/jpeg")
        assertTrue(result.isValid)
    }

    @Test
    fun `validateMimeType returns Valid for text-plain`() {
        val result = Validation.validateMimeType("text/plain")
        assertTrue(result.isValid)
    }

    @Test
    fun `validateMimeType returns Valid for application-octet-stream`() {
        val result = Validation.validateMimeType("application/octet-stream")
        assertTrue(result.isValid)
    }

    @Test
    fun `validateMimeType returns Invalid for null`() {
        val result = Validation.validateMimeType(null)
        assertTrue(result.isInvalid)
        assertEquals("MIME type is required", (result as ValidationResult.Invalid).message)
    }

    @Test
    fun `validateMimeType returns Invalid for blank`() {
        val result = Validation.validateMimeType("  ")
        assertTrue(result.isInvalid)
    }

    @Test
    fun `validateMimeType returns Invalid for too long`() {
        val longType = "application/" + "a".repeat(120)
        val result = Validation.validateMimeType(longType)
        assertTrue(result.isInvalid)
        assertTrue((result as ValidationResult.Invalid).message.contains("too long"))
    }

    @Test
    fun `validateMimeType returns Invalid for missing slash`() {
        val result = Validation.validateMimeType("applicationpdf")
        assertTrue(result.isInvalid)
        assertEquals("Invalid MIME type format", (result as ValidationResult.Invalid).message)
    }

    @Test
    fun `validateMimeType returns Invalid for injection attempt`() {
        val result = Validation.validateMimeType("text/html; <script>alert(1)</script>")
        assertTrue(result.isInvalid)
    }

    // ==================== validateEncryptedData Tests ====================

    @Test
    fun `validateEncryptedData returns Valid for valid Base64`() {
        val result = Validation.validateEncryptedData("SGVsbG8gV29ybGQ=")
        assertTrue(result.isValid)
    }

    @Test
    fun `validateEncryptedData returns Valid for Base64 with plus and slash`() {
        val result = Validation.validateEncryptedData("aGVs+bG8/V29y=")
        assertTrue(result.isValid)
    }

    @Test
    fun `validateEncryptedData returns Invalid for null`() {
        val result = Validation.validateEncryptedData(null)
        assertTrue(result.isInvalid)
        assertEquals("Encrypted data is required", (result as ValidationResult.Invalid).message)
    }

    @Test
    fun `validateEncryptedData returns Invalid for blank`() {
        val result = Validation.validateEncryptedData("  ")
        assertTrue(result.isInvalid)
    }

    @Test
    fun `validateEncryptedData returns Invalid for too long data`() {
        val longData = "A".repeat(Validation.MAX_ENCRYPTED_DATA_LENGTH + 1)
        val result = Validation.validateEncryptedData(longData)
        assertTrue(result.isInvalid)
        assertTrue((result as ValidationResult.Invalid).message.contains("too large"))
    }

    @Test
    fun `validateEncryptedData returns Invalid for non-Base64 characters`() {
        val result = Validation.validateEncryptedData("not base64! @#\$%")
        assertTrue(result.isInvalid)
        assertTrue((result as ValidationResult.Invalid).message.contains("invalid encoding"))
    }

    @Test
    fun `validateEncryptedData uses custom field name`() {
        val result = Validation.validateEncryptedData(null, "Master key")
        assertTrue(result.isInvalid)
        assertEquals("Master key is required", (result as ValidationResult.Invalid).message)
    }

    // ==================== validateListSize Tests ====================

    @Test
    fun `validateListSize returns Valid for zero`() {
        val result = Validation.validateListSize(0)
        assertTrue(result.isValid)
    }

    @Test
    fun `validateListSize returns Valid for normal size`() {
        val result = Validation.validateListSize(50)
        assertTrue(result.isValid)
    }

    @Test
    fun `validateListSize returns Valid for exactly max`() {
        val result = Validation.validateListSize(Validation.MAX_LIST_SIZE)
        assertTrue(result.isValid)
    }

    @Test
    fun `validateListSize returns Invalid for negative`() {
        val result = Validation.validateListSize(-1)
        assertTrue(result.isInvalid)
        assertTrue((result as ValidationResult.Invalid).message.contains("negative"))
    }

    @Test
    fun `validateListSize returns Invalid for exceeding max`() {
        val result = Validation.validateListSize(Validation.MAX_LIST_SIZE + 1)
        assertTrue(result.isInvalid)
        assertTrue((result as ValidationResult.Invalid).message.contains("too large"))
    }

    @Test
    fun `validateListSize uses custom field name`() {
        val result = Validation.validateListSize(-1, "Recipients")
        assertTrue(result.isInvalid)
        assertEquals("Recipients size cannot be negative", (result as ValidationResult.Invalid).message)
    }

    // ==================== sanitizeString Tests ====================

    @Test
    fun `sanitizeString returns empty for null`() {
        val result = Validation.sanitizeString(null)
        assertEquals("", result)
    }

    @Test
    fun `sanitizeString preserves normal text`() {
        val result = Validation.sanitizeString("Hello, World!")
        assertEquals("Hello, World!", result)
    }

    @Test
    fun `sanitizeString removes control characters`() {
        val input = "Hello\u0001World\u0002"
        val result = Validation.sanitizeString(input)
        assertEquals("HelloWorld", result)
    }

    @Test
    fun `sanitizeString preserves tabs and newlines`() {
        val input = "Hello\tWorld\nNew line\rReturn"
        val result = Validation.sanitizeString(input)
        assertEquals("Hello\tWorld\nNew line\rReturn", result)
    }

    @Test
    fun `sanitizeString truncates to max length`() {
        val input = "a".repeat(2000)
        val result = Validation.sanitizeString(input, maxLength = 100)
        assertEquals(100, result.length)
    }

    @Test
    fun `sanitizeString trims whitespace`() {
        val result = Validation.sanitizeString("  hello  ")
        assertEquals("hello", result)
    }

    @Test
    fun `sanitizeString uses default max length of 1000`() {
        val input = "a".repeat(1500)
        val result = Validation.sanitizeString(input)
        assertEquals(1000, result.length)
    }

    @Test
    fun `sanitizeString removes null bytes`() {
        val input = "Hello\u0000World"
        val result = Validation.sanitizeString(input)
        assertEquals("HelloWorld", result)
    }

    // ==================== allValid Tests ====================

    @Test
    fun `allValid returns true when all results are valid`() {
        val result = Validation.allValid(
            ValidationResult.Valid,
            ValidationResult.Valid,
            ValidationResult.Valid
        )
        assertTrue(result)
    }

    @Test
    fun `allValid returns false when any result is invalid`() {
        val result = Validation.allValid(
            ValidationResult.Valid,
            ValidationResult.Invalid("error"),
            ValidationResult.Valid
        )
        assertFalse(result)
    }

    @Test
    fun `allValid returns true for empty varargs`() {
        val result = Validation.allValid()
        assertTrue(result)
    }

    // ==================== firstError Tests ====================

    @Test
    fun `firstError returns null when all valid`() {
        val result = Validation.firstError(
            ValidationResult.Valid,
            ValidationResult.Valid
        )
        assertNull(result)
    }

    @Test
    fun `firstError returns first error message`() {
        val result = Validation.firstError(
            ValidationResult.Valid,
            ValidationResult.Invalid("first error"),
            ValidationResult.Invalid("second error")
        )
        assertEquals("first error", result)
    }

    @Test
    fun `firstError returns null for empty varargs`() {
        val result = Validation.firstError()
        assertNull(result)
    }

    // ==================== throwIfInvalid Tests ====================

    @Test
    fun `throwIfInvalid does nothing for Valid result`() {
        // Should not throw
        ValidationResult.Valid.throwIfInvalid()
    }

    @Test(expected = IllegalArgumentException::class)
    fun `throwIfInvalid throws IllegalArgumentException for Invalid result`() {
        ValidationResult.Invalid("test error").throwIfInvalid()
    }

    @Test
    fun `throwIfInvalid includes message in exception`() {
        try {
            ValidationResult.Invalid("custom error message").throwIfInvalid()
            fail("Expected IllegalArgumentException")
        } catch (e: IllegalArgumentException) {
            assertEquals("custom error message", e.message)
        }
    }

    // ==================== ValidationResult Properties Tests ====================

    @Test
    fun `Valid result has isValid true and isInvalid false`() {
        val result = ValidationResult.Valid
        assertTrue(result.isValid)
        assertFalse(result.isInvalid)
    }

    @Test
    fun `Invalid result has isValid false and isInvalid true`() {
        val result = ValidationResult.Invalid("error")
        assertFalse(result.isValid)
        assertTrue(result.isInvalid)
    }

    // ==================== Constants Tests ====================

    @Test
    fun `MAX_FILE_SIZE is 100MB`() {
        assertEquals(100L * 1024 * 1024, Validation.MAX_FILE_SIZE)
    }

    @Test
    fun `MIN_PASSWORD_LENGTH is 8`() {
        assertEquals(8, Validation.MIN_PASSWORD_LENGTH)
    }

    @Test
    fun `MAX_PASSWORD_LENGTH is 128`() {
        assertEquals(128, Validation.MAX_PASSWORD_LENGTH)
    }

    @Test
    fun `MAX_EMAIL_LENGTH is 254`() {
        assertEquals(254, Validation.MAX_EMAIL_LENGTH)
    }

    @Test
    fun `MAX_LIST_SIZE is 1000`() {
        assertEquals(1000, Validation.MAX_LIST_SIZE)
    }
}
