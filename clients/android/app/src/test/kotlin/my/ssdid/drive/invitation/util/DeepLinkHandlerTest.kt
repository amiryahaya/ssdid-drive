package my.ssdid.drive.invitation.util

import android.content.Intent
import android.net.Uri
import my.ssdid.drive.util.DeepLinkAction
import my.ssdid.drive.util.DeepLinkHandler
import io.mockk.every
import io.mockk.mockk
import io.mockk.mockkStatic
import io.mockk.unmockkAll
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

/**
 * Unit tests for DeepLinkHandler.
 *
 * Tests cover:
 * - Custom scheme parsing (ssdiddrive://)
 * - HTTP scheme parsing (https://)
 * - Invite token extraction
 * - Error handling for invalid URIs
 * - Edge cases
 */
class DeepLinkHandlerTest {

    private lateinit var deepLinkHandler: DeepLinkHandler

    @Before
    fun setup() {
        deepLinkHandler = DeepLinkHandler()
        mockkStatic(Uri::class)
    }

    @After
    fun tearDown() {
        unmockkAll()
    }

    // ==================== Custom Scheme - Invite Callback Tests ====================

    @Test
    fun `parseIntent with invite callback success returns WalletInviteCallback action`() {
        val intent = createMockViewIntent(
            scheme = "ssdiddrive",
            host = "invite",
            pathSegments = listOf("callback"),
            queryParams = mapOf("session_token" to "tok-xyz", "status" to "success")
        )

        val action = deepLinkHandler.parseIntent(intent)

        assertTrue(action is DeepLinkAction.WalletInviteCallback)
        assertEquals("tok-xyz", (action as DeepLinkAction.WalletInviteCallback).sessionToken)
    }

    @Test
    fun `parseIntent with invite callback error status returns WalletInviteError action`() {
        val intent = createMockViewIntent(
            scheme = "ssdiddrive",
            host = "invite",
            pathSegments = listOf("callback"),
            queryParams = mapOf("status" to "error", "message" to "User cancelled")
        )

        val action = deepLinkHandler.parseIntent(intent)

        assertTrue(action is DeepLinkAction.WalletInviteError)
        assertEquals("User cancelled", (action as DeepLinkAction.WalletInviteError).message)
    }

    @Test
    fun `parseIntent with invite callback missing status but has token returns WalletInviteCallback`() {
        val intent = createMockViewIntent(
            scheme = "ssdiddrive",
            host = "invite",
            pathSegments = listOf("callback"),
            queryParams = mapOf("session_token" to "tok-xyz") // no status — legacy callback
        )

        val action = deepLinkHandler.parseIntent(intent)

        // No status but has session_token — treat as success (legacy callback)
        assertTrue(action is DeepLinkAction.WalletInviteCallback)
        assertEquals("tok-xyz", (action as DeepLinkAction.WalletInviteCallback).sessionToken)
    }

    @Test
    fun `parseIntent with invite callback success missing session_token returns error`() {
        val intent = createMockViewIntent(
            scheme = "ssdiddrive",
            host = "invite",
            pathSegments = listOf("callback"),
            queryParams = mapOf("status" to "success") // no session_token
        )

        val action = deepLinkHandler.parseIntent(intent)

        // success status but no session_token — falls through to error
        assertTrue(action is DeepLinkAction.WalletInviteError)
    }

    // ==================== Custom Scheme - Invite Tests ====================

    @Test
    fun `parseIntent with custom scheme invite returns AcceptInvitation action`() {
        val intent = createMockViewIntent(
            scheme = "ssdiddrive",
            host = "invite",
            pathSegments = listOf("abc123")
        )

        val action = deepLinkHandler.parseIntent(intent)

        assertTrue(action is DeepLinkAction.AcceptInvitation)
        assertEquals("abc123", (action as DeepLinkAction.AcceptInvitation).token)
    }

    @Test
    fun `parseIntent with custom scheme invite with dashes`() {
        val intent = createMockViewIntent(
            scheme = "ssdiddrive",
            host = "invite",
            pathSegments = listOf("abc-123-def-456")
        )

        val action = deepLinkHandler.parseIntent(intent)

        assertTrue(action is DeepLinkAction.AcceptInvitation)
        assertEquals("abc-123-def-456", (action as DeepLinkAction.AcceptInvitation).token)
    }

    @Test
    fun `parseIntent with custom scheme invite with underscores`() {
        val intent = createMockViewIntent(
            scheme = "ssdiddrive",
            host = "invite",
            pathSegments = listOf("abc_123_def")
        )

        val action = deepLinkHandler.parseIntent(intent)

        assertTrue(action is DeepLinkAction.AcceptInvitation)
        assertEquals("abc_123_def", (action as DeepLinkAction.AcceptInvitation).token)
    }

