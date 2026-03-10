package my.ssdid.drive.util

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PersistableBundle
import io.mockk.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

/**
 * Unit tests for SecureClipboard.
 *
 * Tests cover:
 * - Copying sensitive text to clipboard
 * - Password copy with short timeout
 * - Recovery key copy with very short timeout
 * - Share link copy (non-sensitive)
 * - Clipboard clearing
 * - Pending clear cancellation
 * - Clipboard content checking
 * - Clipboard state retrieval
 * - Clipboard listener management
 * - Timeout constants
 */
class SecureClipboardTest {

    private lateinit var context: Context
    private lateinit var clipboardManager: ClipboardManager
    private lateinit var handler: Handler
    private lateinit var looper: Looper
    private lateinit var secureClipboard: SecureClipboard

    private val capturedClipData = slot<ClipData>()
    private val capturedRunnable = slot<Runnable>()
    private val capturedDelay = slot<Long>()

    @Before
    fun setup() {
        context = mockk(relaxed = true)
        clipboardManager = mockk(relaxed = true)
        handler = mockk(relaxed = true)
        looper = mockk(relaxed = true)

        every { context.getSystemService(Context.CLIPBOARD_SERVICE) } returns clipboardManager
        every { clipboardManager.setPrimaryClip(capture(capturedClipData)) } just Runs

        mockkStatic(Looper::class)
        every { Looper.getMainLooper() } returns looper

        mockkConstructor(Handler::class)
        every { anyConstructed<Handler>().postDelayed(capture(capturedRunnable), capture(capturedDelay)) } returns true
        every { anyConstructed<Handler>().removeCallbacks(any<Runnable>()) } returns Unit

        // Default to pre-Tiramisu for most tests
        mockkStatic(Build.VERSION::class)

        secureClipboard = SecureClipboard(context)
    }

    @After
    fun tearDown() {
        unmockkStatic(Looper::class)
        unmockkStatic(Build.VERSION::class)
        unmockkConstructor(Handler::class)
    }

    // ==================== copySensitiveText Tests ====================

    @Test
    fun `copySensitiveText sets clip data on clipboard`() {
        secureClipboard.copySensitiveText("Label", "secret value")

        verify { clipboardManager.setPrimaryClip(any()) }
    }

    @Test
    fun `copySensitiveText schedules auto-clear with default timeout`() {
        secureClipboard.copySensitiveText("Label", "secret")

        verify { anyConstructed<Handler>().postDelayed(any(), eq(SecureClipboard.DEFAULT_CLEAR_TIMEOUT_MS)) }
    }

    @Test
    fun `copySensitiveText schedules auto-clear with custom timeout`() {
        secureClipboard.copySensitiveText("Label", "secret", clearAfterMs = 5000L)

        verify { anyConstructed<Handler>().postDelayed(any(), eq(5000L)) }
    }

    @Test
    fun `copySensitiveText does not schedule clear when clearAfterMs is 0`() {
        secureClipboard.copySensitiveText("Label", "secret", clearAfterMs = 0)

        verify(exactly = 0) { anyConstructed<Handler>().postDelayed(any(), any()) }
    }

    @Test
    fun `copySensitiveText cancels previous pending clear`() {
        // First copy schedules a clear
        secureClipboard.copySensitiveText("Label1", "secret1")

        // Second copy should cancel the first clear
        secureClipboard.copySensitiveText("Label2", "secret2")

        verify(atLeast = 1) { anyConstructed<Handler>().removeCallbacks(any<Runnable>()) }
    }

    // ==================== copyPassword Tests ====================

    @Test
    fun `copyPassword uses PASSWORD_CLEAR_TIMEOUT_MS by default`() {
        secureClipboard.copyPassword("mypassword")

        verify { anyConstructed<Handler>().postDelayed(any(), eq(SecureClipboard.PASSWORD_CLEAR_TIMEOUT_MS)) }
    }

    @Test
    fun `copyPassword sets clip data on clipboard`() {
        secureClipboard.copyPassword("pass123")

        verify { clipboardManager.setPrimaryClip(any()) }
    }

    @Test
    fun `copyPassword uses custom timeout when provided`() {
        secureClipboard.copyPassword("pass", clearAfterMs = 10_000L)

        verify { anyConstructed<Handler>().postDelayed(any(), eq(10_000L)) }
    }

    // ==================== copyRecoveryKey Tests ====================

    @Test
    fun `copyRecoveryKey uses RECOVERY_KEY_CLEAR_TIMEOUT_MS by default`() {
        secureClipboard.copyRecoveryKey("seed-phrase-words-here")

        verify { anyConstructed<Handler>().postDelayed(any(), eq(SecureClipboard.RECOVERY_KEY_CLEAR_TIMEOUT_MS)) }
    }

    @Test
    fun `copyRecoveryKey sets clip data`() {
        secureClipboard.copyRecoveryKey("recovery-seed")

        verify { clipboardManager.setPrimaryClip(any()) }
    }

    // ==================== copyShareLink Tests ====================

    @Test
    fun `copyShareLink uses SHARE_LINK_CLEAR_TIMEOUT_MS by default`() {
        secureClipboard.copyShareLink("https://share.example.com/abc")

        verify { anyConstructed<Handler>().postDelayed(any(), eq(SecureClipboard.SHARE_LINK_CLEAR_TIMEOUT_MS)) }
    }

    @Test
    fun `copyShareLink sets clip data`() {
        secureClipboard.copyShareLink("https://share.example.com/link")

        verify { clipboardManager.setPrimaryClip(any()) }
    }

