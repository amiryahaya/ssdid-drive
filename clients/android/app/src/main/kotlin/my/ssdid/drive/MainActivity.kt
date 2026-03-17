package my.ssdid.drive

import android.content.Intent
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.navigation.NavHostController
import androidx.navigation.compose.rememberNavController
import my.ssdid.drive.data.local.PreferencesManager
import my.ssdid.drive.domain.repository.AuthRepository
import my.ssdid.drive.presentation.common.theme.SsdidDriveTheme
import my.ssdid.drive.presentation.navigation.NavGraph
import my.ssdid.drive.presentation.navigation.NavigationViewModel
import my.ssdid.drive.presentation.navigation.Screen
import my.ssdid.drive.util.DeepLinkAction
import my.ssdid.drive.util.DeepLinkHandler
import my.ssdid.drive.util.ShareIntentManager
import my.ssdid.drive.util.WalletCallbackHolder
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * Main Activity for SSDID Drive.
 *
 * This is the single activity that hosts all Compose screens.
 * Navigation is handled via Jetpack Navigation Compose.
 *
 * SECURITY: Screen capture protection is enabled in release builds
 * to prevent screenshots and screen recording of sensitive data.
 */
@AndroidEntryPoint
class MainActivity : ComponentActivity() {

    @Inject
    lateinit var deepLinkHandler: DeepLinkHandler

    @Inject
    lateinit var authRepository: AuthRepository

    @Inject
    lateinit var preferencesManager: PreferencesManager

    @Inject
    lateinit var shareIntentManager: ShareIntentManager

    // State-driven recomposition: avoids duplicate setContent calls in onNewIntent/onResume
    private val _deepLinkAction = MutableStateFlow<DeepLinkAction?>(null)
    private val _shouldLock = MutableStateFlow(false)
    private var backgroundTimestamp: Long = 0L

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Enable screen capture protection in release builds
        // This prevents screenshots, screen recording, and display on non-secure displays
        if (!BuildConfig.DEBUG) {
            window.setFlags(
                WindowManager.LayoutParams.FLAG_SECURE,
                WindowManager.LayoutParams.FLAG_SECURE
            )
        }

        enableEdgeToEdge()

        // Handle deep link from launch intent
        _deepLinkAction.value = deepLinkHandler.parseIntent(intent)
        handleShareIntent(_deepLinkAction.value)

        // Single setContent — state changes drive recomposition
        setContent {
            val deepLinkAction by _deepLinkAction.collectAsState()
            val shouldLock by _shouldLock.collectAsState()

            SsdidDriveApp(
                deepLinkAction = deepLinkAction,
                onDeepLinkHandled = { _deepLinkAction.value = null },
                shouldLock = shouldLock,
                onLockHandled = { _shouldLock.value = false }
            )
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val action = deepLinkHandler.parseIntent(intent)
        handleShareIntent(action)
        // State change triggers recomposition — no second setContent needed
        _deepLinkAction.value = action
    }

    /**
     * Handle share intent by storing URIs in ShareIntentManager.
     */
    private fun handleShareIntent(action: DeepLinkAction?) {
        if (action is DeepLinkAction.UploadFiles) {
            shareIntentManager.setPendingFiles(action.uris, action.mimeType)
        }
    }

    override fun onStop() {
        super.onStop()
        // Record when app went to background
        backgroundTimestamp = System.currentTimeMillis()
    }

    override fun onResume() {
        super.onResume()

        // Check if we should lock due to auto-lock timeout
        if (backgroundTimestamp > 0) {
            lifecycleScope.launch {
                val autoLockEnabled = preferencesManager.autoLockEnabled.first()
                val biometricEnabled = authRepository.isBiometricUnlockEnabled()

                if (autoLockEnabled && biometricEnabled) {
                    val timeout = preferencesManager.autoLockTimeout.first()
                    val elapsedMinutes = (System.currentTimeMillis() - backgroundTimestamp) / 60000

                    if (timeout.minutes >= 0 && elapsedMinutes >= timeout.minutes) {
                        authRepository.lockKeys()
                        // State change triggers recomposition — no setContent needed
                        _shouldLock.value = true
                    }
                }
            }
        }
    }

