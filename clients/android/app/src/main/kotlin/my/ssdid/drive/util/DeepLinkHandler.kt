package my.ssdid.drive.util

import android.content.Intent
import android.net.Uri
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Handles deep links and share intents for the app.
 *
 * Supported deep link formats:
 * - ssdiddrive://share/{shareId} - Open a shared file/folder
 * - ssdiddrive://file/{fileId} - Open a specific file
 * - ssdiddrive://folder/{folderId} - Open a specific folder
 * - ssdiddrive://invite/{token} - Accept invitation (registration)
 * - https://app.ssdiddrive.example/share/{shareId} - App link to shared content
 * - https://app.ssdiddrive.example/invite/{token} - App link for invitation
 *
 * Supported share intents:
 * - ACTION_SEND with single file
 * - ACTION_SEND_MULTIPLE with multiple files
 */
@Singleton
class DeepLinkHandler @Inject constructor() {

    /**
     * Parse an intent and return the deep link action, if any.
     */
    fun parseIntent(intent: Intent?): DeepLinkAction? {
        if (intent == null) return null

        return when (intent.action) {
            Intent.ACTION_VIEW -> parseViewIntent(intent)
            Intent.ACTION_SEND -> parseSendIntent(intent)
            Intent.ACTION_SEND_MULTIPLE -> parseSendMultipleIntent(intent)
            else -> null
        }
    }

    private fun parseViewIntent(intent: Intent): DeepLinkAction? {
        val uri = intent.data ?: return null

        return when (uri.scheme) {
            "ssdiddrive" -> parseCustomScheme(uri)
            "https", "http" -> parseHttpScheme(uri)
            else -> null
        }
    }

    private fun parseCustomScheme(uri: Uri): DeepLinkAction? {
        // ssdiddrive://share/{shareId}
        // ssdiddrive://file/{fileId}
        // ssdiddrive://folder/{folderId}
        // ssdiddrive://invite/{token}

        val host = uri.host ?: return null
        val pathSegments = uri.pathSegments

        return when (host) {
            "share" -> {
                val shareId = pathSegments.firstOrNull() ?: uri.lastPathSegment
                shareId?.let { DeepLinkAction.OpenShare(it) }
            }
            "file" -> {
                val fileId = pathSegments.firstOrNull() ?: uri.lastPathSegment
                fileId?.let { DeepLinkAction.OpenFile(it) }
            }
            "folder" -> {
                val folderId = pathSegments.firstOrNull() ?: uri.lastPathSegment
                folderId?.let { DeepLinkAction.OpenFolder(it) }
            }
            "invite" -> {
                val segment = pathSegments.firstOrNull()
                if (segment == "callback") {
                    // ssdiddrive://invite/callback?session_token=...&status=...
                    val sessionToken = uri.getQueryParameter("session_token")
                    val status = uri.getQueryParameter("status") ?: ""

                    when {
                        status == "success" && sessionToken != null ->
                            DeepLinkAction.WalletInviteCallback(sessionToken)
                        status == "error" ->
                            DeepLinkAction.WalletInviteError(
                                uri.getQueryParameter("message") ?: "Invitation failed"
                            )
                        status == "denied" -> null
                        sessionToken != null ->
                            // No status but has token — treat as success (legacy callback)
                            DeepLinkAction.WalletInviteCallback(sessionToken)
                        else ->
                            DeepLinkAction.WalletInviteError("Invitation failed")
                    }
                } else {
                    // ssdiddrive://invite/{token} — open invitation acceptance screen
                    val token = segment ?: uri.lastPathSegment
                    token?.let { DeepLinkAction.AcceptInvitation(it) }
                }
            }
            "auth" -> {
                // ssdiddrive://auth/callback?session_token=... (SSDID Wallet)
                // ssdiddrive://auth/callback?token=...&provider=... (OIDC browser redirect)
                val segment = pathSegments.firstOrNull()
                if (segment == "callback") {
                    val sessionToken = uri.getQueryParameter("session_token")
                        ?: uri.getQueryParameter("token")
                    val error = uri.getQueryParameter("error")
                    when {
                        sessionToken != null -> DeepLinkAction.WalletAuthCallback(sessionToken)
                        error != null -> DeepLinkAction.OidcAuthError(error)
                        else -> null
                    }
                } else null
            }
            else -> null
        }
    }

