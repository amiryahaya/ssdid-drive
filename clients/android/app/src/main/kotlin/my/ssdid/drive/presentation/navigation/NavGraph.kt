package my.ssdid.drive.presentation.navigation

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.platform.LocalContext
import androidx.navigation.NavController
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.navArgument
import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.android.EntryPointAccessors
import dagger.hilt.components.SingletonComponent
import my.ssdid.drive.util.AnalyticsManager
import my.ssdid.drive.presentation.auth.InviteAcceptScreen
import my.ssdid.drive.presentation.auth.LockScreen
import my.ssdid.drive.presentation.auth.LoginScreen
import my.ssdid.drive.presentation.auth.RegisterScreen
import my.ssdid.drive.presentation.auth.TotpSetupScreen
import my.ssdid.drive.presentation.auth.TotpVerifyScreen
import my.ssdid.drive.presentation.files.FileBrowserScreen
import my.ssdid.drive.presentation.recovery.InitiateRecoveryScreen
import my.ssdid.drive.presentation.recovery.PendingRequestsScreen
import my.ssdid.drive.presentation.recovery.RecoveryScreen
import my.ssdid.drive.presentation.recovery.RecoverySetupScreen
import my.ssdid.drive.presentation.recovery.TrusteeSelectionScreen
import my.ssdid.drive.presentation.files.upload.ShareIntentScreen
import my.ssdid.drive.presentation.settings.CreateInvitationScreen
import my.ssdid.drive.presentation.settings.InvitationsScreen
import my.ssdid.drive.presentation.settings.LinkedLoginsScreen
import my.ssdid.drive.presentation.settings.MembersScreen
import my.ssdid.drive.presentation.settings.SentInvitationsScreen
import my.ssdid.drive.presentation.settings.SettingsScreen
import my.ssdid.drive.presentation.tenant.JoinTenantScreen
import my.ssdid.drive.presentation.sharing.ReceivedSharesScreen
import my.ssdid.drive.presentation.sharing.CreatedSharesScreen
import my.ssdid.drive.presentation.sharing.ShareFileScreen
import my.ssdid.drive.presentation.sharing.ShareFolderScreen
import my.ssdid.drive.presentation.files.preview.FilePreviewScreen
import my.ssdid.drive.presentation.activity.ActivityScreen
import my.ssdid.drive.presentation.onboarding.OnboardingScreen
import my.ssdid.drive.presentation.piichat.ConversationsScreen

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
        val listener = NavController.OnDestinationChangedListener { _, destination, _ ->
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
            LoginScreen(
                onLoginSuccess = {
                    navController.navigate(Screen.Files.route) {
                        popUpTo(Screen.Login.route) { inclusive = true }
                    }
                },
                onNavigateToRegister = {
                    navController.navigate(Screen.Register.route)
                },
                onNavigateToRecovery = {
                    navController.navigate(Screen.Recovery.route)
                },
                onNavigateToTotp = { email ->
                    navController.navigate(Screen.TotpVerify.createRoute(email))
                },
                onNavigateToJoinTenant = {
                    navController.navigate(Screen.JoinTenant.route)
                },
                onNavigateToTenantRequest = {
                    navController.navigate(Screen.TenantRequest.route)
                },
                onOidcLogin = { _ ->
                    // OIDC is handled by the LoginViewModel via native SDK callbacks
                }
            )
        }

        // TOTP verification (login step 2)
        composable(
            route = Screen.TotpVerify.route,
            arguments = listOf(
                navArgument(Screen.ARG_EMAIL) { type = NavType.StringType }
            )
        ) {
            TotpVerifyScreen(
                onLoginSuccess = {
                    navController.navigate(Screen.Files.route) {
                        popUpTo(Screen.Login.route) { inclusive = true }
                    }
                },
                onNavigateToRecovery = { email ->
                    navController.navigate(Screen.TotpRecovery.createRoute(email))
                },
                onNavigateBack = { navController.popBackStack() }
            )
        }

        // TOTP setup
        composable(Screen.TotpSetup.route) {
            TotpSetupScreen(
                onSetupComplete = {
                    navController.navigate(Screen.Files.route) {
                        popUpTo(Screen.TotpSetup.route) { inclusive = true }
                    }
                },
                onNavigateBack = { navController.popBackStack() }
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

        // Activity
        composable(Screen.Activity.route) {
            ActivityScreen(
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
                onNavigateToCreateInvitation = {
                    navController.navigate(Screen.CreateInvitation.route)
                },
                onNavigateToSentInvitations = {
                    navController.navigate(Screen.SentInvitations.route)
                },
                onNavigateToMembers = {
                    navController.navigate(Screen.Members.route)
                },
                onNavigateToPiiChat = {
                    navController.navigate(Screen.PiiConversations.route)
                },
                onNavigateToJoinTenant = {
                    navController.navigate(Screen.JoinTenant.route)
                },
                onNavigateToLinkedLogins = {
                    navController.navigate(Screen.LinkedLogins.route)
                }
            )
        }

        // Join Tenant (invite code entry)
        composable(Screen.JoinTenant.route) {
            JoinTenantScreen(
                onNavigateBack = { navController.popBackStack() },
                onJoinSuccess = {
                    navController.navigate(Screen.Files.route) {
                        popUpTo(Screen.JoinTenant.route) { inclusive = true }
                    }
                },
                onNavigateToLogin = {
                    navController.navigate(Screen.Login.route) {
                        popUpTo(Screen.JoinTenant.route) { inclusive = true }
                    }
                },
                isLoggedIn = true
            )
        }

        // Invitations - Received (pending)
        composable(Screen.Invitations.route) {
            InvitationsScreen(
                onNavigateBack = { navController.popBackStack() }
            )
        }

        // Invitations - Create
        composable(Screen.CreateInvitation.route) {
            CreateInvitationScreen(
                onNavigateBack = { navController.popBackStack() }
            )
        }

        // Invitations - Sent
        composable(Screen.SentInvitations.route) {
            SentInvitationsScreen(
                onNavigateBack = { navController.popBackStack() }
            )
        }

        // Members management
        composable(Screen.Members.route) {
            MembersScreen(
                onNavigateBack = { navController.popBackStack() }
            )
        }

        // Linked logins management
        composable(Screen.LinkedLogins.route) {
            LinkedLoginsScreen(
                onNavigateBack = { navController.popBackStack() },
                onOidcLink = { provider ->
                    // OIDC linking is handled by the LinkedLoginsViewModel via native SDK callbacks
                    // The provider parameter triggers the platform-specific OIDC flow
                }
            )
        }

        // Recovery screens
        composable(Screen.Recovery.route) {
            RecoveryScreen(
                onNavigateBack = { navController.popBackStack() },
                onRecoveryComplete = {
                    navController.navigate(Screen.Login.route) {
                        popUpTo(Screen.Recovery.route) { inclusive = true }
                    }
                }
            )
        }

        composable(Screen.RecoverySetup.route) {
            RecoverySetupScreen(
                onNavigateBack = { navController.popBackStack() }
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

        // PII Chat - Coming Soon
        composable(Screen.PiiConversations.route) {
            ConversationsScreen(
                onNavigateBack = { navController.popBackStack() }
            )
        }
    }
}