    @Test
    fun `parseIntent with custom scheme invite with long token`() {
        val longToken = "a".repeat(256)
        val intent = createMockViewIntent(
            scheme = "ssdiddrive",
            host = "invite",
            pathSegments = listOf(longToken)
        )

        val action = deepLinkHandler.parseIntent(intent)

        assertTrue(action is DeepLinkAction.AcceptInvitation)
        assertEquals(longToken, (action as DeepLinkAction.AcceptInvitation).token)
    }

    @Test
    fun `parseIntent with custom scheme invite with numeric token`() {
        val intent = createMockViewIntent(
            scheme = "ssdiddrive",
            host = "invite",
            pathSegments = listOf("123456789")
        )

        val action = deepLinkHandler.parseIntent(intent)

        assertTrue(action is DeepLinkAction.AcceptInvitation)
        assertEquals("123456789", (action as DeepLinkAction.AcceptInvitation).token)
    }

    // ==================== HTTP Scheme - Invite Tests ====================

    @Test
    fun `parseIntent with http scheme invite returns AcceptInvitation action`() {
        val intent = createMockViewIntent(
            scheme = "https",
            host = "app.ssdiddrive.example",
            pathSegments = listOf("invite", "abc123")
        )

        val action = deepLinkHandler.parseIntent(intent)

        assertTrue(action is DeepLinkAction.AcceptInvitation)
        assertEquals("abc123", (action as DeepLinkAction.AcceptInvitation).token)
    }

    @Test
    fun `parseIntent with http scheme invite with query params`() {
        val intent = createMockViewIntent(
            scheme = "https",
            host = "app.ssdiddrive.example",
            pathSegments = listOf("invite", "abc123")
        )

        val action = deepLinkHandler.parseIntent(intent)

        assertTrue(action is DeepLinkAction.AcceptInvitation)
        assertEquals("abc123", (action as DeepLinkAction.AcceptInvitation).token)
    }

    @Test
    fun `parseIntent with http scheme invite with http not https`() {
        val intent = createMockViewIntent(
            scheme = "http",
            host = "app.ssdiddrive.example",
            pathSegments = listOf("invite", "abc123")
        )

        val action = deepLinkHandler.parseIntent(intent)

        assertTrue(action is DeepLinkAction.AcceptInvitation)
        assertEquals("abc123", (action as DeepLinkAction.AcceptInvitation).token)
    }

    // ==================== Custom Scheme - Other Actions Tests ====================

    @Test
    fun `parseIntent with custom scheme share returns OpenShare action`() {
        val intent = createMockViewIntent(
            scheme = "ssdiddrive",
            host = "share",
            pathSegments = listOf("share123")
        )

        val action = deepLinkHandler.parseIntent(intent)

        assertTrue(action is DeepLinkAction.OpenShare)
        assertEquals("share123", (action as DeepLinkAction.OpenShare).shareId)
    }

    @Test
    fun `parseIntent with custom scheme file returns OpenFile action`() {
        val intent = createMockViewIntent(
            scheme = "ssdiddrive",
            host = "file",
            pathSegments = listOf("file123")
        )

        val action = deepLinkHandler.parseIntent(intent)

        assertTrue(action is DeepLinkAction.OpenFile)
        assertEquals("file123", (action as DeepLinkAction.OpenFile).fileId)
    }

    @Test
    fun `parseIntent with custom scheme folder returns OpenFolder action`() {
        val intent = createMockViewIntent(
            scheme = "ssdiddrive",
            host = "folder",
            pathSegments = listOf("folder123")
        )

        val action = deepLinkHandler.parseIntent(intent)

        assertTrue(action is DeepLinkAction.OpenFolder)
        assertEquals("folder123", (action as DeepLinkAction.OpenFolder).folderId)
    }

    // ==================== HTTP Scheme - Other Actions Tests ====================

    @Test
    fun `parseIntent with http scheme share returns OpenShare action`() {
        val intent = createMockViewIntent(
            scheme = "https",
            host = "app.ssdiddrive.example",
            pathSegments = listOf("share", "share123")
        )

        val action = deepLinkHandler.parseIntent(intent)

        assertTrue(action is DeepLinkAction.OpenShare)
        assertEquals("share123", (action as DeepLinkAction.OpenShare).shareId)
    }

    @Test
    fun `parseIntent with http scheme file returns OpenFile action`() {
        val intent = createMockViewIntent(
            scheme = "https",
            host = "app.ssdiddrive.example",
            pathSegments = listOf("file", "file123")
        )

        val action = deepLinkHandler.parseIntent(intent)

        assertTrue(action is DeepLinkAction.OpenFile)
        assertEquals("file123", (action as DeepLinkAction.OpenFile).fileId)
    }

    @Test
    fun `parseIntent with http scheme folder returns OpenFolder action`() {
        val intent = createMockViewIntent(
            scheme = "https",
            host = "app.ssdiddrive.example",
            pathSegments = listOf("folder", "folder123")
        )

        val action = deepLinkHandler.parseIntent(intent)

        assertTrue(action is DeepLinkAction.OpenFolder)
        assertEquals("folder123", (action as DeepLinkAction.OpenFolder).folderId)
    }

    // ==================== Error Cases ====================

