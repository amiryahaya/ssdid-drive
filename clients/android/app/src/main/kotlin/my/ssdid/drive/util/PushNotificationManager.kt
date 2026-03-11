package my.ssdid.drive.util

import android.content.Context
import android.content.Intent
import com.onesignal.OneSignal
import com.onesignal.debug.LogLevel
import com.onesignal.notifications.INotificationClickEvent
import com.onesignal.notifications.INotificationClickListener
import com.onesignal.user.subscriptions.IPushSubscriptionObserver
import com.onesignal.user.subscriptions.PushSubscriptionChangedState
import my.ssdid.drive.BuildConfig
import my.ssdid.drive.MainActivity
import my.ssdid.drive.data.remote.ApiService
import my.ssdid.drive.data.remote.dto.RegisterPushRequest
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Manager for OneSignal push notifications.
 *
 * Handles:
 * - SDK initialization
 * - User association (external_user_id)
 * - Player ID registration with backend
 * - Push notification permission requests
 * - Click listener for server push deep linking
 *
 * ## Usage
 *
 * Initialize once in Application.onCreate():
 * ```kotlin
 * pushNotificationManager.initialize()
 * ```
 *
 * After login, associate the user and register player ID:
 * ```kotlin
 * pushNotificationManager.login(userId, enrollmentId)
 * ```
 *
 * On logout, clear the association:
 * ```kotlin
 * pushNotificationManager.logout(enrollmentId)
 * ```
 */
@Singleton
class PushNotificationManager @Inject constructor(
    @ApplicationContext private val context: Context,
    private val apiService: ApiService
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var currentEnrollmentId: String? = null
    private var subscriptionObserver: IPushSubscriptionObserver? = null

    companion object {
        private const val TAG = "PushNotificationManager"
    }

    /**
     * Initialize OneSignal SDK.
     * Call this once in Application.onCreate().
     */
    fun initialize() {
        // Set log level for debugging (disable in production)
        if (BuildConfig.ENABLE_LOGGING) {
            OneSignal.Debug.logLevel = LogLevel.VERBOSE
        } else {
            OneSignal.Debug.logLevel = LogLevel.NONE
        }

        // Initialize with app ID from BuildConfig (D1: pass app ID explicitly)
        OneSignal.initWithContext(context, BuildConfig.ONESIGNAL_APP_ID)

        // D10: Add click listener for server push deep linking
        OneSignal.Notifications.addClickListener(object : INotificationClickListener {
            override fun onClick(event: INotificationClickEvent) {
                val data = event.notification.additionalData
                if (data != null) {
                    val actionType = data.optString("action_type", null)
                    val resourceId = data.optString("resource_id", null)
                    if (actionType != null && resourceId != null) {
                        handlePushDeepLink(actionType, resourceId)
                    }
                }
            }
        })

        Logger.d(TAG, "OneSignal initialized")
    }

    /**
     * Associate current user with OneSignal and register player ID with backend.
     *
     * Call this after successful login and device enrollment.
     *
     * @param userId The user's ID (will be set as external_user_id in OneSignal)
     * @param enrollmentId The device enrollment ID for registering the player ID
     */
    fun login(userId: String, enrollmentId: String) {
        currentEnrollmentId = enrollmentId

        // Set external user ID in OneSignal for user-targeted notifications
        OneSignal.login(userId)

        Logger.d(TAG, "OneSignal login completed")

        // D3: Try to register immediately if subscription ID is already available
        val playerId = OneSignal.User.pushSubscription.id
        if (!playerId.isNullOrEmpty()) {
            registerPlayerIdDirect(enrollmentId, playerId)
        }

        // D3/D8: Wire up subscription observer to detect when subscription ID becomes available
        removeSubscriptionObserver()
        val observer = object : IPushSubscriptionObserver {
            override fun onPushSubscriptionChange(state: PushSubscriptionChangedState) {
                val subscriptionId = state.current.id
                if (!subscriptionId.isNullOrEmpty()) {
                    currentEnrollmentId?.let { eid ->
                        registerPlayerIdDirect(eid, subscriptionId)
                    }
                }
            }
        }
        subscriptionObserver = observer
        OneSignal.User.pushSubscription.addObserver(observer)
    }

    /**
     * Clear user association from OneSignal and unregister from backend.
     *
     * Call this on logout.
     *
     * @param enrollmentId The device enrollment ID to unregister
     */
    fun logout(enrollmentId: String? = currentEnrollmentId) {
        // D5: Remove subscription observer on logout to prevent leaks
        removeSubscriptionObserver()

        // Logout from OneSignal (clears external_user_id)
        OneSignal.logout()

        Logger.d(TAG, "OneSignal logout")

        // Unregister player ID from backend
        enrollmentId?.let { id ->
            scope.launch {
                try {
                    apiService.unregisterPush(id)
                    Logger.d(TAG, "Unregistered push from backend")
                } catch (e: Exception) {
                    Logger.e(TAG, "Failed to unregister push from backend", e)
                }
            }
        }

        currentEnrollmentId = null
    }

    /**
     * Request push notification permission from user.
     *
     * On Android 13+, this will show the system permission dialog.
     * On older versions, this is a no-op.
     *
     * D2: Only requests if permission hasn't already been granted.
     */
    fun requestPermission() {
        if (!hasPermission()) {
            scope.launch {
                OneSignal.Notifications.requestPermission(true)
            }
        }
    }

    /**
     * Check if push notification permission is granted.
     */
    fun hasPermission(): Boolean {
        return OneSignal.Notifications.permission
    }

    /**
     * Get the current OneSignal subscription ID (player ID).
     */
    fun getSubscriptionId(): String? {
        return OneSignal.User.pushSubscription.id
    }

    /**
     * Check if user is subscribed to push notifications.
     */
    fun isSubscribed(): Boolean {
        return OneSignal.User.pushSubscription.optedIn
    }

    /**
     * D3: Register a specific player ID with the backend directly (no delay).
     */
    private fun registerPlayerIdDirect(enrollmentId: String, playerId: String) {
        scope.launch {
            try {
                apiService.registerPushPlayerId(enrollmentId, RegisterPushRequest(playerId))
                Logger.d(TAG, "Registered player ID with backend")
            } catch (e: Exception) {
                Logger.e(TAG, "Failed to register player ID with backend", e)
            }
        }
    }

    /**
     * D5: Remove the subscription observer to prevent leaks.
     */
    private fun removeSubscriptionObserver() {
        subscriptionObserver?.let {
            OneSignal.User.pushSubscription.removeObserver(it)
            subscriptionObserver = null
        }
    }

    /**
     * D10: Handle deep link from push notification click.
     *
     * Parses the notification's additionalData to extract action type and resource ID,
     * then navigates to the appropriate screen via Intent.
     */
    private fun handlePushDeepLink(actionType: String, resourceId: String) {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("push_action_type", actionType)
            putExtra("push_resource_id", resourceId)

            // Build a deep link URI based on action type
            val deepLink = when (actionType) {
                "share" -> "ssdiddrive://share/$resourceId"
                "file" -> "ssdiddrive://file/$resourceId"
                "folder" -> "ssdiddrive://folder/$resourceId"
                "recovery" -> "ssdiddrive://recovery/$resourceId"
                else -> null
            }
            deepLink?.let { data = android.net.Uri.parse(it) }
        }
        context.startActivity(intent)
    }
}