    /**
     * Enable screen capture protection programmatically.
     * Call this when navigating to sensitive screens.
     */
    fun enableScreenCaptureProtection() {
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
    }

    /**
     * Disable screen capture protection programmatically.
     * Call this when leaving sensitive screens (only in debug builds).
     *
     * SECURITY: In release builds, protection remains enabled at all times.
     */
    fun disableScreenCaptureProtection() {
        if (BuildConfig.DEBUG) {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }

    /**
     * Check if screen capture protection is currently enabled.
     */
    fun isScreenCaptureProtectionEnabled(): Boolean {
        return window.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE != 0
    }
}

@Composable
fun SsdidDriveApp(
    deepLinkAction: DeepLinkAction? = null,
    onDeepLinkHandled: () -> Unit = {},
    shouldLock: Boolean = false,
    onLockHandled: () -> Unit = {}
) {
    val navController = rememberNavController()
    val navigationViewModel: NavigationViewModel = hiltViewModel()
    val startDestination by navigationViewModel.startDestination.collectAsState()

    // Handle deep link navigation
    LaunchedEffect(deepLinkAction, startDestination) {
        if (deepLinkAction != null && startDestination != null) {
            handleDeepLink(navController, deepLinkAction)
            onDeepLinkHandled()
        }
    }

    // Handle lock screen navigation from auto-lock
    LaunchedEffect(shouldLock) {
        if (shouldLock) {
            navController.navigate(Screen.Lock.route) {
                popUpTo(0) { inclusive = false }
            }
            onLockHandled()
        }
    }

    SsdidDriveTheme {
        Surface(
            modifier = Modifier.fillMaxSize(),
            color = MaterialTheme.colorScheme.background
        ) {
            startDestination?.let { destination ->
                NavGraph(
                    navController = navController,
                    startDestination = destination,
                    onOnboardingComplete = { navigationViewModel.completeOnboarding() }
                )
            }
        }
    }
}

/**
 * Handle navigation based on deep link action.
 */
private fun handleDeepLink(navController: NavHostController, action: DeepLinkAction) {
    when (action) {
        is DeepLinkAction.OpenShare -> {
            // Navigate to share details screen
            // The exact route depends on whether it's a file or folder share
            // For now, navigate to received shares
            navController.navigate("shares/received")
        }
        is DeepLinkAction.OpenFile -> {
            // Navigate to file preview
            navController.navigate("file/${action.fileId}")
        }
        is DeepLinkAction.OpenFolder -> {
            // Navigate to folder
            navController.navigate("folder/${action.folderId}")
        }
        is DeepLinkAction.UploadFiles -> {
            // Navigate to share intent screen
            // URIs are stored in ShareIntentManager before this is called
            navController.navigate(Screen.ShareIntent.route)
        }
        is DeepLinkAction.AcceptInvitation -> {
            // Navigate to invitation acceptance screen
            // This bypasses auth check since it's for new user registration
            navController.navigate(Screen.InviteAccept.createRoute(action.token)) {
                // Clear the back stack so user can't go back to previous screens
                popUpTo(0) { inclusive = true }
            }
        }
        is DeepLinkAction.WalletAuthCallback -> {
            // Store session token for LoginViewModel to consume on resume
            WalletCallbackHolder.set(action.sessionToken, WalletCallbackHolder.Flow.AUTH)
            navController.navigate(Screen.Login.route) {
                launchSingleTop = true
            }
        }
        is DeepLinkAction.WalletInviteCallback -> {
            // Store session token tagged for invite flow — InviteAcceptScreen
            // consumes it on resume via lifecycle observer
            WalletCallbackHolder.set(action.sessionToken, WalletCallbackHolder.Flow.INVITE)
        }
        is DeepLinkAction.WalletInviteError -> {
            // Store error for InviteAcceptScreen to consume on resume
            WalletCallbackHolder.setError(action.message, WalletCallbackHolder.Flow.INVITE)
        }
        is DeepLinkAction.OidcAuthError -> {
            // Store OIDC browser redirect error for LoginScreen to surface on resume
            WalletCallbackHolder.setError(action.error, WalletCallbackHolder.Flow.AUTH)
            navController.navigate(Screen.Login.route) {
                launchSingleTop = true
            }
        }
    }
}