    // ==================== clearClipboard Tests ====================

    @Test
    fun `clearClipboard cancels pending clear`() {
        secureClipboard.copySensitiveText("Label", "data")

        secureClipboard.clearClipboard()

        verify(atLeast = 1) { anyConstructed<Handler>().removeCallbacks(any<Runnable>()) }
    }

    // ==================== cancelPendingClear Tests ====================

    @Test
    fun `cancelPendingClear removes scheduled callback`() {
        secureClipboard.copySensitiveText("Label", "data")

        secureClipboard.cancelPendingClear()

        verify(atLeast = 1) { anyConstructed<Handler>().removeCallbacks(any<Runnable>()) }
    }

    @Test
    fun `cancelPendingClear is safe when no pending clear exists`() {
        // Should not throw
        secureClipboard.cancelPendingClear()
    }

    // ==================== hasClipboardContent Tests ====================

    @Test
    fun `hasClipboardContent returns true when label matches`() {
        val description = mockk<ClipDescription>()
        every { description.label } returns "Password"

        val clip = mockk<ClipData>()
        every { clip.description } returns description
        every { clip.itemCount } returns 1

        every { clipboardManager.primaryClip } returns clip

        assertTrue(secureClipboard.hasClipboardContent("Password"))
    }

    @Test
    fun `hasClipboardContent returns false when label does not match`() {
        val description = mockk<ClipDescription>()
        every { description.label } returns "Other"

        val clip = mockk<ClipData>()
        every { clip.description } returns description
        every { clip.itemCount } returns 1

        every { clipboardManager.primaryClip } returns clip

        assertFalse(secureClipboard.hasClipboardContent("Password"))
    }

    @Test
    fun `hasClipboardContent returns false when clipboard is null`() {
        every { clipboardManager.primaryClip } returns null

        assertFalse(secureClipboard.hasClipboardContent("Label"))
    }

    @Test
    fun `hasClipboardContent returns false when item count is 0`() {
        val description = mockk<ClipDescription>()
        every { description.label } returns "Password"

        val clip = mockk<ClipData>()
        every { clip.description } returns description
        every { clip.itemCount } returns 0

        every { clipboardManager.primaryClip } returns clip

        assertFalse(secureClipboard.hasClipboardContent("Password"))
    }

    @Test
    fun `hasClipboardContent returns false on exception`() {
        every { clipboardManager.primaryClip } throws SecurityException("denied")

        assertFalse(secureClipboard.hasClipboardContent("Label"))
    }

    // ==================== getTimeUntilClear Tests ====================

    @Test
    fun `getTimeUntilClear returns 0`() {
        assertEquals(0L, secureClipboard.getTimeUntilClear())
    }

    // ==================== addClipboardListener Tests ====================

    @Test
    fun `addClipboardListener registers listener and returns removal function`() {
        val listener = mockk<() -> Unit>(relaxed = true)

        val removeListener = secureClipboard.addClipboardListener(listener)

        verify { clipboardManager.addPrimaryClipChangedListener(any()) }

        // Invoke removal
        removeListener()

        verify { clipboardManager.removePrimaryClipChangedListener(any()) }
    }

    // ==================== getClipboardState Tests ====================

    @Test
    fun `getClipboardState returns empty state when clipboard is empty`() {
        every { clipboardManager.primaryClip } returns null

        val state = secureClipboard.getClipboardState()

        assertFalse(state.hasSensitiveContent)
        assertNull(state.label)
        assertFalse(state.willAutoClear)
    }

    @Test
    fun `getClipboardState returns safe state on exception`() {
        every { clipboardManager.primaryClip } throws SecurityException("denied")

        val state = secureClipboard.getClipboardState()

        assertFalse(state.hasSensitiveContent)
        assertNull(state.label)
        assertFalse(state.willAutoClear)
    }

    // ==================== Timeout Constants Tests ====================

    @Test
    fun `DEFAULT_CLEAR_TIMEOUT_MS is 60 seconds`() {
        assertEquals(60_000L, SecureClipboard.DEFAULT_CLEAR_TIMEOUT_MS)
    }

    @Test
    fun `PASSWORD_CLEAR_TIMEOUT_MS is 30 seconds`() {
        assertEquals(30_000L, SecureClipboard.PASSWORD_CLEAR_TIMEOUT_MS)
    }

    @Test
    fun `RECOVERY_KEY_CLEAR_TIMEOUT_MS is 15 seconds`() {
        assertEquals(15_000L, SecureClipboard.RECOVERY_KEY_CLEAR_TIMEOUT_MS)
    }

    @Test
    fun `SHARE_LINK_CLEAR_TIMEOUT_MS is 5 minutes`() {
        assertEquals(300_000L, SecureClipboard.SHARE_LINK_CLEAR_TIMEOUT_MS)
    }

    @Test
    fun `timeout values are ordered by sensitivity`() {
        assertTrue(
            "Recovery key timeout should be shortest",
            SecureClipboard.RECOVERY_KEY_CLEAR_TIMEOUT_MS < SecureClipboard.PASSWORD_CLEAR_TIMEOUT_MS
        )
        assertTrue(
            "Password timeout should be shorter than default",
            SecureClipboard.PASSWORD_CLEAR_TIMEOUT_MS < SecureClipboard.DEFAULT_CLEAR_TIMEOUT_MS
        )
        assertTrue(
            "Default timeout should be shorter than share link",
            SecureClipboard.DEFAULT_CLEAR_TIMEOUT_MS < SecureClipboard.SHARE_LINK_CLEAR_TIMEOUT_MS
        )
    }
}
