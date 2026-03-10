package my.ssdid.drive.util

import org.junit.Assert.*
import org.junit.Test

/**
 * Unit tests for Result and AppException.
 *
 * Tests cover:
 * - Result.success / Result.error factory methods
 * - isSuccess / isError properties
 * - getOrNull / exceptionOrNull
 * - map / flatMap transformations
 * - fold
 * - onSuccess / onError side effects
 * - AppException subtypes
 */
class ResultTest {

    // ==================== Factory Methods ====================

    @Test
    fun `success creates a Success result`() {
        val result = Result.success("hello")

        assertTrue(result is Result.Success)
        assertEquals("hello", (result as Result.Success).data)
    }

    @Test
    fun `error with AppException creates an Error result`() {
        val exception = AppException.Network("timeout")
        val result = Result.error<String>(exception)

        assertTrue(result is Result.Error)
        assertEquals(exception, (result as Result.Error).exception)
    }

    @Test
    fun `error with message creates an Error with Unknown exception`() {
        val result = Result.error<String>("something went wrong")

        assertTrue(result is Result.Error)
        val error = (result as Result.Error).exception
        assertTrue(error is AppException.Unknown)
        assertEquals("something went wrong", error.message)
    }

    // ==================== isSuccess / isError ====================

    @Test
    fun `isSuccess returns true for Success`() {
        val result = Result.success(42)

        assertTrue(result.isSuccess)
        assertFalse(result.isError)
    }

    @Test
    fun `isError returns true for Error`() {
        val result = Result.error<Int>(AppException.NotFound())

        assertTrue(result.isError)
        assertFalse(result.isSuccess)
    }

    // ==================== getOrNull ====================

    @Test
    fun `getOrNull returns data for Success`() {
        val result = Result.success("data")

        assertEquals("data", result.getOrNull())
    }

    @Test
    fun `getOrNull returns null for Error`() {
        val result = Result.error<String>(AppException.Unauthorized())

        assertNull(result.getOrNull())
    }

    // ==================== exceptionOrNull ====================

    @Test
    fun `exceptionOrNull returns null for Success`() {
        val result = Result.success("ok")

        assertNull(result.exceptionOrNull())
    }

    @Test
    fun `exceptionOrNull returns exception for Error`() {
        val exception = AppException.Forbidden("no access")
        val result = Result.error<String>(exception)

        assertEquals(exception, result.exceptionOrNull())
    }

    // ==================== map ====================

    @Test
    fun `map transforms Success value`() {
        val result = Result.success(5)

        val mapped = result.map { it * 2 }

        assertTrue(mapped.isSuccess)
        assertEquals(10, mapped.getOrNull())
    }

    @Test
    fun `map preserves Error without calling transform`() {
        val exception = AppException.Network("fail")
        val result = Result.error<Int>(exception)
        var transformCalled = false

        val mapped = result.map {
            transformCalled = true
            it * 2
        }

        assertTrue(mapped.isError)
        assertFalse(transformCalled)
        assertEquals(exception, mapped.exceptionOrNull())
    }

    @Test
    fun `map can change result type`() {
        val result = Result.success(42)

        val mapped = result.map { it.toString() }

        assertEquals("42", mapped.getOrNull())
    }

    // ==================== flatMap ====================

    @Test
    fun `flatMap with Success transform returns new Success`() {
        val result = Result.success(10)

        val flatMapped = result.flatMap { Result.success(it + 5) }

        assertTrue(flatMapped.isSuccess)
        assertEquals(15, flatMapped.getOrNull())
    }

    @Test
    fun `flatMap with Success transform returning Error propagates Error`() {
        val result = Result.success(10)

        val flatMapped = result.flatMap<Int> {
            Result.error(AppException.ValidationError("invalid"))
        }

        assertTrue(flatMapped.isError)
        assertTrue(flatMapped.exceptionOrNull() is AppException.ValidationError)
    }

    @Test
    fun `flatMap on Error skips transform`() {
        val exception = AppException.Network("offline")
        val result = Result.error<Int>(exception)
        var transformCalled = false

        val flatMapped = result.flatMap {
            transformCalled = true
            Result.success(it * 2)
        }

        assertFalse(transformCalled)
        assertTrue(flatMapped.isError)
        assertEquals(exception, flatMapped.exceptionOrNull())
    }

    // ==================== fold ====================

    @Test
    fun `fold applies onSuccess for Success result`() {
        val result = Result.success("hello")

        val folded = result.fold(
            onSuccess = { it.length },
            onFailure = { -1 }
        )

        assertEquals(5, folded)
    }

    @Test
    fun `fold applies onFailure for Error result`() {
        val result = Result.error<String>(AppException.Unauthorized("denied"))

        val folded = result.fold(
            onSuccess = { it.length },
            onFailure = { -1 }
        )

        assertEquals(-1, folded)
    }

