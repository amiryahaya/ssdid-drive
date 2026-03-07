package my.ssdid.drive.domain.repository

import my.ssdid.drive.domain.model.DeviceEnrollment
import my.ssdid.drive.util.Result

/**
 * Repository interface for device enrollment operations.
 *
 * Manages device enrollment, cryptographic device binding, and enrollment status.
 */
interface DeviceRepository {

    /**
     * Enroll the current device.
     * Generates a device key pair and registers with the backend.
     *
     * @param deviceName Optional user-friendly name for the device
     * @return Result containing the enrollment or an error
     */
    suspend fun enrollDevice(deviceName: String? = null): Result<DeviceEnrollment>

    /**
     * Get the current device's enrollment.
     * Returns null if device is not enrolled.
     */
    suspend fun getCurrentEnrollment(): Result<DeviceEnrollment?>

    /**
     * List all enrolled devices for the current user.
     */
    suspend fun listEnrollments(): Result<List<DeviceEnrollment>>

    /**
     * Update an enrollment (e.g., rename the device).
     *
     * @param enrollmentId The enrollment ID to update
     * @param deviceName New device name
     */
    suspend fun updateEnrollment(enrollmentId: String, deviceName: String): Result<DeviceEnrollment>

    /**
     * Revoke an enrollment.
     * After revocation, the device can no longer sign requests.
     *
     * @param enrollmentId The enrollment ID to revoke
     */
    suspend fun revokeEnrollment(enrollmentId: String): Result<Unit>

    /**
     * Check if the current device is enrolled and active.
     */
    suspend fun isDeviceEnrolled(): Boolean

    /**
     * Sign a request payload using the device's private key.
     * Returns the base64-encoded signature.
     *
     * @param payload The payload to sign (method|path|timestamp|body_hash)
     * @return Result containing the base64 signature or an error
     */
    suspend fun signRequest(payload: String): Result<String>

    /**
     * Get the current device's enrollment ID (if enrolled).
     * Used for including in request headers.
     */
    suspend fun getEnrollmentId(): String?

    /**
     * Clear local device enrollment data.
     * Called on logout or when enrollment is revoked.
     */
    suspend fun clearEnrollment()

    /**
     * Register push notifications for the enrolled device.
     * Call after device enrollment and successful login.
     *
     * @param userId The user's ID for push notification targeting
     */
    fun registerPushNotifications(userId: String)

    /**
     * Unregister push notifications.
     * Call on logout to stop receiving notifications on this device.
     */
    fun unregisterPushNotifications()
}