    private fun parseHttpScheme(uri: Uri): DeepLinkAction? {
        // https://app.ssdiddrive.example/share/{shareId}
        // https://app.ssdiddrive.example/invite/{token}

        val pathSegments = uri.pathSegments
        if (pathSegments.isEmpty()) return null

        return when (pathSegments.first()) {
            "share" -> {
                val shareId = pathSegments.getOrNull(1)
                shareId?.let { DeepLinkAction.OpenShare(it) }
            }
            "file" -> {
                val fileId = pathSegments.getOrNull(1)
                fileId?.let { DeepLinkAction.OpenFile(it) }
            }
            "folder" -> {
                val folderId = pathSegments.getOrNull(1)
                folderId?.let { DeepLinkAction.OpenFolder(it) }
            }
            "invite" -> {
                val token = pathSegments.getOrNull(1)
                token?.let { DeepLinkAction.AcceptInvitation(it) }
            }
            else -> null
        }
    }

    @Suppress("DEPRECATION")
    private fun parseSendIntent(intent: Intent): DeepLinkAction? {
        // Single file shared from another app
        val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            ?: return null

        val mimeType = intent.type ?: "*/*"

        return DeepLinkAction.UploadFiles(listOf(uri), mimeType)
    }

    @Suppress("DEPRECATION")
    private fun parseSendMultipleIntent(intent: Intent): DeepLinkAction? {
        // Multiple files shared from another app
        val uris = intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
            ?: return null

        if (uris.isEmpty()) return null

        val mimeType = intent.type ?: "*/*"

        return DeepLinkAction.UploadFiles(uris, mimeType)
    }

    /**
     * Generate a deep link URI for sharing.
     */
    fun generateShareLink(shareId: String): Uri {
        return Uri.parse("ssdiddrive://share/$shareId")
    }

    /**
     * Generate an HTTPS link for sharing (requires backend support).
     */
    fun generateWebShareLink(shareId: String, baseUrl: String = "https://ssdiddrive.example.com"): Uri {
        return Uri.parse("$baseUrl/share/$shareId")
    }
}

/**
 * Represents an action to be taken based on a deep link or intent.
 */
sealed class DeepLinkAction {
    /**
     * Open a shared file or folder by share ID.
     */
    data class OpenShare(val shareId: String) : DeepLinkAction()

    /**
     * Open a specific file by file ID.
     */
    data class OpenFile(val fileId: String) : DeepLinkAction()

    /**
     * Open a specific folder by folder ID.
     */
    data class OpenFolder(val folderId: String) : DeepLinkAction()

    /**
     * Upload files received from another app.
     */
    data class UploadFiles(val uris: List<Uri>, val mimeType: String) : DeepLinkAction()

    /**
     * Accept an invitation using a token.
     * This takes the user to the invitation acceptance/registration screen.
     */
    data class AcceptInvitation(val token: String) : DeepLinkAction()

    /**
     * Handle SSDID Wallet authentication callback.
     * Contains the session token from the wallet after successful authentication.
     * Also used for OIDC browser redirect callback (token param).
     */
    data class WalletAuthCallback(val sessionToken: String) : DeepLinkAction()

    /**
     * Handle OIDC browser redirect callback error.
     */
    data class OidcAuthError(val error: String) : DeepLinkAction()

    /**
     * Handle SSDID Wallet invitation callback with session token.
     */
    data class WalletInviteCallback(val sessionToken: String) : DeepLinkAction()

    /**
     * Handle SSDID Wallet invitation callback with error.
     */
    data class WalletInviteError(val message: String) : DeepLinkAction()
}