    @Test
    fun `fold can return different type`() {
        val result = Result.success(42)

        val folded: String = result.fold(
            onSuccess = { "value=$it" },
            onFailure = { "error=${it.message}" }
        )

        assertEquals("value=42", folded)
    }

    // ==================== onSuccess ====================

    @Test
    fun `onSuccess executes action for Success`() {
        val result = Result.success("data")
        var captured: String? = null

        result.onSuccess { captured = it }

        assertEquals("data", captured)
    }

    @Test
    fun `onSuccess does not execute action for Error`() {
        val result = Result.error<String>(AppException.NotFound())
        var actionCalled = false

        result.onSuccess { actionCalled = true }

        assertFalse(actionCalled)
    }

    @Test
    fun `onSuccess returns the same Result for chaining`() {
        val result = Result.success("test")

        val returned = result.onSuccess { }

        assertSame(result, returned)
    }

    // ==================== onError ====================

    @Test
    fun `onError executes action for Error`() {
        val exception = AppException.CryptoError("decrypt failed")
        val result = Result.error<String>(exception)
        var captured: AppException? = null

        result.onError { captured = it }

        assertEquals(exception, captured)
    }

    @Test
    fun `onError does not execute action for Success`() {
        val result = Result.success("ok")
        var actionCalled = false

        result.onError { actionCalled = true }

        assertFalse(actionCalled)
    }

    @Test
    fun `onError returns the same Result for chaining`() {
        val result = Result.error<String>(AppException.Unknown())

        val returned = result.onError { }

        assertSame(result, returned)
    }

    // ==================== Chaining ====================

    @Test
    fun `onSuccess and onError can be chained`() {
        var successValue: String? = null
        var errorValue: AppException? = null

        Result.success("chained")
            .onSuccess { successValue = it }
            .onError { errorValue = it }

        assertEquals("chained", successValue)
        assertNull(errorValue)
    }

    @Test
    fun `map and flatMap can be chained`() {
        val result = Result.success(2)
            .map { it * 3 }
            .flatMap { Result.success(it + 1) }
            .map { it.toString() }

        assertEquals("7", result.getOrNull())
    }

    // ==================== AppException Tests ====================

    @Test
    fun `Network exception has default message`() {
        val ex = AppException.Network()
        assertEquals("Network error", ex.message)
    }

    @Test
    fun `Network exception preserves cause`() {
        val cause = RuntimeException("socket closed")
        val ex = AppException.Network("connection failed", cause)

        assertEquals("connection failed", ex.message)
        assertSame(cause, ex.cause)
    }

    @Test
    fun `Unauthorized exception has default message`() {
        assertEquals("Unauthorized", AppException.Unauthorized().message)
    }

    @Test
    fun `Forbidden exception has default message`() {
        assertEquals("Access denied", AppException.Forbidden().message)
    }

    @Test
    fun `NotFound exception has default message`() {
        assertEquals("Not found", AppException.NotFound().message)
    }

    @Test
    fun `Conflict exception has default message`() {
        assertEquals("Conflict", AppException.Conflict().message)
    }

    @Test
    fun `QuotaExceeded exception has default message`() {
        assertEquals("Storage quota exceeded", AppException.QuotaExceeded().message)
    }

    @Test
    fun `CryptoError exception requires message`() {
        val ex = AppException.CryptoError("key derivation failed")
        assertEquals("key derivation failed", ex.message)
    }

    @Test
    fun `SignatureInvalid exception has default message`() {
        assertEquals("Signature verification failed", AppException.SignatureInvalid().message)
    }

    @Test
    fun `ValidationError exception requires message`() {
        val ex = AppException.ValidationError("email is invalid")
        assertEquals("email is invalid", ex.message)
    }

    @Test
    fun `Unknown exception has default message`() {
        assertEquals("Unknown error", AppException.Unknown().message)
    }

    @Test
    fun `all AppException subtypes are Throwable`() {
        val exceptions: List<AppException> = listOf(
            AppException.Network(),
            AppException.Unauthorized(),
            AppException.Forbidden(),
            AppException.NotFound(),
            AppException.Conflict(),
            AppException.QuotaExceeded(),
            AppException.CryptoError("err"),
            AppException.SignatureInvalid(),
            AppException.ValidationError("err"),
            AppException.Unknown()
        )

        exceptions.forEach { ex ->
            assertTrue("${ex::class.simpleName} should be Throwable", ex is Throwable)
            assertTrue("${ex::class.simpleName} should be Exception", ex is Exception)
            assertTrue("${ex::class.simpleName} should be AppException", ex is AppException)
        }
    }

    // ==================== Null / Unit Data ====================

    @Test
    fun `success with Unit data works`() {
        val result = Result.success(Unit)

        assertTrue(result.isSuccess)
        assertEquals(Unit, result.getOrNull())
    }

    @Test
    fun `success with null data works`() {
        val result = Result.success(null)

        assertTrue(result.isSuccess)
        assertNull(result.getOrNull())
    }
}
