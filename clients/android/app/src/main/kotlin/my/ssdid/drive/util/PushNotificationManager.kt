package my.ssdid.drive.util

import android.content.Context
import android.util.Log
import com.onesignal.OneSignal
import com.onesignal.debug.LogLevel
import my.ssdid.drive.BuildConfig
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

        // Initialize with app ID from manifest (set via build flavor)
        OneSignal.initWithContext(context)

        Log.d(TAG, "OneSignal initialized")
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

        Log.d(TAG, "OneSignal login: userId=$userId")

        // Get player ID and register with backend
        registerPlayerIdWithBackend(enrollmentId)
    }

    /**
     * Clear user association from OneSignal and unregister from backend.
     *
     * Call this on logout.
     *
     * @param enrollmentId The device enrollment ID to unregister
     */
    fun logout(enrollmentId: String? = currentEnrollmentId) {
        // Logout from OneSignal (clears external_user_id)
        OneSignal.logout()

        Log.d(TAG, "OneSignal logout")

        // Unregister player ID from backend
        enrollmentId?.let { id ->
            scope.launch {
                try {
                    apiService.unregisterPush(id)
                    Log.d(TAG, "Unregistered push from backend: enrollmentId=$id")
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to unregister push from backend", e)
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
     */
    fun requestPermission() {
        scope.launch {
            OneSignal.Notifications.requestPermission(true)
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
     * Register the current player ID with the backend.
     */
    private fun registerPlayerIdWithBackend(enrollmentId: String) {
        scope.launch {
            // Wait a bit for OneSignal to fully initialize and get the subscription
            kotlinx.coroutines.delay(1000)

            val playerId = OneSignal.User.pushSubscription.id
            if (playerId != null) {
                try {
                    apiService.registerPushPlayerId(enrollmentId, RegisterPushRequest(playerId))
                    Log.d(TAG, "Registered player ID with backend: playerId=$playerId")
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to register player ID with backend", e)
                }
            } else {
                Log.w(TAG, "No player ID available yet")
            }
        }
    }

    /**
     * Add a listener for subscription changes.
     *
     * Use this to register player ID when it becomes available
     * (e.g., after first permission grant).
     */
    fun addSubscriptionObserver(onChanged: (subscriptionId: String?) -> Unit) {
        OneSignal.User.pushSubscription.addObserver(
            object : com.onesignal.user.subscriptions.IPushSubscriptionObserver {
                override fun onPushSubscriptionChange(state: com.onesignal.user.subscriptions.PushSubscriptionChangedState) {
                    val subscriptionId = state.current.id
                    onChanged(subscriptionId)

                    // Auto-register with backend if we have an enrollment
                    currentEnrollmentId?.let { enrollmentId ->
                        if (subscriptionId != null) {
                            registerPlayerIdWithBackend(enrollmentId)
                        }
                    }
                }
            }
        )
    }
}