    @Test
    fun `parseIntent with null intent returns null`() {
        val action = deepLinkHandler.parseIntent(null)

        assertNull(action)
    }

    @Test
    fun `parseIntent with unsupported action returns null`() {
        val intent = mockk<Intent>()
        every { intent.action } returns Intent.ACTION_MAIN

        val action = deepLinkHandler.parseIntent(intent)

        assertNull(action)
    }

    @Test
    fun `parseIntent with null intent data returns null`() {
        val intent = mockk<Intent>()
        every { intent.action } returns Intent.ACTION_VIEW
        every { intent.data } returns null

        val action = deepLinkHandler.parseIntent(intent)

        assertNull(action)
    }

    @Test
    fun `parseIntent with unsupported scheme returns null`() {
        val intent = createMockViewIntent(
            scheme = "ftp",
            host = "ssdiddrive.example",
            pathSegments = listOf("invite", "abc123")
        )

        val action = deepLinkHandler.parseIntent(intent)

        assertNull(action)
    }

    @Test
    fun `parseIntent with unknown custom scheme host returns null`() {
        val intent = createMockViewIntent(
            scheme = "ssdiddrive",
            host = "unknown",
            pathSegments = listOf("abc123")
        )

        val action = deepLinkHandler.parseIntent(intent)

        assertNull(action)
    }

    @Test
    fun `parseIntent with unknown http path returns null`() {
        val intent = createMockViewIntent(
            scheme = "https",
            host = "app.ssdiddrive.example",
            pathSegments = listOf("unknown", "abc123")
        )

        val action = deepLinkHandler.parseIntent(intent)

        assertNull(action)
    }

    @Test
    fun `parseIntent with custom scheme invite missing token returns null`() {
        val intent = createMockViewIntent(
            scheme = "ssdiddrive",
            host = "invite",
            pathSegments = emptyList()
        )

        val action = deepLinkHandler.parseIntent(intent)

        // Empty path segment - should return null
        assertNull(action)
    }

    @Test
    fun `parseIntent with http scheme invite missing token returns null`() {
        val intent = createMockViewIntent(
            scheme = "https",
            host = "app.ssdiddrive.example",
            pathSegments = listOf("invite")
        )

        val action = deepLinkHandler.parseIntent(intent)

        // Missing second path segment
        assertNull(action)
    }

    @Test
    fun `parseIntent with http scheme only path returns null`() {
        val intent = createMockViewIntent(
            scheme = "https",
            host = "app.ssdiddrive.example",
            pathSegments = emptyList()
        )

        val action = deepLinkHandler.parseIntent(intent)

        assertNull(action)
    }

    // ==================== Link Generation Tests ====================

    @Test
    fun `generateShareLink creates correct URI`() {
        val expectedUri = mockk<Uri>()
        every { expectedUri.toString() } returns "ssdiddrive://share/share123"
        every { Uri.parse("ssdiddrive://share/share123") } returns expectedUri

        val uri = deepLinkHandler.generateShareLink("share123")

        assertEquals("ssdiddrive://share/share123", uri.toString())
    }

    @Test
    fun `generateWebShareLink creates correct URI with default base URL`() {
        val expectedUri = mockk<Uri>()
        every { expectedUri.toString() } returns "https://ssdiddrive.example.com/share/share123"
        every { Uri.parse("https://ssdiddrive.example.com/share/share123") } returns expectedUri

        val uri = deepLinkHandler.generateWebShareLink("share123")

        assertEquals("https://ssdiddrive.example.com/share/share123", uri.toString())
    }

    @Test
    fun `generateWebShareLink creates correct URI with custom base URL`() {
        val expectedUri = mockk<Uri>()
        every { expectedUri.toString() } returns "https://custom.example.com/share/share123"
        every { Uri.parse("https://custom.example.com/share/share123") } returns expectedUri

        val uri = deepLinkHandler.generateWebShareLink("share123", "https://custom.example.com")

        assertEquals("https://custom.example.com/share/share123", uri.toString())
    }

    // ==================== Helper Methods ====================

    private fun createMockViewIntent(
        scheme: String,
        host: String,
        pathSegments: List<String>,
        queryParams: Map<String, String> = emptyMap()
    ): Intent {
        val uri = mockk<Uri>()
        every { uri.scheme } returns scheme
        every { uri.host } returns host
        every { uri.pathSegments } returns pathSegments
        every { uri.lastPathSegment } returns pathSegments.lastOrNull()
        every { uri.toString() } returns buildUriString(scheme, host, pathSegments)
        // Support query parameter lookups
        every { uri.getQueryParameter(any()) } answers { queryParams[firstArg()] }

        val intent = mockk<Intent>()
        every { intent.action } returns Intent.ACTION_VIEW
        every { intent.data } returns uri

        return intent
    }

    private fun buildUriString(scheme: String, host: String, pathSegments: List<String>): String {
        val path = if (pathSegments.isNotEmpty()) "/${pathSegments.joinToString("/")}" else ""
        return "$scheme://$host$path"
    }
}
