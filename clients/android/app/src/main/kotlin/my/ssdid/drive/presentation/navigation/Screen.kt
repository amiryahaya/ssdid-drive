package my.ssdid.drive.presentation.navigation

import java.net.URLEncoder

/**
 * Sealed class representing all screens in the app.
 * Used for type-safe navigation.
 */
sealed class Screen(val route: String) {

    // Onboarding
    data object Onboarding : Screen("onboarding")

    // Auth screens
    data object Login : Screen("login")
    data object Register : Screen("register")
    data object Lock : Screen("lock")
    data object EmailLogin : Screen("email-login")
    data object TotpVerify : Screen("totp-verify/{email}") {
        fun createRoute(email: String) = "totp-verify/${URLEncoder.encode(email, "UTF-8")}"
    }
    data object TotpSetup : Screen("totp-setup")
    data object TotpRecovery : Screen("totp-recovery/{email}") {
        fun createRoute(email: String) = "totp-recovery/${URLEncoder.encode(email, "UTF-8")}"
    }

    // Invitation acceptance (deep link)
    data object InviteAccept : Screen("invite/{token}") {
        fun createRoute(token: String) = "invite/${URLEncoder.encode(token, "UTF-8")}"
    }

    // Main screens
    data object Files : Screen("files")
    data object FileBrowser : Screen("files/{folderId}") {
        fun createRoute(folderId: String) = "files/$folderId"
    }

    // Sharing screens
    data object ReceivedShares : Screen("shares/received")
    data object CreatedShares : Screen("shares/created")
    data object ShareFile : Screen("share/file/{fileId}") {
        fun createRoute(fileId: String) = "share/file/$fileId"
    }
    data object ShareFolder : Screen("share/folder/{folderId}") {
        fun createRoute(folderId: String) = "share/folder/$folderId"
    }

    // Recovery screens
    data object Recovery : Screen("recovery")
    data object RecoverySetup : Screen("recovery/setup")
    data object RecoveryTrustees : Screen("recovery/trustees/{totalShares}") {
        fun createRoute(totalShares: Int) = "recovery/trustees/$totalShares"
    }
    data object TrusteeDashboard : Screen("recovery/trustee-dashboard")
    data object InitiateRecovery : Screen("recovery/initiate")

    // Activity
    data object Activity : Screen("activity")

    // Settings screens
    data object Settings : Screen("settings")
    data object Profile : Screen("settings/profile")
    data object Security : Screen("settings/security")
    data object Invitations : Screen("settings/invitations")
    data object CreateInvitation : Screen("settings/invitations/create")
    data object SentInvitations : Screen("settings/invitations/sent")
    data object Members : Screen("settings/members")
    data object LinkedLogins : Screen("settings/linked-logins")

    // Tenant screens
    data object JoinTenant : Screen("join-tenant")

    // File operations
    data object FilePreview : Screen("file/{fileId}/preview") {
        fun createRoute(fileId: String) = "file/$fileId/preview"
    }
    data object Upload : Screen("upload/{folderId}") {
        fun createRoute(folderId: String) = "upload/$folderId"
    }

    // Share intent (receive files from other apps)
    data object ShareIntent : Screen("share-intent")

    // PII Chat screens
    data object PiiConversations : Screen("pii-chat/conversations")
    data class PiiChat(val conversationId: String) : Screen("pii-chat/{conversationId}") {
        companion object {
            const val ROUTE = "pii-chat/{conversationId}"
            fun createRoute(conversationId: String) = "pii-chat/$conversationId"
        }
    }

    companion object {
        const val ARG_FOLDER_ID = "folderId"
        const val ARG_FILE_ID = "fileId"
        const val ARG_TOTAL_SHARES = "totalShares"
        const val ARG_TOKEN = "token"
        const val ARG_CONVERSATION_ID = "conversationId"
        const val ARG_EMAIL = "email"
    }
}
