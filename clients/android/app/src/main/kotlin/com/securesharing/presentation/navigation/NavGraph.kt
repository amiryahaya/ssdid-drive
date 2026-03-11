package com.securesharing.presentation.navigation

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.navArgument
import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.ui.platform.LocalContext
import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.android.EntryPointAccessors
import dagger.hilt.components.SingletonComponent
import com.securesharing.util.AnalyticsManager
import com.securesharing.presentation.auth.InviteAcceptScreen
import com.securesharing.presentation.auth.LockScreen
import com.securesharing.presentation.auth.LoginScreen
import com.securesharing.presentation.auth.RegisterScreen
import com.securesharing.presentation.files.FileBrowserScreen
import com.securesharing.presentation.recovery.InitiateRecoveryScreen
import com.securesharing.presentation.recovery.PendingRequestsScreen
import com.securesharing.presentation.recovery.RecoverySetupScreen
import com.securesharing.presentation.recovery.TrusteeSelectionScreen
import com.securesharing.presentation.files.upload.ShareIntentScreen
import com.securesharing.presentation.settings.CredentialManagerScreen
import com.securesharing.presentation.settings.InvitationsScreen
import com.securesharing.presentation.settings.SettingsScreen
import com.securesharing.presentation.sharing.ReceivedSharesScreen
import com.securesharing.presentation.sharing.CreatedSharesScreen
import com.securesharing.presentation.sharing.ShareFileScreen
import com.securesharing.presentation.sharing.ShareFolderScreen
import com.securesharing.presentation.files.preview.FilePreviewScreen
import com.securesharing.presentation.onboarding.OnboardingScreen
import com.securesharing.presentation.piichat.ConversationsScreen
import com.securesharing.presentation.piichat.ChatScreen

@EntryPoint
@InstallIn(SingletonComponent::class)
interface NavGraphEntryPoint {
    fun analyticsManager(): AnalyticsManager
}

/**
 * Main navigation graph for the app.
 */
