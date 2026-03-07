package com.securesharing.service

/**
 * Firebase Cloud Messaging Service - NOT USED.
 *
 * This app uses OneSignal for push notifications, which handles FCM internally.
 * See [com.securesharing.util.PushNotificationManager] for the push notification implementation.
 *
 * ## Setup Instructions
 *
 * 1. Create a OneSignal account at https://onesignal.com
 * 2. Create an app in OneSignal dashboard
 * 3. Configure Android platform with your Firebase Server Key
 * 4. Update build.gradle.kts with your OneSignal App IDs:
 *    - dev: Development/testing app
 *    - staging: Staging environment app
 *    - prod: Production app
 *
 * The manifest placeholder `onesignal_app_id` is configured per build flavor.
 *
 * ## No additional code needed
 *
 * OneSignal SDK handles:
 * - FCM token registration
 * - Token refresh
 * - Notification display
 * - Background message handling
 *
 * @see com.securesharing.util.PushNotificationManager
 */
object FCMServiceDocumentation {
    const val SETUP_URL = "https://documentation.onesignal.com/docs/android-sdk-setup"
}
