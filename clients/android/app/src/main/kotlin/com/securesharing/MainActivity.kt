package com.securesharing

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
import com.securesharing.data.local.PreferencesManager
import com.securesharing.domain.repository.AuthRepository
import com.securesharing.presentation.common.theme.SecureSharingTheme
import com.securesharing.presentation.navigation.NavGraph
import com.securesharing.presentation.navigation.NavigationViewModel
import com.securesharing.presentation.navigation.Screen
import com.securesharing.util.DeepLinkAction
import com.securesharing.util.DeepLinkHandler
import com.securesharing.util.OidcCallbackHolder
import com.securesharing.util.ShareIntentManager
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * Main Activity for SecureSharing.
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

    private var pendingDeepLinkAction: DeepLinkAction? = null
    private var backgroundTimestamp: Long = 0L
    private var shouldLockOnResume: Boolean = false

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
        pendingDeepLinkAction = deepLinkHandler.parseIntent(intent)
        handleShareIntent(pendingDeepLinkAction)

        setContent {
            SecureSharingApp(
                deepLinkAction = pendingDeepLinkAction,
                onDeepLinkHandled = { pendingDeepLinkAction = null },
                shouldLock = shouldLockOnResume,
                onLockHandled = { shouldLockOnResume = false }
            )
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Handle deep link from new intent (when app is already running)
        pendingDeepLinkAction = deepLinkHandler.parseIntent(intent)
        setIntent(intent)
        handleShareIntent(pendingDeepLinkAction)

        // Re-compose with new deep link
        setContent {
            SecureSharingApp(
                deepLinkAction = pendingDeepLinkAction,
                onDeepLinkHandled = { pendingDeepLinkAction = null },
                shouldLock = shouldLockOnResume,
                onLockHandled = { shouldLockOnResume = false }
            )
        }
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
                        // Lock the app
                        authRepository.lockKeys()
                        shouldLockOnResume = true

                        // Re-compose to navigate to lock screen
                        setContent {
                            SecureSharingApp(
                                deepLinkAction = pendingDeepLinkAction,
                                onDeepLinkHandled = { pendingDeepLinkAction = null },
                                shouldLock = shouldLockOnResume,
                                onLockHandled = { shouldLockOnResume = false }
                            )
                        }
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
fun SecureSharingApp(
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

    SecureSharingTheme {
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
        is DeepLinkAction.OidcCallback -> {
            // Store callback data for LoginScreen's OidcLoginViewModel to consume
            OidcCallbackHolder.set(action.code, action.state)
            navController.navigate(Screen.Login.route) {
                launchSingleTop = true
            }
        }
    }
}