@Composable
fun NavGraph(
    navController: NavHostController,
    startDestination: String,
    onOnboardingComplete: () -> Unit = {}
) {
    val context = LocalContext.current
    val entryPoint = EntryPointAccessors.fromApplication(
        context.applicationContext,
        NavGraphEntryPoint::class.java
    )
    val analyticsManager = entryPoint.analyticsManager()

    DisposableEffect(navController) {
        val listener = NavHostController.OnDestinationChangedListener { _, destination, _ ->
            val route = destination.route?.substringBefore("/")?.substringBefore("?") ?: "unknown"
            analyticsManager.trackNavigation(
                from = navController.previousBackStackEntry?.destination?.route
                    ?.substringBefore("/")?.substringBefore("?") ?: "none",
                to = route
            )
        }
        navController.addOnDestinationChangedListener(listener)
        onDispose { navController.removeOnDestinationChangedListener(listener) }
    }

    NavHost(
        navController = navController,
        startDestination = startDestination
    ) {
        // Onboarding screen for first-time users
        composable(Screen.Onboarding.route) {
            OnboardingScreen(
                onComplete = {
                    onOnboardingComplete()
                    navController.navigate(Screen.Login.route) {
                        popUpTo(Screen.Onboarding.route) { inclusive = true }
                    }
                }
            )
        }

        // Auth screens
        composable(Screen.Login.route) {
            val context = LocalContext.current
            LoginScreen(
                onLoginSuccess = {
                    navController.navigate(Screen.Files.route) {
                        popUpTo(Screen.Login.route) { inclusive = true }
                    }
                },
                onOidcBrowserOpen = { url ->
                    val customTabsIntent = CustomTabsIntent.Builder().build()
                    customTabsIntent.launchUrl(context, Uri.parse(url))
                }
            )
        }

        // Register screen (kept for backwards compatibility, but hidden from UI)
        composable(Screen.Register.route) {
            RegisterScreen(
                onNavigateToLogin = {
                    navController.popBackStack()
                },
                onRegisterSuccess = {
                    navController.navigate(Screen.Files.route) {
                        popUpTo(Screen.Register.route) { inclusive = true }
                    }
                }
            )
        }

        // Invitation acceptance screen (deep link: /invite/{token})
        composable(
            route = Screen.InviteAccept.route,
            arguments = listOf(
                navArgument(Screen.ARG_TOKEN) { type = NavType.StringType }
            )
        ) {
            InviteAcceptScreen(
                onRegistrationSuccess = {
                    navController.navigate(Screen.Files.route) {
                        popUpTo(0) { inclusive = true }
                    }
                },
                onNavigateToLogin = {
                    navController.navigate(Screen.Login.route) {
                        popUpTo(Screen.InviteAccept.route) { inclusive = true }
                    }
                }
            )
        }

        // Lock screen - shown when app is locked
        composable(Screen.Lock.route) {
            LockScreen(
                onUnlocked = {
                    navController.navigate(Screen.Files.route) {
                        popUpTo(Screen.Lock.route) { inclusive = true }
                    }
                }
            )
        }

        // File browser - root
        composable(Screen.Files.route) {
            FileBrowserScreen(
                folderId = null,
                onNavigateToFolder = { folderId ->
                    navController.navigate(Screen.FileBrowser.createRoute(folderId))
                },
                onNavigateToFile = { fileId ->
                    navController.navigate(Screen.FilePreview.createRoute(fileId))
                },
                onNavigateToSettings = {
                    navController.navigate(Screen.Settings.route)
                },
                onNavigateToShares = {
                    navController.navigate(Screen.ReceivedShares.route)
                },
                onNavigateToShareFile = { fileId ->
                    navController.navigate(Screen.ShareFile.createRoute(fileId))
                },
                onNavigateToShareFolder = { folderId ->
                    navController.navigate(Screen.ShareFolder.createRoute(folderId))
                }
            )
        }

        // File browser - subfolder
        composable(
            route = Screen.FileBrowser.route,
            arguments = listOf(
                navArgument(Screen.ARG_FOLDER_ID) { type = NavType.StringType }
            )
        ) { backStackEntry ->
            val folderId = backStackEntry.arguments?.getString(Screen.ARG_FOLDER_ID)
            FileBrowserScreen(
                folderId = folderId,
                onNavigateToFolder = { newFolderId ->
                    navController.navigate(Screen.FileBrowser.createRoute(newFolderId))
                },
                onNavigateToFile = { fileId ->
                    navController.navigate(Screen.FilePreview.createRoute(fileId))
                },
                onNavigateBack = {
                    navController.popBackStack()
                },
                onNavigateToSettings = {
                    navController.navigate(Screen.Settings.route)
                },
                onNavigateToShares = {
                    navController.navigate(Screen.ReceivedShares.route)
                },
                onNavigateToShareFile = { fileId ->
                    navController.navigate(Screen.ShareFile.createRoute(fileId))
                },
                onNavigateToShareFolder = { folderId ->
                    navController.navigate(Screen.ShareFolder.createRoute(folderId))
                }
            )
        }

        // Sharing screens
        composable(Screen.ReceivedShares.route) {
            ReceivedSharesScreen(
                onNavigateBack = { navController.popBackStack() },
                onNavigateToFile = { fileId ->
                    navController.navigate(Screen.FilePreview.createRoute(fileId))
                },
                onNavigateToFolder = { folderId ->
                    navController.navigate(Screen.FileBrowser.createRoute(folderId))
                },
                onNavigateToCreated = {
                    navController.navigate(Screen.CreatedShares.route)
                }
            )
        }

        composable(Screen.CreatedShares.route) {
            CreatedSharesScreen(
                onNavigateBack = { navController.popBackStack() }
            )
        }

        // Settings
        composable(Screen.Settings.route) {
            SettingsScreen(
                onNavigateBack = { navController.popBackStack() },
                onLogout = {
                    navController.navigate(Screen.Login.route) {
                        popUpTo(0) { inclusive = true }
                    }
                },
                onNavigateToRecoverySetup = {
                    navController.navigate(Screen.RecoverySetup.route)
                },
                onNavigateToTrusteeDashboard = {
                    navController.navigate(Screen.TrusteeDashboard.route)
                },
                onNavigateToInitiateRecovery = {
                    navController.navigate(Screen.InitiateRecovery.route)
                },
                onNavigateToInvitations = {
                    navController.navigate(Screen.Invitations.route)
                },
                onNavigateToPiiChat = {
                    navController.navigate(Screen.PiiConversations.route)
                },
                onNavigateToCredentials = {
                    navController.navigate(Screen.Credentials.route)
                }
            )
        }

        // Credentials
        composable(Screen.Credentials.route) {
            CredentialManagerScreen(
                onNavigateBack = { navController.popBackStack() }
            )
        }

        // Invitations
        composable(Screen.Invitations.route) {
            InvitationsScreen(
                onNavigateBack = { navController.popBackStack() }
            )
        }

        // Recovery screens
        composable(Screen.RecoverySetup.route) {
            RecoverySetupScreen(
                onNavigateBack = { navController.popBackStack() },
                onNavigateToTrusteeSelection = { totalShares ->
                    navController.navigate(Screen.RecoveryTrustees.createRoute(totalShares))
                }
            )
        }

        composable(
            route = Screen.RecoveryTrustees.route,
            arguments = listOf(
                navArgument(Screen.ARG_TOTAL_SHARES) { type = NavType.IntType }
            )
        ) { backStackEntry ->
            val totalShares = backStackEntry.arguments?.getInt(Screen.ARG_TOTAL_SHARES) ?: 3
            TrusteeSelectionScreen(
                totalShares = totalShares,
                onNavigateBack = { navController.popBackStack() },
                onComplete = {
                    navController.navigate(Screen.Settings.route) {
                        popUpTo(Screen.RecoverySetup.route) { inclusive = true }
                    }
                }
            )
        }

        composable(Screen.TrusteeDashboard.route) {
            PendingRequestsScreen(
                onNavigateBack = { navController.popBackStack() }
            )
        }

        composable(Screen.InitiateRecovery.route) {
            InitiateRecoveryScreen(
                onNavigateBack = { navController.popBackStack() },
                onRecoveryComplete = {
                    navController.navigate(Screen.Login.route) {
                        popUpTo(0) { inclusive = true }
                    }
                }
            )
        }

        // File preview
        composable(
            route = Screen.FilePreview.route,
            arguments = listOf(
                navArgument(Screen.ARG_FILE_ID) { type = NavType.StringType }
            )
        ) { backStackEntry ->
            val fileId = backStackEntry.arguments?.getString(Screen.ARG_FILE_ID) ?: return@composable
            FilePreviewScreen(
                fileId = fileId,
                onNavigateBack = { navController.popBackStack() },
                onShare = { id ->
                    navController.navigate(Screen.ShareFile.createRoute(id))
                },
                onDownload = { /* Handle download */ }
            )
        }

        // Share file screen
        composable(
            route = Screen.ShareFile.route,
            arguments = listOf(
                navArgument(Screen.ARG_FILE_ID) { type = NavType.StringType }
            )
        ) {
            ShareFileScreen(
                onNavigateBack = { navController.popBackStack() },
                onShareSuccess = {
                    navController.popBackStack()
                }
            )
        }

        // Share folder screen
        composable(
            route = Screen.ShareFolder.route,
            arguments = listOf(
                navArgument(Screen.ARG_FOLDER_ID) { type = NavType.StringType }
            )
        ) {
            ShareFolderScreen(
                onNavigateBack = { navController.popBackStack() },
                onShareSuccess = {
                    navController.popBackStack()
                }
            )
        }

        // Share intent - upload files received from other apps
        composable(Screen.ShareIntent.route) {
            ShareIntentScreen(
                onNavigateBack = {
                    navController.popBackStack()
                },
                onUploadComplete = {
                    navController.navigate(Screen.Files.route) {
                        popUpTo(Screen.ShareIntent.route) { inclusive = true }
                    }
                }
            )
        }

        // PII Chat - Conversation list
        composable(Screen.PiiConversations.route) {
            ConversationsScreen(
                onNavigateBack = { navController.popBackStack() },
                onNavigateToChat = { conversationId ->
                    navController.navigate(Screen.PiiChat.createRoute(conversationId))
                }
            )
        }

        // PII Chat - Chat screen
        composable(
            route = Screen.PiiChat.ROUTE,
            arguments = listOf(
                navArgument(Screen.ARG_CONVERSATION_ID) { type = NavType.StringType }
            )
        ) {
            ChatScreen(
                onNavigateBack = { navController.popBackStack() }
            )
        }
    }
}
